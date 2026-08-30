# ADR-0010: 每个工具使用独立本地 Swift package

- Status: Accepted
- Date: 2026-08-30
- Supersedes: [ADR-0003](0003-enforce-module-dependencies-with-targets.md)
- Amends: [ADR-0006](0006-require-apple-silicon.md)

## Context

OneBox 将持续接入更多工具。独立 Xcode target 已能阻止工具互相 import，但源码、测试、资源、第三方依赖和构建设置仍由根 `project.yml` 集中拥有。随着工具数量增长，新增或修改一个工具需要理解并改动整个工程配置，工具也不能从自己的目录独立构建和测试。

目录约定本身不能强制所有权。目标是让每个工具成为有实体源码、测试、资源、依赖清单和最小公开 interface 的独立 module，同时继续静态链接进同一个受信任的 OneBox 应用。

## Options considered

### 继续使用独立 Xcode target

现有验证成本最低，也已经阻止工具间 import；但根工程继续拥有所有工具的构建细节，package locality 和独立验证不会随工具数量扩展。

### 所有工具放入一个仓库级 Swift package

只维护一个 manifest，但工具仍共享同一个 package 配置和依赖解析范围。它不能保证新增工具拥有独立的依赖、资源和测试边界。

### 每个工具使用独立本地 Swift package

每个工具从自己的 package 根目录独立构建和测试。OneBox 只消费静态 library product，并在唯一 composition root 注入平台 adapter。代价是维护多个 manifest，并需要分别处理 package 资源和 App 集成测试。

### 动态插件或独立进程

提供更强的加载、崩溃或安全隔离，但会引入签名、版本兼容、进程通信和供应链问题。当前工具仍由同一作者随 OneBox 一起编译发布，没有这项需求。

## Decision

- 每个工具必须位于 `Packages/Tools/<ToolName>/`，并拥有自己的 `Package.swift`、`Sources/<ModuleName>/`、`Tests/<TestModuleName>/` 和所需实体资源。没有测试的占位工具也必须至少能独立 `swift build`。
- 每个工具 package 只发布一个与工具 module 同名的静态 library product。工具 package 不得依赖、import 或通过测试访问另一个工具 package。
- 共享基础能力放入 `Packages/OneBoxCore`。该 package 只分别发布 `OneBoxRuntime`、`OneBoxDesignSystem` 和 `OneBoxHost` products，不创建 `OneBoxCore` umbrella module，也不依赖任何工具。
- 工具只能依赖它实际使用的 OneBoxCore products和已记录的第三方 package。工具不得依赖 `OneBoxHost` 或 `OneBox` App。第三方版本、资源和 package 内 build settings 由消费它的 manifest 拥有。
- `OneBox/App/AppComposition.swift` 继续作为唯一 concrete tool registration 和顺序来源。App target 拥有应用生命周期、窗口、生产平台 adapter、发行资源、签名和最终打包；工具通过自己定义的窄 interface 接收宿主能力，不能查找宿主实现或全局容器。
- 工具拥有自己的业务资源。只有 App 发行流程拥有的资源或二进制可以留在根工程；工具必须通过显式注入的 URL 或窄 interface 使用它们，不能从 package 实现中隐式查找 `Bundle.main`。
- 每个 package 的正式公开 interface 只包含组合根所需入口和真实平台 seam。业务状态、数据库、provider、队列和 UI 实现默认保持 internal；测试通过 `@testable import` 验证同一个 module。
- 每个 package 必须在自身目录独立通过 Debug build 和测试。根验证流程另外构建 OneBox、运行 App-hosted composition/lifecycle 测试，并保留 Release benchmark、真实网络测试和发行包验收。
- `Package.swift` 是 package 内 target、依赖、资源和 Swift 设置的配置真相；`project.yml` 只管理 OneBox application、App-hosted 测试、最终 package product 组装、签名和发行配置。生成的 Xcode 工程仍不进入版本库。
- OneBox 最终应用仍只支持 Apple Silicon 和 macOS 15+。Package manifest 声明 macOS 15+；CI、benchmark 和发行验收继续在 arm64 主机运行，App 的 `ARCHS` 仍由 `project.yml` 锁定。
- 新工具从第一次可运行提交起就必须是独立 package。禁止先把源码加入 App 或共享 package，再承诺以后拆分。
- 本决定不引入动态插件、远程代码加载、独立进程或独立工具发布。所有工具仍静态链接并运行在 OneBox 进程内，因此 package 隔离不是安全、内存或崩溃隔离。

## Consequences

### Positive

- 编译器和 manifest 同时约束工具依赖方向，工具实现不能通过根工程配置偶然看到其他工具。
- 源码、测试、资源、依赖和验证集中在同一个 package，后续迭代和删除具有更强 locality。
- 单个工具可以独立构建和测试；根工程只随工具数量增加 product 依赖与一个 composition registration。
- 最小公开 interface 降低宿主和未来代码直接耦合工具内部领域类型的风险。

### Negative

- 仓库需要维护一个基础 package 和每个工具各自的 manifest。
- Package 资源进入独立 bundle；迁移时必须显式处理 `Bundle.module`、Debug-only fixture 和 App 发行资源。
- Package tests 与 App-hosted tests 使用不同 runner，检查脚本必须聚合两类结果。
- Xcode、SwiftPM 和 GRDB 的集成仍需在 clean DerivedData、benchmark 和最终签名产物上验证。
- 所有工具仍在同一进程内；一个工具崩溃或阻塞主线程仍可能影响整个 OneBox。
