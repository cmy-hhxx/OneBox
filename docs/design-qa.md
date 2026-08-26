# UI 验收记录

本文只记录可复现的 UI 验收步骤、结论和未验证项，不提交界面截图。强制设计契约以[设计规范](design.md)为准；自动化结果不能替代当前人工检查。

## 2026-08-26 — OneBox 侧栏 24pt 品牌标识

状态：通过。针对实际截图中标识底色与侧栏不一致、细节缩小后发糊的问题，侧栏使用透明的 SwiftUI `Canvas` 光学版本；AppIcon 使用完整的高分辨率品牌 master。

### 根因与修复

- 原侧栏直接把 1254px 的成品位图压缩到 24pt；位图自带的浅色背景与侧栏背景存在可见色差，同时柔和阴影、圆角和五官在小尺寸下失去清晰度。
- 当前侧栏标识只绘制外盒、内盒与表情，背景完全透明；几何针对 24pt 单独校准，不依赖运行时缩放大图。
- 浅色和深色外盒、内核颜色由 `DesignPalette.brandMarkHost` 与 `DesignPalette.brandMarkCore` 统一提供，构图保持一致，避免两套外观产生割裂。

### 可复现环境

- 平台：Apple Silicon，macOS 26.5 SDK，Debug 构建。
- 品牌资源校验与 AppIcon 生成：`swift scripts/generate-brand-assets.swift`。
- 构建与自动检查：`./scripts/check.sh`。
- 启动参数沿用下节记录的 `--ui-default`、`--ui-minimum` 和 `--ui-dark` 入口。

### 人工视觉结论

- 品牌行浅色：标识背景与侧栏连续，24pt 边缘、五官和内外盒层级清晰；与字标视觉重量协调。
- 默认浅色 1048×648pt：标识、字标和导航共同左轴稳定，无裁切或标题挤压。
- 最小浅色 900×556pt：几何和留白与默认窗口一致，没有布局回归。
- 默认深色占位 1048×648pt：深色外盒与柔沙内核保持品牌身份，背景透明；颜色切换没有改变构图、尺寸或对齐。

像素采样回归将标识透明角与相邻侧栏背景的最大通道色差从 11 降为 0，并确认实现不再引用 `Image("OneBoxBrandMark")`、而是使用 `Canvas`。这项检查只覆盖本次割裂问题，人工结论以当前可复现步骤为准。

## 2026-08-26 — ASCII 工坊首条业务竖切

状态：视觉结构、键盘主路径和辅助功能语义检查通过；本次错误横幅语义色修复尚未在默认、最小和深色占位窗口重新人工验证。真实 VoiceOver 语音、手势遍历及关闭检查器后的焦点恢复也尚未人工验证，因此本记录不构成错误状态视觉或 VoiceOver 完整可用声明。

### 可复现环境

- 平台：Apple Silicon，macOS 26.5 SDK，Debug 构建。
- 构建与自动检查：`./scripts/check.sh`。
- 默认浅色：关闭正在运行的 OneBox 后，执行 `.build/DerivedData/Build/Products/Debug/OneBox.app/Contents/MacOS/OneBox --ui-default`。
- 最小浅色：关闭正在运行的 OneBox 后，执行 `.build/DerivedData/Build/Products/Debug/OneBox.app/Contents/MacOS/OneBox --ui-minimum`。
- 深色占位：关闭正在运行的 OneBox 后，执行 `.build/DerivedData/Build/Products/Debug/OneBox.app/Contents/MacOS/OneBox --ui-default --ui-dark`。
- Release 性能：`./scripts/benchmark-ascii.sh`；结果必须满足 [ADR-0006](decisions/0006-require-apple-silicon.md) 的 Apple Silicon 与 Metal 前提。

这些 `--ui-*` 参数只存在于 Debug 构建，用于稳定复现验收窗口，不是产品设置。

本次 `./scripts/check.sh` 通过：ASCII 工坊 10 个 Swift Testing suite 共 36 个测试通过，App、Runtime 和 Design System 的 XCTest 也全部通过；Debug 中的性能用例按设计显式跳过，并由 Release 命令单独执行。`./scripts/benchmark-ascii.sh` 的 1080p 静态导出用例通过，整条 XCTest 用例耗时 0.066 秒，同时满足 2 秒耗时上限和 250 MB 物理内存上限。

本次错误横幅已按设计契约改为 `negative` 文字和边框配合 `surface` 背景，且未改变布局尺寸。尝试复验原生窗口时，本机 UI 捕获环境对 OneBox 和 Finder 均返回 `failedToCreateImageDestination`，无法取得可比较画面；因此没有沿用此前截图结论冒充本次人工证据，默认、最小和深色占位下的错误状态仍列为未验证。

### 人工视觉结论

- 默认浅色 1048×648pt：操作条、舞台、方形画布和侧边栏完整；无截断、重叠、意外换行或水平滚动。
- 最小浅色 900×556pt：约 899pt 的比例宽度经窗口系统取整为 900pt；结构与默认窗口一致，无控件溢出。
- 默认深色占位 1048×648pt：几何、边距和层级未改变；ASCII 输出画布仍使用所选领域配色，符合深色仅验收结构的范围。

逐项对照 `docs/design.md` 后确认：浅色仍使用锁定的语义 token；宿主没有系统蓝色、全高分隔线、重复品牌名或额外搜索入口；标题、工具栏、舞台和侧边栏共同边线稳定；当前画面没有需要数字列对齐的数据表。

### 交互与辅助功能证据

- 聚焦“ASCII 画布”后，空格在“暂停”和“播放”之间切换；方向键、`+`/`-` 和 `0` 均由画布焦点范围处理，不注册为窗口级快捷键。
- 参数检查器切换到“自定义”字符集后，输入前后都含空格的 ` 01 `，文本值原样保留，播放状态未变化。
- Escape 能关闭参数检查器；检查器暴露 modal 语义和辅助功能 escape 操作，关闭逻辑通过 `@AccessibilityFocusState` 请求把焦点还给“参数”按钮。
- macOS 辅助功能树能识别画布名称和键盘提示，并为画布、重置按钮暴露“缩小画布”“放大画布”“重置视图”替代操作；工具栏按钮、菜单、滑块和复选框均暴露名称、角色及当前值。

未验证项：本次没有开启系统 VoiceOver、Voice Control、Switch Control 或 Full Keyboard Access；因此没有验证真实语音内容、遍历顺序、VoiceOver escape 手势后的实际焦点位置及这些辅助输入模式的端到端任务完成度。后续若要声明任一模式完整可用，必须在启用对应系统功能后补充人工步骤和结果，不能只引用辅助功能树。
