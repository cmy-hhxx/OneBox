# OneBox

OneBox 是一个面向单个本机用户的 macOS 工具箱。内置工具共享宿主和设计系统，但各自拥有业务状态与生命周期。

## 当前范围

- 仅支持 Apple Silicon 和 macOS 15+。
- 产品代码使用 Swift；UI 以 SwiftUI 为主，必要时使用 AppKit 和 Metal。
- 工具由同一受信任作者维护，随应用静态编译和发布；不加载第三方或远程代码。
- 主窗口默认 1048×648pt、保留最小尺寸并允许自由改变宽高；工具一级切换立即完成，次级页面和辅助检查器统一从右侧进入，辅助检查器默认收起并在首次明确打开时才安装。
- 三个工具共享 BoardUI 视觉与动效的 SwiftUI 实现：浮动侧栏、白色工作区、Inter 字体、蓝色操作、统一输入与滑块。侧栏默认 260pt，窄窗口 212pt，折叠保留 60pt 图标栏；组件与资源来源见[原生适配说明](docs/boardui-native.md)。
- 股票看盘只在被选中且内容挂载时访问本地数据和公开行情源；不提供常驻后台或独立桌面外壳。
- PodPin 启动时不联网；用户发起的导入、在线播放、下载或重试可以访问公开内容源。
- 提供可显式开启的应用内调试日志，内嵌在主窗口工作区底部，按三个工具和时间查看、搜索并复制底层错误；展开日志时当前工具保持挂载与操作。

| 工具 | 状态 | 范围 |
| --- | --- | --- |
| ASCII 工坊 | 已实现 | 将图片转换为可调整、可动画并可导出的 ASCII 画面 |
| 股票看盘 | 已实现 | 查看 A股、港股和美股的自选行情、分时数据与本地提醒 |
| PodPin | 已实现 | 从公开链接收藏、下载、整理并连续收听音频 |

### ASCII 工坊

- 导入 PNG、JPEG 或 SVG；文件上限为 50 MB。PNG/JPEG 声明尺寸每边不超过 16384px、总计不超过 64MP，解码后的最长边不超过 4096px。
- 初次打开以 OneBox 品牌图作为默认素材且保持静态；支持三种固定画布比例、七套配色、字符大小、密度、对比度、反色与透明背景、三种可显式开启的动画及强度，以及平移和缩放。
- 导出固定尺寸、`time = 0` 的静态 PNG；不支持视频、动图、自定义输出尺寸或工程恢复。
- 失败导入保留上一个有效素材。完整验证范围见 [UI 验收](docs/design-qa.md)。

### 股票看盘

- 支持按名称或代码搜索 A股、港股和美股，维护有序自选列表，并用 JSON 整体替换列表。
- 展示行情源最近返回的有效交易日报价和分时行情；周末、节假日或当天尚无新行情时保留上一交易日信息并标明日期。A股收盘后提供 B/S 复盘标记。腾讯行情失败时回退到东方财富，并保留最近一次成功缓存和数据状态诊断。
- 观察列表提供清晰的分时缩略图；空间足够时显示选中标的大图，包含价格与交易时段刻度、昨收参考和逐分钟悬停读数。低价 ETF 使用与价格量级匹配的纵轴范围。
- 支持按昨收涨跌幅或每个标的的目标价提醒；上涨和下跌可分别播放牛叫与熊吼。提醒只显示在 OneBox 内，不发送系统通知。
- 只有选中股票看盘后才打开数据库、搜索或刷新；切换到其他工具时取消刷新，写完待保存设置并关闭数据库。不提供独立浮窗、置顶、鼠标穿透、菜单栏、全局快捷键、登录启动或后台监控。

行情来自无服务等级承诺的公开端点，可能延迟、中断、缺失或出错；缓存和 provider fallback 不保证及时性或准确性。股票看盘只用于信息展示，不构成投资建议，也不提供账户、下单或交易能力。数据处理和删除方法见[股票看盘隐私说明](docs/stock-watch-privacy.md)。

### PodPin

- 导入用户主动提供的 B 站、抖音、小宇宙和 Fireside 公开链接；B 站支持有序多分 P 选择。
- 资料库保留收件箱、层级文件夹、最近导入、最近播放和已下载集合；重复内容会移动并刷新，不丢失原有身份、播放进度或离线媒体。
- 支持在线或离线播放、持久待播队列、自动续播、15/30 秒跳转、五档速率、音量与输出设备、系统媒体键，以及只记录实际听过区间的进度恢复。
- 资料库是根页面；导入和正在播放作为可返回的右推页面，待播队列使用原生右侧检查器。PodPin 不再提供独立设置页，播放速率在播放条和正在播放页直接调整。
- 继续使用 `~/Library/Application Support/PodPin/` 和原 PodPin 偏好 suite，因此已有资料库无需复制；不要同时运行独立 PodPin 与 OneBox 中的 PodPin。
- Debug 和测试构建提供内置 fixture；未打包外部媒体工具的开发构建支持在线播放。日常使用的完整 Release 应通过 `scripts/build-release.sh` 生成到 `dist/OneBox.app`，其中包含按[媒体工具策略](Tools/README.md)验证并打包的 `ffmpeg`、`ffprobe` 和暂留 `yt-dlp`。
- 不支持账号、登录、私有或付费内容、普通多链接批量、云同步、目录订阅、剪贴板监听、transcript、独立菜单栏入口或全局浮动播放器。

## 调试日志

点击侧栏底部“调试日志”，或按 `⇧⌘L` 展开或收起主窗口底部的日志区域。拖动工作区与日志之间的分隔线调整高度，开启“调试模式”后可直接在上方工具内重现问题。侧栏展开时会选中当前工具；日志内可切换全部模块、ASCII 工坊、股票看盘和 PodPin，按错误、操作或时间搜索，复制单条或当前筛选结果。工具错误提示中的日志入口会展开并筛选当前模块，快捷键保留已有筛选；关闭按钮只收起日志。

每条记录包含发生时间、模块、操作和底层错误；复制内容的时间使用含毫秒与时区的 ISO 8601。错误保留原有描述、domain/code 和最深层 underlying error，敏感路径、URL 查询及授权字段脱敏。取消操作不记为错误。

日志只保留本次进程内最近 500 条，退出后消失；关闭调试模式停止采集，已有记录仍可查看、复制或清空。应用只在偏好中保存调试开关，不写日志文件。也可给可执行文件传入 `--debug-mode`，从启动时开始采集本次运行。日志边界见 [ADR-0012](docs/decisions/0012-add-opt-in-in-app-diagnostics.md)。

## 开发

需要 Apple Silicon、Xcode 26+ 和由 `.mise.toml` 固定的 XcodeGen 2.46：

```sh
mise trust
mise install
./scripts/bootstrap.sh
open OneBox.xcodeproj
```

```sh
./scripts/check.sh
./scripts/benchmark-ascii.sh # Release ASCII 导出与内存基准
./scripts/benchmark-stock-watch.sh # Release 股票看盘刷新、存储与图表准备基准
./scripts/benchmark-podpin.sh # Release PodPin 离线工作区与文件夹树基准

# 每个 package 也可从自己的根目录独立运行 Debug/Release build 与 test：
cd Packages/Tools/PodPinTool
xcrun swift build && xcrun swift test
xcrun swift build -c release && xcrun swift test -c release --traits Testing
cd ../../..

# 显式运行 PodPin 真实公开链接/下载测试：
./scripts/test.sh --podpin-live
./scripts/test.sh --podpin-live-downloads # 先按 lock 获取、重建并验证媒体工具

# 首次准备或 lock 变更时显式获取媒体工具：
./scripts/fetch-podpin-tools.sh

# 每次生成支持 PodPin 离线下载的完整本地 Release：
./scripts/build-release.sh
open dist/OneBox.app
```

`build-release.sh` 生成工程、构建关闭 coverage 的 arm64 Release，再在临时目录执行媒体工具校验、打包与签名；全部成功后才替换 `dist/OneBox.app`，失败会保留上一次完整产物。该入口不获取或更新媒体工具，缓存缺失时按提示先运行 `fetch-podpin-tools.sh`。普通 `xcodebuild` 的 DerivedData 产物用于开发与验证，不是完整交付包；后续开发构建不会覆盖 `dist/OneBox.app`。

三条 package benchmark 命令都会在 `.build/Logs` 写入原始日志，以及带运行环境元数据和 median/P95/max 的 JSON 报告；Release UI 性能计划由 Xcode 写入 xcresult。性能门槛与固定机执行方式见[工程规范](docs/engineering.md)，窗口、检查器、Reduce Motion 和辅助技术矩阵见 [UI 验收](docs/design-qa.md)。

默认 `check` 不访问第三方内容页面；首次建立 SwiftPM 缓存时，Xcode 仍可能联网取得精确锁定的 GRDB 依赖。`--podpin-live-downloads` 会先运行唯一获准联网的媒体工具获取脚本，并只把 lock 选择且验证通过的路径交给 live tests。

### 第三方依赖

| 依赖 | 用途 | 版本与维护 | 许可证 | 删除成本 |
| --- | --- | --- | --- | --- |
| [Inter](https://github.com/rsms/inter) | 界面字体，中文由系统字体回退 | 随 DesignSystem 打包 Inter 4.1 variable，在进程内注册 | SIL OFL 1.1 | 移除字体资源并恢复系统字体角色 |
| [BoardUI](https://www.boardui.com) | 共享原生控件的设计与源码依据 | 官方免费组件；开发参考 CLI 0.5.5、skill 2026.9.11 | MIT | 替换 SwiftUI 控件与对应设计 token；产品无需 React 运行时 |
| [GRDB](https://github.com/groue/GRDB.swift) | 股票看盘和 PodPin 的 SQLite 访问、schema、迁移与事务 | Swift Package Manager 精确固定 7.11.1；升级时重新运行两个工具的数据库、迁移和并发验证 | MIT | 必须重写两个工具各自的数据库边界、迁移与并发验证 |

每个本地 package 的 `Package.swift` 管理自己的 target、依赖、资源和 Swift 设置；`project.yml` 只管理 OneBox App、平台 adapter、最终 product 组装、签名、发行资源和 App-hosted 验证。生成的 Xcode 工程和 `.build/`、`dist/` 不进入版本库。完整许可证见[第三方声明](THIRD_PARTY_NOTICES.md)。

## 文档

- [架构](docs/architecture.md)与[工具模块契约](docs/module-contract.md)
- [股票看盘领域模型](docs/stock-watch-domain.md)与[隐私说明](docs/stock-watch-privacy.md)
- [设计规范](docs/design.md)、[UI 验收](docs/design-qa.md)与[品牌资产](docs/assets/brand/README.md)
- [工程规范](docs/engineering.md)与[架构决策](docs/decisions/README.md)
- [第三方声明](THIRD_PARTY_NOTICES.md)
