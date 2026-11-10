import Foundation
import CryptoKit
import SwiftUI

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var sources: [ScriptSource] = []
    @Published private(set) var favorites: [SavedItem] = []
    @Published private(set) var history: [SavedItem] = []
    @Published private(set) var downloads: [DownloadRecord] = []
    @Published var error: String?
    @Published var downloadStatus: String?
    private let directory: URL
    private var downloadTask: Task<Void, Never>?

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
            let records = self.directory.appendingPathComponent("downloads.json")
            if FileManager.default.fileExists(atPath: records.path) { downloads = try JSONDecoder().decode([DownloadRecord].self, from: Data(contentsOf: records)) }
        } catch { self.error = "读取资料失败，原文件已保留：\(error.localizedDescription)" }
    }
    func source(_ id: String) -> ScriptSource? { sources.first { $0.id == id } }
    func install(code: String, origin: String) throws {
        guard code.utf8.count <= 4 * 1024 * 1024 else { throw AppFailure("脚本超过 4 MB") }
        if code.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("REXENC") { throw AppFailure("当前版暂不支持 REXENC 加密源，请导入明文 JS 内容源") }
        let identityInput = origin == "pasted" ? code : origin
        let identity = "script." + SHA256.hash(data: Data(identityInput.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        let temporary = ScriptSource(id: identity, title: "", version: "", code: code, origin: origin)
        let runtime = try ScriptRuntime(source: temporary)
        defer { runtime.close() }
        let id = string(runtime.metadata["id"])
        let existing = source(id)
        let installed = ScriptSource(id: id, title: string(runtime.metadata["title"]), version: string(runtime.metadata["version"]), code: code, origin: origin, settings: existing?.settings ?? [:])
        if let index = sources.firstIndex(where: { $0.id == id }) { sources[index] = installed }
        else { sources.append(installed) }
        save()
    }
    func importURL(_ address: String) async throws {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { throw AppFailure("请输入 HTTP(S) 内容源地址") }
        var request = URLRequest(url: url); request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw AppFailure("内容源下载失败") }
        guard data.count <= 4 * 1024 * 1024, let text = String(data: data, encoding: .utf8) else { throw AppFailure("内容源必须是 4 MB 以内的 UTF-8 文件") }
        try install(code: text, origin: address)
    }
    func importFile(_ url: URL) throws {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard data.count <= 32 * 1024 * 1024 else { throw AppFailure("导入文件超过 32 MB") }
        if url.pathExtension.lowercased() == "json" {
            let backup = try JSONDecoder().decode(Backup.self, from: data)
            guard backup.format == "webox-ios", backup.version == 1 else { throw AppFailure("此备份格式暂不支持；Android 备份尚未适配") }
            guard Set(backup.sources.map(\.id)).count == backup.sources.count else { throw AppFailure("备份含重复内容源") }
            for source in backup.sources {
                guard source.code.utf8.count <= 4 * 1024 * 1024 else { throw AppFailure("备份中脚本超过 4 MB") }
                let runtime = try ScriptRuntime(source: source); runtime.close()
            }
            // Merge imported records; preserve local entries unless the imported identity matches.
            for source in backup.sources { sources.removeAll { $0.id == source.id }; sources.append(source) }
            for item in backup.favorites { favorites.removeAll { $0.id == item.id }; favorites.append(item) }
            for item in backup.history { history.removeAll { $0.id == item.id }; history.append(item) }
            history.sort { $0.date > $1.date }; save()
        } else {
            guard let code = String(data: data, encoding: .utf8) else { throw AppFailure("请选择 UTF-8 JavaScript 文件") }
            try install(code: code, origin: url.lastPathComponent)
        }
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
        let data = try encoder.encode(Backup(sources: sources, favorites: favorites, history: history))
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
