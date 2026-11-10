# 0.2 功能与验证

此版继续使用当前 WeBox-for-IOS 工程。第一期 Webox-IOS 仅用于查漏补缺；新 UI 按用户指定的 ui-design-iteration 技能优化，不整包替换旧工程。

新增实现：

- 发现页、内容源切换、最近观看、全局搜索、显式配置入口、系统深浅色；离线 UI 预览及审查记录见 ui-draft/。
- WKWebView 独立 Worker 计算环境，支持 WebAssembly、Base64 二进制输入、1 MB 输出上限、任务截止时间和取消；CSP 禁止 Worker 网络请求。
- RSA PKCS#1 加解密，解析 SPKI / PKCS#8 包装；解密返回 UTF-8，与 Android 端契约一致。补齐 AES-GCM。
- binary size/read/write/slice/patch/concat；每会话 64 MB，write/patch 返回新句柄，保留输入缓冲。
- 请求头统一通过 token 隔离的 loopback 代理传递到 HLS 清单、变体、密钥、初始化段及媒体分片。支持 memoryHls、mediaProcessor request/response 和处理后 Range。
- AVPlayer 与 MPVKit/libmpv 双引擎；mpv 使用 CAMetalLayer/MoltenVK 渲染。播放器内可切换引擎、倍速与画面比例；系统播放器支持 AirPlay 和画中画。
- 前台 HLS 离线包，保留清单、AES 密钥、初始化段与 byte range，不把 TS 简单拼接为 MP4。拒绝尚未结束的直播清单。
- REXENC v2：按 APK 协议向原 HTTPS 服务请求内容密钥并进行 AES-GCM 认证解密；401/403 直接报告需要原服务授权，不绕过认证。
- 来源合集更新、M3U、AppleCMS JSON/XML 适配、Android ordinary 备份及第一期 iOS 备份导入；Android 未映射设置保留在备份侧边数据中。
- Widget.tmdb 接口与可配置 API Key/Bearer Token、HTTPS 服务和语言。

## 三个用户脚本

原文件保存在 TestFixtures/，仅复制到测试 Bundle，不预装到 App，不修改脚本中的站点算法。文件用于回归导入及真实 WebAssembly 兼容性。

Linux/Node 的实际网络探测（不代表 iOS 真机视频验证）：

| 源 | 导入 | 目录 | 选集 / 播放线路 |
| --- | --- | --- | --- |
| 4K影视 | 成功 | 首屏 30 项 | 55 选集；取得 1 条播放线路 |
| 瓜子 | 成功 | 首屏 30 项 | 首条影片无选集，下一条有 1 集；取得 1 条播放线路 |
| 磁力熊 | 成功 | 首屏 23 项 | 1 个网页入口；取得 1 条播放线路 |

站点内容、接口和访问授权可能改变；应用不为网站补造选集，也不把磁力链接转换成直接媒体。应以网页实际返回的可用入口为准。

## 仍需区分的边界

本轮补上了此前被拒绝的主机能力，但不是对 Android 全部行为的无条件等价保证：mpv 的 HDR/硬解/音轨表现、iOS 真机 AirPlay/画中画和特殊 CDN 均需设备验证；下载暂为前台单任务，尚未提供后台断点恢复与队列管理；原生 JSContext 中恶意同步死循环仍无法被异步超时终止。REXENC 密钥服务是否批准具体用户取决于原服务。DRM/FairPlay/Widevine 不在这些普通源接口的实现范围内。

开源：MPVKit 以固定提交与 SwiftPM 校验和引用，二进制来自其公开 release，见项目 project.yml。原 JS 运行资源保留原始许可；第一期代码参考地址与提交记录在设计契约中。
