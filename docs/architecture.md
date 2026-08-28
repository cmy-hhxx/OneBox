# 架构

OneBox 是静态注册的模块化单体，见 [ADR-0001](decisions/0001-use-static-module-registration.md)。独立 Xcode target 强制编译依赖，但所有模块仍在同一进程中，不构成安全或崩溃隔离。

## 模块

| Target | 源目录 | 职责 | 项目内依赖 |
| --- | --- | --- | --- |
| `OneBox` | `OneBox/App` | 应用生命周期、窗口、组合根和生产 adapter | Host、Runtime、DesignSystem、全部 Tool |
| `OneBoxHost` | `OneBox/Host` | 侧边栏、选择和内容区域 | Runtime、DesignSystem |
| `OneBoxRuntime` | `OneBox/Runtime` | 工具 ID、注册值和目录 | 无 |
| `OneBoxDesignSystem` | `OneBox/DesignSystem` | 颜色、字体、几何和占位视图 | 无 |
| `*Tool` | `OneBox/Tools/<Tool>` | 工具入口、业务状态和实现 | Runtime、DesignSystem；PodPin 另依赖 GRDB |

依赖方向由 `project.yml` 定义，具体边界见 [ADR-0003](decisions/0003-enforce-module-dependencies-with-targets.md) 和 [ADR-0004](decisions/0004-keep-app-specific-platform-code-in-app.md)。

## 边界

- `OneBox/App/AppComposition.swift` 是唯一注册具体工具的组合根。
- PodPin 通过 `PodPinModule` 惰性组装资料库、导入与播放；registration 构建不打开数据库或安装媒体监听器。
- 工具不得导入其他工具、Host 或 App。
- 无依赖工具可以公开静态 registration；有依赖工具公开窄 factory，由组合根注入平台能力或配置。
- 跨模块接口由使用方定义。工具不得查找宿主、全局容器或系统默认实现。
- 共享代码只在出现第二个真实消费者后提取。

ASCII 工坊通过 `AsciiArtModule.makeRegistration(deviceProvider:)` 接收 `AsciiMetalDeviceProviding`。App 只提供 Metal 设备；解码、会话、渲染和导出留在工具内部。

## 当前运行状态

- 宿主启动时选择第一个 registration，因此 ASCII 工坊默认打开；其他工具在被选择前不构造内容。
- ASCII 工坊在注册时创建内存会话和惰性渲染缓存，不请求设备或执行 I/O。隐藏、窗口失活或暂停时停止持续绘制，关闭视图时取消导入和导出。
- PodPin 首次被选择时才打开 `~/Library/Application Support/PodPin/podpin.sqlite`、恢复播放状态并安装系统媒体命令。切换工具后，已开始的播放和下载由同一 session 继续拥有；应用退出会等待其 flush 和清理。
- PodPin 的公开链接适配、GRDB repository、媒体文件、待播队列和播放进度都留在 `PodPinTool` 内。宿主不读取其数据。可选浏览器访客状态只在反滥用挑战和用户明确选择后临时读取。
- 股票看盘和窗口聚焦仅显示“待接入”。当前没有启动即运行的后台调度；运行时诊断只使用脱敏 Unified Logging。

工具接入规则见 [工具模块契约](module-contract.md)；当前事实仍以源码、测试和 `project.yml` 为准。
