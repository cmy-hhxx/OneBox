# 工具模块契约

工具以 `ToolRegistration` 静态进入组合根，不通过配置或磁盘扫描发现：

```swift
ToolRegistration(id: id, displayName: name) {
    ToolScene()
}
```

注册值只包含 ID、展示名称和 SwiftUI 内容构造方式。无依赖工具可以公开静态 registration；需要平台能力或配置时，公开窄 `makeRegistration(...)` factory，并在工具内部组装状态和实现。注册过程不得执行业务 I/O 或提前创建昂贵资源。

股票看盘使用 `StockWatchModule.makeRegistration(platform:)`。工具定义的 `@MainActor StockWatchPlatformClient` 只有 `copyText(_:)`、`revealDirectory(_:)`、`playAlertSound(named:fileExtension:)` 和 `stopAlertSound()`；App 的 `MacStockWatchPlatformClient` 提供唯一 AppKit adapter。网络、数据库和领域状态不放进 platform 接口，也不由 Host 管理。

## 边界与生命周期

- 工具的项目内依赖只包括 Runtime 和 DesignSystem，不导入其他工具、Host 或 App；经记录并由 `project.yml` 固定的第三方包仍留在使用它的工具 target。
- 跨模块平台接口由工具定义，由 App 提供生产 adapter；测试使用同一接口提供 stand-in。
- 工具内容在被选择时构造，首个 registration 在应用启动时默认打开。当前没有启动后台激活机制。
- 同一工具最多有一个活动实例；重复打开不得重复注册监听器。
- 工具关闭后停止自己拥有的任务、定时器和订阅。异步工作必须有取消点和超时。
- 工具拥有业务状态和存储命名空间；宿主不解析工具数据。
- 工具把可恢复错误转换为可分类、可展示的结果，不得终止宿主。

优先使用 SwiftUI 的 scene、view 和 task 生命周期，不增加通用激活层。需要启动后台任务时，必须同时定义宿主调度、生命周期测试和对应 ADR。

## UI

宿主拥有窗口和导航，工具拥有内容与领域操作。两者均遵守 [设计规范](design.md)。未实现工具只显示“待接入”，不得提供无行为的控件或示例数据。

## 新增工具

1. 创建独立 Tool target，并满足上述依赖方向。
2. 在 `AppComposition` 注册一次。
3. 覆盖注册、生命周期和平台接缝测试。
4. 确认移除该 registration 后，宿主与其他工具仍能构建。
