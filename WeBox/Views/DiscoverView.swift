import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var selectedSourceID: String?
    @State private var importing = false
    @State private var searching = false
    private var selectedSource: ScriptSource? { library.sources.first { $0.id == selectedSourceID } ?? library.sources.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                if library.sources.isEmpty {
                    ContentUnavailableView {
                        Label("从一个内容源开始", systemImage: "square.stack.3d.up")
                    } description: { Text("导入你的内容源，建立属于自己的影视库。") }
                    actions: { Button("添加内容源") { importing = true }.buttonStyle(.borderedProminent) }
                    .padding(.vertical, 30)
                } else {
                    sourcePicker
                    if let source = selectedSource {
                        DiscoverCatalogView(source: source)
                            .id(source.id + source.version + String(source.installedAt.timeIntervalSince1970))
                    }
                    if !library.history.isEmpty { continueWatching }
                    if !library.favorites.isEmpty { favorites }
                }
            }.padding(.horizontal, WeBoxTheme.gutter).padding(.top, 12).padding(.bottom, 30)
        }
        .background(WeBoxTheme.background)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $importing) { ImportSourceView() }
        .sheet(isPresented: $searching) { GlobalSearchView() }
        .accessibilityIdentifier("discover.home")
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("WeBox").font(.largeTitle.bold()).tracking(-0.8)
                    Text("发现喜欢的影视，留住想看的故事。").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button { importing = true } label: {
                    Image(systemName: "plus").font(.title3.weight(.semibold)).frame(width: 44, height: 44)
                        .background(WeBoxTheme.card, in: Circle())
                }.accessibilityLabel("添加内容源")
            }
            Button { searching = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                    Text("搜索电影、剧集").font(.body)
                    Spacer()
                    Text("全部内容源").font(.caption)
                }.foregroundStyle(.secondary).padding(.horizontal, 16).frame(minHeight: 50)
                    .background(WeBoxTheme.card, in: RoundedRectangle(cornerRadius: WeBoxTheme.radius))
            }.buttonStyle(.plain).accessibilityIdentifier("search.global")
        }
    }
    private var sourcePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading("我的内容源") {
                NavigationLink { SourcesView() } label: { Text("管理") }
                    .accessibilityIdentifier("source.manage")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(library.sources) { source in
                        Button { selectedSourceID = source.id } label: {
                            SourceChip(title: source.title, selected: source.id == selectedSource?.id)
                        }.buttonStyle(.plain)
                    }
                }
            }.contentMargins(.vertical, 1)
        }
    }
    private var continueWatching: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading("继续观看") { NavigationLink("全部") { SavedListView(history: true) } }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(library.history.prefix(8))) { saved in
                        if let source = library.source(saved.sourceID) {
                            NavigationLink { DetailView(source: source, item: saved.item) } label: {
                                HStack(spacing: 12) {
                                    PosterView(address: saved.item.poster).frame(width: 52, height: 74).clipShape(RoundedRectangle(cornerRadius: 10))
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(saved.item.title).font(.subheadline.bold()).foregroundStyle(.primary).lineLimit(2)
                                        Text(source.title).font(.caption).foregroundStyle(.secondary)
                                        Label("已看到 \(Int(saved.position / 60)) 分钟", systemImage: "play.fill").font(.caption2).foregroundStyle(WeBoxTheme.accent)
                                    }
                                    Spacer(minLength: 0)
                                }.padding(12).frame(width: 245, alignment: .leading)
                                    .background(WeBoxTheme.card, in: RoundedRectangle(cornerRadius: WeBoxTheme.radius))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
    private var favorites: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading("想看的故事") { NavigationLink("全部收藏") { SavedListView(history: false) } }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(library.favorites.prefix(10))) { saved in
                        if let source = library.source(saved.sourceID) {
                            NavigationLink { DetailView(source: source, item: saved.item) } label: { MediaPosterCard(item: saved.item).frame(width: 110) }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

private struct DiscoverCatalogView: View {
    @StateObject private var model: BrowserModel
    init(source: ScriptSource) { _model = StateObject(wrappedValue: BrowserModel(source: source)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(model.source.title) {
                NavigationLink("配置") { SourceSettingsView(source: model.source) }
                NavigationLink { BrowserView(source: model.source) } label: { Text("浏览全部"); Image(systemName: "chevron.right").font(.caption.bold()) }
            }
            if model.busy && model.items.isEmpty {
                HStack(spacing: 10) { ProgressView(); Text("正在为你展开片单…").font(.subheadline).foregroundStyle(.secondary) }
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else if let error = model.error, model.items.isEmpty {
                InlineErrorView(message: error) { Task { model.close(); await model.start() } }
            } else if model.items.isEmpty {
                ContentUnavailableView("暂无内容", systemImage: "rectangle.stack", description: Text("进入内容源选择其他栏目或调整筛选。"))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 170), spacing: 12)], alignment: .leading, spacing: 18) {
                    ForEach(Array(model.items.prefix(6))) { item in
                        NavigationLink { DetailView(source: model.source, item: item) } label: { MediaPosterCard(item: item) }.buttonStyle(.plain)
                    }
                }
            }
        }.task { await model.start() }
        .onDisappear { model.close() }
    }
}

struct GlobalSearchGroup: Identifiable {
    let source: ScriptSource
    var items: [ContentItem] = []
    var error: String?
    var id: String { source.id }
}
@MainActor
final class GlobalSearchModel: ObservableObject {
    @Published var groups: [GlobalSearchGroup] = []
    @Published var busy = false
    private var generation = 0
    private var engine: ScriptRuntime?
    func search(_ query: String, sources: [ScriptSource]) async {
        cancel()
        let token = generation
        groups = []; busy = true
        for source in sources {
            guard token == generation, !Task.isCancelled else { break }
            var group = GlobalSearchGroup(source: source)
            do {
                let runtime = try ScriptRuntime(source: source); engine = runtime
                defer { runtime.close(); engine = nil }
                try await runtime.configure()
                guard let module = runtime.searchModule else { group.error = "此内容源不提供搜索"; groups.append(group); continue }
                var params = source.settings
                for field in module.parameters { params[field.id] = params[field.id] ?? field.value }
                params["keyword"] = query; params["page"] = "1"; params["__wb_page"] = "1"; params["offset"] = "0"
                let result = try await runtime.invoke(module.function, arguments: [params])
                let object = result as? [String: Any]
                let rows = result as? [[String: Any]] ?? object?["items"] as? [[String: Any]] ?? object?["list"] as? [[String: Any]] ?? []
                group.items = rows.map(ContentItem.init)
            } catch { group.error = error.localizedDescription }
            if token == generation { groups.append(group) }
        }
        if token == generation { busy = false }
    }
    func cancel() { generation += 1; engine?.close(); engine = nil; busy = false }
}
struct GlobalSearchView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = GlobalSearchModel()
    @State private var query = ""
    @State private var selectedSources: Set<String> = []
    @State private var task: Task<Void, Never>?
    var body: some View {
        NavigationStack {
            content
                .navigationTitle("搜索").navigationBarTitleDisplayMode(.inline)
                .searchable(text: $query, prompt: "电影、剧集或关键词")
                .onSubmit(of: .search, perform: submit)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
                .onAppear { selectedSources = Set(library.sources.map(\.id)) }
                .onDisappear { task?.cancel(); model.cancel() }
        }
    }
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                sourceChoices
                if model.groups.isEmpty && !model.busy {
                    ContentUnavailableView("下一部，想看什么？", systemImage: "magnifyingglass", description: Text("选择内容源，输入片名后开始搜索。"))
                }
                ForEach(model.groups) { group in GlobalSearchResultSection(group: group) }
                if model.busy {
                    HStack { ProgressView(); Text("正在搜索内容源…"); Spacer(); Button("停止") { task?.cancel(); model.cancel() } }.font(.subheadline)
                }
            }.padding(WeBoxTheme.gutter)
        }.background(WeBoxTheme.background)
    }
    private var sourceChoices: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(library.sources) { source in
                    Button { toggleSource(source.id) } label: { SourceChip(title: source.title, selected: selectedSources.contains(source.id)) }.buttonStyle(.plain)
                }
            }
        }
    }
    private func toggleSource(_ id: String) {
        if selectedSources.contains(id) { selectedSources.remove(id) } else { selectedSources.insert(id) }
    }
    private func submit() {
        let word = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }
        task?.cancel()
        let sources = library.sources.filter { selectedSources.contains($0.id) }
        task = Task { await model.search(word, sources: sources) }
    }
}

private struct GlobalSearchResultSection: View {
    let group: GlobalSearchGroup
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(group.source.title) { Text("\(group.items.count) 项").foregroundStyle(.secondary) }
            if let error = group.error { Text(error).font(.subheadline).foregroundStyle(.secondary) }
            else if group.items.isEmpty { Text("没有找到相关内容").font(.subheadline).foregroundStyle(.secondary) }
            else {
                ForEach(group.items) { item in
                    NavigationLink { DetailView(source: group.source, item: item) } label: { MediaListRow(item: item, subtitle: item.summary) }.buttonStyle(.plain)
                }
            }
        }
    }
}
