# Design QA

本文件只记录可复现的 UI 验收。设计规则以 [docs/design.md](docs/design.md) 为准；工作截图可以生成到 `.build/DesignQA`，但任何作为交付依据的证据都必须使用仓库相对路径长期保存。

## 证据规则

每次需要截图验收的 UI 变更记录以下内容：

- 变更范围和对应设计规则；
- 可重复的构建、启动参数或人工操作步骤；
- 默认窗口、最小支持窗口和要求的外观状态；
- 相对路径 `docs/assets/design-qa/<change>/...` 下的必要截图；
- 可观察差异、结论和仍未验证的项目。

不得引用 `/Users/...`、`/var/folders/...`、剪贴板临时文件或 `.build/...` 作为长期证据。无法合法提交的外部参考必须记录稳定来源和取得方式；没有可访问证据时，结论只能标为“未验证”。

## 当前基线

- 日期：2026-08-25。
- 范围：浅色宿主、展开与折叠侧边栏、三个占位工具、默认窗口、最小支持窗口，以及深色占位结构。
- 验证步骤：先运行 `./scripts/check.sh`；再从 Xcode 运行 `OneBox` scheme，分别传入 `--ui-default`、`--ui-minimum` 和 `--ui-default --ui-dark`。在默认浅色窗口依次切换三个工具，并折叠、展开侧边栏。
- 代码验证：窗口比例、最小尺寸、侧边栏宽度、排版 token 和浅色颜色值由 Design System 集中定义；窗口几何和浅色锁定值有单元测试覆盖。
- 截图：[默认浅色](docs/assets/design-qa/architecture-simplification/default-light.jpeg)、[最小浅色](docs/assets/design-qa/architecture-simplification/minimum-light.jpeg)、[默认暗色占位](docs/assets/design-qa/architecture-simplification/default-dark-placeholder.jpeg)。
- 结论：默认与最小浅色窗口保持既定比例、224pt 侧栏、共同文字左轴和无系统蓝色的锁定配色；工具切换与侧栏折叠保留正确选中状态；深色只验证了与浅色相同的几何结构。
- 状态：**通过**。当前工具仍是占位内容，因此数字列、长列表滚动和真实工具内容的视觉验收不适用，待对应功能实现时验证。
