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
    init(selection: PlaybackSelection, position: Double, record: @escaping (Double) -> Void) {
        let asset = AVURLAsset(url: selection.source.url, options: ["AVURLAssetHTTPHeaderFieldsKey": selection.source.headers])
        let item = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: item)
        observer = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                if item.status == .failed { self?.error = item.error?.localizedDescription ?? "此格式或播放线路无法由 iOS 解码，请选择其他线路" }
            }
        }
        progressObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 5, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self, time.seconds.isFinite, Date().timeIntervalSince(self.lastSave) > 10 else { return }
            self.lastSave = Date(); record(time.seconds)
        }
        if position > 0 && !selection.item.isLive { player.seek(to: CMTime(seconds: position, preferredTimescale: 600)) }
    }
    func stop() {
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
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            if let model { NativePlayer(player: model.player).ignoresSafeArea() }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title).symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.6)) }
                    Text(selection.item.title).font(.headline).lineLimit(1).shadow(radius: 4)
                    Spacer()
                }
                if let error = model?.error { Text(error).font(.callout).padding().background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 12)) }
            }.padding()
        }
        .onAppear {
            let item = selection.item
            let library = library, sourceID = sourceID
            model = PlayerModel(selection: selection, position: library.position(item, sourceID: sourceID)) { position in library.record(item, sourceID: sourceID, position: position) }
            library.record(item, sourceID: sourceID, position: library.position(item, sourceID: sourceID))
            model?.player.play()
        }
        .onDisappear {
            if let model { library.record(selection.item, sourceID: sourceID, position: model.player.currentTime().seconds); model.stop() }
            model = nil
        }
    }
}
struct NativePlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.updatesNowPlayingInfoCenter = true
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) { controller.player = player }
}
