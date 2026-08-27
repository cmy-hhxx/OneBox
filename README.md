# OneBox

OneBox 是一个面向单个本机用户的 macOS 工具箱。内置工具共享宿主和设计系统，但各自拥有业务状态与生命周期。

## 当前范围

- 仅支持 Apple Silicon 和 macOS 15+。
- 产品代码使用 Swift；UI 以 SwiftUI 为主，必要时使用 AppKit 和 Metal。
- 工具由同一受信任作者维护，随应用静态编译和发布；不加载第三方或远程代码。
- 当前没有第三方包依赖。

| 工具 | 状态 | 范围 |
| --- | --- | --- |
| ASCII 工坊 | 已实现 | 将图片转换为可调整、可动画并可导出的 ASCII 画面 |
| 股票看盘 | 占位 | 查看自选股票行情与提醒 |
| 博客收听 | 占位 | 获取博客内容并提供音频收听 |
| 窗口聚焦 | 占位 | 通过窗口晃动触发聚焦 |

### ASCII 工坊

- 导入 PNG、JPEG 或 SVG；文件上限为 50 MB，解码后的最长边不超过 4096px。
- 支持三种固定画布比例、七套配色、字符调整、三种动画以及平移和缩放。
- 导出固定尺寸、`time = 0` 的静态 PNG；不支持视频、动图、自定义输出尺寸或工程恢复。
- 失败导入保留上一个有效素材。完整验证范围见 [UI 验收](docs/design-qa.md)。

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
```

`project.yml` 是工程配置源；生成的 Xcode 工程和 `.build/`、`dist/` 不进入版本库。

## 文档

- [架构](docs/architecture.md)与[工具模块契约](docs/module-contract.md)
- [设计规范](docs/design.md)、[UI 验收](docs/design-qa.md)与[品牌资产](docs/assets/brand/README.md)
- [工程规范](docs/engineering.md)与[架构决策](docs/decisions/README.md)
- [第三方声明](THIRD_PARTY_NOTICES.md)
