# OneBox

OneBox 是一个面向单个本机用户的 macOS 工具箱。内置工具共享宿主和设计系统，但各自拥有业务状态与生命周期。

## 当前范围

- 仅支持 Apple Silicon 和 macOS 15+。
- 产品代码使用 Swift；UI 以 SwiftUI 为主，必要时使用 AppKit 和 Metal。
- 工具由同一受信任作者维护，随应用静态编译和发布；不加载第三方或远程代码。
- 主窗口默认 1048×648pt、保留最小尺寸并允许自由改变宽高；工具一级切换立即完成，次级页面和辅助检查器统一从右侧进入，辅助检查器默认收起并在首次明确打开时才安装。
- 股票看盘只在被选中且内容挂载时访问本地数据和公开行情源；不提供常驻后台或独立桌面外壳。
- PodPin 启动时不联网；用户发起的导入、在线播放、下载或重试可以访问公开内容源。

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
- 展示当前交易日的分时行情；A股收盘后提供 B/S 复盘标记。腾讯行情失败时回退到东方财富，并保留最近一次成功缓存和数据状态诊断。
- 支持按昨收涨跌幅或每个标的的目标价提醒；上涨和下跌可分别播放牛叫与熊吼。提醒只显示在 OneBox 内，不发送系统通知。
- 只有选中股票看盘后才打开数据库、搜索或刷新；切换到其他工具时取消刷新，写完待保存设置并关闭数据库。不提供独立浮窗、置顶、鼠标穿透、菜单栏、全局快捷键、登录启动或后台监控。

行情来自无服务等级承诺的公开端点，可能延迟、中断、缺失或出错；缓存和 provider fallback 不保证及时性或准确性。股票看盘只用于信息展示，不构成投资建议，也不提供账户、下单或交易能力。数据处理和删除方法见[股票看盘隐私说明](docs/stock-watch-privacy.md)。

### PodPin

- 导入用户主动提供的 B 站、抖音、小宇宙和 Fireside 公开链接；B 站支持有序多分 P 选择。
- 资料库保留收件箱、层级文件夹、最近导入、最近播放和已下载集合；重复内容会移动并刷新，不丢失原有身份、播放进度或离线媒体。
- 支持在线或离线播放、持久待播队列、自动续播、15/30 秒跳转、五档速率、音量与输出设备、系统媒体键，以及只记录实际听过区间的进度恢复。
- 资料库是根页面；导入和正在播放作为可返回的右推页面，待播队列使用原生右侧检查器。PodPin 不再提供独立设置页，播放速率在播放条和正在播放页直接调整。
- 继续使用 `~/Library/Application Support/PodPin/` 和原 PodPin 偏好 suite，因此已有资料库无需复制；不要同时运行独立 PodPin 与 OneBox 中的 PodPin。
- Debug 和测试构建提供内置 fixture；未打包外部媒体工具的构建支持在线播放。离线下载的 Release 产物还需按[媒体工具策略](Tools/README.md)获取并打包锁定的 `ffmpeg`、`ffprobe` 和暂留 `yt-dlp`。
- 不支持账号、登录、私有或付费内容、普通多链接批量、云同步、目录订阅、剪贴板监听、transcript、独立菜单栏入口或全局浮动播放器。

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

# 需要验证 PodPin 离线下载的本地 Release 产物时：
./scripts/fetch-podpin-tools.sh
xcodebuild -project OneBox.xcodeproj -scheme OneBox -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/DerivedData build
./scripts/package-podpin-tools.sh .build/DerivedData/Build/Products/Release/OneBox.app
```

三条 package benchmark 命令都会在 `.build/Logs` 写入原始日志，以及带运行环境元数据和 median/P95/max 的 JSON 报告；Release UI 性能计划由 Xcode 写入 xcresult。性能门槛与固定机执行方式见[工程规范](docs/engineering.md)，窗口、检查器、Reduce Motion 和辅助技术矩阵见 [UI 验收](docs/design-qa.md)。

默认 `check` 不访问第三方内容页面；首次建立 SwiftPM 缓存时，Xcode 仍可能联网取得精确锁定的 GRDB 依赖。`--podpin-live-downloads` 会先运行唯一获准联网的媒体工具获取脚本，并只把 lock 选择且验证通过的路径交给 live tests。

### 第三方依赖

| 依赖 | 用途 | 版本与维护 | 许可证 | 删除成本 |
| --- | --- | --- | --- | --- |
| [GRDB](https://github.com/groue/GRDB.swift) | 股票看盘和 PodPin 的 SQLite 访问、schema、迁移与事务 | Swift Package Manager 精确固定 7.11.1；升级时重新运行两个工具的数据库、迁移和并发验证 | MIT | 必须重写两个工具各自的数据库边界、迁移与并发验证 |

每个本地 package 的 `Package.swift` 管理自己的 target、依赖、资源和 Swift 设置；`project.yml` 只管理 OneBox App、平台 adapter、最终 product 组装、签名、发行资源和 App-hosted 验证。生成的 Xcode 工程和 `.build/`、`dist/` 不进入版本库。完整许可证见[第三方声明](THIRD_PARTY_NOTICES.md)。

## 文档

- [架构](docs/architecture.md)与[工具模块契约](docs/module-contract.md)
- [股票看盘领域模型](docs/stock-watch-domain.md)与[隐私说明](docs/stock-watch-privacy.md)
- [设计规范](docs/design.md)、[UI 验收](docs/design-qa.md)与[品牌资产](docs/assets/brand/README.md)
- [工程规范](docs/engineering.md)与[架构决策](docs/decisions/README.md)
- [第三方声明](THIRD_PARTY_NOTICES.md)
