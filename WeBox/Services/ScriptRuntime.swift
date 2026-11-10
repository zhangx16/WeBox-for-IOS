import Foundation
import JavaScriptCore
import Security

@MainActor
final class ScriptRuntime {
    let source: ScriptSource
    private let context: JSContext
    private var pending: [String: CheckedContinuation<String, Error>] = [:]
    private var requests: [String: Task<Void, Never>] = [:]
    private var deadlines: [String: Task<Void, Never>] = [:]
    private var timers: [Int: Task<Void, Never>] = [:]
    private var timerID = 0
    private(set) var metadata: [String: Any] = [:]
    private(set) var logs: [String] = []
    private let defaults: UserDefaults
    private let networkSession: URLSession
    private let storagePrefix: String
    private var lastException: String?

    init(source: ScriptSource, defaults: UserDefaults = .standard, networkSession: URLSession = .shared) throws {
        self.source = source
        self.defaults = defaults
        self.networkSession = networkSession
        storagePrefix = "script.\(source.id)."
        guard let context = JSContext() else { throw AppFailure("JavaScriptCore 初始化失败") }
        self.context = context
        context.exceptionHandler = { [weak self] _, value in self?.lastException = value?.toString() ?? "脚本错误" }
        let sync: @convention(block) (String) -> String = { [weak self] raw in
            guard let self else { return "null" }
            do { return try jsonText(self.handleSync(raw)) }
            catch { return (try? jsonText(["__hostError": error.localizedDescription])) ?? "null" }
        }
        let request: @convention(block) (String, String) -> Void = { [weak self] id, raw in self?.startRequest(id: id, raw: raw) }
        let complete: @convention(block) (String, String, String) -> Void = { [weak self] id, result, error in
            guard let self, let continuation = self.pending.removeValue(forKey: id) else { return }
            self.deadlines.removeValue(forKey: id)?.cancel()
            if error.isEmpty { continuation.resume(returning: result) }
            else { continuation.resume(throwing: AppFailure(error)) }
        }
        let log: @convention(block) (String) -> Void = { [weak self] line in
            self?.logs.append(line)
            if (self?.logs.count ?? 0) > 100 { self?.logs.removeFirst() }
        }
        let timeout: @convention(block) (JSValue, Double) -> Int = { [weak self] callback, milliseconds in
            guard let self else { return 0 }
            self.timerID += 1
            let id = self.timerID
            self.timers[id] = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(max(0, min(milliseconds, 60_000))))
                guard !Task.isCancelled, let self else { return }
                callback.call(withArguments: [])
                self.timers.removeValue(forKey: id)
            }
            return id
        }
        let clear: @convention(block) (Int) -> Void = { [weak self] id in self?.timers.removeValue(forKey: id)?.cancel() }
        let crypto: @convention(block) (String) -> String = { _ in Self.resource("cryptojs", "js") }
        context.setObject(sync, forKeyedSubscript: "__hostSync" as NSString)
        context.setObject(request, forKeyedSubscript: "__hostRequest" as NSString)
        context.setObject(complete, forKeyedSubscript: "__hostComplete" as NSString)
        context.setObject(log, forKeyedSubscript: "__nativeLog" as NSString)
        context.setObject(timeout, forKeyedSubscript: "setTimeout" as NSString)
        context.setObject(clear, forKeyedSubscript: "clearTimeout" as NSString)
        context.setObject(crypto, forKeyedSubscript: "__nativeCryptoResource" as NSString)
        try evaluate(Self.resource("bridge", "js"))
        for name in ["cheerio", "widget", "webox", "xptv", "ios-compat"] { try evaluate(Self.resource(name, "js")) }
        // Source text stays intact: no eval-based transformations of user functions.
        try evaluate(source.code)
        try evaluate("if(typeof WidgetMetadata==='undefined' && typeof getConfig==='function'){__weboxXptvAttach('compat.'+" + (try jsonText(source.id)) + ",function(){return typeof app==='object'?app:{};});}")
        let nativeSettings = Dictionary(uniqueKeysWithValues: source.settings.map { ( $0.key.hasPrefix("__wbSetting_") ? String($0.key.dropFirst(12)) : $0.key, $0.value) })
        try evaluate("if(typeof __wbHasSource==='function'&&__wbHasSource())__wbSetSettings(" + (try jsonText(try jsonText(nativeSettings))) + ");")
        guard let raw = context.evaluateScript("__weboxMetadata()")?.toString(), let metadata = try jsonObject(raw) as? [String: Any], !string(metadata["id"]).isEmpty else {
            throw AppFailure(lastException ?? "内容源缺少有效的元数据")
        }
        self.metadata = metadata
    }

    static func resource(_ name: String, _ ext: String) -> String {
        let url = Bundle.main.url(forResource: name, withExtension: ext)
            ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Runtime")
        guard let url else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
    func evaluate(_ code: String) throws {
        lastException = nil
        context.exception = nil
        context.evaluateScript(code)
        if let exception = lastException { throw AppFailure(exception) }
    }
    func configure() async throws {
        let host = string(metadata["hostProtocol"])
        let result: Any
        if host == "webox" { result = try await invoke("__wbConfigure", arguments: []) }
        else if host == "xptv" { result = try await invoke("__weboxXptvConfigure", arguments: [source.settings]) }
        else { return }
        if let object = result as? [String: Any] { metadata = object }
    }
    var modules: [ScriptModule] { (metadata["modules"] as? [[String: Any]] ?? []).map(ScriptModule.init).filter { $0.type != "stream" } }
    var searchModule: ScriptModule? { (metadata["search"] as? [String: Any]).map(ScriptModule.init) }
    var globals: [ScriptParameter] { (metadata["globalParams"] as? [[String: Any]] ?? []).map(ScriptParameter.init) }
    func invoke(_ name: String, arguments: [Any]) async throws -> Any {
        try Task.checkCancellation()
        let id = UUID().uuidString
        let code = "__invokeIOS(" + (try jsonText(id)) + "," + (try jsonText(name)) + "," + (try jsonText(try jsonText(arguments))) + ");"
        let result: String = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = continuation
                deadlines[id] = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(65))
                    guard !Task.isCancelled, let self else { return }
                    self.failInvocation(id, message: "脚本调用超时，请检查网络或内容源")
                }
                do { try evaluate(code) }
                catch { failInvocation(id, message: error.localizedDescription) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.failInvocation(id, message: "操作已取消") }
        }
        return (try? jsonObject(result)) ?? result
    }
    private func failInvocation(_ id: String, message: String) {
        deadlines.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.resume(throwing: AppFailure(message))
    }
    func close() {
        for task in requests.values { task.cancel() }; requests.removeAll()
        for task in timers.values { task.cancel() }; timers.removeAll()
        for task in deadlines.values { task.cancel() }; deadlines.removeAll()
        let values = pending.values; pending.removeAll()
        for continuation in values { continuation.resume(throwing: CancellationError()) }
        context.exceptionHandler = nil
    }

    private func handleSync(_ raw: String) throws -> Any {
        guard let call = try jsonObject(raw) as? [String: Any] else { throw AppFailure("原生调用格式错误") }
        let method = string(call["method"]), p = call["params"] as? [String: Any] ?? [:]
        let key = storagePrefix + string(p["key"])
        switch method {
        case "runtime.capabilities": return ["compute": false]
        case "url.validate":
            guard let url = URL(string: string(p["url"])), url.host != nil,
                  (url.scheme == "https" || (p["allowHttp"] as? Bool == true && url.scheme == "http")) else { throw AppFailure("无效或不允许的 URL") }
            return url.absoluteString
        case "url.resolve":
            guard let base = URL(string: string(p["base"])), let result = URL(string: string(p["url"]), relativeTo: base)?.absoluteURL else { throw AppFailure("URL 无法解析") }
            return result.absoluteString
        case "url.origin":
            guard let url = URL(string: string(p["url"])), let scheme = url.scheme, let host = url.host else { throw AppFailure("无效 URL") }
            return scheme + "://" + host + (url.port.map { ":\($0)" } ?? "")
        case "storage.getItem", "native.store.get": return defaults.string(forKey: key + ".json").flatMap { try? jsonObject($0) } ?? defaults.object(forKey: key) ?? NSNull()
        case "storage.setItem", "native.store.set":
            let value = p["value"] ?? NSNull()
            if value is NSNull { defaults.removeObject(forKey: key) } else {
                // Persist JSON text to support nested nulls without violating property-list constraints.
                defaults.set(try jsonText(value), forKey: key + ".json")
                defaults.removeObject(forKey: key)
            }
            return true
        case "storage.removeItem", "native.store.remove": defaults.removeObject(forKey: key); defaults.removeObject(forKey: key + ".json"); return true
        case "storage.keys": return storageKeys()
        case "storage.clear": for k in defaults.dictionaryRepresentation().keys where k.hasPrefix(storagePrefix) { defaults.removeObject(forKey: k) }; return true
        case "sharedCache.getItem": return defaults.string(forKey: "cache.\(string(p["namespace"])).\(string(p["key"]))").flatMap { try? jsonObject($0) } ?? NSNull()
        case "sharedCache.setItem": defaults.set(try jsonText(p["value"] ?? NSNull()), forKey: "cache.\(string(p["namespace"])).\(string(p["key"]))"); return true
        case "sharedCache.removeItem": defaults.removeObject(forKey: "cache.\(string(p["namespace"])).\(string(p["key"]))"); return true
        case "sharedCache.keys":
            let prefix = "cache.\(string(p["namespace"]))."
            return defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
        case "storage.readJSON": return defaults.string(forKey: key + ".json").flatMap { try? jsonObject($0) } ?? defaults.object(forKey: key) ?? NSNull()
        case "native.cancelled": return false
        case "native.cache.generation": return 1
        case "native.cache.seconds": return p["seconds"] ?? 0
        case "i18n": return p["value"] ?? ""
        case "crypto.random":
            let size = max(0, min(p["size"] as? Int ?? 0, 65536))
            var bytes = [UInt8](repeating: 0, count: size)
            guard SecRandomCopyBytes(kSecRandomDefault, size, &bytes) == errSecSuccess else { throw AppFailure("随机数生成失败") }
            return bytes.map(Int.init)
        default: throw AppFailure("当前 iOS 版未实现原生接口：\(method)")
        }
    }
    private func storageKeys() -> [String] {
        Array(Set(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(storagePrefix) }.map {
            let key = String($0.dropFirst(storagePrefix.count)); return key.hasSuffix(".json") ? String(key.dropLast(5)) : key
        })).sorted()
    }
    private func startRequest(id: String, raw: String) {
        requests[id] = Task { [weak self] in
            guard let self else { return }
            let result: [String: Any]
            do {
                guard let call = try jsonObject(raw) as? [String: Any] else { throw AppFailure("请求格式无效") }
                let p = call["params"] as? [String: Any] ?? [:]
                switch string(call["method"]) {
                case "request": result = try await Self.request(p, session: self.networkSession)
                default: throw AppFailure("当前 iOS 版未实现接口：\(string(call["method"]))")
                }
            } catch { result = ["error": error.localizedDescription] }
            guard !Task.isCancelled else { self.requests.removeValue(forKey: id); return }
            self.context.objectForKeyedSubscript("__resolveNative")?.call(withArguments: [id, (try? jsonText(result)) ?? "null"])
            self.requests.removeValue(forKey: id)
        }
    }
    static func request(_ p: [String: Any], session: URLSession = .shared) async throws -> [String: Any] {
        guard var components = URLComponents(string: string(p["url"])), ["https", "http"].contains(components.scheme?.lowercased() ?? "") else { throw AppFailure("仅支持 HTTP(S) 请求") }
        if p["httpsOnly"] as? Bool == true && components.scheme != "https" { throw AppFailure("此内容源禁止 HTTP 请求") }
        if let query = p["params"] as? [String: Any], !query.isEmpty {
            components.queryItems = (components.queryItems ?? []) + query.map { URLQueryItem(name: $0.key, value: string($0.value)) }
        }
        guard let url = components.url, url.host != nil else { throw AppFailure("无效的请求 URL") }
        var request = URLRequest(url: url)
        request.httpMethod = string(p["method"]).isEmpty ? "GET" : string(p["method"])
        request.timeoutInterval = max(1, min(p["timeout"] as? Double ?? 20, 60))
        for (key, value) in p["headers"] as? [String: String] ?? [:] { request.setValue(value, forHTTPHeaderField: key) }
        if let body = p["data"], !(body is NSNull) {
            if let text = body as? String { request.httpBody = Data(text.utf8) }
            else if (request.value(forHTTPHeaderField: "Content-Type") ?? "").contains("application/x-www-form-urlencoded"), let values = body as? [String: Any] {
                var form = URLComponents(); form.queryItems = values.map { URLQueryItem(name: $0.key, value: string($0.value)) }
                request.httpBody = Data((form.percentEncodedQuery ?? "").utf8)
            } else {
                request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.fragmentsAllowed])
                if request.value(forHTTPHeaderField: "Content-Type") == nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
            }
        }
        let delegate = RequestRedirectPolicy(allow: p["allow_redirects"] as? Bool ?? true, httpsOnly: p["httpsOnly"] as? Bool ?? false)
        let (data, response) = try await session.data(for: request, delegate: delegate)
        guard let http = response as? HTTPURLResponse else { throw AppFailure("服务器没有返回 HTTP 响应") }
        guard data.count <= 16 * 1024 * 1024 else { throw AppFailure("脚本响应超过 16 MB，请使用媒体播放接口") }
        var body: Any = p["base64Data"] as? Bool == true ? data.base64EncodedString() : String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        if p["decodable"] as? Bool != false && p["base64Data"] as? Bool != true, let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) { body = json }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields { headers[String(describing: key)] = String(describing: value) }
        return ["statusCode": http.statusCode, "data": body, "headers": headers, "url": http.url?.absoluteString ?? url.absoluteString]
    }
}

final class RequestRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let allow: Bool
    let httpsOnly: Bool
    init(allow: Bool, httpsOnly: Bool) { self.allow = allow; self.httpsOnly = httpsOnly }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(allow && (!httpsOnly || request.url?.scheme == "https") ? request : nil)
    }
}
