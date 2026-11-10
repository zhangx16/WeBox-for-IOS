import Foundation

/// Runtime-owned, bounded binary buffers; handles never reference filesystem paths.
final class BinaryStore {
    private var values: [String: Data] = [:]
    private let limit = 64 * 1024 * 1024
    var byteCount: Int { var total = 0; for value in values.values { total += value.count }; return total }
    func create(_ bytes: Data) throws -> String {
        guard bytes.count <= limit - byteCount else { throw AppFailure("二进制缓冲超过 64 MB 会话额度") }
        let id = "wb:" + UUID().uuidString; values[id] = bytes; return id
    }
    func read(_ handle: String) throws -> Data {
        guard let bytes = values[handle] else { throw AppFailure("二进制句柄已失效或不属于当前会话") }; return bytes
    }
    func clear() { values.removeAll() }
    func release(_ handle: String) { values.removeValue(forKey: handle) }
    func call(_ method: String, _ p: [String: Any]) throws -> Any {
        if method == "binary.concat" {
            guard let handles = p["handles"] as? [String] else { throw AppFailure("二进制拼接参数无效") }
            var result = Data()
            for handle in handles {
                let bytes = try read(handle)
                guard bytes.count <= limit - byteCount - result.count else { throw AppFailure("二进制拼接超过会话额度") }
                result.append(bytes)
            }
            return try create(result)
        }
        let handle = string(p["handle"]); let bytes = try read(handle)
        if method == "binary.size" { return bytes.count }
        let offset = try integer(p["offset"], default: 0)
        let length = try integer(p["length"], default: max(0, bytes.count - offset))
        guard offset <= bytes.count, length <= bytes.count - offset else { throw AppFailure("二进制读写范围越界") }
        switch method {
        case "binary.read":
            guard length <= 65536 else { throw AppFailure("单次二进制读取超过 64 KiB") }
            return bytes.subdata(in: offset..<(offset + length)).base64EncodedString()
        case "binary.slice": return try create(bytes.subdata(in: offset..<(offset + length)))
        case "binary.write":
            let replacement = try NativeCrypto.decode(string(p["data"]), encoding: "base64")
            guard replacement.count <= 65536, replacement.count <= bytes.count - offset else { throw AppFailure("二进制写入越界或超过 64 KiB") }
            var result = bytes; result.replaceSubrange(offset..<(offset + replacement.count), with: replacement); return try create(result)
        case "binary.patch":
            guard let patches = p["patches"] as? [[String: Any]] else { throw AppFailure("二进制补丁参数无效") }
            var result = bytes
            for patch in patches {
                let start = try integer(patch["offset"], default: 0)
                let replacement = try NativeCrypto.decode(string(patch["data"]), encoding: "base64")
                guard start <= result.count, replacement.count <= result.count - start else { throw AppFailure("二进制补丁范围越界") }
                result.replaceSubrange(start..<(start + replacement.count), with: replacement)
            }
            return try create(result)
        default: throw AppFailure("未知二进制接口")
        }
    }
    private func integer(_ raw: Any?, default fallback: Int) throws -> Int {
        guard let raw else { return fallback }
        guard let number = raw as? NSNumber, number.doubleValue.isFinite, number.doubleValue >= 0, number.doubleValue.rounded(.towardZero) == number.doubleValue, number.doubleValue <= Double(Int.max - 1) else { throw AppFailure("二进制偏移或长度不是非负整数") }
        return number.intValue
    }
}
