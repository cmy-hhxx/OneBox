# OneBox

OneBox 是一个面向单个本机用户的 macOS 工具箱。内置工具共享宿主和设计系统，但各自拥有业务状态与生命周期。

## 当前范围

- 仅支持 Apple Silicon 和 macOS 15+。
- 产品代码使用 Swift；UI 以 SwiftUI 为主，必要时使用 AppKit 和 Metal。
- 工具由同一受信任作者维护，随应用静态编译和发布；不加载第三方或远程代码。
- 股票看盘只在被选中且内容挂载时访问本地数据和公开行情源；不提供常驻后台或独立桌面外壳。

| 工具 | 状态 | 范围 |
| --- | --- | --- |
| ASCII 工坊 | 已实现 | 将图片转换为可调整、可动画并可导出的 ASCII 画面 |
| 股票看盘 | 已实现 | 查看 A股、港股和美股的自选行情、分时数据与本地提醒 |
| 博客收听 | 占位 | 获取博客内容并提供音频收听 |
| 窗口聚焦 | 占位 | 通过窗口晃动触发聚焦 |

### ASCII 工坊

- 导入 PNG、JPEG 或 SVG；文件上限为 50 MB，解码后的最长边不超过 4096px。
- 初次打开以 OneBox 品牌图作为默认素材；支持三种固定画布比例、七套配色、字符调整、三种动画以及平移和缩放。
- 导出固定尺寸、`time = 0` 的静态 PNG；不支持视频、动图、自定义输出尺寸或工程恢复。
- 失败导入保留上一个有效素材。完整验证范围见 [UI 验收](docs/design-qa.md)。

### 股票看盘

- 支持按名称或代码搜索 A股、港股和美股，维护有序自选列表，并用 JSON 整体替换列表。
- 展示当前交易日的分时行情；A股收盘后提供 B/S 复盘标记。腾讯行情失败时回退到东方财富，并保留最近一次成功缓存和数据状态诊断。
- 支持按昨收涨跌幅或每个标的的目标价提醒；上涨和下跌可分别播放牛叫与熊吼。提醒只显示在 OneBox 内，不发送系统通知。
- 只有选中股票看盘后才打开数据库、搜索或刷新；切换到其他工具时取消刷新，写完待保存设置并关闭数据库。不提供独立浮窗、置顶、鼠标穿透、菜单栏、全局快捷键、登录启动或后台监控。

行情来自无服务等级承诺的公开端点，可能延迟、中断、缺失或出错；缓存和 provider fallback 不保证及时性或准确性。股票看盘只用于信息展示，不构成投资建议，也不提供账户、下单或交易能力。数据处理和删除方法见[股票看盘隐私说明](docs/stock-watch-privacy.md)。

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
```

### 第三方依赖

| 依赖 | 用途 | 版本与维护 | 许可证 | 删除成本 |
| --- | --- | --- | --- | --- |
| [GRDB](https://github.com/groue/GRDB.swift) | 股票看盘的 SQLite 访问、schema、迁移和并发数据库队列 | Swift Package Manager 精确固定 7.11.1；升级时重新运行数据库、迁移和并发验证 | MIT | 必须重写数据库边界、迁移与并发验证 |

`project.yml` 是工程和依赖版本的配置源；生成的 Xcode 工程和 `.build/`、`dist/` 不进入版本库。完整许可证见[第三方声明](THIRD_PARTY_NOTICES.md)。

## 文档

- [架构](docs/architecture.md)与[工具模块契约](docs/module-contract.md)
- [股票看盘领域模型](docs/stock-watch-domain.md)与[隐私说明](docs/stock-watch-privacy.md)
- [设计规范](docs/design.md)、[UI 验收](docs/design-qa.md)与[品牌资产](docs/assets/brand/README.md)
- [工程规范](docs/engineering.md)与[架构决策](docs/decisions/README.md)
- [第三方声明](THIRD_PARTY_NOTICES.md)
