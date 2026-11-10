import XCTest
import CryptoKit
import Security
@testable import WeBox

final class CompatibilityTests: XCTestCase {
    @MainActor
    func testThreeSuppliedSourcesImportAndDeclareExpectedInterfaces() throws {
        let names = ["4k影视.webox", "瓜子.webox", "磁力熊.webox"]
        for name in names {
            let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "js", subdirectory: "TestFixtures"))
            let code = try String(contentsOf: url, encoding: .utf8)
            let runtime = try ScriptRuntime(source: ScriptSource(id: "fixture." + name, title: name, version: "", code: code, origin: "test"))
            XCTAssertFalse(runtime.modules.isEmpty, name)
            XCTAssertNotNil(runtime.searchModule, name)
            XCTAssertEqual(string(runtime.metadata["hostProtocol"]), "webox")
            runtime.close()
        }
    }
    @MainActor
    func testActual4KWebAssemblyRunsInIsolatedCompute() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "4k影视.webox", withExtension: "js", subdirectory: "TestFixtures"))
        let runtime = try ScriptRuntime(source: ScriptSource(id: "4k.fixture", title: "", version: "", code: try String(contentsOf: url, encoding: .utf8), origin: "test"))
        defer { runtime.close() }
        try runtime.evaluate("async function __testWasm(){return await Widget.compute.run({code:kvmBuildRequest.toString(),input:{dataid:'12345',episodeId:'abc123',quality:'1080',playKey:'fixture',serverTime:String(Math.floor(Date.now()/1000)),loadedAt:Date.now()},binaries:{module:KVM_WASM_BASE64},timeout:10});}")
        let result = try await runtime.invoke("__testWasm", arguments: []) as? [String: Any]
        XCTAssertTrue(string(result?["url"]).contains("/"))
    }
    @MainActor
    func testComputeCancellationAndNetworkIsolation() async throws {
        let service = ComputeService()
        let result = try await service.run(["code": "async function(input,binaries){let denied=false;try{await fetch('https://example.com')}catch(e){denied=true}return {answer:input.x+2,bytes:binaries.data.length,denied};}", "input": ["x": 40], "binaries": ["data": Data([1,2,3]).base64EncodedString()], "timeout": 5]) as! [String: Any]
        XCTAssertEqual(result["answer"] as? Int, 42); XCTAssertEqual(result["bytes"] as? Int, 3); XCTAssertEqual(result["denied"] as? Bool, true)
        do { _ = try await service.run(["code": "function(){while(true){}}", "timeout": 0.1]); XCTFail("Expected worker deadline") } catch { XCTAssertTrue(error.localizedDescription.contains("超时")) }
        service.close()
    }
    func testRSADecryptReturnsUTF8AndAcceptsPKCS8SPKI() throws {
        var error: Unmanaged<CFError>?
        let privateKey = try XCTUnwrap(SecKeyCreateRandomKey([kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 1024] as CFDictionary, &error))
        let publicKey = try XCTUnwrap(SecKeyCopyPublicKey(privateKey))
        let privateData = try XCTUnwrap(SecKeyCopyExternalRepresentation(privateKey, &error)) as Data
        let publicData = try XCTUnwrap(SecKeyCopyExternalRepresentation(publicKey, &error)) as Data
        func wrap(_ tag: UInt8, _ data: Data) -> Data {
            var result = Data([tag]); if data.count < 128 { result.append(UInt8(data.count)) } else { var length = data.count; var bytes: [UInt8] = []; while length > 0 { bytes.insert(UInt8(length & 255), at: 0); length >>= 8 }; result.append(0x80 | UInt8(bytes.count)); result.append(contentsOf: bytes) }; result.append(data); return result
        }
        let algorithm = Data([0x30,0x0d,0x06,0x09,0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x01,0x01,0x05,0x00])
        let spki = wrap(0x30, algorithm + wrap(0x03, Data([0]) + publicData))
        let pkcs8 = wrap(0x30, Data([2,1,0]) + algorithm + wrap(0x04, privateData))
        let plaintext = "{\"key\":\"中文-test\"}"
        let ciphertext = try NativeCrypto.rsa(["key": spki.base64EncodedString(), "text": plaintext])
        XCTAssertEqual(try NativeCrypto.rsa(["key": pkcs8.base64EncodedString(), "text": ciphertext, "decrypt": true]), plaintext)
    }
    @MainActor
    func testREXENCAuthenticatedContainerRoundTrip() throws {
        let key = Data(repeating: 7, count: 32), nonce = Data(repeating: 3, count: 12)
        let plaintext = "WidgetMetadata={id:'rex.fixture',title:'REX',modules:[]};"
        let box = try AES.GCM.seal(Data(plaintext.utf8), using: SymmetricKey(data: key), nonce: AES.GCM.Nonce(data: nonce))
        let header = try jsonText(["v": 2, "mkv": "rex-1", "alg": "A256GCM", "iv": nonce.base64EncodedString(), "kb": Data(repeating: 1, count: 60).base64EncodedString()])
        let container = try SourceFormats.parseREX("REXENC\n" + header + "\n" + (box.ciphertext + box.tag).base64EncodedString())
        XCTAssertEqual(try SourceFormats.decryptREX(container, key: key), plaintext)
        XCTAssertThrowsError(try SourceFormats.decryptREX(container, key: Data(repeating: 0, count: 32)))
    }
    func testBinaryBuffersAndPlaylistRewrite() throws {
        let store = BinaryStore(); let original = try store.create(Data([0,1,2,3]))
        let changed = try store.call("binary.write", ["handle": original, "offset": 1, "data": Data([9]).base64EncodedString()]) as! String
        XCTAssertEqual(try store.read(changed), Data([0,9,2,3]))
        XCTAssertThrowsError(try store.call("binary.read", ["handle": original, "offset": -1, "length": 1]))
        let playlist = "#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI=\"key.bin\"\n#EXT-X-MAP:URI=\"init.mp4\"\n#EXTINF:2,\nsegment.ts\n#EXT-X-ENDLIST"
        var kinds: [String] = []
        let rewritten = try MediaPlaylist.rewriteResources(playlist, base: URL(string: "https://example.com/path/index.m3u8")!) { url, kind, _ in kinds.append(kind); return "http://127.0.0.1/" + url.lastPathComponent }
        XCTAssertEqual(kinds, ["key", "init", "segment"])
        XCTAssertTrue(rewritten.contains("http://127.0.0.1/segment.ts")); XCTAssertTrue(rewritten.contains("#EXT-X-ENDLIST"))
    }
}
