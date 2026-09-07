# 架构

OneBox 是静态注册的模块化单体，见 [ADR-0001](decisions/0001-use-static-module-registration.md)。共享模块和已迁移工具通过本地 Swift package 强制编译依赖；所有模块仍在同一进程中，不构成安全或崩溃隔离。

## 模块

| Module | Package 或源目录 | 职责 | 依赖 |
| --- | --- | --- | --- |
| `OneBox` | `OneBox/App` | 应用生命周期、窗口、组合根和生产 adapter；打包许可证、Debug fixture 与外部工具 | Host、Runtime、DesignSystem、全部 Tool |
| `OneBoxHost` | `Packages/OneBoxCore/Sources/OneBoxHost` | 侧边栏、选择和内容区域 | Runtime、DesignSystem |
| `OneBoxRuntime` | `Packages/OneBoxCore/Sources/OneBoxRuntime` | 工具 ID、注册值、目录和应用退出 hook | 无 |
| `OneBoxDesignSystem` | `Packages/OneBoxCore/Sources/OneBoxDesignSystem` | 颜色、字体和几何 | 无 |
| `AsciiArtTool` | `Packages/Tools/AsciiArtTool` | ASCII 会话、渲染、资源、导出和 package tests | Runtime、DesignSystem |
| `StockWatchTool` | `Packages/Tools/StockWatchTool` | 行情、自选、提醒、声音资源、缓存、迁移和 package tests | Runtime、DesignSystem、GRDB 7.11.1 |
| `PodPinTool` | `Packages/Tools/PodPinTool` | 音频导入、资料库、下载、队列、播放和 package tests | Runtime、DesignSystem、GRDB 7.11.1 |

Runtime 与 Tool module 默认 `nonisolated`；DesignSystem、Host、SwiftUI 入口和可观察状态归 `MainActor`，网络与数据库工作不阻塞主 actor。GRDB 由 Swift Package Manager 精确固定到 7.11.1。移除它需要重写两个工具各自的数据库边界、迁移和并发验证。

每个 `Package.swift` 定义 package 内依赖、资源和编译设置；`project.yml` 只定义最终 App 组装、签名、发行资源和 App-hosted tests。当前边界见 [ADR-0010](decisions/0010-require-package-per-tool-isolation.md) 和 [ADR-0004](decisions/0004-keep-app-specific-platform-code-in-app.md)；原 Xcode-target 决定 [ADR-0003](decisions/0003-enforce-module-dependencies-with-targets.md) 已被取代。

## 边界

- `OneBox/App/AppComposition.swift` 是唯一注册具体工具的组合根。
- 工具不得导入其他工具、Host 或 App。
- 无依赖工具可以公开静态 registration；有依赖工具公开窄 factory，由组合根注入平台能力或配置。
- 跨模块接口由使用方定义。工具不得查找宿主、全局容器或系统默认实现。
- 共享代码只在出现第二个真实消费者后提取。

ASCII 工坊通过 `AsciiArtModule.makeRegistration(deviceProvider:)` 接收 `AsciiMetalDeviceProviding`。App 只提供 Metal 设备；解码、会话、渲染和导出留在工具内部。

股票看盘通过 `StockWatchModule.makeRegistration(platform:)` 接收工具定义的 `StockWatchPlatformClient`。该 `@MainActor` 窄接口只有 `copyText(_:)`、`revealDirectory(_:)`、`playAlertSound(at:)` 和 `stopAlertSound()`；package 从 `Bundle.module` 解析自己拥有的 WAV，再把 URL 交给 `MacStockWatchPlatformClient` 播放。数据库、provider fallback、缓存和提醒规则留在工具内部。registration 保留既有 `stock-watch` ID 和“股票看盘”名称，不形成旧独立应用的品牌壳或运行入口。

PodPin 通过 `PodPinModule.makeRegistration(platform:debugFixtureAudioURL:externalToolsDirectoryURL:)` 接收工具定义的 `PodPinPlatformProviding` 和两个显式资源 URL。`PodPinSystemPlatformAdapter` 提供旧偏好、文件系统和系统媒体播放能力，并由 App adapter 独占 `Bundle.main` 中 Debug fixture 与最终 `Tools` 目录的发现。package 的测试 helper 通过 `Bundle.module` 读取自己的 fixture；production target 不声明该资源，Release App 也不复制它。工具 locator 只接受注入目录或测试 override，并在运行前确认候选存在且可执行，不读取宿主 Bundle 或环境变量。registration 捕获一个惰性 session；构建 registration 不打开数据库、不联网，也不安装媒体监听器。公开链接适配、GRDB repository、媒体文件、队列和播放进度都留在 `PodPinTool` 内。迁移决定见 [ADR-0007](decisions/0007-integrate-podpin-as-a-tool.md)。

## 生命周期

[ADR-0008](decisions/0008-own-work-with-visible-tool-lifecycle.md) 将股票看盘的可见 SwiftUI 内容作为工作 owner：

1. `makeRegistration(platform:)` 和视图构造不打开数据库、不联网，也不启动刷新。
2. 宿主选中并挂载股票看盘后，视图 task 才打开数据库、恢复本地状态，并启动首次刷新和 15/30/60 秒可选循环。
3. 切换到其他工具使内容离屏时，取消搜索、刷新、定时器、提醒消失任务和声音；随后排空自选列表写入、flush 提醒设置并关闭数据库。
4. 再次进入时先等待上一次关闭完成，再创建新的数据库和 store，避免 close/open 竞态。
5. 应用在股票看盘仍可见时退出，registration 的退出 hook 会请求同一个幂等 shutdown；宿主最多等待 15 秒，超时后取消准备并继续退出。

该生命周期没有宿主启动后台激活、菜单栏 worker 或常驻调度。窗口只被其他窗口遮挡或失去焦点不会让 SwiftUI 内容离屏；当前生命周期不把这种状态当作停机信号。

PodPin 首次被选择时才创建 session 内容并打开旧命名空间数据库。切换工具后，用户已明确开始的播放和下载仍由 session 持有；应用退出 hook 在同一 15 秒期限内请求取消并等待导入、下载和解析，flush 播放与资料库状态，停止媒体命令并关闭数据库；无法合作取消的 framework 工作不会无限阻塞应用退出。shutdown 幂等且支持有界取消。

## 数据与网络

股票看盘的可写数据库固定为：

```text
~/Library/Application Support/OneBox/StockWatch/marketsprite.sqlite
```

只有新库不存在时，工具才从下面的独立应用数据库执行一次只读校验和原子导入：

```text
~/Library/Application Support/MarketSprite/marketsprite.sqlite
```

上面的独立应用旧库不会被写入、移动、归档或删除；成功导入后只写 OneBox 命名空间。schema、完整性和并发策略见 [ADR-0009](decisions/0009-use-onebox-grdb-database-and-one-time-import.md)，本地数据内容与删除方法见[股票看盘隐私说明](stock-watch-privacy.md)。刷新间隔、牛熊声音开关和已解析的公开美股 provider 标识存入 OneBox 的 `UserDefaults` 键空间；provider 标识的校验与失效恢复见 [ADR-0011](decisions/0011-cache-public-market-provider-identifiers-in-preferences.md)。

工具只通过 HTTPS 访问三个公开端点：

| 端点 | 用途 | 发送内容 |
| --- | --- | --- |
| `searchapi.eastmoney.com` | A股、港股和美股搜索；必要时解析并本地缓存美股行情标识 | 用户输入的名称或代码，以及固定的类型、结果数和公开 provider token |
| `web.ifzq.gtimg.cn` | 首选分时行情 | 单个标的的 provider code |
| `push2delay.eastmoney.com` | 腾讯失败后的东方财富分时 fallback | 单个标的的 `secid` 和固定字段、单日参数 |

provider 响应先解析和校验，再进入内存和本地缓存。请求不包含 OneBox 账户、交易指令或整份自选列表；工具离屏后不发起搜索或刷新。公开端点没有 OneBox 可承诺的 SLA，数据可能延迟、中断、缺失或错误。

PodPin 继续使用 `~/Library/Application Support/PodPin/` 和原 PodPin 偏好 suite，不复制已有资料库。当前使用 `podpin.playbackRate`、`podpin.playbackVolume` 和 `podpin.lastLibraryCollection`；遗留的 `podpin.nowPlayingContentOpacity` 键保留在用户偏好中但不再读取、写入或主动删除，封面固定使用正常不透明度。只有用户发起的公开链接导入、在线播放、下载或重试才访问声明的内容源；外部媒体工具策略和锁定信息见 [`Tools/README.md`](../Tools/README.md)。

## 当前运行状态

- 宿主启动时选择第一个 registration，因此 ASCII 工坊默认打开；其他工具在被选择前不构造内容。
- ASCII 工坊在注册时创建默认静态的内存会话和惰性渲染缓存，不请求设备或执行 I/O。用户显式选择动画并播放后才持续绘制；工具隐藏、场景失活、窗口最小化、窗口完全遮挡或用户暂停时停止，关闭视图时取消导入和导出。
- 股票看盘已接入既有 registration；只在可见期间打开本地库和公开行情源，不请求系统通知权限，也不执行后台监控。
- PodPin 首次被选择时才开库并安装系统媒体命令；离屏后已开始的播放和下载可以继续，应用退出会等待其 flush 和清理。
- 性能区间统一使用 `com.cmy.OneBox` subsystem，并按 Host、ASCII、StockWatch、PodPin category 区分；PodPin 的事件日志保持脱敏。日志只记录固定区间和分类状态，不记录用户内容、完整查询或绝对用户路径。

工具接入规则见 [工具模块契约](module-contract.md)；当前事实仍以源码、测试、各 `Package.swift` 和 `project.yml` 为准。
