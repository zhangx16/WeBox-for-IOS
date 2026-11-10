import XCTest
import SwiftUI
@testable import WeBox

final class InterfaceTests: XCTestCase {
    @MainActor
    func testDiscoverInterfaceRendersAtPhoneSize() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = LibraryStore(directory: directory)
        let controller = UIHostingController(rootView: RootView().environmentObject(library))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first { window.windowScene = scene }
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(700))
        controller.view.layoutIfNeeded()
        XCTAssertGreaterThan(controller.view.bounds.width, 0)
        let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("build")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (style, name) in [(UIUserInterfaceStyle.light, "light"), (.dark, "dark")] {
            window.overrideUserInterfaceStyle = style
            try await Task.sleep(for: .milliseconds(100))
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image); attachment.name = "WeBox-Discover-\(name)"; attachment.lifetime = .keepAlways; add(attachment)
            try image.pngData()?.write(to: output.appendingPathComponent(name == "light" ? "WeBox-home.png" : "WeBox-home-dark.png"))
        }
    }
}
