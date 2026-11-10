import XCTest
@testable import WeBox

final class RuntimeTests: XCTestCase {
    @MainActor
    func testBundledDemoBrowseSearchDetailAndPlayback() async throws {
        let source = ScriptSource(id: "dev.webox.demo", title: "Demo", version: "1", code: ScriptRuntime.resource("demo", "js"), origin: "test")
        XCTAssertFalse(source.code.isEmpty)
        let runtime = try ScriptRuntime(source: source)
        defer { runtime.close() }
        XCTAssertEqual(string(runtime.metadata["id"]), "dev.webox.demo")
        let rows = try await runtime.invoke("loadList", arguments: [["group": "all"]]) as! [[String: Any]]
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(string(rows[0]["title"]), "Big Buck Bunny")
        let noMatch = try await runtime.invoke("search", arguments: [["keyword": "no-match"]]) as! [Any]
        XCTAssertTrue(noMatch.isEmpty)
        let match = try await runtime.invoke("search", arguments: [["keyword": "BUNNY"]]) as! [Any]
        XCTAssertEqual(match.count, 1)
        let detail = try await runtime.invoke("loadDetail", arguments: ["demo:bunny"]) as! [String: Any]
        XCTAssertTrue(string(detail["videoUrl"]).hasSuffix(".mp4"))
        let streams = try await runtime.invoke("loadResource", arguments: [["link": "demo:bunny"]]) as! [[String: Any]]
        XCTAssertEqual(try PlaySource(streams[0]).url.scheme, "https")
    }

    @MainActor
    func testNativeWeBoxCursorSettingsDetailAndPlay() async throws {
        let code = """
        WeBox.define({api:'1.0',id:'test.native',name:'Native',version:'1.0.0',
          settings:{fields:[{key:'token',label:'Token',type:'text',required:true}]},
          filters:async()=>[{key:'genre',label:'Genre',type:'select',options:[{label:'All',value:'all'}],default:'all'}],
          list:async(ctx,q)=>({items:[{id:q.cursor||'first',title:ctx.settings.token,kind:'movie'}],nextCursor:q.cursor?null:'second'}),
          search:async(ctx,q)=>({items:[],nextCursor:null}),
          detail:async(ctx,q)=>({id:q.id,title:'Native detail',kind:'movie',groups:[{id:'main',name:'Main',episodes:[{id:'movie',name:'Play'}]}]}),
          play:async(ctx,q)=>({sources:[{id:'direct',name:'MP4',url:'https://example.com/movie.mp4'}]})
        });
        """
        let runtime = try ScriptRuntime(source: ScriptSource(id: "test.native", title: "", version: "", code: code, origin: "test", settings: ["__wbSetting_token": "configured"]))
        defer { runtime.close() }
        try await runtime.configure()
        XCTAssertEqual(runtime.modules.first?.function, "__wbList")
        let first = try await runtime.invoke("__wbList", arguments: [["__wb_page": "1", "genre": "all"]]) as! [String: Any]
        let rows = first["items"] as! [[String: Any]]
        XCTAssertEqual(string(rows[0]["title"]), "configured")
        XCTAssertEqual(first["hasMore"] as? Bool, true)
        let second = try await runtime.invoke("__wbList", arguments: [["__wb_page": "2", "genre": "all"]]) as! [String: Any]
        XCTAssertEqual(second["hasMore"] as? Bool, false)
        XCTAssertEqual(string((second["items"] as! [[String: Any]])[0]["id"]), "second")
        let detail = try await runtime.invoke("__wbDetail", arguments: [string(rows[0]["link"])]) as! [String: Any]
        let episode = (detail["childItems"] as! [[String: Any]])[0]
        let streams = try await runtime.invoke("__wbPlay", arguments: [["link": string(episode["link"])]]) as! [[String: Any]]
        XCTAssertEqual(try PlaySource(streams[0]).url.path, "/movie.mp4")
    }

    @MainActor
    func testStorageIsolationCryptoHTMLTimersAndErrors() async throws {
        let suite = "webox.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let code = """
        WidgetMetadata={id:'test.host',title:'Host',version:'1',modules:[]};
        async function exercise(){
          Widget.storage.set('nested',{list:[1,null,'three']});
          var saved=Widget.storage.get('nested');
          await new Promise(resolve=>setTimeout(resolve,1));
          var text=Widget.html.load('<h1>Hello iOS</h1>')('h1').text();
          return {saved:saved,hash:Widget.crypto.md5('abc'),text:text,
            encoded:Widget.crypto.base64Decode(Widget.crypto.base64Encode('中文'))};
        }
        async function fail(){throw new Error('expected-script-error');}
        """
        let source = ScriptSource(id: "test.host", title: "", version: "", code: code, origin: "test")
        let runtime = try ScriptRuntime(source: source, defaults: defaults)
        defer { runtime.close() }
        let result = try await runtime.invoke("exercise", arguments: []) as! [String: Any]
        XCTAssertEqual(string(result["hash"]), "900150983cd24fb0d6963f7d28e17f72")
        XCTAssertEqual(string(result["text"]), "Hello iOS")
        XCTAssertEqual(string(result["encoded"]), "中文")
        XCTAssertEqual(((result["saved"] as! [String: Any])["list"] as! [Any]).count, 3)
        var other = source; other.id = "test.other"
        let isolated = try ScriptRuntime(source: other, defaults: defaults)
        defer { isolated.close() }
        try isolated.evaluate("async function read(){return Widget.storage.get('nested');}")
        let value = try await isolated.invoke("read", arguments: [])
        XCTAssertTrue(value is NSNull)
        do { _ = try await runtime.invoke("fail", arguments: []); XCTFail("Expected script error") }
        catch { XCTAssertTrue(error.localizedDescription.contains("expected-script-error")) }
    }

    @MainActor
    func testXPTVAdapterBrowseDetailAndPlay() async throws {
        let code = """
        var app={title:'XPTV fixture',site:'https://example.com'};
        async function getConfig(){return {title:'XPTV fixture',tabs:[{name:'All',ext:{id:'all'}}]};}
        async function getCards(p){return {list:[{vod_id:'1',vod_name:'Fixture',ext:{id:'1'}}],hasMore:false};}
        async function getTracks(p){return [{title:'Main',tracks:[{name:'Episode 1',ext:{url:'https://example.com/a.mp4'}}]}];}
        async function getPlayinfo(p){return {url:p.url};}
        """
        let runtime = try ScriptRuntime(source: ScriptSource(id: "fixture.xptv", title: "", version: "", code: code, origin: "test"))
        defer { runtime.close() }
        try await runtime.configure()
        XCTAssertEqual(string(runtime.metadata["hostProtocol"]), "xptv")
        let page = try await runtime.invoke("compatBrowse", arguments: [["page": "1"]]) as! [String: Any]
        let first = (page["items"] as! [[String: Any]])[0]
        let episodes = try await runtime.invoke("loadDetail", arguments: [string(first["link"])]) as! [[String: Any]]
        let streams = try await runtime.invoke("loadResource", arguments: [["link": string(episodes[0]["link"])]]) as! [[String: Any]]
        XCTAssertEqual(try PlaySource(streams[0]).url.path, "/a.mp4")
    }

    @MainActor
    func testUnsupportedCapabilityFailsExplicitly() throws {
        let code = "WeBox.define({api:'1.0',id:'test.unsupported',name:'Bad',version:'1.0.0',requires:['binary'],list:async()=>{},detail:async()=>{},play:async()=>{}})"
        XCTAssertThrowsError(try ScriptRuntime(source: ScriptSource(id: "test", title: "", version: "", code: code, origin: "test")))
        XCTAssertThrowsError(try PlaySource(["manifest": "#EXTM3U", "baseUrl": "https://example.com"]))
    }

    @MainActor
    func testBackupRoundTripAndHistoryPersistence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryStore(directory: directory)
        let source = try XCTUnwrap(store.sources.first)
        let item = ContentItem(["id": "bunny", "title": "Bunny", "link": "demo:bunny"])
        store.toggleFavorite(item, sourceID: source.id)
        store.record(item, sourceID: source.id, position: 42)
        let backup = try store.exportBackup()
        let restored = LibraryStore(directory: directory.appendingPathComponent("restore"))
        try restored.importFile(backup)
        XCTAssertTrue(restored.isFavorite(item, sourceID: source.id))
        XCTAssertEqual(restored.position(item, sourceID: source.id), 42)
        let reloaded = LibraryStore(directory: directory.appendingPathComponent("restore"))
        XCTAssertEqual(reloaded.history.count, 1)
    }
}

final class FixtureURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "fixture.webox.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let payload: [String: Any] = ["query": request.url?.query ?? "", "header": request.value(forHTTPHeaderField: "X-WeBox") ?? "", "method": request.httpMethod ?? "", "body": request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""]
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json", "X-Fixture": "yes"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: payload))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
extension RuntimeTests {
    @MainActor
    func testNativeAsyncHTTPBridge() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FixtureURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let code = """
        WidgetMetadata={id:'test.http',title:'HTTP',version:'1',modules:[]};
        async function send(){return await Widget.http.post('https://fixture.webox.test/echo',{title:'中文'},
          {headers:{'X-WeBox':'bridge'},params:{q:'hello world'}});}
        """
        let runtime = try ScriptRuntime(source: ScriptSource(id: "test.http", title: "", version: "", code: code, origin: "test"), networkSession: session)
        defer { runtime.close() }
        let response = try await runtime.invoke("send", arguments: []) as! [String: Any]
        XCTAssertEqual(response["statusCode"] as? Int, 200)
        let body = response["data"] as! [String: Any]
        XCTAssertEqual(string(body["header"]), "bridge")
        XCTAssertEqual(string(body["method"]), "POST")
        XCTAssertTrue(string(body["query"]).contains("q=hello%20world"))
        XCTAssertTrue(string(body["body"]).contains("中文"))
    }

    @MainActor
    func testAESKnownVector() async throws {
        let code = """
        WidgetMetadata={id:'test.aes',title:'AES',version:'1',modules:[]};
        async function vector(){return Widget.crypto.aesEncrypt('00112233445566778899aabbccddeeff','000102030405060708090a0b0c0d0e0f','',
          {mode:'ECB',padding:'NoPadding',keyEncoding:'hex',inputEncoding:'hex',outputEncoding:'hex'});}
        """
        let runtime = try ScriptRuntime(source: ScriptSource(id: "test.aes", title: "", version: "", code: code, origin: "test"))
        defer { runtime.close() }
        let result = try await runtime.invoke("vector", arguments: [])
        XCTAssertEqual(string(result), "69c4e0d86a7b0430d8cdb78070b4c55a")
    }
}
