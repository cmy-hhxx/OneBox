# 工程规范

## 实现

- 先在 README 写清当前工具的用户结果、支持输入和排除范围，再交付最小端到端路径。
- 只实现当前需求；不预建共享层、feature flag、迁移框架、兼容包装或回退链。
- 接口或内部格式变化时，同步更新所有当前调用者并删除旧路径。该规则不授权删除已承诺保留的用户数据。
- 模块用小接口隐藏深实现；第二个真实消费者出现前不提取共享模块。
- 新依赖只通过 Swift Package Manager 引入，并记录需求、维护状态、许可证和删除成本。
- `StockWatchTool` 与 `PodPinTool` manifest 分别直接依赖 GRDB 与 GRDBSQLite products，SwiftPM 会自然传播 module map；`project.yml` 和 App consumers 不得复制 DerivedData 相对路径 workaround 或禁用 explicit modules。
- StockWatch 与 PodPin Release benchmark 显式启用非默认 `Benchmark` package trait；PodPin 基准也启用 `Testing` trait，以便 SwiftPM 能编译同一 package 中的既有测试目标。两者只为对应验证编译 internal test hooks，最终 App 与普通 Release build 都不启用这些 traits。

## Swift

- App、Host 和 DesignSystem 默认隔离到 `MainActor`；Runtime 与 Tool 默认 `nonisolated`，UI 入口显式标记 `@MainActor`。
- 禁止全局可变业务状态。异步任务必须有 owner、取消点和超时，不在主线程执行阻塞 I/O。
- 使用类型化错误；代码标识符和提交消息使用英文，注释只解释约束和原因。
- 每个 `Package.swift` 是对应 package 内 target、依赖、资源和 Swift 设置的配置源；`project.yml` 只管理 App 组装、平台 adapter、签名、发行资源和 App-hosted 测试。生成文件必须有可复现命令。

## 验证

- 测试可观察行为、模块接口和生命周期，不穿透接口断言实现细节。
- bug 修复先添加稳定复现；平台能力通过窄测试 adapter 替换。
- 局部变化运行相关检查；共享接口覆盖全部当前消费者。未验证事项必须明确说明。
- UI 变化遵守 [设计规范](design.md)，并按 [UI 验收](design-qa.md)检查默认和最小窗口。截图只作本地临时证据，不提交仓库。

提交前运行：

```sh
./scripts/check.sh
```

该脚本要求 Apple Silicon，检查 Markdown 链接和 `.swift-format`，生成工程并运行确定性的功能与结构测试。默认 PodPin package 测试只运行 `PodPinToolTests`；`PodPinPerformanceTests` 仅由 Release benchmark 调用。ASCII Release 性能与内存基准另运行 `./scripts/benchmark-ascii.sh`；股票看盘 Release 刷新、存储与图表准备基准另运行 `./scripts/benchmark-stock-watch.sh`；PodPin 离线工作区基准另运行 `./scripts/benchmark-podpin.sh`。

### 性能预算与固定机流程

性能工作遵循“测量 → 定位长更新或过度更新 → 优化 → 重测”。主线程以 100ms 作为立即反馈预算，任何核心路径不得出现 250ms 或更长的 hang；使用 SwiftUI Instrument、Time Profiler、Hangs 和 Hitches 给出证据，不凭类型擦除、文件长度或代码形状推断瓶颈。

固定 Apple Silicon 机器使用 Release、关闭 coverage。冷启动采样 10 次；其他场景先预热一次，再采样 30 次并记录 median、P95 和 max。三条 package benchmark 脚本在 `.build/Logs` 写原始日志和 JSON；JSON 记录 git SHA、芯片、内存、macOS、Xcode、显示刷新率、原始样本和统计值，不额外生成空的测试摘要产物。固定机必须连接可被系统识别的显示器；无法取得正数刷新率时报告生成直接失败，不能写入 `unknown` 后继续比较。`OneBoxPerformance` Release UI 测试计划通过 Xcode 生成 xcresult；工具暖切换、PodPin 热重入、检查器和路由在 XCTest 内保留每个用户可见状态的原始耗时数组，并直接执行上表的绝对 P95 门槛。本地播放自动门槛以 `AVPlayer.timeControlStatus == .playing` 对应的可观察播放状态和 `PlaybackStart` signpost 为终点；物理扬声器的实际出声仍需固定机人工或音频采集验证，不用按钮标签伪装可听状态。

| 用户路径 | Release 验收预算 |
| --- | --- |
| 冷启动到可交互 | median ≤1.0s，max ≤1.5s，无 ≥250ms hang |
| 任意点击的首个视觉反馈 | P95 ≤100ms |
| 工具首次激活 | loading 或壳层 ≤100ms，本地首个有效内容 P95 ≤500ms |
| 三工具暖切换 | 稳定首帧 P95 ≤200ms |
| 检查器与 PodPin 路由 | 首个变化 ≤100ms，受控帧 hitch ratio <1%，路由按 BoardUI 面板曲线约 300ms 完成 |
| PodPin 热重入 | 缓存命中时首屏查询为 0，已有内容 P95 ≤100ms，无 loading 空白帧 |
| PodPin 文件夹树 | 1,000 节点 P95 <100ms；10,000 节点 P95 <200ms |
| 本地播放 | 点击到可听声音 P95 ≤300ms |
| 远程播放或导入 | 100ms 内出现进行中反馈；不对公网延迟设硬门 |
| 长列表滚动 | 60Hz 固定机 ≥99% 帧不超过 16.7ms，无 ≥250ms hang |
| 连续切换 20 轮 | 无泄漏，footprint 增长 ≤max(5%, 20MiB) |
| 空闲 60 秒 | 平均 CPU <1%；无用户任务时无网络、数据库或持续 GPU 活动 |

固定机还使用相对门槛：median 回退 >10%、P95 回退 >15%、峰值物理内存回退 >10% 或 20MiB 即越线。每份可比较报告必须非空、包含 clock metric，且每个 series 至少有 30 个样本；基线与候选的架构、芯片、物理内存、macOS、Xcode 和显示刷新率必须完全一致，双方的 clock 与 `Memory Peak Physical` series 集合也必须一致。UI xcresult 门禁使用 `xcresulttool get test-results summary|metrics --schema-version 0.1.0` 的公开版本化 schema，要求 10 个冷启动样本、其余 metric 30 个样本、相同的设备/系统/测试/metric 集合，再对时间 median/P95 和峰值物理内存应用同一相对阈值。单次 measure 的 `Memory Physical` 增量仍写入报告供诊断，但其零值和分配粒度不作为相对门禁。测量或相对门槛首次越线会完整重跑一次，两次都越线才阻断；报告 schema、基线配置或环境不兼容直接以退出码 2 失败，不通过重跑掩盖。Package benchmark 中可确定性测量的工作使用 XCTest 绝对阈值；启动、首帧、声音、帧稳定性和空闲活动等端到端预算由 Release UI 路线与 Instruments 验收，不能用共享 CI runner 的时钟结果替代。

PR 只运行确定性功能、结构和编译检查，不在共享 runner 上设置时钟门槛。`.github/workflows/performance.yml` 只调度带 `self-hosted`、`macOS`、`ARM64`、`onebox-performance` 标签的固定机器，在 nightly、手动触发和 `v*` release tag 上依次运行三套 package benchmark，再运行 `OneBoxPerformance` Release UI 测试并上传日志、JSON 和 xcresult。UI 流程先完成一次不重试的 `build-for-testing`，配置或编译失败立即终止；随后 `test-without-building` 首次失败才复跑一次，并分别保留两轮 xcresult。

首次给固定机建立基线时，先在机器上手动运行，不设置 baseline variable，也不放置 `Benchmarks/Baselines/*.json`；三条脚本仍会执行绝对预算并产出合法的 30-sample 候选报告，UI 测试同时产出候选 xcresult。机器空闲、刷新率和电源状态固定后，至少再运行一轮，并分别把首轮 JSON 作为 `ONEBOX_ASCII_BENCHMARK_BASELINE`、`ONEBOX_STOCKWATCH_BENCHMARK_BASELINE`、`ONEBOX_PODPIN_BENCHMARK_BASELINE` 输入，把首轮 xcresult 路径作为 `ONEBOX_UI_PERFORMANCE_BASELINE` 输入，确认第二轮通过环境和相对门槛。人工审阅两轮原始样本后，才能把选定报告复制为仓库内 `Benchmarks/Baselines/ascii.json`、`stock-watch.json`、`podpin.json`，或将报告与 xcresult 保存到固定 runner 的只读路径并设置对应 repository variable。自动 workflow 要求四个 variable 都指向可读的已批准产物，不承担首次建基线；脚本不会自动提升当前结果为基线，环境升级后也必须重新走这套受控流程。

发布前依次运行 `./scripts/check.sh`、三套 Release benchmark、Release App clean build 和 PodPin live smoke；只有变更涉及下载链路时才运行 `./scripts/test.sh --podpin-live-downloads`。arm64 产物至少在 macOS 15.x 和当前支持的最新版各完成一次 smoke。

`scripts/test.sh` 分别构建和测试 `OneBoxCore`、`AsciiArtTool`、`StockWatchTool`、`PodPinTool` 四个 Swift package，并保存各自的日志和 JSON coverage；coverage 门要求报告包含 package 自身实际覆盖的源码行。默认模式随后仅在 Xcode `build-for-testing`、`test-without-building` 命令通过 test option 和命令级 build setting 显式启用 coverage，并要求 App 与 App-hosted tests 的 `xccov` 报告都包含实际覆盖行。共享 scheme 和工程的基础 build setting 默认关闭 coverage，普通 Debug/Release App build 不得带 LLVM coverage 插桩。两个 PodPin live 模式把 opt-in flags 和锁定媒体工具路径直接导出给 SwiftPM test 进程，不修改 `.xctestrun`，并保留 package coverage。Xcode 26.6 启动 macOS test host 时会把中间 `PackageFrameworks` 目录置于搜索路径前方，dyld 可能卡在其中的 GRDB wrapper；其并行 test bundle 载入以及 RPAC/Main Thread Checker 注入也可能卡住。脚本会从生成的 `.xctestrun` 中移除该中间目录和两项注入，使 test host 使用 `OneBox.app` 内已签名的 framework。离线工具打包会拒绝带 coverage 插桩或 App entitlement 的 Release 产物，并移除最终 App 中仅指向构建目录的 rpath。Xcode IDE 的正常运行仍保留这些诊断器。

| 产物 | 位置 |
| --- | --- |
| Xcode 工程 | `OneBox.xcodeproj` |
| DerivedData | `.build/DerivedData*` |
| 测试结果 | `.build/TestResults` |
| 日志 | `.build/Logs` |

以上目录和 `dist/` 均为本地产物，不进入版本库。

## 文档与决策

- README 记录产品范围和入口；架构文档记录当前结构；模块、工程和设计文档记录契约；QA 记录验证方法和缺口；ADR 记录长期决策。
- 非 ADR 文档原地更新，不保留并行旧版或按日期增长的实现日志。实现、测试和文档在同一变更中使用同一术语。
- 架构、权限、持久化布局或运行位置变化必须写 ADR。
- 性能 signpost 使用统一的 `com.cmy.OneBox` subsystem，按 Host、ASCII、StockWatch 和 PodPin category 记录固定、脱敏的区间；PodPin 不恢复旧 JSONL 事件流。
- 应用内调试日志遵守 [ADR-0012](decisions/0012-add-opt-in-in-app-diagnostics.md)：经用户开启后，由工具在错误归一化为展示结果前上报，保留原始描述、domain/code 和最深层 underlying error；取消不记为错误。操作名不得包含用户内容。Host 入队前移除用户及临时目录路径、URL 查询与凭据、授权和敏感字段，正常模式不采集，日志不落盘或上传，仅保留最近 500 条。只持久化调试开关，不将日志正文写入偏好、数据库或系统事件流。

提交格式为 `<type>(<scope>): <imperative summary>`，一次提交只表达一个可回滚意图。
