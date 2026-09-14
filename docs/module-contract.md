# 工具模块契约

工具以 `ToolRegistration` 静态进入组合根，不通过配置或磁盘扫描发现：

```swift
ToolRegistration(
    id: id,
    displayName: name,
    systemImage: "headphones",
    summary: "收藏、整理与收听音频"
) {
    ToolScene()
}
```

注册值包含 ID、展示名称、SF Symbol 名称 `systemImage`、简短用途 `summary`、SwiftUI 内容构造方式和默认 no-op 的应用退出清理方式。宿主在侧栏显示图标与名称，在内容区显示名称与非空用途；注册过程只提供静态元数据。`systemImage` 默认 `square.grid.2x2`、`summary` 默认空串，当前三个工具均显式提供。无依赖工具可以公开静态 registration；需要平台能力或配置时，公开窄 `makeRegistration(...)` factory，并在工具内部组装状态和实现。注册过程不得执行业务 I/O、安装监听器或提前创建昂贵资源；退出 hook 只由 App 在确认退出时调用。

股票看盘使用 `StockWatchModule.makeRegistration(platform:)`。工具定义的 `@MainActor StockWatchPlatformClient` 只有 `copyText(_:)`、`revealDirectory(_:)`、`playAlertSound(at:)` 和 `stopAlertSound()`；工具从自己的 package bundle 解析提醒声音 URL，App 的 `MacStockWatchPlatformClient` 只提供唯一 AppKit 播放 adapter。网络、数据库和领域状态不放进 platform 接口，也不由 Host 管理。其可见内容离屏时排空持久化并关库；应用在内容仍可见时退出，则由 registration hook 请求同一个幂等 shutdown。只有媒体 session 可以在离屏后继续用户已明确启动的播放或下载。

## 边界与生命周期

- 每个工具位于 `Packages/Tools/<ToolName>/`，只发布同名静态 library product，并从自己的 manifest 精确声明所需 Runtime、DesignSystem 和第三方 package；不得依赖或导入其他工具、Host 或 App。
- 工具 package 实体拥有自己的 `Sources`、`Tests` 和业务资源。实现使用 `Bundle.module` 读取 package 资源；只有 App 发行流程拥有的资源或二进制才通过窄接口或显式 URL 注入。
- 跨模块平台接口由工具定义，由 App 提供生产 adapter；测试使用同一接口提供 stand-in。
- 工具内容在被选择时构造，首个 registration 在应用启动时默认打开。当前没有启动后台激活机制；已被用户激活的媒体工具可以继续拥有明确开始的播放和下载。
- 同一工具最多有一个活动实例；重复打开不得重复注册监听器。
- 离开工具界面时取消与该界面绑定的探测、授权和刷新。明确允许后台继续的播放或下载由 registration 捕获的 session 持有；应用退出时，宿主同时启动所有 registration 的清理，并在同一个 15 秒期限内等待其持久化和移除任务、定时器与订阅。期限到达后取消全部准备并继续退出。shutdown 必须幂等且可取消；超时退出不能声称持久化已完成。异步工作必须有取消点和超时。
- 工具拥有业务状态和存储命名空间；宿主不解析工具数据。
- 工具把可恢复错误转换为可分类、可展示的结果，不得终止宿主。

优先使用 SwiftUI 的 scene、view 和 task 生命周期，不增加通用激活层。需要启动后台任务时，必须同时定义宿主调度、生命周期测试和对应 ADR。

## 诊断

- 三个工具的 registration factory 接受 Runtime 定义的 `ToolDiagnostics`，默认 `.disabled`。组合根绑定模块身份并注入；工具不依赖 Host 的存储或日志界面。
- 在捕获原始错误、尚未转换为用户提示的边界调用 `record(_:operation:)`。操作名描述失败步骤，不拼接用户内容；已有原始校验诊断可使用 `record(message:operation:)`。
- Error 事件保留 domain/code、原有描述和最深层 underlying error；取消任务、取消网络请求和用户取消不作为错误上报。Host 在进入内存记录前统一移除敏感路径、查询和授权字段。
- 工具可通过 SwiftUI environment 中的 `openToolDiagnostics` 请求展开并筛选当前模块的日志；默认 action 为 no-op。Host 在主窗口底部呈现可调整高度的日志区域，App 提供复制能力和快捷键。日志的展开、收起和高度调整不替换工具内容，不改变其可见生命周期。

容量、持久化和内嵌界面所有权见 [ADR-0012](decisions/0012-add-opt-in-in-app-diagnostics.md)。

## UI

宿主拥有可自由缩放的窗口、一级工具导航和当前工具标题/用途，工具拥有内容、任务标题与领域操作。一级工具切换立即发生；工具内次级页面使用可逆的 trailing push/pop；辅助信息使用 DesignSystem 提供的原生 trailing inspector，任务型提交才使用 sheet。两者均遵守 [设计规范](design.md)。三个工具复用 BoardUI 原生适配的 DesignSystem；`ToolSlider` 等控件只接收 Binding 与交互回调，不持有数据库、provider 或播放 controller。工具不导入开发参考目录中的 React 组件，也不增加新的跨工具依赖。未实现工具只显示“待接入”，不得提供无行为的控件或示例数据。

## 新增工具

1. 创建 `Packages/Tools/<ToolName>/Package.swift`、同名静态 library product、源码、测试和所需实体资源。
2. 从 package 根目录独立运行 Debug/Release build 与 tests，并确认 manifest 不依赖其他工具。
3. 只把组合所需入口和真实平台 seam 标记为 `public`；在 `AppComposition` 注册一次并由 App 提供生产 adapter。
4. 覆盖注册、生命周期、资源和平台接缝测试，再确认移除该 package product 和 registration 后宿主与其他工具仍能构建。
