# ADR-0002: 选择 Swift macOS 技术栈

- Status: Accepted
- Date: 2026-08-24

## Context

股票看盘和博客收听主要需要网络、持久化、通知与音频。OneBox v1 的支持范围确定为 macOS，并且没有现有代码需要迁移。

技术栈需要长期服务原生 UI、窗口控制、辅助功能、菜单栏、音频和通知，同时保持单人项目的维护成本最低。

## Options considered

### SwiftUI + AppKit + Swift Package Manager

- 最适合 macOS 系统能力、辅助功能权限、窗口控制、菜单栏和音频。
- 单语言、原生 UI、部署面小，适合个人长期维护。
- 跨 Windows/Linux 基本等于重写；真正的进程插件隔离需要额外设计。

### Tauri 2 + TypeScript UI + Rust

- Web UI 开发效率高，Tauri capability/permission 模型适合收敛宿主能力。
- 可覆盖主流桌面平台，安装体积通常比 Electron 小。
- 同时维护 TypeScript、Rust 和平台桥接；复杂 macOS 行为仍需要原生代码。

### Electron + TypeScript

- Web 生态成熟，主进程/renderer/utility process 模型清晰，进程隔离工具最齐全。
- 内存和分发体积成本最高；系统原生感与深层 macOS 集成需要更多打磨。

## Decision

OneBox v1 只支持 macOS，产品代码统一使用 Swift：

- SwiftUI 负责应用生命周期和主要 UI；
- AppKit 只补充窗口控制、辅助功能等 SwiftUI 未覆盖的 macOS 能力；
- Foundation 提供网络、持久化和基础系统能力；
- Xcode 负责构建、签名和发布；
- Swift Package Manager 管理第三方依赖。

不引入 TypeScript、JavaScript、Rust、Electron、Tauri 或第二套应用运行时。新工具默认采用简单 SwiftUI MV 和依赖注入，不预装 MVVM、MVI、TCA 或 Clean Architecture。

## Consequences

### Positive

- 单一语言和原生工具链降低个人项目的构建、调试与发布成本。
- SwiftUI 提供统一 UI，AppKit 可以直接覆盖窗口和辅助功能等深层 macOS 集成。
- 不为未进入支持范围的 Windows/Linux 支付双语言、WebView 和平台桥接成本。

### Negative

- Windows 和 Linux 不在 v1 支持范围；未来若增加，需要重新做产品和架构决策。
- 部分 SwiftUI 未覆盖的能力需要直接理解和使用 AppKit。

### Neutral or follow-up

- 本 ADR 只选择技术栈，不决定工具优先级或描述当前实现进度；产品范围以 README 为准，已实现状态以架构文档为准。

## Sources

- [Swift](https://developer.apple.com/swift/)
- [SwiftUI](https://developer.apple.com/documentation/swiftui)
- [AppKit](https://developer.apple.com/documentation/appkit)
- [Apple platform tools and distribution](https://developer.apple.com/documentation/TechnologyOverviews/tools-and-distribution)
