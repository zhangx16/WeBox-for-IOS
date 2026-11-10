import Foundation
import CryptoKit

/// Preserve HLS manifests, encryption keys, initialization maps and byte ranges.
/// Files are fetched through the same proxy as playback (headers/processors).
@MainActor
final class MediaOfflineDownloader {
    private var files: [String: String] = [:]
    private var seenPlaylists = Set<String>()
    private let session: URLSession
    private let progress: (Int) -> Void
    private var completed = 0
    init(session: URLSession = .shared, progress: @escaping (Int) -> Void = { _ in }) { self.session = session; self.progress = progress }
    func download(source: PlaySource, destination: URL) async throws -> URL {
        let proxy = MediaProxy(source: source, session: session)
        defer { proxy.close() }
        let root = try await proxy.start()
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        return try await playlist(root, directory: destination, depth: 0, filename: "index.m3u8")
    }
    private func fetch(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw AppFailure("离线资源下载失败") }
        return (data, http)
    }
    private func playlist(_ url: URL, directory: URL, depth: Int, filename: String) async throws -> URL {
        guard depth <= 5, seenPlaylists.insert(url.absoluteString).inserted else { throw AppFailure("HLS 清单循环或嵌套过深") }
        let (data, _) = try await fetch(url)
        guard let text = String(data: data, encoding: .utf8), text.hasPrefix("#EXTM3U") else { throw AppFailure("HLS 清单无效") }
        let isMaster = text.contains("#EXT-X-STREAM-INF:")
        guard isMaster || text.contains("#EXT-X-ENDLIST") else { throw AppFailure("直播或尚未结束的 HLS 不支持离线下载") }
        var localFiles: [String: String] = [:]
        var resources: [(URL, String)] = []
        _ = try MediaPlaylist.rewriteResources(text, base: url) { remote, kind, _ in
            resources.append((remote, kind)); return remote.absoluteString
        }
        // Keep only the highest bitrate video variant; retain declared alternate audio/subtitles.
        let preferred = MediaPlaylist.preferredVariant(text, base: url)
        let lines = text.components(separatedBy: .newlines)
        var retained: [String] = [], discardNextVariant = false
        for (index, line) in lines.enumerated() {
            if line.hasPrefix("#EXT-X-STREAM-INF:"), index + 1 < lines.count, let preferred {
                discardNextVariant = MediaPlaylist.resolve(lines[index + 1], base: url) != preferred
                if discardNextVariant { continue }
            } else if discardNextVariant && !line.hasPrefix("#") && !line.isEmpty { discardNextVariant = false; continue }
            retained.append(line)
        }
        let retainedText = retained.joined(separator: "\n")
        resources.removeAll()
        _ = try MediaPlaylist.rewriteResources(retainedText, base: url) { remote, kind, _ in resources.append((remote, kind)); return remote.absoluteString }
        for (remote, kind) in resources {
            try Task.checkCancellation()
            if let existing = files[remote.absoluteString] { localFiles[remote.absoluteString] = existing; continue }
            let digest = SHA256.hash(data: Data(remote.absoluteString.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
            let name = digest + (kind == "playlist" ? ".m3u8" : "." + (remote.pathExtension.isEmpty ? "bin" : remote.pathExtension))
            if kind == "playlist" { _ = try await playlist(remote, directory: directory, depth: depth + 1, filename: name) }
            else {
                let (bytes, _) = try await fetch(remote)
                try bytes.write(to: directory.appendingPathComponent(name), options: .atomic)
                completed += 1; progress(completed)
            }
            files[remote.absoluteString] = name; localFiles[remote.absoluteString] = name
        }
        let rewritten = try MediaPlaylist.rewriteResources(retainedText, base: url) { remote, _, _ in
            guard let name = localFiles[remote.absoluteString] else { throw AppFailure("离线清单资源遗漏") }; return name
        }
        let target = directory.appendingPathComponent(filename)
        try Data(rewritten.utf8).write(to: target, options: .atomic)
        return target
    }
}
