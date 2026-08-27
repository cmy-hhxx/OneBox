# 设计规范

OneBox 使用紧凑的原生 macOS 界面。生产外观固定为浅色；宿主和工具共享 DesignSystem，不在页面内另建字体、颜色或间距体系。

## 宿主

- 默认窗口为 1048×648pt，并锁定该比例；最小高度为 556pt，最小宽度由同一比例计算。
- 侧边栏固定为 224pt；主内容左右和底部内边距为 24pt，顶部为 8pt。
- 侧边栏顶部只显示一次 `24pt 标识 + OneBox`；内容区不重复品牌名或工具标题。
- 一级导航使用纯文字和单层中性选中底，不使用图标、描边、强调色竖线、阴影或全高分隔线。
- 侧栏只有一个折叠按钮：展开时位于侧栏右上方，折叠后位于主区左上方。
- 不实现全局搜索、命令面板、第二套导航或常驻快捷键说明。
- 删除不影响理解、数据含义或风险判断的副标题、提示语和重复元数据。

## 浅色配色

宿主颜色必须使用 DesignSystem 语义 token。ASCII 工坊的领域配色只作用于输出画布。

| Token | Hex | 用途 |
| --- | --- | --- |
| `background` | `#FBFBFA` | 主内容背景 |
| `sidebar` | `#F0F0EE` | 侧边栏背景 |
| `surface` | `#FFFFFF` | 控件和独立表面 |
| `surfaceElevated` | `#EEEEEC` | 悬停表面和透明棋盘格 |
| `selection` | `#E4E4E2` | 导航选中底色 |
| `border` | `#D8D8D5` | 组件内部边框 |
| `textPrimary` | `#1B1C1E` | 主文字 |
| `textSecondary` | `#66676A` | 次级文字和功能图标 |
| `accent` | `#BC4535` | 主操作和焦点 |
| `negative` | `#B42318` | 错误状态 |
| `brandMarkHost` | `#3569CE` | 侧栏标识外盒和五官 |
| `brandMarkCore` | `#FFF1D6` | 侧栏标识内核 |
| `brandGradientStart` | `#3B6FD8` | ASCII OneBox 配色起点 |
| `brandGradientMiddle` | `#8A5CBF` | ASCII OneBox 配色中点 |
| `brandGradientEnd` | `#BC4535` | ASCII OneBox 配色终点 |

- 应用根视图使用 `accent` 作为 tint，不出现系统蓝色控件。
- 常驻颜色不得通过透明度临时派生；新增颜色先定义用途明确的语义 token。
- 状态不能只依赖颜色表达。
- 配色变更必须同步更新本表、`LightPaletteHex`、`LightPaletteTests` 和 UI 验收。

## 字体与布局

统一使用 SF Pro 和 DesignSystem 字体角色：

| 角色 | 规格 |
| --- | --- |
| Sidebar title | 20pt / Semibold |
| Section title | 14pt / Semibold |
| Body / Control | 13pt / Regular 或 Medium |
| Metadata | 12pt / Regular |

- 可见文字不得小于 12pt；需要列对齐的数字使用 `.monospacedDigit()`。
- 当前间距使用 4、8、12、16 和 24pt。侧栏外边距为 12pt，品牌标识和导航文字从 20pt 左轴开始。
- 同层内容共享左右边线；使用 frame、Grid、alignment guide 或基线对齐，不用负 padding、任意 `offset` 或透明字符补位。
- 工具内功能图标使用 SF Symbols，常规图标采用 16×16pt 光学框和 24×24pt 容器；纯图标按钮必须有辅助功能名称。

## 工具内容

工具拥有内容和领域操作，不改变宿主导航、全局配色或字体尺度。上下文快捷键只在工具可见且焦点正确时生效。

ASCII 工坊遵守以下布局和交互：

- 内容由紧凑操作条、单层画布和默认展开的 248pt 右侧检查器组成；检查器可以从操作条或自身关闭，并支持 Escape 和辅助功能 escape。
- 单行操作条无外层卡片并与画布左右对齐。导入、画布、动画和输出按任务顺序分组；同组间距为 8pt、组间距为 16pt。配色和动画使用宽度稳定的单层菜单，播放与参数使用固定 32pt 图标位，唯一实心主操作“导出”位于右侧。
- 画布只提供 1:1、16:9 和 9:16，并始终完整适配工作区；检查器不改变输出几何。
- 透明画布使用 `surface` 与 `surfaceElevated` 棋盘格，棋盘格不进入导出。
- 拖动使用捕获后的相对指针位移平移，不受物理屏幕边缘限制；滚轮和捏合以指针位置缩放；双击或“重置视图”恢复默认构图。
- 画布聚焦时，方向键平移，`+`/`-` 缩放，`0` 重置，空格播放或暂停。文本输入中的空格不得触发播放。
- 减少动态效果开启时默认静态，用户显式播放后才能启动动画。

交付 UI 变化前，按 [UI 验收](design-qa.md)完成检查。
