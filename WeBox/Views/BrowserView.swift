import SwiftUI

struct BrowserView: View {
    @EnvironmentObject private var library: LibraryStore
    @StateObject private var model: BrowserModel
    @State private var filtering = false
    init(source: ScriptSource) { _model = StateObject(wrappedValue: BrowserModel(source: source)) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                browseControls
                if let error = model.error {
                    InlineErrorView(message: error) { Task { await retry() } }
                }
                if !model.busy && model.items.isEmpty && model.error == nil {
                    ContentUnavailableView("这里还没有内容", systemImage: "rectangle.stack", description: Text("换一个栏目，或调整筛选条件再试。"))
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 190), spacing: 12)], alignment: .leading, spacing: 20) {
                    ForEach(model.items) { item in
                        NavigationLink { DetailView(source: library.source(model.source.id) ?? model.source, item: item) } label: { MediaPosterCard(item: item) }.buttonStyle(.plain)
                    }
                }
                if model.busy { ProgressView("正在加载片单…").frame(maxWidth: .infinity).padding(.vertical, 28) }
                if model.hasMore && !model.busy {
                    Button { Task { await model.load(reset: false) } } label: { Text("加载更多").frame(maxWidth: .infinity).frame(minHeight: 44) }.buttonStyle(.bordered)
                }
            }.padding(WeBoxTheme.gutter)
        }
        .background(WeBoxTheme.background)
        .navigationTitle(model.source.title).navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .searchable(text: $model.query, prompt: model.searchable ? "搜索当前内容源" : "此内容源没有搜索功能")
        .onSubmit(of: .search) { Task { await model.load(reset: true) } }
        .onChange(of: model.query) { old, value in if !old.isEmpty && value.isEmpty { Task { await model.load(reset: true) } } }
        .refreshable { await model.load(reset: true) }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !model.filterDefinitions.isEmpty { Button("筛选", systemImage: "line.3.horizontal.decrease.circle") { filtering = true }.disabled(model.busy) }
                NavigationLink { SourceSettingsView(source: library.source(model.source.id) ?? model.source) } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("内容源配置")
            }
        }
        .sheet(isPresented: $filtering) {
            NavigationStack {
                Form { ForEach(model.filterDefinitions) { parameter in
                    ParameterField(parameter: parameter, value: Binding(get: { model.parameters[parameter.id] ?? parameter.value }, set: { model.parameters[parameter.id] = $0 }))
                } }.navigationTitle("筛选").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { filtering = false } }
                    ToolbarItem(placement: .confirmationAction) { Button("应用") { filtering = false; Task { await model.load(reset: true) } }.bold() }
                }
            }.presentationDetents([.medium, .large])
        }
        .task { model.source = library.source(model.source.id) ?? model.source; await model.start() }
    }
    @ViewBuilder private var browseControls: some View {
        if model.modules.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { ForEach(model.modules) { module in
                    Button { model.selectedModule = module.id; Task { await model.changeModule() } } label: { SourceChip(title: module.title, selected: model.selectedModule == module.id) }.buttonStyle(.plain).disabled(model.busy)
                } }
            }
        }
        if !model.items.isEmpty {
            HStack {
                Text(model.query.isEmpty ? "全部片单" : "搜索结果").font(.title3.bold())
                Spacer()
                Text("\(model.items.count) 项").font(.caption).foregroundStyle(.secondary)
                if !model.filterDefinitions.isEmpty {
                    Button("筛选") { filtering = true }.font(.subheadline).disabled(model.busy)
                }
            }
        }
    }
    @MainActor private func retry() async {
        if model.modules.isEmpty { model.source = library.source(model.source.id) ?? model.source; model.close(); await model.start() }
        else { await model.load(reset: true) }
    }
}

struct DetailView: View {
    @EnvironmentObject private var library: LibraryStore
    @StateObject private var model: DetailModel
    @State private var playback: PlaybackSelection?
    @State private var summaryExpanded = false
    init(source: ScriptSource, item: ContentItem) { _model = StateObject(wrappedValue: DetailModel(source: source, item: item)) }
    private var episodes: [ContentItem] { model.detail.children.isEmpty ? [model.detail] : model.detail.children }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                identity
                playbackActions
                if !model.detail.summary.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("故事简介").font(.title3.bold())
                        Text(model.detail.summary).font(.subheadline).foregroundStyle(.secondary)
                            .lineLimit(summaryExpanded ? nil : 4).textSelection(.enabled)
                        Button(summaryExpanded ? "收起" : "展开简介") { withAnimation { summaryExpanded.toggle() } }.font(.subheadline)
                    }
                }
                if model.busy { ProgressView("正在获取播放信息…").frame(maxWidth: .infinity).padding(.vertical, 12) }
                if let error = model.error { InlineErrorView(message: error) }
                episodeGroups
                if !model.streams.isEmpty { playbackSources }
            }.padding(WeBoxTheme.gutter)
        }
        .background(WeBoxTheme.background)
        .navigationTitle("影片详情").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task { await model.start() }
        .fullScreenCover(item: $playback) { selection in PlayerScreen(selection: selection, sourceID: model.source.id).environmentObject(library) }
        .onDisappear { if playback == nil { model.close() } }
    }
    private var identity: some View {
        HStack(alignment: .top, spacing: 20) {
            PosterView(address: model.detail.poster).frame(width: 120, height: 180).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 12) {
                Text(model.detail.title).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                Text(model.source.title).font(.subheadline).foregroundStyle(.secondary)
                if model.detail.isLive { Label("正在直播", systemImage: "dot.radiowaves.left.and.right").font(.caption).foregroundStyle(.red) }
                Button { library.toggleFavorite(model.detail, sourceID: model.source.id) } label: {
                    Label(library.isFavorite(model.detail, sourceID: model.source.id) ? "已加入收藏" : "加入收藏", systemImage: library.isFavorite(model.detail, sourceID: model.source.id) ? "heart.fill" : "heart")
                        .font(.subheadline).frame(minHeight: 36)
                }.buttonStyle(.bordered)
                Spacer(minLength: 0)
            }.frame(minHeight: 180, alignment: .topLeading)
            Spacer(minLength: 0)
        }
    }
    private var playbackActions: some View {
        let first = episodes.first ?? model.detail
        let position = library.position(first, sourceID: model.source.id)
        return Button { Task { await play(first) } } label: {
            Label(position > 0 ? "继续观看 · \(Int(position / 60)) 分钟" : "立即播放", systemImage: "play.fill")
                .font(.headline).frame(maxWidth: .infinity).frame(minHeight: 42)
        }.buttonStyle(.borderedProminent).disabled(model.busy)
    }
    @ViewBuilder private var episodeGroups: some View {
        let groups = Array(Set(model.detail.children.map(\.group))).sorted()
        ForEach(groups, id: \.self) { group in
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(group.isEmpty ? "选集" : group) { Text("\(model.detail.children.filter { $0.group == group }.count) 集").foregroundStyle(.secondary) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                    ForEach(model.detail.children.filter { $0.group == group }) { episode in
                        Button { Task { await play(episode) } } label: {
                            Text(episode.title).font(.subheadline).lineLimit(2).frame(maxWidth: .infinity).frame(minHeight: 44)
                                .foregroundStyle(model.selectedEpisode?.id == episode.id ? WeBoxTheme.accent : Color.primary)
                                .background(model.selectedEpisode?.id == episode.id ? WeBoxTheme.accent.opacity(0.12) : WeBoxTheme.card, in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain).disabled(model.busy)
                    }
                }
            }
        }
    }
    private var playbackSources: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("播放线路").font(.title3.bold())
            VStack(spacing: 0) {
                ForEach(model.streams) { source in
                    HStack(spacing: 16) {
                        Button { playback = PlaybackSelection(source: source, item: model.selectedEpisode ?? model.detail) } label: {
                            Label(source.name, systemImage: "play.circle.fill").font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 48)
                        }
                        if source.downloadable && !(model.selectedEpisode?.isLive ?? model.detail.isLive) {
                            Button { library.download(source, title: model.detail.title + " · " + (model.selectedEpisode?.title ?? "")) } label: { Image(systemName: "arrow.down.circle").font(.title3).frame(width: 44, height: 44) }.accessibilityLabel("下载 \(source.name)")
                        }
                    }.padding(.horizontal, 16).padding(.vertical, 4)
                    if source.id != model.streams.last?.id { Divider().padding(.leading, 16) }
                }
            }.background(WeBoxTheme.card, in: RoundedRectangle(cornerRadius: WeBoxTheme.radius))
        }
    }
    @MainActor private func play(_ episode: ContentItem) async {
        await model.resolve(episode)
        if let first = model.streams.first, model.error == nil { playback = PlaybackSelection(source: first, item: episode) }
    }
}
