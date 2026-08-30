# 工程规范

## 实现

- 先在 README 写清当前工具的用户结果、支持输入和排除范围，再交付最小端到端路径。
- 只实现当前需求；不预建共享层、feature flag、迁移框架、兼容包装或回退链。
- 接口或内部格式变化时，同步更新所有当前调用者并删除旧路径。该规则不授权删除已承诺保留的用户数据。
- 模块用小接口隐藏深实现；第二个真实消费者出现前不提取共享模块。
- 新依赖只通过 Swift Package Manager 引入，并记录需求、维护状态、许可证和删除成本。
- `StockWatchTool` 与 `PodPinTool` manifest 分别直接依赖 GRDB 与 GRDBSQLite products，SwiftPM 会自然传播 module map；`project.yml` 和 App consumers 不得复制 DerivedData 相对路径 workaround 或禁用 explicit modules。
- StockWatch Release benchmark 显式启用非默认 `Benchmark` package trait；PodPin 完整 Release tests 显式启用非默认 `Testing` trait。两者只为对应验证编译 internal test hooks，最终 App 与普通 Release build 都不启用这些 traits。

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

该脚本要求 Apple Silicon，检查 Markdown 链接和 `.swift-format`，生成工程并运行全部测试。ASCII Release 性能与内存基准另运行 `./scripts/benchmark-ascii.sh`；股票看盘 Release 刷新、存储与图表准备基准另运行 `./scripts/benchmark-stock-watch.sh`。

`scripts/test.sh` 分别构建和测试 `OneBoxCore`、`AsciiArtTool`、`StockWatchTool`、`PodPinTool` 四个 Swift package，并保存各自的日志和 JSON coverage；coverage 门要求报告包含 package 自身实际覆盖的源码行。默认模式随后仅在 scheme 的 Test action 以及 Xcode `build-for-testing`、`test-without-building` 命令显式启用 coverage，并要求 App 与 App-hosted tests 的 `xccov` 报告都包含实际覆盖行。工程的基础 build setting 关闭 coverage，普通 Debug/Release App build 不得带 LLVM coverage 插桩。两个 PodPin live 模式把 opt-in flags 和锁定媒体工具路径直接导出给 SwiftPM test 进程，不修改 `.xctestrun`，并保留 package coverage。Xcode 26.6 启动 macOS test host 时会把中间 `PackageFrameworks` 目录置于搜索路径前方，dyld 可能卡在其中的 GRDB wrapper；其并行 test bundle 载入以及 RPAC/Main Thread Checker 注入也可能卡住。脚本会从生成的 `.xctestrun` 中移除该中间目录和两项注入，使 test host 使用 `OneBox.app` 内已签名的 framework。离线工具打包会拒绝带 coverage 插桩或 App entitlement 的 Release 产物，并移除最终 App 中仅指向构建目录的 rpath。Xcode IDE 的正常运行仍保留这些诊断器。

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
- 股票看盘只用 macOS Unified Logging signpost 记录固定性能区间；PodPin 使用脱敏事件日志且不恢复旧 JSONL 事件流。新增日志不得记录密钥、授权信息、用户内容、完整 URL 查询参数、用户名或绝对用户路径。

提交格式为 `<type>(<scope>): <imperative summary>`，一次提交只表达一个可回滚意图。
