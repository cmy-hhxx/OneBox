# 侧栏动画性能验证

2026-09-13，在同一台 Apple Silicon Mac、macOS 26.6.2、Release 且关闭 coverage 的 OneBox 窗口中，比较股票页面的连续 12 次左侧栏切换和 4 次检查器切换。窗口为 1048×648pt，包含一个缓存分时行情标的。

## 优化与实际应用采样

宿主明确主内容的剩余宽度；共享检查器使用定向布局，只测量原生面板并向主内容提供实际宽度。没有调整动画时长、模糊、阴影或原生检查器的呈现状态机。

| 20 秒 Time Profiler 采样 | 修改前 | 仅宿主宽度优化 | 宿主与检查器优化 |
| --- | ---: | ---: | ---: |
| 主线程有效栈样本 | 5,808 | 4,563 | 3,790 |
| 包含 NSHostingView.layout 的样本 | 3,318 | 2,400 | 1,670 |

CPU 采样间隔为 1ms；同样操作下主线程活动样本减少约 35%，布局样本减少约 50%。这是单机 CPU 对比，包含原生辅助功能操作开销，不是显示帧率或 GPU hitch ratio 的达标证明。SwiftUI Instrument 的首轮 trace 在整理阶段未完成，因此不作为验证证据。

原始 Time Profiler trace、导出栈与汇总脚本保留在忽略目录 `.build/AnimationPerformance/`，名称为 `cpu-before`、`cpu-host1`、`cpu-after`。trace 可能包含进程环境，不应直接上传或提交；共享结论只使用本文的聚合数据。

## 回归与受控诊断

`SidebarLayoutTests.testHostProposesOnlyTheAvailableWidthToToolContent` 与 `ToolInspectorPresentationTests.testAnimationDoesNotProbeWorkspaceAtZeroOrUnboundedWidths` 在旧实现上失败：实际工具收到零宽度／无限宽度提案；新实现通过。检查器原有连续宽度、快速反向、首次懒安装、主内容身份、减少动态效果与队列宽度测试保留。

另有可选的 `StockWatchAnimationPerformanceTests`，使用内存数据库、三个各 240 点的固定行情标的，每种方向预热一次并采样 30 次。运行命令：

```sh
ONEBOX_ANIMATION_PERFORMANCE_REPORT="$PWD/.build/AnimationPerformance/local.json" \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" \
xcrun swift test --disable-sandbox \
  --package-path Packages/Tools/StockWatchTool \
  --scratch-path .build/SwiftPM/StockWatchTool \
  --configuration release --traits Benchmark \
  --filter StockWatchAnimationPerformanceTests
```

测试报告记录 NSView 尺寸更新和主线程采样间隔。一次屏幕刷新内可能出现多次尺寸更新，不能把它们当作实际渲染帧。此次前后各 120 次受控切换通过，检查器首次尺寸变化 P95 从 10.1/10.8ms 降至 8.2/8.4ms；持续采样间隔没有明确改善。该诊断只用于布局比较，默认测试跳过，不在普通 CI 中添加机器相关的时钟门槛。
