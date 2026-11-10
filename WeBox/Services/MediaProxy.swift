import Foundation
import Network

/// Serves a token-scoped loopback URL. This avoids relying on undocumented
/// AVURLAsset header forwarding and routes every playlist/key/segment through
/// the same source headers and optional script processors.
@MainActor
final class MediaProxy {
    let source: PlaySource
    private let session: URLSession
    private let token = UUID().uuidString
    private let queue = DispatchQueue(label: "dev.webox.media.http")
    private var listener: NWListener?
    private var origin: URL?
    private var connections: [UUID: NWConnection] = [:]
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var stopped = false

    init(source: PlaySource, session: URLSession = .shared) { self.source = source; self.session = session }

    func start() async throws -> URL {
        if let origin { return localURL(for: source.url, origin: origin, root: true) }
        guard source.processor == nil || source.runtime != nil else { throw AppFailure("媒体处理器缺少所属脚本会话") }
        stopped = false
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        let port: NWEndpoint.Port = try await withCheckedThrowingContinuation { continuation in
            var finished = false
            listener.stateUpdateHandler = { [weak listener] state in
                switch state {
                case .ready:
                    guard !finished, let port = listener?.port else { return }; finished = true
                    continuation.resume(returning: port)
                case .failed(let error):
                    guard !finished else { return }; finished = true; continuation.resume(throwing: error)
                case .cancelled:
                    guard !finished else { return }; finished = true; continuation.resume(throwing: CancellationError())
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.start(queue: queue)
        }
        guard !stopped else { throw CancellationError() }
        let address = URL(string: "http://127.0.0.1:\(port.rawValue)")!
        origin = address
        return localURL(for: source.url, origin: address, root: true)
    }

    func close() {
        stopped = true
        listener?.cancel(); listener = nil; origin = nil
        for task in tasks.values { task.cancel() }; tasks.removeAll()
        for connection in connections.values { connection.cancel() }; connections.removeAll()
    }

    private func accept(_ connection: NWConnection) {
        guard !stopped else { connection.cancel(); return }
        let id = UUID(); connections[id] = connection
        connection.start(queue: queue)
        receive(connection, id: id, accumulated: Data())
    }
    private func receive(_ connection: NWConnection, id: UUID, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, done, error in
            Task { @MainActor in
                guard let self else { connection.cancel(); return }
                var buffer = accumulated; if let data { buffer.append(data) }
                guard buffer.count <= 64 * 1024 else { self.finish(id); return }
                if buffer.range(of: Data("\r\n\r\n".utf8)) != nil {
                    self.tasks[id] = Task { [weak self] in
                        guard let self else { return }
                        do { try await self.serve(buffer, connection: connection) }
                        catch { try? await self.send(connection, status: 502, headers: ["Content-Type": "text/plain; charset=utf-8"], body: Data(error.localizedDescription.utf8), head: false) }
                        self.finish(id)
                    }
                } else if done || error != nil { self.finish(id) }
                else { self.receive(connection, id: id, accumulated: buffer) }
            }
        }
    }
    private func finish(_ id: UUID) { connections.removeValue(forKey: id)?.cancel(); tasks.removeValue(forKey: id) }

    private func localURL(for remote: URL, origin: URL, root: Bool = false, kind: String = "resource", byteRange: Bool = false) -> URL {
        let encoded = Data(remote.absoluteString.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let suffix = root && source.isHLS ? "root.m3u8" : remote.lastPathComponent.isEmpty ? "resource" : remote.lastPathComponent
        return origin.appendingPathComponent(token).appendingPathComponent(root ? "root" : encoded).appendingPathComponent((root && source.isHLS ? "playlist" : kind) + (byteRange ? "~range" : "")).appendingPathComponent(suffix)
    }

    private func serve(_ raw: Data, connection: NWConnection) async throws {
        guard let text = String(data: raw, encoding: .utf8), let first = text.components(separatedBy: "\r\n").first else { throw AppFailure("无效媒体请求") }
        let parts = first.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" || parts[0] == "HEAD", let origin else { throw AppFailure("媒体代理仅接受 GET/HEAD") }
        let path = String(parts[1]).components(separatedBy: "?")[0].split(separator: "/").map(String.init)
        guard path.count >= 3, path[0] == token else { try await send(connection, status: 404, headers: [:], body: Data(), head: false); return }
        var incoming: [String: String] = [:]
        for line in text.components(separatedBy: "\r\n").dropFirst() {
            guard let index = line.firstIndex(of: ":") else { continue }
            incoming[String(line[..<index]).lowercased()] = String(line[line.index(after: index)...]).trimmingCharacters(in: .whitespaces)
        }
        let remote: URL
        if path[1] == "root" { remote = source.url }
        else {
            var encoded = path[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
            guard let bytes = Data(base64Encoded: encoded), let value = String(data: bytes, encoding: .utf8), let address = URL(string: value), ["http", "https"].contains(address.scheme ?? "") else { throw AppFailure("无效媒体资源") }
            remote = address
        }
        let head = parts[0] == "HEAD"
        if path[1] == "root", let manifest = source.manifest {
            let rewritten = try MediaPlaylist.rewriteResources(manifest, base: source.baseURL ?? remote) { url, kind, range in self.localURL(for: url, origin: origin, kind: kind, byteRange: range).absoluteString }
            try await send(connection, status: 200, headers: ["Content-Type": "application/vnd.apple.mpegurl", "Cache-Control": "no-store"], body: Data(rewritten.utf8), head: head)
            return
        }
        let declaredKind = path[2].replacingOccurrences(of: "~range", with: "")
        let isPlaylist = declaredKind == "playlist" || remote.pathExtension.lowercased() == "m3u8" || (path[1] == "root" && source.isHLS)
        let kind = isPlaylist ? "playlist" : declaredKind
        let responseFunction = string(source.processor?["response"])
        if path[2].hasSuffix("~range"), !responseFunction.isEmpty, !isPlaylist { throw AppFailure("分片 BYTERANGE 与媒体正文转换不能同时使用") }
        var headers = source.headers
        for key in ["range", "if-range", "if-none-match", "if-modified-since"] {
            if let value = incoming[key], !headers.keys.contains(where: { $0.lowercased() == key }) { headers[key] = value }
        }
        var actual = remote
        if let function = source.processor?["request"] as? String, !function.isEmpty, let runtime = source.runtime {
            let input: [String: Any] = ["url": remote.absoluteString, "headers": headers, "kind": kind, "method": "GET", "context": source.processor?["context"] ?? [:]]
            guard let transformed = try await runtime.invoke(function, arguments: [input]) as? [String: Any] else { throw AppFailure("媒体请求处理器返回格式无效") }
            if let value = transformed["url"] as? String {
                guard let address = URL(string: value), ["http", "https"].contains(address.scheme ?? "") else { throw AppFailure("媒体处理器返回无效 URL") }; actual = address
            }
            if let changed = transformed["headers"] as? [String: String] { headers = changed }
        }
        if !responseFunction.isEmpty && !isPlaylist { headers = headers.filter { $0.key.lowercased() != "range" } }
        var request = URLRequest(url: actual); request.allHTTPHeaderFields = headers; request.timeoutInterval = 30
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw AppFailure("媒体服务器未返回 HTTP 响应") }
        let mime = http.value(forHTTPHeaderField: "Content-Type") ?? MediaPlaylist.mime(for: actual)
        let playlist = isPlaylist || mime.lowercased().contains("mpegurl")
        // A transformer sees an entire resource; ordinary video responses stream
        // immediately and do not buffer a full movie in application memory.
        if playlist || !responseFunction.isEmpty {
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation(); data.append(byte)
                if data.count > 64 * 1024 * 1024 { throw AppFailure("媒体处理资源超过 64 MB") }
            }
            var contentType = mime
            if !playlist, !responseFunction.isEmpty, let runtime = source.runtime {
                let handle = try runtime.mediaCreateBinary(data)
                let input: [String: Any] = ["url": actual.absoluteString, "kind": kind, "statusCode": http.statusCode, "headers": Self.forwardHeaders(http), "body": handle, "size": data.count, "mimeType": mime, "context": source.processor?["context"] ?? [:]]
                guard let changed = try await runtime.invoke(responseFunction, arguments: [input]) as? [String: Any] else { throw AppFailure("媒体响应处理器返回格式无效") }
                let transformedHandle = string(changed["body"]).isEmpty ? handle : string(changed["body"])
                data = try runtime.mediaReadBinary(handle: transformedHandle)
                runtime.mediaReleaseBinary(handle: handle)
                if transformedHandle != handle { runtime.mediaReleaseBinary(handle: transformedHandle) }
                let returnedMime = string(changed["mimeType"]); if !returnedMime.isEmpty { contentType = returnedMime }
            }
            var forwarded = Self.forwardHeaders(http)
            if playlist, let text = String(data: data, encoding: .utf8) {
                let rewritten = try MediaPlaylist.rewriteResources(text, base: http.url ?? actual) { url, kind, range in self.localURL(for: url, origin: origin, kind: kind, byteRange: range).absoluteString }
                data = Data(rewritten.utf8); contentType = "application/vnd.apple.mpegurl"
                forwarded.removeValue(forKey: "Content-Range")
            }
            forwarded["Content-Type"] = contentType
            if !playlist, !responseFunction.isEmpty, let rangeHeader = incoming["range"] {
                do {
                    let range = try MediaByteRange.parse(rangeHeader, size: data.count)
                    forwarded["Content-Range"] = "bytes \(range.lowerBound)-\(range.upperBound - 1)/\(data.count)"
                    forwarded["Accept-Ranges"] = "bytes"
                    try await send(connection, status: 206, headers: forwarded, body: data.subdata(in: range), head: head)
                } catch {
                    try await send(connection, status: 416, headers: ["Content-Range": "bytes */\(data.count)"], body: Data(), head: head)
                }
            } else { try await send(connection, status: http.statusCode, headers: forwarded, body: data, head: head) }
        } else {
            var forwarded = Self.forwardHeaders(http); forwarded["Content-Type"] = mime
            let chunked = http.expectedContentLength < 0
            if chunked { forwarded["Transfer-Encoding"] = "chunked" }
            else { forwarded["Content-Length"] = String(http.expectedContentLength) }
            try await write(connection, data: makeHeader(status: http.statusCode, headers: forwarded))
            if head { return }
            var buffer = Data(); buffer.reserveCapacity(65_536)
            for try await byte in bytes {
                try Task.checkCancellation(); buffer.append(byte)
                if buffer.count >= 65_536 { try await writeChunk(connection, data: buffer, chunked: chunked); buffer.removeAll(keepingCapacity: true) }
            }
            if !buffer.isEmpty { try await writeChunk(connection, data: buffer, chunked: chunked) }
            if chunked { try await write(connection, data: Data("0\r\n\r\n".utf8)) }
        }
    }

    private static func forwardHeaders(_ response: HTTPURLResponse) -> [String: String] {
        var result: [String: String] = [:]
        for name in ["Content-Range", "Accept-Ranges", "ETag", "Last-Modified", "Cache-Control"] { if let value = response.value(forHTTPHeaderField: name) { result[name] = value } }
        return result
    }
    private func send(_ connection: NWConnection, status: Int, headers: [String: String], body: Data, head: Bool) async throws {
        var headers = headers; headers["Content-Length"] = String(body.count)
        try await write(connection, data: makeHeader(status: status, headers: headers))
        if !head { try await write(connection, data: body) }
    }
    private func makeHeader(status: Int, headers: [String: String]) -> Data {
        var values = headers; values["Connection"] = "close"; values["Access-Control-Allow-Origin"] = "*"
        let text = "HTTP/1.1 \(status) \(HTTPURLResponse.localizedString(forStatusCode: status))\r\n" + values.filter { !$0.key.contains("\r") && !$0.key.contains("\n") && !$0.value.contains("\r") && !$0.value.contains("\n") }.map { "\($0.key): \($0.value)\r\n" }.joined() + "\r\n"
        return Data(text.utf8)
    }
    private func writeChunk(_ connection: NWConnection, data: Data, chunked: Bool) async throws {
        if chunked {
            var framed = Data((String(data.count, radix: 16) + "\r\n").utf8); framed.append(data); framed.append(Data("\r\n".utf8))
            try await write(connection, data: framed)
        } else { try await write(connection, data: data) }
    }
    private func write(_ connection: NWConnection, data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }
}
