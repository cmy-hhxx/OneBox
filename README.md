# OneBox

OneBox 是一个面向单个本机用户的 macOS 工具箱。内置工具共享宿主和设计系统，但各自拥有业务状态与生命周期。

## 当前范围

- 仅支持 Apple Silicon 和 macOS 15+。
- 产品代码使用 Swift；UI 以 SwiftUI 为主，必要时使用 AppKit 和 Metal。
- 工具由同一受信任作者维护，随应用静态编译和发布；不加载第三方或远程代码。
- PodPin 通过 Swift Package Manager 精确锁定 GRDB 7.11.1；评估时上游仍持续维护，使用 MIT
  许可证。移除它需要替换 SQLite 迁移、查询与事务 repository；其余产品代码使用系统框架。

| 工具 | 状态 | 范围 |
| --- | --- | --- |
| ASCII 工坊 | 已实现 | 将图片转换为可调整、可动画并可导出的 ASCII 画面 |
| 股票看盘 | 占位 | 查看自选股票行情与提醒 |
| PodPin | 已实现 | 从公开链接收藏、下载、整理并连续收听音频 |
| 窗口聚焦 | 占位 | 通过窗口晃动触发聚焦 |

### ASCII 工坊

- 导入 PNG、JPEG 或 SVG；文件上限为 50 MB，解码后的最长边不超过 4096px。
- 初次打开以 OneBox 品牌图作为默认素材；支持三种固定画布比例、七套配色、字符调整、三种动画以及平移和缩放。
- 导出固定尺寸、`time = 0` 的静态 PNG；不支持视频、动图、自定义输出尺寸或工程恢复。
- 失败导入保留上一个有效素材。完整验证范围见 [UI 验收](docs/design-qa.md)。

### PodPin

- 导入用户主动提供的 B 站、抖音、小宇宙和 Fireside 公开链接；B 站支持有序多分 P 选择。
- 资料库保留收件箱、层级文件夹、最近导入、最近播放和已下载集合；重复内容会移动并刷新，
  不丢失原有身份、播放进度或离线媒体。
- 支持在线或离线播放、持久待播队列、自动续播、15/30 秒跳转、五档速率、音量与输出
  设备、系统媒体键，以及只记录实际听过区间的进度恢复。
- 继续使用 `~/Library/Application Support/PodPin/` 和原 PodPin 偏好 suite，因此已有
  资料库无需复制；不要同时运行独立 PodPin 与 OneBox 中的 PodPin。
- Debug 和测试构建提供内置 fixture；未打包外部媒体工具的构建支持在线播放。离线下载的
  Release 产物还需按[媒体工具策略](Tools/README.md)获取并打包锁定的 `ffmpeg`、`ffprobe`
  和暂留 `yt-dlp`。
- 不支持账号、登录、私有或付费内容、普通多链接批量、云同步、目录订阅、剪贴板监听、
  transcript、独立菜单栏入口或全局浮动播放器。

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

# 显式运行 PodPin 真实公开链接/下载测试：
./scripts/test.sh --podpin-live
./scripts/test.sh --podpin-live-downloads # 先按 lock 获取、重建并验证媒体工具

# 需要验证 PodPin 离线下载的本地 Release 产物时：
./scripts/fetch-podpin-tools.sh
xcodebuild -project OneBox.xcodeproj -scheme OneBox -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/DerivedData build
./scripts/package-podpin-tools.sh .build/DerivedData/Build/Products/Release/OneBox.app
```

默认 `check` 不访问第三方内容页面；首次建立 SwiftPM 缓存时，Xcode 仍可能联网取得精确锁定的 GRDB 依赖。`--podpin-live-downloads` 会先运行唯一获准联网的媒体工具获取脚本，并只把 lock 选择且验证通过的路径交给 live tests。

`project.yml` 是工程配置源；生成的 Xcode 工程和 `.build/`、`dist/` 不进入版本库。

## 文档

- [架构](docs/architecture.md)与[工具模块契约](docs/module-contract.md)
- [设计规范](docs/design.md)、[UI 验收](docs/design-qa.md)与[品牌资产](docs/assets/brand/README.md)
- [工程规范](docs/engineering.md)与[架构决策](docs/decisions/README.md)
- [第三方声明](THIRD_PARTY_NOTICES.md)
