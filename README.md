# OneBox

OneBox 是一个个人桌面工具箱：多个用途不同的工具共享同一个宿主和一致的使用体验，但各自拥有独立的业务、状态、数据和生命周期。

## 产品范围

- 当前只有一个本机用户和一个受信任的模块作者。
- 工具随 OneBox 一起编译和发布，不加载第三方或远程代码。
- v1 只支持 macOS；产品代码统一使用 Swift。
- UI 使用 SwiftUI，窗口、辅助功能等 macOS 专属能力按需使用 AppKit，依赖通过 Swift Package Manager 管理。
- 当前只搭建 macOS 宿主、静态工具注册和统一占位状态；三个工具的业务均待接入。

## 初始工具

| 工具 | 目标 |
| --- | --- |
| 股票看盘 | 查看自选股票行情与提醒 |
| 博客收听 | 获取博客内容并提供音频收听 |
| 窗口聚焦 | 通过窗口晃动触发聚焦 |

## 下一条业务竖切

当前尚未选择要先实现的工具。开始业务代码前，必须先在本节写清一个工具的：用户可观察结果、真实输入或平台能力、明确不做的范围、失败状态和完成检查。没有这五项时，只允许维护现有宿主，不横向预建网络、存储、权限或生命周期层。

选择工具会改变产品优先级和外部依赖，因此不能从侧边栏顺序或占位代码自动推断。

## 运行

`project.yml` 是唯一工程配置源；生成的 Xcode 工程和本地构建产物不进入版本库：

本地验证要求 macOS 15 或更新版本、支持 Swift 6 的 Xcode 16 或更新版本，以及 XcodeGen 2.46。仓库通过 `.mise.toml` 固定 XcodeGen 版本：

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

验证脚本会先按 `.swift-format` 运行严格静态检查，再执行测试，并把 DerivedData、`.xcresult` 和完整构建日志分别写入 `.build/DerivedData`、`.build/TestResults` 与 `.build/Logs`。

## 文档

- [设计入口](DESIGN.md)：AI 与实现者读取设计规则的固定入口。
- [设计规范](docs/design.md)：视觉方向、默认浅色外观、信息密度、字体、图标和对齐硬约束。
- [架构](docs/architecture.md)：当前系统关系、职责和依赖方向。
- [模块契约](docs/module-contract.md)：新增工具必须遵守的接口与生命周期规则。
- [工程规范](docs/engineering.md)：实现、依赖、代码、测试和变更原则。
- [日志规范](docs/logging.md)：运行时日志字段、隐私和记录规则。
- [架构决策](docs/decisions/README.md)：已经接受和仍待确认的长期决定。
