import Foundation
import CryptoKit
import Security

/// Exact Android host wire formats: RSA encrypt -> Base64, RSA decrypt -> UTF-8.
/// Security.framework expects PKCS#1; strip SPKI / PKCS#8 envelopes structurally.
enum NativeCrypto {
    static func rsa(_ parameters: [String: Any]) throws -> String {
        let decrypt = parameters["decrypt"] as? Bool ?? false
        let key = try importRSA(string(parameters["key"]), privateKey: decrypt)
        let text = string(parameters["text"])
        let input = try decode(text, encoding: decrypt ? "base64" : "utf8")
        let blockSize = SecKeyGetBlockSize(key)
        guard decrypt ? input.count == blockSize : input.count <= blockSize - 11 else {
            throw AppFailure(decrypt ? "RSA 密文长度无效" : "RSA 明文超过密钥允许的长度")
        }
        var error: Unmanaged<CFError>?
        let result = decrypt
            ? SecKeyCreateDecryptedData(key, .rsaEncryptionPKCS1, input as CFData, &error)
            : SecKeyCreateEncryptedData(key, .rsaEncryptionPKCS1, input as CFData, &error)
        guard let result else {
            let reason = error?.takeRetainedValue().localizedDescription ?? "密钥或数据不匹配"
            throw AppFailure("RSA \(decrypt ? "解密" : "加密")失败：\(reason)")
        }
        if decrypt {
            guard let value = String(data: result as Data, encoding: .utf8) else { throw AppFailure("RSA 解密结果不是 UTF-8 文本") }
            return value
        }
        return (result as Data).base64EncodedString()
    }

    static func importRSA(_ pem: String, privateKey: Bool) throws -> SecKey {
        let body = pem.components(separatedBy: .newlines).filter { !$0.hasPrefix("-----") }.joined()
        guard let bytes = Data(base64Encoded: body.filter { !$0.isWhitespace }), !bytes.isEmpty else { throw AppFailure("RSA 密钥不是有效的 PEM / Base64") }
        let sequence = try DERNode.parse([UInt8](bytes), at: 0)
        guard sequence.tag == 0x30, sequence.end == bytes.count else { throw AppFailure("RSA 密钥 DER 结构无效") }
        let fields = try sequence.children(in: [UInt8](bytes))
        var raw = bytes
        if privateKey, fields.count >= 3, fields[1].tag == 0x30, fields[2].tag == 0x04 {
            // PrivateKeyInfo: version, algorithm, privateKey OCTET STRING.
            raw = Data(bytes[fields[2].content..<fields[2].end])
        } else if !privateKey, fields.count == 2, fields[0].tag == 0x30, fields[1].tag == 0x03 {
            // SubjectPublicKeyInfo BIT STRING begins with the unused-bit count.
            guard fields[1].length > 1, bytes[fields[1].content] == 0 else { throw AppFailure("RSA 公钥 BIT STRING 无效") }
            raw = Data(bytes[(fields[1].content + 1)..<fields[1].end])
        }
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: privateKey ? kSecAttrKeyClassPrivate : kSecAttrKeyClassPublic]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(raw as CFData, attributes as CFDictionary, &error) else {
            _ = error?.takeRetainedValue()
            throw AppFailure("RSA 密钥无法导入，请检查 PKCS#1 / PKCS#8 / SPKI 格式")
        }
        return key
    }

    static func aesGCM(_ p: [String: Any]) throws -> String {
        let decrypt = p["decrypt"] as? Bool ?? false
        let key = try decode(string(p["key"]), encoding: string(p["keyEncoding"]).nonempty ?? "utf8")
        let iv = try decode(string(p["iv"]), encoding: string(p["ivEncoding"]).nonempty ?? "utf8")
        guard [16, 24, 32].contains(key.count), iv.count == 12 else { throw AppFailure("AES-GCM 需要有效 AES 密钥和 12 字节 IV") }
        let input = try decode(string(p["text"]), encoding: string(p["inputEncoding"]).nonempty ?? (decrypt ? "base64" : "utf8"))
        let nonce = try AES.GCM.Nonce(data: iv), symmetric = SymmetricKey(data: key)
        let output: Data
        if decrypt {
            guard input.count >= 16 else { throw AppFailure("AES-GCM 密文缺少认证标签") }
            let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: input.dropLast(16), tag: input.suffix(16))
            output = try AES.GCM.open(box, using: symmetric)
        } else {
            let box = try AES.GCM.seal(input, using: symmetric, nonce: nonce)
            output = box.ciphertext + box.tag
        }
        return try encode(output, encoding: string(p["outputEncoding"]).nonempty ?? (decrypt ? "utf8" : "base64"))
    }
    static func decode(_ text: String, encoding: String) throws -> Data {
        switch encoding.lowercased() {
        case "utf8", "utf-8": return Data(text.utf8)
        case "base64":
            guard let value = Data(base64Encoded: text.filter { !$0.isWhitespace }) else { throw AppFailure("Base64 格式无效") }; return value
        case "hex":
            guard text.count % 2 == 0 else { throw AppFailure("Hex 长度无效") }
            var bytes = Data(); var index = text.startIndex
            while index < text.endIndex {
                let next = text.index(index, offsetBy: 2)
                guard let byte = UInt8(text[index..<next], radix: 16) else { throw AppFailure("Hex 字节无效") }
                bytes.append(byte); index = next
            }
            return bytes
        case "latin1", "binary":
            guard text.unicodeScalars.allSatisfy({ $0.value <= 255 }) else { throw AppFailure("Latin-1 文本包含超出字节范围的字符") }
            return Data(text.unicodeScalars.map { UInt8($0.value) })
        default: throw AppFailure("不支持的字节编码：\(encoding)")
        }
    }
    static func encode(_ data: Data, encoding: String) throws -> String {
        switch encoding.lowercased() {
        case "utf8", "utf-8":
            guard let value = String(data: data, encoding: .utf8) else { throw AppFailure("数据不是 UTF-8 文本") }; return value
        case "base64": return data.base64EncodedString()
        case "hex": return data.map { String(format: "%02x", $0) }.joined()
        case "latin1", "binary": return String(data.map { Character(UnicodeScalar($0)) })
        default: throw AppFailure("不支持的字节编码：\(encoding)")
        }
    }
}
private extension String { var nonempty: String? { isEmpty ? nil : self } }
private struct DERNode {
    let tag: UInt8, content: Int, length: Int
    var end: Int { content + length }
    static func parse(_ data: [UInt8], at start: Int) throws -> DERNode {
        guard start >= 0, start + 2 <= data.count else { throw AppFailure("DER 字段不完整") }
        let tag = data[start]; var offset = start + 2; var length = Int(data[start + 1])
        if length & 0x80 != 0 {
            let count = length & 0x7f
            guard count > 0, count <= 4, offset + count <= data.count else { throw AppFailure("DER 长度无效") }
            length = 0
            for _ in 0..<count { length = length * 256 + Int(data[offset]); offset += 1 }
        }
        guard length <= data.count - offset else { throw AppFailure("DER 字段超出边界") }
        return DERNode(tag: tag, content: offset, length: length)
    }
    func children(in data: [UInt8]) throws -> [DERNode] {
        var rows: [DERNode] = [], offset = content
        while offset < end {
            let child = try Self.parse(data, at: offset)
            guard child.end <= end else { throw AppFailure("DER 子字段超出边界") }
            rows.append(child); offset = child.end
        }
        return rows
    }
}
