# WeBox for iOS

基于本机 WeBox Android 0.1.64（versionCode 67）静态分析实现的 iOS 原生移植预览版。SwiftUI + JavaScriptCore + AVPlayer，最低 iOS 17，支持 iPhone / iPad。

目前支持：

- 明文 JavaScript 内容源：WeBox.define 1.0/1.1、WidgetMetadata、XPTV getConfig/getCards/getTracks/getPlayinfo。
- 链接、文件与文本导入；源全局配置；分类、动态筛选、分页、搜索、详情与选集。
- AVPlayer 直播/点播、线路切换、AirPlay、画中画、播放进度与继续观看。
- 收藏、观看历史、iOS JSON 备份导入导出、MP4/MOV/M4V 直链下载与本地播放。
- 原生 HTTP 请求（请求头、Cookie、重定向、查询参数、正文）、Cheerio、CryptoJS 常用摘要/编码/AES、源隔离存储、JS 定时器。
- 内置 APK 提供的公开 Big Buck Bunny 示例，可直接验证浏览 → 搜索 → 详情 → 播放。

兼容范围详见 [移植说明](docs/PORTING.md)。这不是 Android 功能的完整等价实现。暂不支持 REXENC、订阅集合、Android 备份、mpv、内存 HLS、媒体处理器、binary、compute、RSA 与原生 TMDB 主机接口。仅安装信任的脚本；脚本与 App 同进程运行，恶意死循环不受异步调用超时保护。

## 获取 IPA

进入 [GitHub Actions](https://github.com/zhangx16/WeBox-for-IOS/actions/workflows/ios.yml)，打开最近成功的 `Build iOS`，下载 `WeBox-iOS-unsigned`，解压取得 `WeBox-unsigned.ipa`。

**这是未签名 IPA，不能直接安装到普通 iPhone。** 请使用自己的开发者证书 / 侧载工具签名后安装，或用 Xcode 选择自己的 Team 构建。仓库不包含签名证书，不提供已签名安装包。GitHub Artifact 下载需要登录，保留 30 天；可手动重新运行工作流生成。

## 本地构建

需要 macOS、Xcode 16+、XcodeGen：

```sh
brew install xcodegen
xcodegen generate
open WeBox.xcodeproj
```

选择 WeBox scheme，在 Signing & Capabilities 中设置自己的 Team 和唯一 Bundle Identifier，然后运行。模拟器不需要开发者证书。测试目标 `WeBoxTests` 覆盖内置示例、WeBox 原生协议、XPTV、存储、HTML、加密、异常传播及备份。

CI 在 macOS 上生成工程，先运行 iOS 模拟器测试，再 archive iPhone App 并打包未签名 IPA。Linux 不能运行 Xcode；编译结果以 CI 为准。

## 分析来源与许可

APK SHA-256：`3471efd5adf82ade673532f82f5d024cbc76a611a9f20fcc3bcb82be33e7891b`。

使用 [REA](https://github.com/morluto/rea) 6.7.0 与固定摘要的 JADX headless 0.7.1 静态分析；未执行 Android App。只提交移植代码和需用的 JS 运行资源，不提交 APK、反编译 Java 全量或本机凭证。来源与摘要见 [分析记录](docs/REVERSE_ENGINEERING.md)。

本项目按 [GPL-3.0](LICENSE) 发布。APK 内提供 GPL-3.0 文本；复用其运行库和演示脚本的版权归原作者。第三方 JS 依赖声明见 [web-licenses.txt](WeBox/Resources/Runtime/web-licenses.txt)。Android App 顶层具体授权与上游源码地址仍待确认；发布至 App Store 或其他渠道前应核实原作者授权及 GPL 对应源码要求。
