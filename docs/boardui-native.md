# BoardUI 原生适配

OneBox 按用户明确选择，保留 SwiftUI 产品实现，并以 BoardUI 的实际免费组件、主题、字体与动效为当前设计依据。开发时安装原组件并对照源码；交付时使用 SwiftUI 的状态、Binding、焦点与辅助功能，将设计连接到现有三个工具。

## 来源与可复现参考

2026-09-13 通过 [BoardUI 官方 MCP](https://www.boardui.com/mcp)完成初始化、主题读取、技能安装、组件发现与安装。参考目录为忽略的 `.build/BoardUIReference/`，CLI 版本为 0.5.5，live skill 版本为 2026.9.11。安装结果解析 33 项组件及传递依赖，写入 46 个文件；已有主题等 5 个文件保持不变。

| 证据 | 位置与作用 |
| --- | --- |
| MCP 协议与执行结果 | `evidence/tools.json`、`init_boardui`、`get_theme`、`get_skill`、`list_components`、`install_components` 的 JSON/Markdown；记录实际工具 schema 和结果 |
| 主题与字体角色 | `styles/theme.css`、`styles/typography.css`；颜色、圆角、阴影、Inter 字号与字重 |
| 控件与动效 | `components/base/`、`components/application/`、`styles/globals.css`；实际渲染结构、状态样式与时序 |
| 开发比对 | 参考目录的本地 React/Vite 预览；安装内容只属于开发参考，不进入 OneBox 产品运行时 |

上述相对路径均以 `.build/BoardUIReference/` 为根。可从[官方组件 registry](https://www.boardui.com/r/button.json)重新取得免费组件；升级参考版本后重新核对源码与原生渲染。当前使用范围为免费组件，未采用付费模板。

源码与技能摘要不一致时，按当前安装源码实现。例如旧 motion 摘要称按下不缩放，而实际 `button.tsx` 与 CSS 定义了 0.98 按压缩放、220ms 按下及 420ms 恢复；OneBox 使用后者。

## 组件映射

| BoardUI 实际源文件／组件 | OneBox 原生实现 | 保留的设计与交互 |
| --- | --- | --- |
| `dashboard-sidebar.tsx`、theme sidebar tokens | `HostSidebar`、`HostSidebarRow` | 浮动浅灰面板、蓝色选中行、轻高光与阴影；展开 260pt，窄窗口 212pt，折叠 60pt 图标栏 |
| `buttons/button.tsx`、`icon-button.tsx` | `ToolActionButtonStyle`、`ToolIconButtonStyle` | 蓝色纵向渐变、白色次操作、轻量动作、悬停／按压／禁用状态；常规 36pt、紧凑 32pt，图标动作 32pt |
| `input/input.tsx`、`textarea/textarea.tsx` | `ToolTextField`、PodPin `TextEditor` | 10pt 圆角灰色字段、2pt 内边框、聚焦占位文字；单行输入保留外部 FocusState，多行仍用原生编辑 |
| `buttons/close-button.tsx`、`checkbox/checkbox-glyph.tsx` | `ToolCloseButtonStyle`、`ToolCheckboxStyle` | 24pt 灰色圆形关闭按钮、16pt 蓝色渐变复选框与 200ms 路径勾选 |
| `switch/switch.tsx` | `ToolSwitchStyle` | 42×24pt 轨道、18pt 圆点、7.5pt 中心压印；保留 Toggle 的读屏语义 |
| `segmented-control/segmented-control.tsx` | `ToolSegmentedPicker` | 4pt 内缩轨道、28pt 选项高度和连续移动的白色选中层，方向键切换值 |
| `slider/slider.tsx` | `ToolSlider` | 32pt 操作高度、6pt 轨道、20pt 圆点、8pt 中心色片与状态阴影；指针、键盘及辅助功能均经过相同值绑定与编辑回调 |
| `table/table.tsx`、`data-table.tsx`、`.bui-table` CSS | 股票行情表、PodPin 资料库与队列 | 灰色表头、内容列、行间分隔和悬停反馈；保留各工具的选择、搜索、排序、下载和播放动作 |
| `select/select.tsx`、dropdown 与 menu styles | 原生菜单、ASCII 选择面板、资料库集合选择 | 统一文字、图标、选中与触发器样式；键盘和系统菜单生命周期保留原生实现 |
| `notification/notification.tsx` 与状态 token | 股票提醒、错误横幅与模块提示 | 图标、语义底色、明确文字与可执行操作；原始错误继续进入现有调试日志 |

`ToolSlider` 当前有三个工具消费者：ASCII 参数、股票提醒阈值、PodPin 的播放进度与音量。它只持有值绑定和编辑回调，数据库、行情源、导入与播放器状态仍由原工具拥有。

侧栏导航与诊断图标使用 20×20pt 等比图形范围，展开按钮内部图形为 18×18pt；不使用 SF 字体字号代替图形边界。导航点击区域仍为 36×36pt。品牌图形完整居中于 24pt 槽位内，四边留出 1pt，避免原始绘图坐标超出画布而裁切。

股票分时大图在领域绘图区内使用共享 `DesignPalette.dark` 的背景、文字、网格和蓝色曲线角色，周围宿主仍为浅色。该图表扩展既有 SwiftUI Canvas，包含价格/交易时段轴和指针读数；没有新增图表依赖或常驻动画循环。

## 动效参数

| 交互 | 当前原生参数 | 减少动态效果 |
| --- | --- | --- |
| 按钮色彩／悬停 | 150ms；`DesignMotion.hover` | 共享主按钮关闭动画 |
| 按钮按下与恢复 | 缩放 0.98；220ms／420ms，`(0.4, 0, 0.2, 1)` | 不缩放，立即反馈 |
| 开关与分段选择 | 200ms，`(0.4, 0, 0.2, 1)` | 立即更新值与位置 |
| 宿主侧栏折叠／展开 | 300ms，`(0.4, 0, 0.2, 1)`；固定导航基线，单行标签裁切、淡变和最多 3pt 模糊 | 立即切换 |
| 检查器占位与原生呈现 | 同一 300ms 侧栏事务；先关闭态挂载，再响应当前请求；12pt 内容间距 | 不插值布局 |
| PodPin 页面 push/pop | 300ms，`(0.32, 0.72, 0, 1)`，保留左右可逆方向 | 最多 100ms 淡变，无横向位移 |
| Slider 悬停／拖动 | 150ms；圆点悬停 1.05、拖动 1.1，焦点环仅用于键盘焦点 | 保留操作与状态，关闭动画 |
| 通知布局弹簧角色 | mass 0.7、stiffness 520、damping 42；由 `DesignMotion.notification` 定义 | 由使用该角色的视图处理 |

原生 macOS sheet、popover、菜单与 trailing inspector 的呈现仍由系统管理。BoardUI 的网页模糊入场和模态 backdrop 没有覆盖到这些系统窗口。现有 Escape 优先级、焦点恢复、工具可见生命周期和播放进度更新边界保持一致。

侧栏动画的主内容使用明确的剩余宽度；检查器布局只让原生面板协商宽度，再向工作区提供一个实际尺寸，避免通用 HStack 在每次动画更新中把整个工具树按零宽度、无限宽度和对齐尺寸重复测量。队列仍保留原生 280–360pt 范围，主内容身份与 300ms 时序保持稳定。测量与回归记录见[动画性能验证](animation-performance.md)。

## 字体与许可

Inter 4.1 variable 随 `OneBoxDesignSystem` 资源打包，通过 CoreText 在当前进程中注册一次；中文由系统字体回退。正文为 Inter 14pt，页面标题为 24pt Medium，其他字体角色见[设计规范](design.md)。图标使用 SF Symbols，诊断正文保留系统等宽字体。

- BoardUI：Copyright © 2026 Mertcan Dundar Esmergul，[MIT 许可](../Licenses/BoardUI-MIT.txt)。
- Inter：The Inter Project Authors，[SIL OFL 1.1](../Licenses/Inter-OFL.txt)，[上游项目](https://github.com/rsms/inter)。
- 早期 Uiverse 参考的许可作为来源记录保留；当前活动设计契约为本页与设计规范。完整分发说明见[第三方声明](../THIRD_PARTY_NOTICES.md)。

原生 bitmap、真实窗口、Metal 和 inspector 的验证边界见 [UI 验收](design-qa.md)。
