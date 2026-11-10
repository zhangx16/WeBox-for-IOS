import Foundation

/// A single URI parser is shared by streaming and offline HLS. It retains tags,
/// byte ranges, key declarations and discontinuities instead of concatenating TS data.
enum MediaPlaylist {
    static func rewrite(_ text: String, base: URL, transform: (URL) throws -> String) throws -> String {
        try rewriteResources(text, base: base) { url, _, _ in try transform(url) }
    }
    static func rewriteResources(_ text: String, base: URL, transform: (URL, String, Bool) throws -> String) throws -> String {
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#EXTM3U") else { throw AppFailure("服务器没有返回有效 HLS 清单") }
        let expression = try NSRegularExpression(pattern: "URI=\"([^\"]+)\"")
        var nextVariant = false, nextRange = false
        return try text.components(separatedBy: .newlines).map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return line }
            if !trimmed.hasPrefix("#") {
                defer { nextVariant = false; nextRange = false }
                guard let url = resolve(trimmed, base: base) else { return trimmed }
                return try transform(url, nextVariant || url.pathExtension.lowercased() == "m3u8" ? "playlist" : "segment", nextRange)
            }
            if trimmed.hasPrefix("#EXT-X-STREAM-INF:") { nextVariant = true }
            if trimmed.hasPrefix("#EXT-X-BYTERANGE:") { nextRange = true }
            let kind: String
            if trimmed.hasPrefix("#EXT-X-KEY:") || trimmed.hasPrefix("#EXT-X-SESSION-KEY:") { kind = "key" }
            else if trimmed.hasPrefix("#EXT-X-MAP:") { kind = "init" }
            else if trimmed.hasPrefix("#EXT-X-MEDIA:") || trimmed.hasPrefix("#EXT-X-I-FRAME-STREAM-INF:") { kind = "playlist" }
            else { kind = "resource" }
            var output = line
            for match in expression.matches(in: line, range: NSRange(line.startIndex..., in: line)).reversed() {
                guard let rawRange = Range(match.range(at: 1), in: line), let replacementRange = Range(match.range(at: 1), in: output),
                      let url = resolve(String(line[rawRange]), base: base) else { continue }
                output.replaceSubrange(replacementRange, with: try transform(url, kind, trimmed.contains("BYTERANGE=")))
            }
            return output
        }.joined(separator: "\n")
    }

    static func resolve(_ value: String, base: URL) -> URL? {
        guard let url = URL(string: value, relativeTo: base)?.absoluteURL,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    static func preferredVariant(_ text: String, base: URL) -> URL? {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        var choices: [(Int, URL)] = []
        for (index, line) in lines.enumerated() where line.hasPrefix("#EXT-X-STREAM-INF:") {
            guard index + 1 < lines.count, let url = resolve(lines[index + 1], base: base) else { continue }
            let bandwidth = line.range(of: "BANDWIDTH=[0-9]+", options: .regularExpression).flatMap { Int(line[$0].dropFirst(10)) } ?? 0
            choices.append((bandwidth, url))
        }
        return choices.max { $0.0 < $1.0 }?.1
    }

    static func mime(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "m3u8": return "application/vnd.apple.mpegurl"
        case "ts": return "video/mp2t"
        case "m4s", "mp4", "m4v": return "video/mp4"
        case "aac": return "audio/aac"
        case "vtt": return "text/vtt"
        case "key": return "application/octet-stream"
        default: return "application/octet-stream"
        }
    }
}


enum MediaByteRange {
    static func parse(_ header: String, size: Int) throws -> Range<Int> {
        guard header.hasPrefix("bytes="), !header.contains(","), size >= 0 else { throw AppFailure("无效的媒体 Range 请求") }
        let values = header.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
        guard values.count == 2 else { throw AppFailure("无效的媒体 Range 请求") }
        if values[0].isEmpty {
            guard let suffix = Int(values[1]), suffix > 0, size > 0 else { throw AppFailure("媒体 Range 超出范围") }
            return max(0, size - suffix)..<size
        }
        guard let start = Int(values[0]), start >= 0, start < size else { throw AppFailure("媒体 Range 超出范围") }
        let last = values[1].isEmpty ? size - 1 : Int(values[1]) ?? -1
        guard last >= start else { throw AppFailure("媒体 Range 超出范围") }
        return start..<min(size, last + 1)
    }
}
