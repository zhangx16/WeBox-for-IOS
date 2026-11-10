import XCTest
@testable import WeBox

final class SourceFormatsTests: XCTestCase {
    @MainActor
    func testM3UHeaderPlaybackAndGroupSearch() async throws {
        let playlist = "#EXTM3U\n#EXTINF:-1 tvg-logo=\"https://example.com/poster.png\" group-title=\"News\",Channel One\n#EXTVLCOPT:http-referrer=https://example.com/\nhttps://example.com/live.m3u8\n"
        let code = try SourceFormats.m3uScript(playlist, title: "Test Live", origin: "https://example.com/channels.m3u")
        let source = ScriptSource(id: "m3u.fixture", title: "", version: "", code: code, origin: "test")
        let runtime = try ScriptRuntime(source: source); defer { runtime.close() }
        let list = try await runtime.invoke("loadList", arguments: [["group": "News"]]) as! [String: Any]
        XCTAssertEqual((list["items"] as? [Any])?.count, 1)
        let streams = try await runtime.invoke("loadResource", arguments: [["link": "https://example.com/live.m3u8"]]) as! [[String: Any]]
        XCTAssertEqual((streams[0]["headers"] as? [String: String])?["Referer"], "https://example.com/")
        XCTAssertEqual(streams[0]["downloadable"] as? Bool, false)
    }
    func testSubscriptionRelativeURLsAndDisabledSources() throws {
        let entries = try XCTUnwrap(SourceFormats.subscription(["version":1,"sources":[["name":"Active","url":"one.js","type":"js"],["url":"two.js","enabled":false]]], origin:"https://example.com/sub/list.json"))
        XCTAssertEqual(entries.count,1); XCTAssertEqual(entries[0].url.absoluteString,"https://example.com/sub/one.js")
        XCTAssertThrowsError(try SourceFormats.subscription(["sources":[["url":"javascript:invalid"]]], origin:"https://example.com/list.json"))
    }
    @MainActor
    func testAndroidOrdinaryBackupImportsScriptsAndPreservesForeignSettings() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryStore(directory: directory)
        let backup: [String:Any] = ["format":"webox-ordinary","version":1,"modules":[["script":"WidgetMetadata={id:'android.fixture',title:'Android',version:'1',modules:[]};","sourceUrl":"https://example.com/a.js","parameters":["token":"saved"]]],"preferences":["custom":"preserved"],"rules":[]]
        try await store.importText(try jsonText(backup))
        XCTAssertEqual(store.source("android.fixture")?.settings["token"],"saved")
        let exported = try jsonObject(String(contentsOf: store.exportBackup(), encoding:.utf8)) as! [String:Any]
        XCTAssertEqual((exported["androidPreferences"] as? [String:Any])?["custom"] as? String,"preserved")
    }
}
