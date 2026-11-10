# APK 静态分析记录

输入：`WeBox-0.1.64-beta.apk`，SHA-256 `3471efd5adf82ade673532f82f5d024cbc76a611a9f20fcc3bcb82be33e7891b`。

REA CLI 6.7.0；JADX headless MCP 0.7.1 JAR SHA-256 `6e5eacf500b64292bfb73c49797c1958f6ee44646e43e868039ae7feb573ff75`，OpenJDK 17。REA inspect-android-package Evidence ID：`ev_830bbe19d39389de6855055fa910171bc98c104b4d64a388f4c3d99226b99395`。

观测：包名 dev.webox.app，versionName 0.1.64，versionCode 67，minSdk 23，targetSdk 36。APK build-info：revision 67b2bff5，timestamp 2026-11-08 15:51:58 UTC+8。REA 类元数据 2650；JADX 加载展开类 2833。全量反编译报告 54 个错误，不能把反编译 Java 当作完整源码。

已声明 Activity：MainActivity、PlayerActivity、ArtworkActivity、ScriptViewerActivity、ReleaseNoticeActivity；DownloadService 为 dataSync 前台服务。lib/arm64-v8a 下包含 QuickJS、mpv、FFmpeg。资源目录根部（不是 assets 子目录）含 runtime/webox.js、widget.js、xptv.js、cheerio.js、cryptojs.js、web-licenses.txt 和 modules/demo.js。

主要移植证据：

- runtime/widget.js：WidgetMetadata、__weboxMetadata、__weboxInvoke、同步/异步 host 接口。
- runtime/webox.js：WeBox.define API 1.0/1.1、settings/filters/list/search/detail/play、游标链、media/binary/compute 的能力声明。
- runtime/xptv.js：getConfig/getCards/getTracks/getPlayinfo 到 Widget 的映射。
- modules/demo.js：公开 Big Buck Bunny URL、分类、搜索、详情及播放线路的示例。
- 反编译类 fr1：WidgetManifest、hostProtocol 与 catalogReady。
- 反编译类 s2/cq0：REXENC 认证取钥和失败条件。此能力未移植，未访问取钥服务。

本机完整 REA JSON、反编译结果保存在 `/root/webox-analysis/`，不提交 APK 与全量 Java。仓库保存运行资源逐文件 SHA-256 以便重现；具体命令可通过 REA inspect-android-package、search-android-classes、inspect-android-class 对同一输入重跑。

所有观测均为静态证据；未启动 Android App 或模拟器，没有将静态推导表述为动态复现。
