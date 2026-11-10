import Foundation
import CryptoKit
import SwiftUI

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var sources: [ScriptSource] = []
    @Published private(set) var favorites: [SavedItem] = []
    @Published private(set) var history: [SavedItem] = []
    @Published private(set) var subscriptions: [SourceSubscription] = []
    @Published private(set) var downloads: [DownloadRecord] = []
    @Published var error: String?
    @Published var downloadStatus: String?
    private let directory: URL
    private var downloadTask: Task<Void, Never>?
    private(set) var androidPreferences: [String: Any] = [:]

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("WeBox", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            let file = self.directory.appendingPathComponent("library.json")
            if FileManager.default.fileExists(atPath: file.path) {
                let backup = try JSONDecoder().decode(Backup.self, from: Data(contentsOf: file))
                sources = backup.sources; favorites = backup.favorites; history = backup.history
            } else {
                let code = ScriptRuntime.resource("demo", "js")
                guard !code.isEmpty else { throw AppFailure("缺少内置公开示例资源") }
                sources = [ScriptSource(id: "dev.webox.demo", title: "公开示例", version: "1.0.1", code: code, origin: "bundled")]
                save()
            }
            let subscriptionFile = self.directory.appendingPathComponent("subscriptions.json")
            if FileManager.default.fileExists(atPath: subscriptionFile.path) { subscriptions = try JSONDecoder().decode([SourceSubscription].self, from: Data(contentsOf: subscriptionFile)) }
            let androidFile = self.directory.appendingPathComponent("android-preferences.json")
            if FileManager.default.fileExists(atPath: androidFile.path) { androidPreferences = try JSONSerialization.jsonObject(with: Data(contentsOf: androidFile)) as? [String: Any] ?? [:] }
            let records = self.directory.appendingPathComponent("downloads.json")
            if FileManager.default.fileExists(atPath: records.path) { downloads = try JSONDecoder().decode([DownloadRecord].self, from: Data(contentsOf: records)) }
        } catch { self.error = "读取资料失败，原文件已保留：\(error.localizedDescription)" }
    }
    func source(_ id: String) -> ScriptSource? { sources.first { $0.id == id } }
    private func preparedSource(code: String, origin: String, settings: [String: String]? = nil) throws -> ScriptSource {
        guard code.utf8.count <= 4 * 1024 * 1024 else { throw AppFailure("脚本超过 4 MB") }
        if SourceFormats.clean(code).hasPrefix("REXENC") { throw AppFailure("加密源需要异步导入，请使用添加内容源入口") }
        let identityInput = origin == "pasted" ? code : origin
        let identity = SourceFormats.stableID(identityInput, prefix: "script")
        let temporary = ScriptSource(id: identity, title: "", version: "", code: code, origin: origin)
        let runtime = try ScriptRuntime(source: temporary)
        defer { runtime.close() }
        let id = string(runtime.metadata["id"])
        return ScriptSource(id: id, title: string(runtime.metadata["title"]), version: string(runtime.metadata["version"]), code: code, origin: origin, settings: settings ?? source(id)?.settings ?? [:])
    }
    func install(code: String, origin: String) throws {
        let installed = try preparedSource(code: code, origin: origin)
        mergeSources([installed]); save()
    }
    private func mergeSources(_ incoming: [ScriptSource]) {
        for source in incoming {
            if let index = sources.firstIndex(where: { $0.id == source.id }) { sources[index] = source }
            else { sources.append(source) }
        }
    }
    func importURL(_ address: String) async throws {
        let url = try SourceFormats.httpURL(address)
        let text = try await downloadSourceText(url)
        try await importText(text, origin: url.absoluteString)
    }
    private func downloadSourceText(_ url: URL) async throws -> String {
        var request = URLRequest(url: url); request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw AppFailure("内容源下载失败（HTTP \(string((response as? HTTPURLResponse)?.statusCode))）") }
        guard data.count <= SourceFormats.maximumDocumentBytes, let text = String(data: data, encoding: .utf8) else { throw AppFailure("内容源必须是 4 MB 以内的 UTF-8 文件") }
        return text
    }
    func importFileAsync(_ url: URL) async throws {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard data.count <= 32 * 1024 * 1024, let text = String(data: data, encoding: .utf8) else { throw AppFailure("文件必须是 32 MB 以内的 UTF-8 文件") }
        try await importText(text, origin: url.absoluteString)
    }
    func importText(_ text: String, origin: String = "pasted") async throws {
        let trimmed = SourceFormats.clean(text)
        if let object = try? jsonObject(trimmed) as? [String: Any], isBackup(object) {
            try restoreBackup(object); return
        }
        var visited = Set<String>()
        let incoming = try await prepareDocument(trimmed, origin: origin, title: "", depth: 0, visited: &visited)
        guard !incoming.isEmpty else { throw AppFailure("来源合集没有启用的内容源") }
        mergeSources(incoming)
        if let object = try? jsonObject(trimmed) as? [String: Any], try SourceFormats.subscription(object, origin: origin) != nil, let url = try? SourceFormats.httpURL(origin) {
            let id = SourceFormats.stableID(url.absoluteString, prefix: "subscription")
            let record = SourceSubscription(id: id, title: string(object["name"] ?? object["title"]).isEmpty ? url.host ?? "来源合集" : string(object["name"] ?? object["title"]), url: url.absoluteString, sourceIDs: incoming.map(\.id), updatedAt: Date())
            subscriptions.removeAll { $0.id == id }; subscriptions.append(record); saveSubscriptions()
        }
        save()
    }
    private func prepareDocument(_ text: String, origin: String, title: String, depth: Int, visited: inout Set<String>) async throws -> [ScriptSource] {
        guard depth <= 3 else { throw AppFailure("来源合集嵌套超过 3 层") }
        guard text.utf8.count <= SourceFormats.maximumDocumentBytes else { throw AppFailure("内容源超过 4 MB") }
        let trimmed = SourceFormats.clean(text)
        let name = title.isEmpty ? URL(string: origin)?.deletingPathExtension().lastPathComponent ?? "内容源" : title
        if trimmed.hasPrefix("#EXTM3U") { return [try preparedSource(code: SourceFormats.m3uScript(trimmed, title: name, origin: origin), origin: origin)] }
        if let object = try? jsonObject(trimmed) as? [String: Any] {
            if let entries = try SourceFormats.subscription(object, origin: origin) {
                var sources: [ScriptSource] = []
                for entry in entries {
                    try Task.checkCancellation()
                    guard visited.insert(entry.url.absoluteString).inserted else { throw AppFailure("来源合集含循环或重复地址") }
                    let body = try await downloadSourceText(entry.url)
                    let children = try await prepareDocument(body, origin: entry.url.absoluteString, title: entry.title, depth: depth + 1, visited: &visited)
                    sources.append(contentsOf: children)
                    guard sources.count <= 100 else { throw AppFailure("来源合集最多支持 100 个内容源") }
                }
                return sources
            }
            if object["api"] is String || object["class"] != nil && object["list"] != nil {
                var config = object
                if config["api"] == nil { config["api"] = try SourceFormats.httpURL(origin).absoluteString }
                return [try preparedSource(code: SourceFormats.vodScript(config, title: name, origin: origin), origin: origin)]
            }
        }
        if trimmed.hasPrefix("<"), trimmed.contains("<list"), trimmed.contains("<video") || trimmed.contains("<class") {
            return [try preparedSource(code: SourceFormats.vodScript(["api": try SourceFormats.httpURL(origin).absoluteString], title: name, origin: origin), origin: origin)]
        }
        let script = try await SourceFormats.decodeScript(trimmed)
        return [try preparedSource(code: script, origin: origin)]
    }
    /// Kept for existing callers restoring local backups; async UI calls the
    /// unified importer above so encrypted sources and collections can fetch.
    func importFile(_ url: URL) throws {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard data.count <= 32 * 1024 * 1024, let text = String(data: data, encoding: .utf8) else { throw AppFailure("文件必须是 32 MB 以内的 UTF-8 文件") }
        if let object = try? jsonObject(text) as? [String: Any], isBackup(object) { try restoreBackup(object) }
        else if SourceFormats.clean(text).hasPrefix("#EXTM3U") { try install(code: SourceFormats.m3uScript(text, title: url.deletingPathExtension().lastPathComponent, origin: url.absoluteString), origin: url.absoluteString) }
        else if let object = try? jsonObject(text) as? [String: Any], object["api"] is String { try install(code: SourceFormats.vodScript(object, title: url.deletingPathExtension().lastPathComponent, origin: url.absoluteString), origin: url.absoluteString) }
        else { try install(code: text, origin: url.absoluteString) }
    }
    func refreshSubscriptions() async throws {
        for subscription in subscriptions { try await importURL(subscription.url) }
    }
    func refresh(_ source: ScriptSource) async throws { try await importURL(source.origin) }
    func removeSubscription(_ subscription: SourceSubscription) {
        subscriptions.removeAll { $0.id == subscription.id }; saveSubscriptions()
    }
    private func saveSubscriptions() {
        do { try JSONEncoder().encode(subscriptions).write(to: directory.appendingPathComponent("subscriptions.json"), options: .atomic) }
        catch { self.error = error.localizedDescription }
    }
    private func isBackup(_ object: [String: Any]) -> Bool {
        ["webox-ios", "webox-ordinary"].contains(string(object["format"])) || object["exportedAt"] != nil && object["sources"] != nil && object["settings"] != nil
    }
    private func restoreBackup(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        guard data.count <= 32 * 1024 * 1024, (object["version"] as? Int) == 1 else { throw AppFailure("不支持的备份版本或备份过大") }
        if string(object["format"]) == "webox-ios" {
            let backup = try JSONDecoder().decode(Backup.self, from: data)
            guard Set(backup.sources.map(\.id)).count == backup.sources.count else { throw AppFailure("备份含重复内容源") }
            for source in backup.sources { let runtime = try ScriptRuntime(source: source); runtime.close() }
            mergeSources(backup.sources)
            mergeSaved(backup.favorites, history: false); mergeSaved(backup.history, history: true)
            if let raw = object["androidPreferences"] as? [String: Any] { androidPreferences = raw; saveAndroidPreferences() }
            if let host = object["hostSettings"] as? [String: String] { restoreHostSettings(host) }
            if let subscriptionsObject = object["subscriptions"] { subscriptions = try JSONDecoder().decode([SourceSubscription].self, from: JSONSerialization.data(withJSONObject: subscriptionsObject)); saveSubscriptions() }
            save(); return
        }
        var imported: [ScriptSource] = [], restoredFavorites: [SavedItem] = [], restoredHistory: [SavedItem] = [], identities: [String: String] = [:]
        if string(object["format"]) == "webox-ordinary" {
            let modules = object["modules"] as? [[String: Any]] ?? []
            guard modules.count <= 1000 else { throw AppFailure("备份条目过多") }
            for module in modules {
                let source = try preparedSource(code: string(module["script"]), origin: string(module["sourceUrl"]), settings: module["parameters"] as? [String: String] ?? [:])
                imported.append(source); identities[source.id] = source.id
            }
            for row in object["vod"] as? [[String: Any]] ?? [] {
                let code = try SourceFormats.vodScript(["api": string(row["url"]), "name": string(row["title"])], title: string(row["title"]), origin: string(row["url"]))
                let source = try preparedSource(code: code, origin: string(row["url"]))
                imported.append(source); identities["vod:" + string(row["id"])] = source.id
            }
            for row in object["m3u"] as? [[String: Any]] ?? [] {
                let record = row["record"] as? [String: Any] ?? [:]
                let code = try SourceFormats.m3uScript(string(row["playlist"]), title: string(record["title"]), origin: string(record["url"]))
                let source = try preparedSource(code: code, origin: string(record["url"]))
                imported.append(source); identities["m3u:" + string(record["id"])] = source.id
            }
            let preferences = object["preferences"] as? [String: Any] ?? [:]
            for value in (preferences["favorites"] as? [String: Any] ?? [:]).values {
                guard let raw = value as? String, let row = try jsonObject(raw) as? [String: Any] else { throw AppFailure("Android 收藏记录格式无效") }
                let originalID = string(row["module"])
                restoredFavorites.append(SavedItem(sourceID: identities[originalID] ?? originalID, item: ContentItem(row)))
            }
            for row in object["visits"] as? [[String: Any]] ?? [] {
                guard let entry = row["entry"] as? [String: Any] else { continue }
                let originalID = string(row["source"])
                restoredHistory.append(SavedItem(sourceID: identities[originalID] ?? originalID, item: ContentItem(entry)))
            }
            // Preserve Android-only preferences/rules verbatim in a sidecar, so
            // importing and re-exporting never silently discards foreign data.
            var raw = preferences
            raw["unmappedRules"] = object["rules"] ?? []
            raw["playback_history"] = preferences["playback_history"] ?? [:]
            androidPreferences = raw
            if let settings = preferences["settings"] as? [String: Any] {
                var host: [String: String] = [:]
                if let value = settings["tmdb_url"] as? String { host["webox.tmdb.service"] = value }
                if let value = settings["tmdb_key"] as? String { host["webox.tmdb.apiKey"] = value }
                restoreHostSettings(host)
            }
        } else {
            // First-edition iOS backup: sources embed scriptText/payload and use
            // kind/name/params instead of this revision's ScriptSource fields.
            for row in object["sources"] as? [[String: Any]] ?? [] {
                let kind = string(row["kind"]), origin = string(row["sourceURL"]), title = string(row["name"])
                let code: String
                if kind == "m3u" { code = try SourceFormats.m3uScript(string(row["payload"]), title: title, origin: origin) }
                else if kind == "vod", let config = try? jsonObject(string(row["payload"])) as? [String: Any] { code = try SourceFormats.vodScript(config, title: title, origin: origin) }
                else { code = string(row["scriptText"]) }
                guard !code.isEmpty else { throw AppFailure("旧版备份缺少脚本正文，请从旧版重新完整导出") }
                let source = try preparedSource(code: code, origin: origin, settings: row["params"] as? [String: String] ?? [:])
                imported.append(source); identities[string(row["id"])] = source.id
            }
            for row in object["favorites"] as? [[String: Any]] ?? [] {
                guard var item = row["item"] as? [String: Any] else { continue }
                if item["link"] == nil { item["link"] = row["link"] }
                let originalID = string(row["sourceID"])
                restoredFavorites.append(SavedItem(sourceID: identities[originalID] ?? originalID, item: ContentItem(item)))
            }
            if let settings = object["settings"] as? [String: Any] {
                var host: [String: String] = [:]
                for (old, new) in [("tmdbService", "webox.tmdb.service"), ("tmdbAPIKey", "webox.tmdb.apiKey"), ("catalogLanguage", "webox.tmdb.language")] { if let value = settings[old] as? String { host[new] = value } }
                restoreHostSettings(host)
            }
        }
        guard Set(imported.map(\.id)).count == imported.count else { throw AppFailure("备份含重复内容源") }
        mergeSources(imported); mergeSaved(restoredFavorites, history: false); mergeSaved(restoredHistory, history: true)
        saveAndroidPreferences(); save()
    }
    private func mergeSaved(_ incoming: [SavedItem], history isHistory: Bool) {
        for item in incoming {
            if isHistory { history.removeAll { $0.id == item.id }; history.append(item) }
            else { favorites.removeAll { $0.id == item.id }; favorites.append(item) }
        }
        if isHistory { history.sort { $0.date > $1.date }; history = Array(history.prefix(200)) }
    }
    private func saveAndroidPreferences() {
        do { try JSONSerialization.data(withJSONObject: androidPreferences).write(to: directory.appendingPathComponent("android-preferences.json"), options: .atomic) }
        catch { self.error = error.localizedDescription }
    }
    private func restoreHostSettings(_ host: [String: String]) {
        let allowed = ["webox.tmdb.service", "webox.tmdb.apiKey", "webox.tmdb.language"]
        for (key, value) in host where allowed.contains(key) { UserDefaults.standard.set(value, forKey: key) }
    }
    func remove(_ source: ScriptSource) { sources.removeAll { $0.id == source.id }; save() }
    func updateSettings(_ id: String, values: [String: String]) {
        guard let index = sources.firstIndex(where: { $0.id == id }) else { return }
        sources[index].settings = values; save()
    }
    func isFavorite(_ item: ContentItem, sourceID: String) -> Bool { favorites.contains { $0.sourceID == sourceID && $0.item.id == item.id } }
    func toggleFavorite(_ item: ContentItem, sourceID: String) {
        if isFavorite(item, sourceID: sourceID) { favorites.removeAll { $0.sourceID == sourceID && $0.item.id == item.id } }
        else { favorites.insert(SavedItem(sourceID: sourceID, item: item), at: 0) }
        save()
    }
    func record(_ item: ContentItem, sourceID: String, position: Double) {
        history.removeAll { $0.sourceID == sourceID && $0.item.id == item.id }
        history.insert(SavedItem(sourceID: sourceID, item: item, position: position.isFinite ? max(0, position) : 0), at: 0)
        history = Array(history.prefix(200)); save()
    }
    func position(_ item: ContentItem, sourceID: String) -> Double { history.first { $0.sourceID == sourceID && $0.item.id == item.id }?.position ?? 0 }
    func clearHistory() { history.removeAll(); save() }
    func exportBackup() throws -> URL {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let encoded = try encoder.encode(Backup(sources: sources, favorites: favorites, history: history))
        var object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        object["androidPreferences"] = androidPreferences
        object["hostSettings"] = Dictionary(uniqueKeysWithValues: ["webox.tmdb.service", "webox.tmdb.apiKey", "webox.tmdb.language"].compactMap { key in UserDefaults.standard.string(forKey: key).map { (key, $0) } })
        object["subscriptions"] = try JSONSerialization.jsonObject(with: encoder.encode(subscriptions))
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("WeBox-iOS-backup.json")
        try data.write(to: url, options: .atomic); return url
    }
    private func save() {
        do { try JSONEncoder().encode(Backup(sources: sources, favorites: favorites, history: history)).write(to: directory.appendingPathComponent("library.json"), options: .atomic) }
        catch { self.error = "保存失败：\(error.localizedDescription)" }
    }
    var downloadsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Downloads", isDirectory: true)
    }
    func localURL(_ record: DownloadRecord) -> URL { downloadsDirectory.appendingPathComponent(record.filename) }
    func download(_ source: PlaySource, title: String) {
        guard downloadTask == nil else { error = "已有下载正在进行"; return }
        guard source.downloadable, ["mp4", "mov", "m4v"].contains(source.url.pathExtension.lowercased()) else { error = "当前支持 MP4/MOV/M4V 直链下载；HLS、直播与媒体处理线路暂不支持"; return }
        downloadStatus = "正在下载 \(title)…"
        downloadTask = Task {
            defer { downloadTask = nil; downloadStatus = nil }
            do {
                var request = URLRequest(url: source.url); request.allHTTPHeaderFields = source.headers
                let (file, response) = try await URLSession.shared.download(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw AppFailure("下载失败") }
                try Task.checkCancellation()
                try FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
                let name = UUID().uuidString + "." + source.url.pathExtension.lowercased()
                try FileManager.default.moveItem(at: file, to: downloadsDirectory.appendingPathComponent(name))
                downloads.insert(DownloadRecord(title: title, filename: name), at: 0); saveDownloads()
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    func cancelDownload() { downloadTask?.cancel() }
    func removeDownload(_ record: DownloadRecord) {
        do { try FileManager.default.removeItem(at: localURL(record)); downloads.removeAll { $0.id == record.id }; saveDownloads() }
        catch { self.error = error.localizedDescription }
    }
    private func saveDownloads() {
        do { try JSONEncoder().encode(downloads).write(to: directory.appendingPathComponent("downloads.json"), options: .atomic) }
        catch { self.error = error.localizedDescription }
    }
}
