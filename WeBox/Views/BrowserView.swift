import SwiftUI

struct BrowserView: View {
    @EnvironmentObject private var library: LibraryStore
    @StateObject private var model: BrowserModel
    @State private var filtering = false
    init(source: ScriptSource) { _model = StateObject(wrappedValue: BrowserModel(source: source)) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if model.modules.count > 1 {
                    Picker("栏目", selection: $model.selectedModule) {
                        ForEach(model.modules) { Text($0.title).tag($0.id) }
                    }.pickerStyle(.menu).disabled(model.busy)
                    .onChange(of: model.selectedModule) { _, _ in Task { await model.changeModule() } }
                }
                if let error = model.error {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        Button("重试") { Task { if model.modules.isEmpty { model.close(); await model.start() } else { await model.load(reset: true) } } }
                    }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                }
                if !model.busy && model.items.isEmpty && model.error == nil { ContentUnavailableView("暂无内容", systemImage: "rectangle.stack", description: Text("尝试更换分类、筛选或搜索词")) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145, maximum: 230), spacing: 16)], spacing: 24) {
                    ForEach(model.items) { item in
                        NavigationLink { DetailView(source: library.source(model.source.id) ?? model.source, item: item) } label: {
                            VStack(alignment: .leading, spacing: 9) {
                                PosterView(address: item.poster).frame(height: 215).clipShape(RoundedRectangle(cornerRadius: 14))
                                Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(2).foregroundStyle(.primary)
                                if !item.summary.isEmpty { Text(item.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                            }
                        }.buttonStyle(.plain)
                    }
                }
                if model.busy { ProgressView("正在读取内容源…").frame(maxWidth: .infinity).padding() }
                if model.hasMore && !model.busy { Button("加载更多") { Task { await model.load(reset: false) } }.buttonStyle(.bordered).frame(maxWidth: .infinity) }
            }.padding()
        }
        .navigationTitle(model.source.title).navigationBarTitleDisplayMode(.inline)
        .searchable(text: $model.query, prompt: model.searchable ? "搜索当前内容源" : "此源暂不支持搜索")
        .onSubmit(of: .search) { Task { await model.load(reset: true) } }
        .onChange(of: model.query) { old, value in
            if !old.isEmpty && value.isEmpty { Task { await model.load(reset: true) } }
        }
        .refreshable { await model.load(reset: true) }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !model.filterDefinitions.isEmpty { Button("筛选", systemImage: "line.3.horizontal.decrease.circle") { filtering = true }.disabled(model.busy) }
                NavigationLink { SourceSettingsView(source: library.source(model.source.id) ?? model.source) } label: { Image(systemName: "slider.horizontal.3") }
            }
        }
        .sheet(isPresented: $filtering) {
            NavigationStack {
                Form { ForEach(model.filterDefinitions) { parameter in
                    ParameterField(parameter: parameter, value: Binding(get: { model.parameters[parameter.id] ?? parameter.value }, set: { model.parameters[parameter.id] = $0 }))
                } }.navigationTitle("筛选")
                .toolbar { Button("应用") { filtering = false; Task { await model.load(reset: true) } } }
            }.presentationDetents([.medium, .large])
        }
        .task { model.source = library.source(model.source.id) ?? model.source; await model.start() }
        // A browser remains alive under a detail route so native cursor pagination survives navigation.
    }
}

struct DetailView: View {
    @EnvironmentObject private var library: LibraryStore
    @StateObject private var model: DetailModel
    @State private var playback: PlaybackSelection?
    init(source: ScriptSource, item: ContentItem) { _model = StateObject(wrappedValue: DetailModel(source: source, item: item)) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 20) {
                    PosterView(address: model.detail.poster).frame(width: 120, height: 170).clipShape(RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 12) {
                        Text(model.detail.title).font(.title2.bold())
                        Text(model.source.title).font(.caption).foregroundStyle(.mint)
                        Button {
                            library.toggleFavorite(model.detail, sourceID: model.source.id)
                        } label: {
                            Label(library.isFavorite(model.detail, sourceID: model.source.id) ? "已收藏" : "收藏", systemImage: library.isFavorite(model.detail, sourceID: model.source.id) ? "heart.fill" : "heart")
                        }.buttonStyle(.bordered)
                    }
                }
                if !model.detail.summary.isEmpty { Text(model.detail.summary).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled) }
                if model.busy { ProgressView("正在加载…") }
                if let error = model.error { Text(error).foregroundStyle(.orange).font(.callout) }
                if model.detail.children.isEmpty && !model.busy {
                    Button { Task { await model.resolve(model.detail) } } label: { Label("获取播放线路", systemImage: "play.fill").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent)
                }
                let groups = Array(Set(model.detail.children.map(\.group))).sorted()
                ForEach(groups, id: \.self) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(group.isEmpty ? "选集" : group).font(.headline)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 10) {
                            ForEach(model.detail.children.filter { $0.group == group }) { episode in
                                Button(episode.title) { Task { await model.resolve(episode) } }.buttonStyle(.bordered).disabled(model.busy)
                            }
                        }
                    }
                }
                if !model.streams.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("播放线路").font(.headline)
                        ForEach(model.streams) { source in
                            HStack {
                                Button { playback = PlaybackSelection(source: source, item: model.selectedEpisode ?? model.detail) } label: { Label(source.name, systemImage: "play.circle.fill").frame(maxWidth: .infinity, alignment: .leading) }
                                if source.downloadable && !(model.selectedEpisode?.isLive ?? model.detail.isLive) {
                                    Button { library.download(source, title: model.detail.title + " · " + (model.selectedEpisode?.title ?? "")) } label: { Image(systemName: "arrow.down.circle") }
                                }
                            }.padding().background(.mint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }.padding()
        }.navigationTitle("详情").navigationBarTitleDisplayMode(.inline)
        .task { await model.start() }
        .fullScreenCover(item: $playback) { selection in
            PlayerScreen(selection: selection, sourceID: model.source.id).environmentObject(library)
        }
        .onDisappear { if playback == nil { model.close() } }
    }
}
