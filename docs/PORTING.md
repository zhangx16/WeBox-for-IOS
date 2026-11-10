# 移植范围与验证边界

| Android 能力 | iOS 实现 | 边界 |
| --- | --- | --- |
| QuickJS 脚本 | JavaScriptCore，复用 APK runtime | JS 语言细节可能不同；源代码不做字符串改写 |
| WeBox.define | 复用校验、游标、过滤、详情/播放映射 | 支持 html/crypto；其他 requires 明确拒绝 |
| WidgetMetadata | 元数据、函数调用、参数、HTTP、存储 | 部分第三方源可能需要未实现的原生接口 |
| XPTV | 复用 xptv.js 兼容层 | 配置、分类、卡片、选集、播放；不含加密取钥 |
| HTTP | URLSession | 支持返回 statusCode/data/headers/url，响应解压由系统处理；非 UTF-8 正文只回退 Latin-1 |
| Crypto | CryptoJS + SecRandomCopyBytes | MD5/SHA/HMAC、编码、CBC/ECB/CTR AES；RSA 不支持 |
| HTML | APK 内 Cheerio | 不执行网页页面 JavaScript |
| mpv | AVPlayer / AVPlayerViewController | 原生解码范围；无法保证 Android 所有容器/编码可用 |
| 播放请求头 | AVURLAsset options | HTTPHeaderFieldsKey 非公开文档约定，系统与分段请求转发行为未保证；需要真机及具体服务器验证 |
| 收藏/历史 | Application Support 中的原子 JSON | 历史最多 200 条，每约 10 秒及退出时记录进度 |
| 下载 | URLSession download | 仅前台 MP4/MOV/M4V；未实现 HLS 离线、后台恢复、并行、进度百分比 |
| 备份 | webox-ios v1 JSON | 合并源、收藏、历史；不包含下载文件和脚本内部缓存；不支持 Android 备份 |
| REXENC | 未实现 | 需要认证取钥的格式直接拒绝，未绕过原服务授权 |
| 内存 HLS / 媒体处理器 / binary / compute / TMDB | 未实现 | 提供明确错误，能力声明为 false |

iOS 没有预装站点或内容订阅。内置演示仅包含 APK 自带的公开 Blender 视频。由用户自行添加有权访问的内容源。

## 生命周期与限制

脚本运行在主线程 JavaScriptCore Context；原生网络异步执行，结果在同一线程回调。每个调用有 65 秒异步截止时间；close 会取消请求与定时器，并释放等待的 continuation。同步脚本死循环无法由这个期限打断，因此不要运行不信任的 JS。浏览器在详情页面下保持 Context，以保留原生游标链。源配置保存后重新进入浏览器以创建新 Context。

脚本存储按源 ID 隔离；sharedCache 与 HTTP Cookie 由所有源共享。删除内容源保留其收藏、历史及内部存储，便于重新安装恢复。应用没有遥测后端。

备份可能含账号/密钥且为明文。用户脚本导入时会执行顶层代码验证元数据，导入备份时亦然；验证完成前不替换现有资料。

## 测试证据

模拟器集成测试覆盖：公开示例全链路的脚本结果、WeBox 设置/筛选/两页游标/详情/播放、XPTV 适配、存储隔离与 nested null、摘要与 UTF-8 Base64、Cheerio、Promise/定时器、脚本异常、未支持能力拒绝及备份持久化。CI 同时编译所有 SwiftUI 和 AVKit 路径并归档设备架构。

未验证：Android 动态行为、第三方站点全量源、真实 HTTP 服务器的特殊 Cookie/跳转策略、真机视频解码/请求头、AirPlay/画中画、实际侧载签名和 App Store 分发。单元测试不等于上述运行验证。
