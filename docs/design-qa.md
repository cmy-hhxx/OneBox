# UI 验收

强制视觉契约见 [设计规范](design.md)。本文件只记录可复现步骤和当前未验证项；截图不进入版本库。

## 运行

1. 在 Apple Silicon 本机运行 `./scripts/check.sh`。
2. 从 Xcode 运行 `OneBox`，或启动 Debug 产物：
   - 默认窗口：`.build/DerivedData/Build/Products/Debug/OneBox.app/Contents/MacOS/OneBox --ui-default`
   - 最小窗口：`.build/DerivedData/Build/Products/Debug/OneBox.app/Contents/MacOS/OneBox --ui-minimum`
3. 性能或内存相关变化另运行 `./scripts/benchmark-ascii.sh`。

`--ui-*` 参数只存在于 Debug 构建。`--ui-dark` 可用于检查结构，但深色不是产品外观或验收目标。

## 人工检查

- 默认和最小窗口：固定比例、侧栏折叠、四个工具切换，以及无截断、重叠、意外换行或水平滚动。
- ASCII 工坊：默认品牌素材、导入、比例、配色、参数、播放、导出、拖放、平移、缩放和预览/导出构图一致；持续拖到物理屏幕边缘后内容仍可继续平移，松开或切走窗口后指针恢复正常。
- 键盘：方向键、`+`/`-`、`0`、空格、Escape；字符输入中的空格不触发播放。
- 辅助功能：名称、状态、手势替代操作、减少动态效果和关闭检查器后的焦点恢复。

自动测试覆盖窗口几何、浅色 token、工具注册、输入限制、静态导出、固定比例、配色、动画生命周期、Metal 路径和画布变换。视觉构图、实际输入设备手感和辅助技术仍需人工检查。

## 未验证

- 实体触控板捏合手感。
- VoiceOver、Voice Control、Switch Control 和 Full Keyboard Access 的端到端任务。
- 错误横幅的默认和最小窗口视觉状态。
