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
- PodPin 资料库：工具栏集合/文件夹切换、新建与管理文件夹、导入入口、平面列表、更多页、空/加载/失败状态和底部播放条；hover 命令同时可由键盘或菜单到达。
- PodPin 导入：分享文字解析、单项归档并播放、B 站多分 P 选择与顺序下载、目标文件夹、浏览器挑战拒绝/选择，以及进度和可恢复错误。
- PodPin 播放：在线与离线、暂停/缓冲/重试、15/30 秒跳转、seek 后听过区间保留空隙、五档速率、音量/输出、待播队列重排/移除/清空/失败重试、系统媒体键和切换其他工具后的连续播放。
- PodPin 设置与播放控件：持久化播放速率、音量和仍适用于嵌入式内容的可见度；不出现独立窗口、菜单栏、鼠标穿透或全局快捷键等无效设置。
- ASCII 工坊：默认品牌素材、导入、比例、配色、参数、播放、导出、拖放、平移、缩放和预览/导出构图一致；持续拖到物理屏幕边缘后内容仍可继续平移，松开或切走窗口后指针恢复正常。
- 键盘：方向键、`+`/`-`、`0`、空格、Escape；字符输入中的空格不触发播放。
- 辅助功能：名称、状态、手势替代操作、减少动态效果和关闭检查器后的焦点恢复。

自动测试覆盖窗口几何、浅色 token、工具注册、ASCII 输入/导出/渲染，以及 PodPin 数据库、资料库规则、四来源 fixture、下载状态机、播放、听过区间、队列、惰性启动和退出清理。视觉构图、真实第三方页面、实际输入设备手感、系统媒体键和辅助技术仍需人工检查。

## 本次迁移证据

- `./scripts/test.sh` 完成 5 个 test target；PodPin 执行 133 个测试，8 个显式 live 场景跳过，0 失败。脚本为 hostless target 保存逐 target 日志、`profdata` 和 coverage report，并为 App-hosted target 保存 `xcresult`。退出用例覆盖启动、导入、活动下载、播放解析、资料库变更和封面生成：退出会取消并等待工作，取消后的迟到数据库写入或封面发布不会发生。
- Debug App 分别以 `--ui-default` 和 `--ui-minimum` 启动，均保持运行并通过 AppKit 正常退出，进程返回 0，启动日志无错误。这只证明两种窗口入口和应用退出链路，不等同于完整人工构图或功能冒烟。
- arm64-only Release App 完成离线工具打包和 Hardened Runtime 重签；三个工具在最终签名后均通过版本启动、系统动态依赖和 deep strict signature 检查。打包后的 Release App 也成功启动并通过 AppKit 正常退出，进程返回 0。
- 窗口截图自动化连续无法从窗口创建图像，错误为 `could not create image from window`；按有限验证原则停止重复该方向。本次没有可交付截图，不能据此声称视觉构图已验收。

## 未验证

- 实体触控板捏合手感。
- VoiceOver、Voice Control、Switch Control 和 Full Keyboard Access 的端到端任务。
- 错误横幅的默认和最小窗口视觉状态。
- PodPin 内容区在默认和最小窗口的完整人工视觉构图；自动检查只覆盖窗口启动尺寸和静态布局约束。
- PodPin 浏览器 Profile 的真实 Keychain 授权、真实抖音下载、系统媒体键和输出设备切换。
- 独立 PodPin 与 OneBox 同时访问旧资料库；该组合不在支持范围内。
