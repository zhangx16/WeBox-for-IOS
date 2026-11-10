import Foundation
import CryptoKit

/// Parsers/adapters for the formats shipped by the Android app. No source needs
/// to know about an iOS-only provider: imported formats become ordinary scripts.
enum SourceFormats {
    static let maximumDocumentBytes = 4 * 1024 * 1024
    static let rexKeyEndpoint = URL(string: "https://api.rexnow.tv/api/widgets/key-session")!

    struct REXContainer {
        let iv: Data
        let keyBlob: String
        let ciphertext: Data
    }
    struct SubscriptionEntry {
        let title: String
        let url: URL
        let type: String
    }
    struct Channel {
        var title: String
        var url: String
        var group: String
        var poster: String
        var headers: [String: String]
        var live: Bool
    }

    static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}")))
    }
    static func stableID(_ value: String, prefix: String) -> String {
        prefix + "." + SHA256.hash(data: Data(value.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
    static func httpURL(_ text: String, relativeTo base: String? = nil) throws -> URL {
        let baseURL = base.flatMap(URL.init(string:))
        guard let url = URL(string: clean(text), relativeTo: baseURL)?.absoluteURL,
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil,
              url.user == nil, url.password == nil else { throw AppFailure("来源清单包含无效的 HTTP(S) 地址") }
        return url
    }
    static func parseREX(_ text: String) throws -> REXContainer {
        let text = clean(text)
        guard text.utf8.count <= 2 * 1024 * 1024 else { throw AppFailure("REXENC 文件超过 2 MB") }
        guard text.hasPrefix("REXENC\n") else { throw AppFailure("REXENC 文件头或换行格式无效") }
        let tail = text.dropFirst(7)
        guard let newline = tail.firstIndex(of: "\n"), tail[..<newline].utf8.count <= 4096,
              let header = try? jsonObject(String(tail[..<newline])) as? [String: Any] else { throw AppFailure("REXENC JSON 头缺失或无效") }
        guard let version = header["v"] as? NSNumber, version.doubleValue == 2,
              string(header["mkv"]) == "rex-1", string(header["alg"]) == "A256GCM" else { throw AppFailure("不支持此 REXENC 容器版本、密钥协议或算法") }
        guard let iv = Data(base64Encoded: string(header["iv"])), iv.count == 12 else { throw AppFailure("REXENC IV 长度无效") }
        let keyBlob = string(header["kb"])
        guard let decodedKeyBlob = Data(base64Encoded: keyBlob), decodedKeyBlob.count == 60 else { throw AppFailure("REXENC 取钥参数长度无效") }
        let body = clean(String(tail[tail.index(after: newline)...]))
        guard let ciphertext = Data(base64Encoded: body), ciphertext.count > 16 else { throw AppFailure("REXENC 正文缺少有效密文或认证标签") }
        return REXContainer(iv: iv, keyBlob: keyBlob, ciphertext: ciphertext)
    }
    static func decryptREX(_ container: REXContainer, key: Data) throws -> String {
        guard key.count == 32 else { throw AppFailure("REXENC 内容密钥长度无效") }
        do {
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: container.iv), ciphertext: container.ciphertext.dropLast(16), tag: container.ciphertext.suffix(16))
            let plaintext = try AES.GCM.open(box, using: SymmetricKey(data: key))
            guard plaintext.count <= 2 * 1024 * 1024, let script = String(data: plaintext, encoding: .utf8) else { throw AppFailure("REXENC 解密正文不是有效 UTF-8 脚本或超过限制") }
            return script
        } catch let error as AppFailure { throw error }
        catch { throw AppFailure("REXENC 认证解密失败，密钥不匹配或文件已损坏") }
    }
    static func decodeScript(_ text: String, session: URLSession = .shared, keyEndpoint: URL = rexKeyEndpoint) async throws -> String {
        guard clean(text).hasPrefix("REXENC") else { return text }
        let container = try parseREX(text)
        guard keyEndpoint.scheme?.lowercased() == "https" else { throw AppFailure("REXENC 取钥服务必须使用 HTTPS") }
        var request = URLRequest(url: keyEndpoint)
        request.httpMethod = "POST"; request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("WeBox/REXENC-v2", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["kb": container.keyBlob, "mkv": "rex-1"])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AppFailure("REXENC 取钥服务未返回 HTTP 响应") }
        if [401, 403].contains(http.statusCode) { throw AppFailure("REXENC 取钥被拒绝，需要服务端认可的授权") }
        guard (200..<300).contains(http.statusCode) else { throw AppFailure("REXENC 取钥失败（HTTP \(http.statusCode)）") }
        guard data.count <= 65536, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let key = Data(base64Encoded: string(object["key"])), key.count == 32 else { throw AppFailure("REXENC 取钥响应或内容密钥无效") }
        return try decryptREX(container, key: key)
    }

    static func subscription(_ object: [String: Any], origin: String) throws -> [SubscriptionEntry]? {
        let rows: [[String: Any]]
        let kind: String
        if let sources = object["sources"] as? [[String: Any]], object["format"] == nil {
            if let version = object["version"] as? NSNumber, version.doubleValue != 1 { throw AppFailure("不支持的来源清单版本") }
            rows = sources; kind = "sources"
        } else if let widgets = object["widgets"] as? [[String: Any]] { rows = widgets; kind = "widgets" }
        else if let vods = object["vods"] as? [[String: Any]] { rows = vods; kind = "vods" }
        else { return nil }
        guard rows.count <= 100 else { throw AppFailure("来源合集最多支持 100 项") }
        return try rows.filter { $0["enabled"] as? Bool != false }.map { row in
            let rawType = string(row["type"]).lowercased()
            let type: String
            if kind == "widgets" { type = "js" }
            else if kind == "vods" {
                switch row["type"] as? Int { case 0, 1: type = "vod"; case 11: type = "m3u"; default: throw AppFailure("来源合集包含尚不支持的 VOD 类型") }
            } else { type = rawType.isEmpty ? "auto" : rawType }
            guard ["auto", "js", "m3u", "vod", "xml", "json"].contains(type) else { throw AppFailure("来源合集格式不受支持：\(type)") }
            return SubscriptionEntry(title: string(row["name"] ?? row["title"]), url: try httpURL(string(row["url"]), relativeTo: origin), type: type)
        }
    }

    static func parseM3U(_ text: String, origin: String) throws -> [Channel] {
        let text = clean(text)
        guard text.hasPrefix("#EXTM3U") else { throw AppFailure("无效的 M3U 文件头") }
        guard text.utf8.count <= maximumDocumentBytes else { throw AppFailure("M3U 文件超过 4 MB") }
        var channels: [Channel] = []
        var title = "", group = "", poster = "", headers: [String: String] = [:]
        for raw in text.components(separatedBy: .newlines) {
            let line = clean(raw)
            if line.hasPrefix("#EXTINF:") {
                title = commaSeparatedTitle(line)
                group = attribute("group-title", in: line)
                poster = attribute("tvg-logo", in: line)
                headers = [:]
            } else if line.lowercased().hasPrefix("#extvlcopt:http-user-agent=") { headers["User-Agent"] = String(line.dropFirst("#EXTVLCOPT:http-user-agent=".count)) }
            else if line.lowercased().hasPrefix("#extvlcopt:http-referrer=") { headers["Referer"] = String(line.dropFirst("#EXTVLCOPT:http-referrer=".count)) }
            else if !line.isEmpty && !line.hasPrefix("#") {
                let url = try httpURL(line, relativeTo: origin)
                if title.isEmpty && text.contains("#EXT-X-TARGETDURATION") {
                    guard let playlist = try? httpURL(origin) else { throw AppFailure("媒体 HLS 文件请使用它的在线地址添加") }
                    return [Channel(title: "HLS 播放列表", url: playlist.absoluteString, group: "播放列表", poster: "", headers: [:], live: !text.contains("#EXT-X-ENDLIST"))]
                }
                let logo = poster.isEmpty ? "" : (try? httpURL(poster, relativeTo: origin).absoluteString) ?? ""
                channels.append(Channel(title: title.isEmpty ? url.lastPathComponent : title, url: url.absoluteString, group: group, poster: logo, headers: headers, live: true))
                title = ""; group = ""; poster = ""; headers = [:]
                guard channels.count <= 10000 else { throw AppFailure("直播列表最多支持 10000 条线路") }
            }
        }
        guard !channels.isEmpty else { throw AppFailure("M3U 文件没有可播放的 HTTP(S) 线路") }
        return channels
    }
    private static func attribute(_ name: String, in text: String) -> String {
        guard let re = try? NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: name) + #"\s*=\s*["']([^"']*)["']"#),
              let match = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let range = Range(match.range(at: 1), in: text) else { return "" }
        return String(text[range])
    }
    private static func commaSeparatedTitle(_ text: String) -> String {
        var quoted = false
        for index in text.indices {
            if text[index] == "\"" { quoted.toggle() }
            if text[index] == "," && !quoted { return String(text[text.index(after: index)...]).trimmingCharacters(in: .whitespaces) }
        }
        return attribute("tvg-name", in: text)
    }
    static func m3uScript(_ text: String, title: String, origin: String) throws -> String {
        let channels = try parseM3U(text, origin: origin)
        let identifier = stableID(origin == "pasted" ? text : origin, prefix: "m3u")
        let rows: [[String: Any]] = channels.enumerated().map { index, channel in
            ["id": "channel-\(index)", "type": "url", "title": channel.title, "link": channel.url, "videoUrl": channel.url, "posterPath": channel.poster, "description": channel.group, "isLive": channel.live, "headers": channel.headers, "group": channel.group]
        }
        let groups = Array(Set(channels.map(\.group).filter { !$0.isEmpty })).sorted()
        let metadata: [String: Any] = ["id": identifier, "title": title.isEmpty ? "M3U 直播" : title, "version": "1.0.0", "modules": [["id": "channels", "title": "频道", "functionName": "loadList", "params": [["name": "group", "title": "分组", "type": "enumeration", "enumOptions": [["title": "全部", "value": ""]] + groups.map { ["title": $0, "value": $0] }], ["name": "page", "type": "page"]]], ["id": "stream", "title": "播放", "type": "stream", "functionName": "loadResource", "params": []]], "search": ["id": "search", "title": "搜索", "functionName": "search", "params": [["name": "keyword", "type": "input"], ["name": "page", "type": "page"]]]]
        return #"""
        // WeBox iOS generated M3U adapter.
        var WidgetMetadata = __METADATA__;
        var __channels = __ROWS__;
        async function loadList(p){var rows=__channels.filter(x=>!p.group||x.group===p.group),offset=(Math.max(1,Number(p.page)||1)-1)*30;return {items:rows.slice(offset,offset+30),hasMore:offset+30<rows.length};}
        async function search(p){var q=String(p.keyword||'').toLowerCase(),rows=__channels.filter(x=>x.title.toLowerCase().includes(q)),offset=(Math.max(1,Number(p.page)||1)-1)*30;return {items:rows.slice(offset,offset+30),hasMore:offset+30<rows.length};}
        async function loadDetail(link){var item=__channels.find(x=>x.link===link);if(!item)throw Error('频道已移除');return item;}
        async function loadResource(p){var item=await loadDetail(p.link);return [{name:item.title,url:item.videoUrl,headers:item.headers,isLive:item.isLive,downloadable:!item.isLive}];}
        """#.replacingOccurrences(of: "__METADATA__", with: try jsonText(metadata)).replacingOccurrences(of: "__ROWS__", with: try jsonText(rows))
    }

    static func vodScript(_ config: [String: Any], title: String, origin: String) throws -> String {
        let api = try httpURL(string(config["api"] ?? config["url"]), relativeTo: origin).absoluteString
        let identifier = stableID(api, prefix: "vod")
        let settings: [String: Any] = ["api": api, "id": identifier, "title": string(config["name"] ?? config["title"]).isEmpty ? (title.isEmpty ? "AppleCMS" : title) : string(config["name"] ?? config["title"]), "headers": config["headers"] as? [String: String] ?? [:]]
        return #"""
        // WeBox iOS generated AppleCMS v10 JSON adapter.
        const __vod=__CONFIG__;
        async function __vodRequest(ctx,q){const r=await ctx.http.get(__vod.api,{query:q,headers:__vod.headers,responseType:'text'});if(r.status<200||r.status>=300)ctx.fail('NETWORK','VOD 服务响应异常（HTTP '+r.status+'）');let data;try{data=typeof r.data==='string'?JSON.parse(r.data):r.data;}catch(_){const $=ctx.html.load(r.data),map={id:'vod_id',name:'vod_name',pic:'vod_pic',note:'vod_remarks',des:'vod_content',type:'type_name'};data={class:$('class ty').toArray().map(n=>({type_id:$(n).attr('id'),type_name:$(n).text()})),pagecount:Number($('list').attr('pagecount')||1),list:$('list video').toArray().map(n=>{let row={};for(const [tag,key]of Object.entries(map))row[key]=$(n).children(tag).first().text();row.vod_play_from=$(n).find('dl dd').toArray().map(d=>$(d).attr('flag')||'线路').join('$$$');row.vod_play_url=$(n).find('dl dd').toArray().map(d=>$(d).text()).join('$$$');return row;})};}if(!data||!Array.isArray(data.list))ctx.fail('INVALID_RESPONSE','VOD 服务没有返回可识别目录');return data;}
        function __vodCard(x){return {id:String(x.vod_id),title:String(x.vod_name||'未命名影片'),kind:'unknown',poster:String(x.vod_pic||''),subtitle:String(x.vod_remarks||'')};}
        function __vodGroups(x){const names=String(x.vod_play_from||'').split('$$$');return String(x.vod_play_url||'').split('$$$').map((row,i)=>({id:String(i),name:names[i]||'线路 '+(i+1),episodes:row.split('#').map((entry,j)=>{const k=entry.indexOf('$'),name=k<0?'播放 '+(j+1):entry.slice(0,k),url=k<0?entry:entry.slice(k+1);return {id:encodeURIComponent(JSON.stringify([j,url])),name:name||'播放 '+(j+1),url};}).filter(e=>/^https?:\/\//i.test(e.url))})).filter(g=>g.episodes.length);}
        async function __vodDetailRow(ctx,id){const data=await __vodRequest(ctx,{ac:'videolist',ids:id});if(!data.list[0])ctx.fail('NOT_FOUND','VOD 影片已移除');return data.list[0];}
        WeBox.define({api:'1.1',id:__vod.id,name:__vod.title,version:'1.0.0',allowHttp:true,requires:['html'],
          async filters(ctx){const data=await __vodRequest(ctx,{ac:'list'});return [{key:'category',label:'分类',type:'select',default:'',options:[{label:'全部',value:''}].concat((data.class||[]).map(x=>({label:String(x.type_name||x.type_id),value:String(x.type_id)})))}];},
          async list(ctx,r){const page=Number(r.cursor||1),data=await __vodRequest(ctx,{ac:'videolist',t:r.filters.category||'',pg:page});return {items:data.list.map(__vodCard),nextCursor:page<Number(data.pagecount||1)?String(page+1):null};},
          async search(ctx,r){const page=Number(r.cursor||1),data=await __vodRequest(ctx,{ac:'videolist',wd:r.query,pg:page});return {items:data.list.map(__vodCard),nextCursor:page<Number(data.pagecount||1)?String(page+1):null};},
          async detail(ctx,r){const x=await __vodDetailRow(ctx,r.id),groups=__vodGroups(x);return {id:r.id,title:String(x.vod_name||'未命名影片'),kind:'unknown',poster:String(x.vod_pic||''),summary:String(x.vod_content||'').replace(/<[^>]*>/g,'').replace(/&nbsp;/g,' '),groups:groups.map(g=>({id:g.id,name:g.name,episodes:g.episodes.map(e=>({id:e.id,name:e.name}))}))};},
          async play(ctx,r){const x=await __vodDetailRow(ctx,r.contentId),group=__vodGroups(x).find(g=>g.id===r.groupId),episode=group&&group.episodes.find(e=>e.id===r.episodeId);if(!episode)ctx.fail('NOT_FOUND','VOD 选集或线路已变化');return {sources:[{id:group.id,name:group.name,url:episode.url,headers:__vod.headers}]};}
        });
        """#.replacingOccurrences(of: "__CONFIG__", with: try jsonText(settings))
    }
}

struct SourceSubscription: Codable, Identifiable {
    var id: String
    var title: String
    var url: String
    var sourceIDs: [String]
    var updatedAt: Date
}
