import SwiftUI
import UniformTypeIdentifiers
import AVKit

struct RootView: View {
    @EnvironmentObject private var library: LibraryStore
    var body: some View {
        TabView {
            NavigationStack { SourcesView() }.tabItem { Label("内容源", systemImage: "square.grid.2x2") }
            NavigationStack { SavedListView(history: false) }.tabItem { Label("收藏", systemImage: "heart") }
            NavigationStack { SavedListView(history: true) }.tabItem { Label("历史", systemImage: "clock") }
            NavigationStack { DownloadsView() }.tabItem { Label("下载", systemImage: "arrow.down.circle") }
            NavigationStack { SettingsView() }.tabItem { Label("设置", systemImage: "gearshape") }
        }
        .tint(.mint)
        .alert("提示", isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) {
            Button("知道了") { library.error = nil }
        } message: { Text(library.error ?? "") }
    }
}
struct SourcesView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var importing = false
    @State private var fileImporter = false
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 14) {
                        Image("WeBoxIcon").resizable().frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 12))
                        Text("你的内容，由你连接。").font(.title2.bold())
                    }
                    Text("添加 JavaScript 内容源，浏览片单与播放视频。").font(.subheadline).foregroundStyle(.secondary)
                }.padding(.vertical, 18).listRowBackground(Color.mint.opacity(0.08))
            }
            Section("已安装 · \(library.sources.count)") {
                ForEach(library.sources) { source in
                    NavigationLink {
                        BrowserView(source: source).id(source.id + source.version + String(source.installedAt.timeIntervalSince1970))
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: source.origin == "bundled" ? "play.rectangle" : "curlybraces").font(.title2).foregroundStyle(.mint).frame(width: 42, height: 48)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(source.title).font(.headline)
                                Text("v\(source.version) · \(source.origin == "bundled" ? "内置公开示例" : "自定义内容源")").font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 8)
                    }
                    .swipeActions {
                        Button("删除", role: .destructive) { library.remove(source) }
                    }
                    .contextMenu {
                        NavigationLink("内容源配置") { SourceSettingsView(source: source) }
                        ShareLink(item: source.code) { Label("分享脚本", systemImage: "square.and.arrow.up") }
                    }
                }
                if library.sources.isEmpty { ContentUnavailableView("还没有内容源", systemImage: "curlybraces", description: Text("点右上角添加 JS 文件或链接")) }
            }
        }
        .navigationTitle("WeBox")
        .toolbar {
            Menu {
                Button("从链接或文本添加", systemImage: "link") { importing = true }
                Button("导入 JS / iOS 备份", systemImage: "doc.badge.plus") { fileImporter = true }
            } label: { Image(systemName: "plus.circle.fill") }
        }
        .sheet(isPresented: $importing) { ImportSourceView() }
        .fileImporter(isPresented: $fileImporter, allowedContentTypes: [.javaScript, .json, .plainText, .data]) { result in
            do { try library.importFile(result.get()) } catch { library.error = error.localizedDescription }
        }
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
    var body: some View {
        NavigationStack {
            Form {
                Picker("添加方式", selection: $mode) { Text("链接").tag(0); Text("脚本文本").tag(1) }.pickerStyle(.segmented)
                if mode == 0 { TextField("https://example.com/source.js", text: $address).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL) }
                else { TextEditor(text: $code).font(.system(.caption, design: .monospaced)).frame(minHeight: 250).autocorrectionDisabled().textInputAutocapitalization(.never) }
                Section { Text("脚本可发起网络请求及保存本地数据，请仅添加你信任的内容源。支持明文 WeBox / Widget / XPTV 脚本；暂不支持加密源与订阅集合。").font(.footnote).foregroundStyle(.secondary) }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("添加内容源").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task {
                        busy = true; error = nil
                        do { if mode == 0 { try await library.importURL(address) } else { try library.install(code: code, origin: "pasted") }; dismiss() }
                        catch { self.error = error.localizedDescription }
                        busy = false
                    } } label: { if busy { ProgressView() } else { Text("添加") } }
                    .disabled(busy || (mode == 0 ? address : code).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .interactiveDismissDisabled(busy)
        }
    }
}
struct SavedListView: View {
    @EnvironmentObject private var library: LibraryStore
    let history: Bool
    var body: some View {
        let rows = history ? library.history : library.favorites
        List {
            if rows.isEmpty { ContentUnavailableView(history ? "还没有观看记录" : "还没有收藏", systemImage: history ? "clock" : "heart") }
            ForEach(rows) { saved in
                if let source = library.source(saved.sourceID) {
                    NavigationLink { DetailView(source: source, item: saved.item) } label: {
                        HStack {
                            PosterView(address: saved.item.poster).frame(width: 52, height: 70).clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 6) {
                                Text(saved.item.title).font(.headline)
                                Text(source.title).font(.caption).foregroundStyle(.secondary)
                                if history { Text("\(saved.date.formatted(date: .abbreviated, time: .shortened)) · \(Int(saved.position)) 秒").font(.caption2).foregroundStyle(.secondary) }
                            }
                        }
                    }
                } else {
                    VStack(alignment: .leading) { Text(saved.item.title); Text("原内容源已移除，请重新安装后打开").font(.caption).foregroundStyle(.secondary) }
                }
            }
        }.navigationTitle(history ? "观看历史" : "我的收藏")
        .toolbar { if history && !rows.isEmpty { Button("清空", role: .destructive) { library.clearHistory() } } }
    }
}
struct SettingsView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var backupURL: URL?
    var body: some View {
        Form {
            Section("资料管理") {
                Button("生成 iOS 备份") { do { backupURL = try library.exportBackup() } catch { library.error = error.localizedDescription } }
                if let backupURL { ShareLink(item: backupURL) { Label("导出备份文件", systemImage: "square.and.arrow.up") } }
                Text("备份包含内容源脚本、配置、收藏与历史。源配置可能包含密钥，请妥善保存。可从内容源页导入 iOS 备份。").font(.footnote).foregroundStyle(.secondary)
            }
            Section("播放与兼容性") {
                LabeledContent("播放器", value: "AVPlayer · AirPlay · 画中画")
                LabeledContent("内容源", value: "WeBox / Widget / XPTV")
                Text("支持 iOS 原生可解码的视频及 HLS。自定义请求头由 AVURLAsset 传递，部分服务器可能不兼容。Android mpv 专有格式、内存 HLS、媒体处理器、binary、compute、TMDB 主机接口、RSA、REXENC 及 Android 备份尚未移植。").font(.footnote).foregroundStyle(.secondary)
            }
            Section("关于") {
                LabeledContent("WeBox for iOS", value: "0.1.0")
                Text("基于 WeBox Android 0.1.64 的静态分析实现。此版本为移植预览版，未验证与所有第三方源兼容。").font(.footnote).foregroundStyle(.secondary)
                Link("项目与构建产物", destination: URL(string: "https://github.com/zhangx16/WeBox-for-IOS")!)
                NavigationLink("开源许可") { ScrollView { Text(ScriptRuntime.resource("web-licenses", "txt")).font(.caption.monospaced()).padding() }.navigationTitle("开源许可") }
            }
        }.navigationTitle("设置")
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
            if let error { Text(error).foregroundStyle(.red) }
            Section { Text("保存后重新进入内容源以应用配置。").font(.footnote) }
        }.navigationTitle("内容源配置")
        .toolbar { Button("保存") { library.updateSettings(source.id, values: values); dismiss() } }
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
        } else if parameter.type == "secret" { SecureField(parameter.title, text: $value).textInputAutocapitalization(.never) }
        else if parameter.type == "boolean" { Toggle(parameter.title, isOn: Binding(get: { value == "true" }, set: { value = $0 ? "true" : "false" })) }
        else { TextField(parameter.title, text: $value, axis: .vertical).textInputAutocapitalization(.never).autocorrectionDisabled() }
    }
}
struct PosterView: View {
    let address: String
    var body: some View {
        AsyncImage(url: URL(string: address)) { image in image.resizable().scaledToFill() } placeholder: {
            ZStack { Color.mint.opacity(0.09); Image(systemName: "play.rectangle").font(.largeTitle).foregroundStyle(.mint.opacity(0.5)) }
        }.clipped()
    }
}
struct DownloadsView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var localPlayback: DownloadRecord?
    var body: some View {
        List {
            if let status = library.downloadStatus {
                HStack { ProgressView(); Text(status); Spacer(); Button("取消") { library.cancelDownload() } }
            }
            if library.downloads.isEmpty { ContentUnavailableView("暂无离线视频", systemImage: "arrow.down.circle", description: Text("在播放线路中选择下载 MP4/MOV/M4V 直链")) }
            ForEach(library.downloads) { item in
                Button { localPlayback = item } label: { Label(item.title, systemImage: "play.circle") }
                    .swipeActions { Button("删除", role: .destructive) { library.removeDownload(item) } }
                    .contextMenu { ShareLink(item: library.localURL(item)) { Text("分享文件") } }
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
