# WeBox for iOS

基于本机 WeBox Android 0.1.64（versionCode 67）静态分析实现的 iOS 原生移植预览版。SwiftUI + JavaScriptCore + AVPlayer，最低 iOS 17，支持 iPhone / iPad。

当前版本 0.2.0 新增独立 JS/WASM 计算、RSA/AES-GCM、二进制缓冲、内存 HLS 与媒体处理代理、mpv 引擎、HLS 离线包、REXENC 认证取钥、订阅、M3U/AppleCMS、Android 备份和 TMDB；重新设计发现、全局搜索与源管理界面。

三个用户提供的 JS 源作为测试夹具回归验证，不预装站点。完整能力与验证边界见 [0.2 兼容说明](docs/COMPATIBILITY-0.2.md)。界面离线预览见 [preview.html](docs/ui-draft/preview.html)。

## 获取 IPA

优先从 [Releases](https://github.com/zhangx16/WeBox-for-IOS/releases) 下载对应版本 IPA。也可以进入 [GitHub Actions](https://github.com/zhangx16/WeBox-for-IOS/actions/workflows/ios.yml)，打开最近成功的 `Build iOS`，下载 `WeBox-iOS-unsigned`，解压取得 `WeBox-unsigned.ipa`。

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
