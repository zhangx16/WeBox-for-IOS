import SwiftUI
import AVKit

struct PlaybackSelection: Identifiable {
    let id = UUID()
    let source: PlaySource
    let item: ContentItem
}
@MainActor
final class PlayerModel: ObservableObject {
    let player: AVPlayer
    @Published var error: String?
    private var observer: NSKeyValueObservation?
    private var progressObserver: Any?
    private var lastSave = Date.distantPast
    private var proxy: MediaProxy?
    private var loadTask: Task<Void, Never>?
    init(selection: PlaybackSelection, position: Double, record: @escaping @MainActor (Double) -> Void) {
        player = AVPlayer()
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let proxy = MediaProxy(source: selection.source); self.proxy = proxy
                let address = try await proxy.start()
                let item = AVPlayerItem(url: address)
                self.player.replaceCurrentItem(with: item)
                if position > 0 && !selection.item.isLive { await self.player.seek(to: CMTime(seconds: position, preferredTimescale: 600)) }
                self.player.play()
                self.observer = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                if item.status == .failed { self?.error = item.error?.localizedDescription ?? "此格式或播放线路无法由 iOS 解码，请选择其他线路" }
            }
        }
            } catch { self.error = error.localizedDescription }
        }
        progressObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 5, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self, time.seconds.isFinite, Date().timeIntervalSince(self.lastSave) > 10 else { return }
                self.lastSave = Date(); record(time.seconds)
            }
        }
        if position > 0 && !selection.item.isLive { player.seek(to: CMTime(seconds: position, preferredTimescale: 600)) }
    }
    func stop() {
        loadTask?.cancel(); loadTask = nil; proxy?.close(); proxy = nil
        player.pause(); observer = nil
        if let progressObserver { player.removeTimeObserver(progressObserver); self.progressObserver = nil }
    }
}
struct PlayerScreen: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let selection: PlaybackSelection
    let sourceID: String
    @State private var model: PlayerModel?
    @State private var mpv: MPVPlaybackController?
    @State private var mpvProxy: MediaProxy?
    @State private var engine = UserDefaults.standard.string(forKey: "webox.player.engine") ?? "native"
    @State private var speed = 1.0
    @State private var locked = false
    @State private var filling = false
    @State private var mpvLoad: Task<Void, Never>?
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            if engine == "mpv", let mpv { MPVPlayerSurface(controller: mpv).ignoresSafeArea() }
            else if let model { NativePlayer(player: model.player, fill: filling).ignoresSafeArea() }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title).symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.6)) }
                    Text(selection.item.title).font(.headline).lineLimit(1).shadow(radius: 4)
                    Spacer()
                    Menu {
                        Button("iOS 原生播放器") { engine = "native"; startPlayback() }
                        Button("mpv · 多格式") { engine = "mpv"; startPlayback() }
                        Button(filling ? "适应画面" : "填充画面") { filling.toggle(); mpv?.aspect(filling ? "fill" : "fit") }
                        ForEach([0.5, 1.0, 1.25, 1.5, 2.0], id: \.self) { value in Button("\(value, specifier: "%.2g")×") { speed = value; model?.player.rate = Float(value); mpv?.speed(value) } }
                    } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }
                }
                if engine == "mpv", let mpv {
                    HStack {
                        Button { mpv.seek(-15) } label: { Image(systemName: "gobackward.15") }
                        Button { mpv.togglePause() } label: { Image(systemName: mpv.paused ? "play.fill" : "pause.fill") }
                        Button { mpv.seek(15) } label: { Image(systemName: "goforward.15") }
                    }.font(.title2).buttonStyle(.bordered).padding(.vertical)
                }
                if let error = engine == "mpv" ? mpv?.error : model?.error { Text(error).font(.callout).padding().background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 12)) }
            }.padding()
        }
        .onAppear { startPlayback() }
        .onDisappear { stopPlayback() }
    }
    private func stopPlayback() {
        if let model { library.record(selection.item, sourceID: sourceID, position: model.player.currentTime().seconds); model.stop() }
        mpvLoad?.cancel(); mpvLoad = nil
        model = nil; mpv?.stop(); mpv = nil; mpvProxy?.close(); mpvProxy = nil
    }
    private func startPlayback() {
        stopPlayback()
        let item = selection.item, library = library, sourceID = sourceID
        if engine == "mpv" {
            let controller = MPVPlaybackController { position in library.record(item, sourceID: sourceID, position: position) }
            mpv = controller
            mpvLoad = Task {
                do {
                    let proxy = MediaProxy(source: selection.source); mpvProxy = proxy
                    let url = try await proxy.start()
                    try Task.checkCancellation()
                    controller.load(url: url, position: library.position(item, sourceID: sourceID))
                } catch { controller.error = error.localizedDescription }
            }
        } else {
            model = PlayerModel(selection: selection, position: library.position(item, sourceID: sourceID)) { position in library.record(item, sourceID: sourceID, position: position) }
        }
    }
}
struct NativePlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    var fill = false
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.updatesNowPlayingInfoCenter = true
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) { controller.player = player; controller.videoGravity = fill ? .resizeAspectFill : .resizeAspect }
}
