import SwiftUI
import AVFoundation

@main
struct WeBoxApp: App {
    @StateObject private var library = LibraryStore()
    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(library).preferredColorScheme(.dark)
                .onOpenURL { url in do { try library.importFile(url) } catch { library.error = error.localizedDescription } }
        }
    }
}
