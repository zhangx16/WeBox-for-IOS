import Foundation

struct AppFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

func jsonText(_ value: Any) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys])
    guard let text = String(data: data, encoding: .utf8) else { throw AppFailure("无法编码 JSON") }
    return text
}
func jsonObject(_ text: String) throws -> Any {
    try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
}
func string(_ value: Any?) -> String {
    guard let value, !(value is NSNull) else { return "" }
    return value as? String ?? String(describing: value)
}

struct ScriptSource: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var version: String
    var code: String
    var origin: String
    var settings: [String: String] = [:]
    var installedAt = Date()
}

struct ContentItem: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var link: String
    var poster: String = ""
    var summary: String = ""
    var videoURL: String = ""
    var group: String = ""
    var isLive: Bool = false
    var children: [ContentItem] = []

    init(_ raw: [String: Any]) {
        link = string(raw["link"] ?? raw["url"] ?? raw["id"])
        id = string(raw["id"] ?? raw["link"] ?? raw["url"] ?? raw["title"])
        title = string(raw["title"] ?? raw["name"])
        poster = string(raw["posterPath"] ?? raw["poster"] ?? raw["cover"])
        summary = string(raw["overview"] ?? raw["description"] ?? raw["summary"])
        videoURL = string(raw["videoUrl"])
        group = string(raw["episodeGroup"])
        isLive = raw["isLive"] as? Bool ?? false
        children = (raw["childItems"] as? [[String: Any]] ?? []).map(ContentItem.init)
        if id.isEmpty { id = link.isEmpty ? title : link }
    }
}
struct PlaySource: Identifiable {
    var id: String
    var name: String
    var url: URL
    var headers: [String: String]
    var downloadable: Bool
    var manifest: String?
    var baseURL: URL?
    var mime: String
    var processor: [String: Any]?
    var runtime: ScriptRuntime?
    init(_ raw: [String: Any]) throws {
        manifest = raw["manifest"] as? String
        let address = string(raw["url"] ?? raw["videoUrl"] ?? raw["baseUrl"])
        guard let parsedURL = URL(string: address), ["http", "https"].contains(parsedURL.scheme?.lowercased() ?? "") else {
            throw AppFailure("播放线路没有有效的 HTTP 视频地址或内存 HLS 基地址")
        }
        if let manifest {
            guard manifest.hasPrefix("#EXTM3U"), manifest.utf8.count <= 2 * 1024 * 1024 else { throw AppFailure("无效或过大的内存 HLS 清单") }
            baseURL = parsedURL
        }
        url = parsedURL
        name = string(raw["name"]); if name.isEmpty { name = "默认线路" }
        id = string(raw["sourceId"] ?? raw["id"]); if id.isEmpty { id = address }
        headers = raw["headers"] as? [String: String] ?? [:]
        downloadable = raw["downloadable"] as? Bool ?? true
        mime = string(raw["mimeType"] ?? raw["mime"])
        processor = raw["processor"] as? [String: Any]
        runtime = nil
    }
    var isHLS: Bool { manifest != nil || url.pathExtension.lowercased() == "m3u8" || mime.lowercased().contains("mpegurl") }
}

struct SavedItem: Codable, Identifiable {
    var sourceID: String
    var item: ContentItem
    var date = Date()
    var position: Double = 0
    var id: String { sourceID + ":" + item.id }
}
struct Backup: Codable {
    var format = "webox-ios"
    var version = 1
    var sources: [ScriptSource]
    var favorites: [SavedItem]
    var history: [SavedItem]
}
struct DownloadRecord: Codable, Identifiable {
    var id = UUID().uuidString
    var title: String
    var filename: String
    var date = Date()
}

struct ScriptParameter: Identifiable {
    var id: String
    var title: String
    var type: String
    var value: String
    var options: [(title: String, value: String)]
    init(_ raw: [String: Any]) {
        id = string(raw["name"])
        title = string(raw["title"]); if title.isEmpty { title = id }
        type = string(raw["type"])
        value = string(raw["value"])
        options = (raw["enumOptions"] as? [[String: Any]] ?? []).map { (string($0["title"]), string($0["value"])) }
        if value.isEmpty { value = options.first?.value ?? "" }
    }
}
struct ScriptModule: Identifiable {
    var id: String
    var title: String
    var function: String
    var type: String
    var parameters: [ScriptParameter]
    init(_ raw: [String: Any]) {
        id = string(raw["id"])
        title = string(raw["title"])
        function = string(raw["functionName"])
        type = string(raw["type"])
        parameters = (raw["params"] as? [[String: Any]] ?? []).map(ScriptParameter.init)
    }
}
