import SwiftUI
import UniformTypeIdentifiers
import AVKit

struct RootView: View {
    @EnvironmentObject private var library: LibraryStore
    var body: some View {
        TabView {
            NavigationStack { DiscoverView() }.tabItem { Label("发现", systemImage: "sparkles.tv") }
            NavigationStack { SavedListView(history: false) }.tabItem { Label("收藏", systemImage: "heart") }
            NavigationStack { DownloadsView() }.tabItem { Label("下载", systemImage: "arrow.down.circle") }
            NavigationStack { SettingsView() }.tabItem { Label("设置", systemImage: "gearshape") }
        }
        .tint(WeBoxTheme.accent)
        .alert("提示", isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) {
            Button("知道了") { library.error = nil }
        } message: { Text(library.error ?? "") }
    }
}

struct SourcesView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var importing = false
    @State private var fileImporter = false
    @State private var importingFile = false
    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image("WeBoxIcon").resizable().frame(width: 54, height: 54).clipShape(RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("连接你的内容").font(.headline)
                        Text("统一管理脚本、直播和影视接口。").font(.subheadline).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 8)
            }
            Section("已安装 · \(library.sources.count)") {
                ForEach(library.sources) { source in
                    NavigationLink { BrowserView(source: source).id(source.id + String(source.installedAt.timeIntervalSince1970)) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: source.origin == "bundled" ? "play.rectangle.fill" : "square.stack.3d.up.fill")
                                .font(.title3).foregroundStyle(WeBoxTheme.accent).frame(width: 34, height: 44)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(source.title).font(.headline)
                                Text("v\(source.version) · \(source.origin == "bundled" ? "内置公开示例" : "自定义内容源")").font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 4)
                    }
                    .swipeActions { Button("删除", role: .destructive) { library.remove(source) } }
                    .contextMenu {
                        NavigationLink { SourceSettingsView(source: source) } label: { Label("内容源配置", systemImage: "slider.horizontal.3") }
                        ShareLink(item: source.code) { Label("分享脚本", systemImage: "square.and.arrow.up") }
                    }
                }
                if library.sources.isEmpty { ContentUnavailableView("还没有内容源", systemImage: "square.stack.3d.up", description: Text("添加文件、链接或文本后即可开始浏览。")) }
            }
        }.navigationTitle("内容源").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
        .toolbar { Menu {
            Button("链接或文本", systemImage: "link") { importing = true }
            Button("从文件导入", systemImage: "doc.badge.plus") { fileImporter = true }
        } label: { Image(systemName: "plus") }.disabled(importingFile) }
        .sheet(isPresented: $importing) { ImportSourceView() }
        .fileImporter(isPresented: $fileImporter, allowedContentTypes: [.javaScript, .json, .plainText, .data]) { result in
            Task {
                importingFile = true; defer { importingFile = false }
                do { try await library.importFileAsync(result.get()) } catch { library.error = error.localizedDescription }
            }
        }
        .overlay { if importingFile { ProgressView("正在导入内容源…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: WeBoxTheme.radius)) } }
    }
}

struct ImportSourceView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var mode = 0
    @State private var address = ""
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?
    @State private var fileImporter = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("添加方式", selection: $mode) { Text("链接").tag(0); Text("文本").tag(1); Text("文件").tag(2) }.pickerStyle(.segmented)
                    if mode == 0 {
                        TextField("https://example.com/source.js", text: $address).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                            .frame(minHeight: 44)
                    } else if mode == 1 {
                        TextEditor(text: $code).font(.system(.caption, design: .monospaced)).frame(minHeight: 220).autocorrectionDisabled().textInputAutocapitalization(.never)
                    } else {
                        Button { fileImporter = true } label: { Label("从“文件”中选择", systemImage: "folder").frame(minHeight: 44) }
                    }
                } header: { Text("添加内容源") } footer: {
                    Text("支持 JS 脚本、订阅、M3U 直播及 VOD 接口配置。加密源会按其授权协议处理。")
                }
                Section {
                    Label("只添加你信任的内容源", systemImage: "checkmark.shield").font(.subheadline.weight(.semibold))
                    Text("脚本可访问网络并保存数据。内容源配置和备份可能包含账号信息，请妥善保管。").font(.footnote).foregroundStyle(.secondary)
                }
                if let error {
                    Section("导入未完成") {
                        Text(error).font(.subheadline).textSelection(.enabled)
                        ShareLink(item: error) { Label("分享错误信息", systemImage: "square.and.arrow.up") }
                    }
                }
            }
            .navigationTitle("添加内容源").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) {
                    if mode != 2 {
                        Button { Task { await performImport() } } label: { if busy { ProgressView() } else { Text("添加").bold() } }
                            .disabled(busy || (mode == 0 ? address : code).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .fileImporter(isPresented: $fileImporter, allowedContentTypes: [.javaScript, .json, .plainText, .data]) { result in
                Task {
                    busy = true; error = nil; defer { busy = false }
                    do { try await library.importFileAsync(result.get()); dismiss() } catch { self.error = error.localizedDescription }
                }
            }
            .overlay { if busy && mode == 2 { ProgressView("正在处理文件…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: WeBoxTheme.radius)) } }
            .interactiveDismissDisabled(busy)
        }
    }
    @MainActor private func performImport() async {
        busy = true; error = nil; defer { busy = false }
        do {
            if mode == 0 { try await library.importURL(address) }
            else { try await library.importText(code, origin: "pasted") }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct SavedListView: View {
    @EnvironmentObject private var library: LibraryStore
    let history: Bool
    var body: some View {
        let rows = history ? library.history : library.favorites
        List {
            if !history {
                Section { NavigationLink { SavedListView(history: true) } label: { Label("观看历史", systemImage: "clock.arrow.circlepath") } }
            }
            Section {
                if rows.isEmpty { ContentUnavailableView(history ? "还没有观看记录" : "把想看的故事留在这里", systemImage: history ? "clock" : "heart", description: Text(history ? "开始播放后，会为你记录观看进度。" : "在影片详情页轻点收藏，下一次更容易找到。")) }
                ForEach(rows) { saved in
                    if let source = library.source(saved.sourceID) {
                        NavigationLink { DetailView(source: source, item: saved.item) } label: {
                            MediaListRow(item: saved.item, subtitle: history ? "\(source.title) · 已看到 \(Int(saved.position / 60)) 分钟" : source.title)
                        }
                    } else {
                        MediaListRow(item: saved.item, subtitle: "原内容源已移除，重新添加后即可打开")
                    }
                }
            }
        }.navigationTitle(history ? "观看历史" : "我的收藏")
        .toolbar { if history && !rows.isEmpty { Button("清空", role: .destructive) { library.clearHistory() } } }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var backupURL: URL?
    @State private var importing = false
    @State private var fileImporter = false
    @AppStorage("webox.tmdb.service") private var tmdbService = "https://api.themoviedb.org/3"
    @AppStorage("webox.tmdb.apiKey") private var tmdbKey = ""
    @AppStorage("webox.tmdb.language") private var tmdbLanguage = "zh-CN"
    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image("WeBoxIcon").resizable().frame(width: 58, height: 58).clipShape(RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("WeBox").font(.title3.bold())
                        Text("你的影视，井然有序。").font(.subheadline).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 8)
            }
            Section("内容与资料") {
                NavigationLink { SourcesView() } label: { Label("内容源管理", systemImage: "square.stack.3d.up") }
                Button { importing = true } label: { Label("添加内容源", systemImage: "plus.circle") }
                Button { do { backupURL = try library.exportBackup() } catch { library.error = error.localizedDescription } } label: { Label("生成备份", systemImage: "arrow.up.doc") }
                if let backupURL { ShareLink(item: backupURL) { Label("导出备份文件", systemImage: "square.and.arrow.up") } }
                Button { fileImporter = true } label: { Label("从备份恢复", systemImage: "arrow.down.doc") }
            }
            Section {
                TextField("服务地址", text: $tmdbService).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("API Key / Bearer Token", text: $tmdbKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("语言", text: $tmdbLanguage).textInputAutocapitalization(.never).autocorrectionDisabled()
            } header: { Text("TMDB 元数据") } footer: { Text("需要元数据服务的内容源可使用你的 API 凭证。未填写时不会自动请求该服务。") }
            Section("播放") {
                LabeledContent("原生播放", value: "AirPlay · 画中画")
                Text("播放页面可切换线路、调整倍速与画面比例。不同服务器和视频编码的可用功能可能不同。").font(.footnote).foregroundStyle(.secondary)
            }
            Section("关于") {
                LabeledContent("版本", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                Link(destination: URL(string: "https://github.com/zhangx16/WeBox-for-IOS/releases")!) { Label("版本与下载", systemImage: "arrow.up.right.square") }
                NavigationLink("开源许可") {
                    ScrollView { Text(ScriptRuntime.resource("web-licenses", "txt")).font(.caption.monospaced()).padding() }.navigationTitle("开源许可")
                }
            }
        }.navigationTitle("设置")
        .sheet(isPresented: $importing) { ImportSourceView() }
        .fileImporter(isPresented: $fileImporter, allowedContentTypes: [.json, .data]) { result in
            Task { do { try await library.importFileAsync(result.get()) } catch { library.error = error.localizedDescription } }
        }
    }
}

struct SourceSettingsView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let source: ScriptSource
    @State private var values: [String: String] = [:]
    @State private var fields: [ScriptParameter] = []
    @State private var error: String?
    var body: some View {
        Form {
            Section(source.title) {
                if fields.isEmpty { Text("此内容源没有声明全局配置").foregroundStyle(.secondary) }
                ForEach(fields) { field in ParameterField(parameter: field, value: Binding(get: { values[field.id] ?? field.value }, set: { values[field.id] = $0 })) }
            }
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            Section { Text("保存后，返回内容源并重新加载以应用配置。").font(.footnote) }
        }.navigationTitle("内容源配置").navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("保存") { library.updateSettings(source.id, values: values); dismiss() }.bold() }
        .task {
            values = source.settings
            do {
                let runtime = try ScriptRuntime(source: source); defer { runtime.close() }
                fields = runtime.globals
                for field in fields where values[field.id] == nil { values[field.id] = field.value }
            } catch { self.error = error.localizedDescription }
        }
    }
}
struct ParameterField: View {
    let parameter: ScriptParameter
    @Binding var value: String
    var body: some View {
        if !parameter.options.isEmpty {
            Picker(parameter.title, selection: $value) { ForEach(parameter.options, id: \.value) { option in Text(option.title).tag(option.value) } }
        } else if parameter.type == "secret" { SecureField(parameter.title, text: $value).textInputAutocapitalization(.never).autocorrectionDisabled() }
        else if parameter.type == "boolean" { Toggle(parameter.title, isOn: Binding(get: { value == "true" }, set: { value = $0 ? "true" : "false" })) }
        else { TextField(parameter.title, text: $value, axis: .vertical).textInputAutocapitalization(.never).autocorrectionDisabled() }
    }
}
struct PosterView: View {
    let address: String
    var body: some View {
        GeometryReader { geometry in
            AsyncImage(url: URL(string: address)) { phase in
                if let image = phase.image { image.resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped() }
                else {
                    ZStack {
                        Rectangle().fill(Color.secondary.opacity(0.09))
                        Image(systemName: "play.rectangle").font(.system(size: 26, weight: .light)).foregroundStyle(.tertiary)
                    }
                }
            }
        }.clipped()
    }
}
struct DownloadsView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var localPlayback: DownloadRecord?
    var body: some View {
        List {
            if let status = library.downloadStatus {
                Section { HStack(spacing: 12) { ProgressView(); Text(status).font(.subheadline); Spacer(); Button("取消") { library.cancelDownload() } } }
            }
            Section {
                if library.downloads.isEmpty { ContentUnavailableView("把故事带在身边", systemImage: "arrow.down.circle", description: Text("在影片播放线路中选择下载，离线时也能继续观看。")) }
                ForEach(library.downloads) { item in
                    Button { localPlayback = item } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "play.rectangle.fill").font(.title2).foregroundStyle(WeBoxTheme.accent).frame(width: 38)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.title).font(.headline).foregroundStyle(.primary)
                                Text(item.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(); Image(systemName: "play.circle").font(.title3)
                        }.padding(.vertical, 6)
                    }
                    .swipeActions { Button("删除", role: .destructive) { library.removeDownload(item) } }
                    .contextMenu { ShareLink(item: library.localURL(item)) { Text("分享文件") } }
                }
            }
        }.navigationTitle("下载")
        .sheet(item: $localPlayback) { item in LocalPlayerView(url: library.localURL(item), title: item.title) }
    }
}
struct LocalPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer
    let title: String
    init(url: URL, title: String) { self.title = title; _player = State(initialValue: AVPlayer(url: url)) }
    var body: some View {
        NavigationStack { VideoPlayer(player: player).navigationTitle(title).navigationBarTitleDisplayMode(.inline).toolbar { Button("完成") { dismiss() } } }
            .onAppear { player.play() }.onDisappear { player.pause() }
    }
}
