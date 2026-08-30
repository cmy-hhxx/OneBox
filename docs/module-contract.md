# 工具模块契约

工具以 `ToolRegistration` 静态进入组合根，不通过配置或磁盘扫描发现：

```swift
ToolRegistration(id: id, displayName: name) {
    ToolScene()
}
```

注册值包含 ID、展示名称、SwiftUI 内容构造方式和默认 no-op 的应用退出清理方式。无依赖工具可以公开静态 registration；需要平台能力或配置时，公开窄 `makeRegistration(...)` factory，并在工具内部组装状态和实现。注册过程不得执行业务 I/O、安装监听器或提前创建昂贵资源；退出 hook 只由 App 在确认退出时调用。

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

## UI

宿主拥有窗口和导航，工具拥有内容与领域操作。两者均遵守 [设计规范](design.md)。未实现工具只显示“待接入”，不得提供无行为的控件或示例数据。

## 新增工具

1. 创建 `Packages/Tools/<ToolName>/Package.swift`、同名静态 library product、源码、测试和所需实体资源。
2. 从 package 根目录独立运行 Debug/Release build 与 tests，并确认 manifest 不依赖其他工具。
3. 只把组合所需入口和真实平台 seam 标记为 `public`；在 `AppComposition` 注册一次并由 App 提供生产 adapter。
4. 覆盖注册、生命周期、资源和平台接缝测试，再确认移除该 package product 和 registration 后宿主与其他工具仍能构建。
