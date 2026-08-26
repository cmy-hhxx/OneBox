# UI 验收基线

本文只保留当前可复现的 UI 验收步骤、结论和未验证项，不作为实现变更日志。强制设计契约以[设计规范](design.md)为准；历史结论由 Git 保留，自动化结果不能替代当前人工检查，界面截图不提交仓库。

## 复现步骤

1. 在 Apple Silicon 本机运行 `./scripts/check.sh`。
2. 从 Xcode 运行 `OneBox` scheme，或关闭已经运行的 OneBox 后直接启动 Debug 产物：
   - 默认浅色：`.build/DerivedData/Build/Products/Debug/OneBox.app/Contents/MacOS/OneBox --ui-default`
   - 最小浅色：`.build/DerivedData/Build/Products/Debug/OneBox.app/Contents/MacOS/OneBox --ui-minimum`
   - 深色结构：`.build/DerivedData/Build/Products/Debug/OneBox.app/Contents/MacOS/OneBox --ui-default --ui-dark`
3. 在默认与最小窗口检查侧栏展开/折叠、四个工具切换，以及 ASCII 工坊的打开、比例、配色、参数、播放、导出、拖放、键盘和直接操控路径。
4. 性能或内存相关改动另运行 `./scripts/benchmark-ascii.sh`；Debug 性能用例的跳过不能替代该检查。

`--ui-*` 参数只存在于 Debug 构建，用于稳定复现验收窗口，不是产品设置。

## 当前结论

最近一次人工基线日期为 2026-08-26：

- 默认浅色 1048×648pt 与最小浅色 900×556pt 均保持固定窗口比例、224pt 侧栏和 24pt 主内容边距；工具栏、单层画布与默认展开的 248pt 停靠检查器没有截断、重叠、意外换行或水平滚动。
- 深色占位保持与浅色相同的几何、控件分组和焦点结构；深色视觉精修仍不在当前验收范围。
- 侧栏 24pt 标识使用透明底 SwiftUI optical mark；浅色、最小窗口和深色占位下均没有背景色块、裁切或标题挤压，AppIcon 继续由浅色 PNG master 生成。
- 操作条没有外层卡片；三个固定比例直接单选，七个配色位于单层菜单，参数入口为纯图标，导出是唯一实心主操作。
- 鼠标拖动画面与指针同向、等距离移动；连续滚轮以指针位置为锚点缩放；双击和“重置视图”恢复默认构图。最小窗口与深色占位下的事件区域、焦点描边和重置入口保持相同几何。
- 画布聚焦后，方向键平移，`+`/`-` 缩放，`0` 重置，空格播放或暂停；自定义字符输入中的空格不会触发播放。
- 辅助功能树暴露画布、工具栏操作、参数栏显隐状态和缩放/重置替代操作；Escape 可关闭停靠检查器，代码会请求把辅助功能焦点还给参数按钮。

## 自动回归范围

- 窗口比例、最小尺寸、浅色 token、工具注册和惰性内容构造。
- ASCII 输入格式与大小限制、失败导入保留上一个有效素材、预览/导出构图一致性、固定比例、配色、字符状态、动画生命周期和 Metal 路径。
- AppKit 拖动坐标转换、精确/离散滚轮曲线、事件拆分稳定性、指针锚定缩放和画布变换重置。

## 未验证项

- 实体触控板捏合手感尚未单独留证；该路径已接入 AppKit，并有缩放因子与锚点变换回归。
- 尚未开启 VoiceOver、Voice Control、Switch Control 或 Full Keyboard Access 完成端到端任务，因此不声明真实语音、遍历顺序、escape 后实际焦点位置或这些输入模式已完整可用。
- 错误横幅改用语义色后的默认、最小和深色占位视觉状态尚未重新人工触发验证。
