import Foundation

/// Widget.tmdb's native transport. Users supply their own API credentials or a
/// compatible HTTPS service. Official v3 supports api_key or a Bearer token.
@MainActor
enum TMDBClient {
    static func get(_ request: [String: Any], defaults: UserDefaults = .standard, session: URLSession = .shared) async throws -> Any {
        let api = string(request["api"]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !api.isEmpty, api.range(of: "^[A-Za-z0-9._/-]+$", options: .regularExpression) != nil,
              !api.components(separatedBy: "/").contains("..") else { throw AppFailure("TMDB 路径无效") }
        let base = defaults.string(forKey: "webox.tmdb.service") ?? "https://api.themoviedb.org/3"
        guard var components = URLComponents(string: base), components.scheme == "https", components.host != nil, components.user == nil, components.password == nil else { throw AppFailure("TMDB 服务需要有效的 HTTPS 地址") }
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty ? "/3/" + api : components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).split(separator: "/").map(String.init).reduce("", { $0 + "/" + $1 }) + "/" + api
        var params = request["params"] as? [String: Any] ?? [:]
        params["language"] = params["language"] ?? defaults.string(forKey: "webox.tmdb.language") ?? "zh-CN"
        let key = defaults.string(forKey: "webox.tmdb.apiKey")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let official = components.host?.lowercased() == "api.themoviedb.org"
        if official && key.isEmpty { throw AppFailure("请在设置中填写自己的 TMDB API Key 或读访问令牌") }
        var headers = ["Accept": "application/json"]
        if !key.isEmpty {
            if key.hasPrefix("eyJ") || key.lowercased().hasPrefix("bearer ") { headers["Authorization"] = key.lowercased().hasPrefix("bearer ") ? key : "Bearer " + key }
            else { params["api_key"] = key }
        }
        guard let url = components.url else { throw AppFailure("TMDB 地址无效") }
        let response = try await ScriptRuntime.request(["url": url.absoluteString, "method": "GET", "params": params, "headers": headers, "httpsOnly": true, "decodable": true], session: session)
        guard let status = response["statusCode"] as? Int, (200..<300).contains(status) else { throw AppFailure("TMDB 请求失败（HTTP \(string(response["statusCode"]))）") }
        let result = response["data"] ?? NSNull()
        if let object = result as? [String: Any], object["success"] as? Bool == false { throw AppFailure(string(object["status_message"]).isEmpty ? "TMDB 服务暂不可用" : string(object["status_message"])) }
        return result
    }
}
