import Foundation

@MainActor
final class BrowserModel: ObservableObject {
    @Published var modules: [ScriptModule] = []
    @Published var selectedModule = ""
    @Published var parameters: [String: String] = [:]
    @Published var filterDefinitions: [ScriptParameter] = []
    @Published var items: [ContentItem] = []
    @Published var busy = false
    @Published var error: String?
    @Published var hasMore = false
    @Published var query = ""
    private(set) var runtime: ScriptRuntime?
    private var page = 1
    private var activeQuery = ""
    private var offset = 0
    private var generation = 0
    var source: ScriptSource
    init(source: ScriptSource) { self.source = source }
    var selected: ScriptModule? { modules.first { $0.id == selectedModule } }
    var searchable: Bool { runtime?.searchModule != nil }

    func start() async {
        guard runtime == nil else { return }
        busy = true
        do {
            let engine = try ScriptRuntime(source: source); runtime = engine
            try await engine.configure()
            modules = engine.modules
            selectedModule = modules.first?.id ?? ""
            resetParameters()
            busy = false
            await load(reset: true)
        } catch { self.error = error.localizedDescription; busy = false }
    }
    func resetParameters() {
        parameters = source.settings
        filterDefinitions = selected?.parameters.filter { !["page", "offset", "input"].contains($0.type) } ?? []
        for parameter in selected?.parameters ?? [] where parameters[parameter.id] == nil { parameters[parameter.id] = parameter.value }
    }
    func changeModule() async { resetParameters(); await load(reset: true) }
    func load(reset: Bool) async {
        guard !busy, let runtime else { return }
        let requestedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let module = requestedQuery.isEmpty ? selected : runtime.searchModule
        guard let module else { error = "内容源没有提供此浏览或搜索功能"; return }
        if !reset && activeQuery != requestedQuery { return }
        busy = true; error = nil
        if reset { page = 1; offset = 0; items = []; activeQuery = requestedQuery; hasMore = false; generation += 1 }
        let token = generation
        var values = parameters
        for p in module.parameters {
            if p.type == "page" { values[p.id] = String(page) }
            else if p.type == "offset" { values[p.id] = String(offset) }
            else if values[p.id] == nil { values[p.id] = p.value }
        }
        values["keyword"] = activeQuery
        values["page"] = String(page); values["__wb_page"] = String(page); values["offset"] = String(offset)
        do {
            let response = try await runtime.invoke(module.function, arguments: [values])
            guard token == generation else { return }
            let object = response as? [String: Any]
            guard let rows = response as? [[String: Any]] ?? object?["items"] as? [[String: Any]] ?? object?["list"] as? [[String: Any]] else { throw AppFailure("内容源没有返回有效列表") }
            let incoming = rows.map(ContentItem.init)
            var seen = Set(items.map(\.id))
            let additions = incoming.filter { seen.insert($0.id).inserted }
            items.append(contentsOf: additions)
            hasMore = (object?["hasMore"] as? Bool ?? (incoming.count >= 30)) && !additions.isEmpty
            page += 1; offset += (object?["rawCount"] as? Int ?? incoming.count)
            if let filters = object?["filters"] as? [[String: Any]] {
                let parsed = filters.map(ScriptParameter.init)
                // Dynamic filters supplement fixed module parameters.
                for p in parsed where parameters[p.id] == nil { parameters[p.id] = p.value }
                filterDefinitions = (selected?.parameters.filter { !["page", "offset", "input"].contains($0.type) } ?? []).filter { p in !parsed.contains { $0.id == p.id } } + parsed
            }
        } catch { if token == generation { self.error = error.localizedDescription } }
        busy = false
    }
    func close() { generation += 1; runtime?.close(); runtime = nil; busy = false }
}

@MainActor
final class DetailModel: ObservableObject {
    @Published var detail: ContentItem
    @Published var busy = false
    @Published var error: String?
    @Published var streams: [PlaySource] = []
    @Published var selectedEpisode: ContentItem?
    private var runtime: ScriptRuntime?
    let source: ScriptSource
    init(source: ScriptSource, item: ContentItem) { self.source = source; detail = item }
    func start() async {
        guard runtime == nil else { return }
        busy = true
        do {
            let engine = try ScriptRuntime(source: source); runtime = engine
            try await engine.configure()
            if detail.link.hasPrefix("webox:episode:") || detail.link.hasPrefix("compat-play:") { busy = false; return }
            let function = string(engine.metadata["hostProtocol"]) == "webox" ? "__wbDetail" : "loadDetail"
            let result = try await engine.invoke(function, arguments: [detail.link])
            if let object = result as? [String: Any] {
                let loaded = ContentItem(object)
                if !loaded.title.isEmpty { detail.title = loaded.title }
                if !loaded.poster.isEmpty { detail.poster = loaded.poster }
                if !loaded.summary.isEmpty { detail.summary = loaded.summary }
                if !loaded.videoURL.isEmpty { detail.videoURL = loaded.videoURL }
                detail.children = loaded.children
            } else if let rows = result as? [[String: Any]] { detail.children = rows.map(ContentItem.init) }
            else { throw AppFailure("详情数据格式不受支持") }
        } catch { self.error = error.localizedDescription }
        busy = false
    }
    func resolve(_ episode: ContentItem) async {
        guard !busy, let runtime else { return }
        busy = true; error = nil; selectedEpisode = episode
        do {
            if !episode.videoURL.isEmpty { streams = [try PlaySource(["url": episode.videoURL, "name": "直接播放"])] }
            else {
                let host = string(runtime.metadata["hostProtocol"])
                let definitions = runtime.metadata["modules"] as? [[String: Any]] ?? []
                let function = host == "webox" ? "__wbPlay" : string(definitions.first { string($0["type"]) == "stream" }?["functionName"])
                var params = source.settings; params["link"] = episode.link; params["id"] = episode.id
                let result = try await runtime.invoke(function.isEmpty ? "loadResource" : function, arguments: [params])
                let rows = result as? [[String: Any]] ?? (result as? [String: Any])?["sources"] as? [[String: Any]] ?? (result as? [String: Any]).map { [$0] } ?? []
                var accepted: [PlaySource] = [], failures: [String] = []
                for row in rows { do { var stream = try PlaySource(row); stream.runtime = runtime; accepted.append(stream) } catch { failures.append(error.localizedDescription) } }
                guard !accepted.isEmpty else { throw AppFailure(failures.first ?? "内容源未返回播放线路") }
                streams = accepted
            }
        } catch { self.error = error.localizedDescription }
        busy = false
    }
    func close() { runtime?.close(); runtime = nil }
}
