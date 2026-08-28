# ADR-0007: 将 PodPin 作为内置工具迁入 OneBox

- Status: Accepted
- Date: 2026-08-27

## Context

PodPin 已经是一个本地优先的单用户音频资料库，拥有公开链接导入、SQLite
资料库、在线与离线播放、持久待播队列、播放进度和系统媒体控制。OneBox 中原有的
“博客收听”仍是占位，但 PodPin 的能力已超出博客范围。

PodPin 原来同时拥有独立应用生命周期、资料库窗口、菜单栏、全局快捷键和浮动窗口。
原样嵌入会产生第二个组合根，并在应用启动时注册进程级监听器。PodPin 还首次为
OneBox 引入业务持久化、后台播放、GRDB 和打包媒体工具。

## Options considered

### 保留独立 PodPin，只从 OneBox 打开

不影响现有应用，但 OneBox 不能管理它的状态、生命周期和界面，也没有完成工具迁移。

### 把 PodPin 独立应用壳原样编进 OneBox

功能表面最接近原应用，但会引入第二个 `@main`、窗口与设置命令冲突、重复导航以及
未受宿主管理的全局资源。

### 迁入一个静态 PodPin 工具 module

复用成熟的领域实现，在 OneBox 内容与生命周期内重新组合；独立应用壳不进入工具
module。需要明确后台生命周期、数据位置和媒体工具发行方式。

## Decision

- 用独立 `PodPinTool` target 替换“博客收听”占位，并在 `AppComposition` 第三位静态
  注册一次。稳定 ID 为 `podpin`，展示名称为 `PodPin`。
- `PodPinTool` 只依赖 Runtime、DesignSystem 和精确锁定的 GRDB 7.11.1。它不导入
  Host、App 或其他工具，也不建立共享音频或平台 target。
- registration 构建保持零业务 I/O、零监听器。用户首次选择 PodPin 后才打开资料库、
  构造播放对象和安装媒体命令。首次激活后，明确开始的播放和下载可以在切换工具后
  继续；导入探测、WebKit 和浏览器授权等瞬态工作在离开相关界面时取消。
- `ToolRegistration` 增加一个默认 no-op 的异步应用退出 hook。App 统一等待已激活
  工具 flush 状态并移除监听器后再完成退出。这是后台工具唯一新增的宿主生命周期
  interface，不加入后台启动或通用 capability bag。
- 不迁入第二个 `@main`、PodPin activation policy、独立资料库 Window、全局设置命令
  或第二套常驻侧栏。资料库、导入、正在播放和设置在 OneBox 工具内容区内切换；
  原浮动播放器的核心控制改成 OneBox 内常驻的紧凑播放条。
- 继续使用 `~/Library/Application Support/PodPin/` 作为 PodPin 工具拥有的数据
  namespace。数据库只保存该目录内的相对媒体路径，因此零复制保留现有资料库、队列、
  进度与媒体。偏好继续读取 `io.github.cmy-hhxx.podpin` suite。OneBox 不解析这些数据，
  同时运行独立 PodPin 与 OneBox PodPin 工具不在支持范围内，且迁移不得删除旧数据。
- OneBox 继续保持非 App Sandbox 和 Hardened Runtime。网络只由用户导入触发；浏览器
  Profile 只在类型化反滥用挑战和用户明确选择后读取，临时 Cookie、header 和媒体 URL
  不写入业务存储或日志。
- 离线下载继续使用锁定的 `ffmpeg`、`ffprobe` 和暂留 `yt-dlp`。二进制不进入 Git；
  专用脚本校验来源、哈希、arm64、动态依赖和许可证后再放入并重签 OneBox app。
- 运行时诊断只使用脱敏的 macOS Unified Logging，不迁移 PodPin 的 JSONL 文件日志。

## Consequences

### Positive

- 原有资料库无需复制或格式转换，成熟的导入、播放、队列与下载实现仍位于一个深
  module 内。
- 未使用 PodPin 的 OneBox 启动不打开数据库、不请求权限，也不占用媒体命令。
- 后台播放和退出 flush 获得显式 owner，重复打开不会重复注册监听器。
- OneBox 保持单一窗口、组合根和设计系统。

### Negative

- 独立 PodPin 与 OneBox 不能同时作为同一资料库的写入者。
- 原菜单栏入口、全局 `⌘⌥P` 和跨 Space 独立浮窗不属于本次嵌入式工具 interface；
  如果后续恢复，必须由 App target 的单一窄 desktop-host adapter 承担并另写 ADR。
- GRDB、媒体工具、嵌套签名和许可证材料增加了构建与发行成本。
- 非 sandbox 路线不适用于当前 App Store 分发；若产品范围改变，需要重新决定浏览器
  恢复、外部进程和旧资料库访问方式。
