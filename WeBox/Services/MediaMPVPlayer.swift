import SwiftUI
import Metal
import QuartzCore
import Libmpv

/// libmpv's documented wid/CAMetalLayer path, via MPVKit's pinned binary release.
@MainActor
final class MPVPlaybackController: ObservableObject {
    @Published var error: String?
    @Published var paused = false
    @Published var position = 0.0
    @Published var duration = 0.0
    private var handle: OpaquePointer?
    private var ticker: Task<Void, Never>?
    private var layer: CAMetalLayer?
    private var initialURL: URL?
    private var initialPosition = 0.0
    private let record: (Double) -> Void
    init(record: @escaping (Double) -> Void) { self.record = record }
    func load(url: URL, position: Double) { initialURL = url; initialPosition = position; if handle != nil { open() } }
    func attach(_ layer: CAMetalLayer) {
        guard handle == nil else { return }
        self.layer = layer
        guard let handle = mpv_create() else { error = "mpv 初始化失败"; return }
        self.handle = handle
        var wid = Int64(Int(bitPattern: Unmanaged.passUnretained(layer).toOpaque()))
        mpv_set_option(handle, "wid", MPV_FORMAT_INT64, &wid)
        for (key, value) in [("vo", "gpu-next"), ("gpu-api", "vulkan"), ("gpu-context", "moltenvk"), ("hwdec", "videotoolbox"), ("ao", "audiounit"), ("terminal", "no"), ("cache", "yes")] { mpv_set_option_string(handle, key, value) }
        let status = mpv_initialize(handle)
        guard status >= 0 else { error = String(cString: mpv_error_string(status)); stop(); return }
        open()
        ticker = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, let self, let handle = self.handle else { return }
                self.position = self.number("time-pos"); self.duration = self.number("duration")
                while let event = mpv_wait_event(handle, 0), event.pointee.event_id != MPV_EVENT_NONE {
                    if event.pointee.event_id == MPV_EVENT_END_FILE, let data = event.pointee.data {
                        let end = data.assumingMemoryBound(to: mpv_event_end_file.self).pointee
                        if end.error < 0 { self.error = String(cString: mpv_error_string(end.error)) }
                    }
                }
                tick += 1; if tick % 20 == 0 { self.record(self.position) }
            }
        }
    }
    private func open() {
        guard let url = initialURL, handle != nil else { return }
        command(["loadfile", url.isFileURL ? url.path : url.absoluteString, "replace"])
        if initialPosition > 0 { command(["seek", String(initialPosition), "absolute"]) }
    }
    func togglePause() { paused.toggle(); set("pause", value: paused ? "yes" : "no") }
    func seek(_ seconds: Double) { command(["seek", String(seconds), "relative"]) }
    func speed(_ value: Double) { set("speed", value: String(value)) }
    func aspect(_ mode: String) { set("video-unscaled", value: "no"); set("panscan", value: mode == "fill" ? "1" : "0") }
    private func set(_ key: String, value: String) { if let handle { mpv_set_property_string(handle, key, value) } }
    private func number(_ key: String) -> Double { guard let handle else { return 0 }; var value = 0.0; mpv_get_property(handle, key, MPV_FORMAT_DOUBLE, &value); return value.isFinite ? value : 0 }
    private func command(_ arguments: [String]) {
        guard let handle else { return }
        let strings = arguments.map { strdup($0) }; defer { for value in strings { free(value) } }
        var pointers = strings.map { $0.map(UnsafePointer.init) }; pointers.append(nil)
        mpv_command(handle, &pointers)
    }
    func stop() {
        ticker?.cancel(); ticker = nil
        if let handle { record(number("time-pos")); mpv_terminate_destroy(handle) }
        handle = nil; layer = nil
    }
}
private final class MPVMetalSurface: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }
    var metal: CAMetalLayer { layer as! CAMetalLayer }
    override func layoutSubviews() { super.layoutSubviews(); metal.drawableSize = CGSize(width: bounds.width * contentScaleFactor, height: bounds.height * contentScaleFactor) }
}
struct MPVPlayerSurface: UIViewRepresentable {
    let controller: MPVPlaybackController
    func makeUIView(context: Context) -> UIView {
        let view = MPVMetalSurface(); view.backgroundColor = .black; view.metal.device = MTLCreateSystemDefaultDevice(); view.metal.framebufferOnly = true
        controller.attach(view.metal); return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
