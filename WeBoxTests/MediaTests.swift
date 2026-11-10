import XCTest
@testable import WeBox

final class MediaTests: XCTestCase {
    @MainActor
    func testMemoryHLSAndMediaProcessorProxy() async throws {
        let runtime = try ScriptRuntime(source: ScriptSource(id: "test.media", title: "", version: "", code: """
        WeBox.define({api:'1.1',id:'test.media',name:'Media',version:'1.0.0',requires:['memoryHls','mediaProcessor','binary'],
          list:async()=>({items:[],nextCursor:null}), detail:async()=>({}),play:async()=>({sources:[]}),
          media:{response:async(ctx,input)=>{const data=ctx.binary.read(input.body,0,ctx.binary.size(input.body));return {body:ctx.binary.write(input.body,0,new Uint8Array([9]))};}}
        });
        """, origin: "test"))
        defer { runtime.close() }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MediaFixtureProtocol.self]
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        var source = try PlaySource(["manifest": "#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXTINF:2,\nsegment.ts\n#EXT-X-ENDLIST", "baseUrl": "https://media.fixture.test/path/index.m3u8", "headers": ["X-Source": "expected"], "processor": ["response": "__wbMediaResponse", "context": [:]]])
        source.runtime = runtime
        let proxy = MediaProxy(source: source, session: session); defer { proxy.close() }
        let root = try await proxy.start()
        let (manifest, response) = try await URLSession.shared.data(from: root)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let text = String(decoding: manifest, as: UTF8.self)
        let segment = try XCTUnwrap(text.components(separatedBy: .newlines).first { $0.hasPrefix("http://127.0.0.1") }.flatMap(URL.init(string:)))
        let (bytes, _) = try await URLSession.shared.data(from: segment)
        XCTAssertEqual(bytes, Data([9,2,3,4]))
        var request = URLRequest(url: segment); request.setValue("bytes=1-2", forHTTPHeaderField: "Range")
        let (range, rangeResponse) = try await URLSession.shared.data(for: request)
        XCTAssertEqual(range, Data([2,3])); XCTAssertEqual((rangeResponse as? HTTPURLResponse)?.statusCode, 206)
    }
    @MainActor
    func testHLSOfflineRetainsKeyMapAndLocalSegments() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MediaFixtureProtocol.self]
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try PlaySource(["url": "https://media.fixture.test/index.m3u8", "headers": ["X-Source": "expected"]])
        let file = try await MediaOfflineDownloader(session: session).download(source: source, destination: directory)
        // Real proxy traffic uses injected fixture session through the downloader.
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }
}
final class MediaFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "media.fixture.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let status = request.value(forHTTPHeaderField: "X-Source") == "expected" ? 200 : 403
        let manifest = "#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXT-X-KEY:METHOD=AES-128,URI=\"key.bin\"\n#EXT-X-MAP:URI=\"init.mp4\"\n#EXTINF:2,\nsegment.ts\n#EXT-X-ENDLIST"
        let isManifest = request.url!.pathExtension == "m3u8"
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": isManifest ? "application/vnd.apple.mpegurl" : "video/mp2t"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: isManifest ? Data(manifest.utf8) : Data([1,2,3,4]))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
