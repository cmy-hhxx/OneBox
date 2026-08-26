# OneBox

OneBox 是一个个人桌面工具箱：多个用途不同的工具共享同一个宿主和一致的使用体验，但各自拥有独立的业务、状态、数据和生命周期。

## 产品范围

- 当前只有一个本机用户和一个受信任的模块作者。
- 工具随 OneBox 一起编译和发布，不加载第三方或远程代码。
- v1 只支持 Apple Silicon 和 macOS 15+；产品代码统一使用 Swift。
- UI 使用 SwiftUI，窗口、辅助功能等 macOS 专属能力按需使用 AppKit，依赖通过 Swift Package Manager 管理。
- 当前已接入首条业务竖切“ASCII 工坊”；其他三个工具仍为统一占位状态。

## 初始工具

| 工具 | 目标 |
| --- | --- |
| ASCII 工坊 | 将图片实时转换为可调、可动画并可导出的 ASCII 画面 |
| 股票看盘 | 查看自选股票行情与提醒 |
| 博客收听 | 获取博客内容并提供音频收听 |
| 窗口聚焦 | 通过窗口晃动触发聚焦 |

## 当前业务竖切

当前已接入的首条业务竖切是“ASCII 工坊”：

- 用户结果：打开 PNG、JPEG 或 SVG，在实时预览中调整字符、配色、构图和三种动画，并导出固定 `time = 0` 的静态 PNG。
- 输入与能力：系统文件选择器和舞台拖放；ImageIO 解码 PNG/JPEG，AppKit 在限幅后把 SVG 栅格化为 `CGImage`，Metal 单 pass 预览与离屏导出。
- 明确排除：视频和动图、3D、主体分离、Bloom、混合模式、自定义输出尺寸/颜色/字体、工程文件和跨启动恢复。
- 失败状态：不支持格式、文件超过 50 MB、解码失败、Metal 不可用、导出失败；失败导入保留上一个有效素材。
- 完成检查：三个固定比例和七套配色正确；预览与导出构图一致；隐藏或暂停时无持续绘制；默认/最小窗口和键盘路径可用；画布聚焦后用方向键平移、`+`/`-` 缩放、`0` 重置、空格播放或暂停，文本输入中的空格不触发播放；辅助功能树必须暴露名称、状态、escape 和手势替代操作，实际 VoiceOver 语音、遍历与焦点恢复必须按 [UI 验收记录](docs/design-qa.md) 单独留证；Apple Silicon 本机通过 Metal 与性能验收。

## 运行

`project.yml` 是唯一工程配置源；生成的 Xcode 工程、`.build/` 与 `dist/` 本地产物不进入版本库：

本地验证要求 Apple Silicon、macOS 15.6 或更新版本、包含 Swift 6.2 的 Xcode 26 或更新版本，以及 XcodeGen 2.46。仓库通过 `.mise.toml` 固定 XcodeGen 版本：

```sh
mise trust
mise install
```

```sh
./scripts/bootstrap.sh
open OneBox.xcodeproj
```

命令行验证：

```sh
./scripts/check.sh
```

Apple Silicon Release 导出与内存基准：

```sh
./scripts/benchmark-ascii.sh
```

验证脚本会先按 `.swift-format` 运行严格静态检查，再执行测试，并把 DerivedData、`.xcresult` 和完整构建日志分别写入 `.build/DerivedData`、`.build/TestResults` 与 `.build/Logs`。

## 文档

- [设计入口](DESIGN.md)：AI 与实现者读取设计规则的固定入口。
- [设计规范](docs/design.md)：视觉方向、默认浅色外观、信息密度、字体、图标和对齐硬约束。
- [品牌资产](docs/assets/brand/README.md)：OneBox“套盒”标识的深浅 master、来源真相和可复现生成规则。
- [架构](docs/architecture.md)：当前系统关系、职责和依赖方向。
- [模块契约](docs/module-contract.md)：新增工具必须遵守的接口与生命周期规则。
- [工程规范](docs/engineering.md)：实现、依赖、代码、测试和变更原则。
- [日志规范](docs/logging.md)：运行时日志字段、隐私和记录规则。
- [架构决策](docs/decisions/README.md)：已记录的长期决定及其当前状态。
- [第三方声明](THIRD_PARTY_NOTICES.md)：移植代码的许可与版权来源。
