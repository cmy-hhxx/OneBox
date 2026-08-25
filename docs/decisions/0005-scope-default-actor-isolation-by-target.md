# ADR-0005: 按 target 设置默认 actor isolation

- Status: Accepted
- Date: 2026-08-25

## Context

工程曾把 `MainActor` 设为所有 target 的默认 isolation。这简化了 SwiftUI 骨架，却也会让工具中的网络、持久化、解析和监听代码默认串行到主 actor。该 build setting 属于 Swift 6.2，而原文档仍声称支持 Xcode 16，工具链承诺与实际语义不一致。

## Options considered

### 全工程默认 MainActor

UI 代码标注最少，但工具业务需要持续退出主 actor，容易隐藏错误的执行所有权。

### 全工程默认 nonisolated

业务代码默认合理，但 App 和 Host 会增加大量重复 UI isolation 标注。

### 按 target 设置

UI module 默认 MainActor，Runtime 与工具默认 nonisolated；跨越默认值的少量入口显式标注。

## Decision

- App、Host 和 DesignSystem target 默认 `MainActor`。
- Runtime 和每个工具 target 默认 `nonisolated`。
- Runtime 的 SwiftUI 注册接口与工具 UI 入口显式使用 `@MainActor`。
- 最低开发工具链提升到包含 Swift 6.2 的 Xcode 26。

## Consequences

### Positive

- UI 状态所有权明确，同时业务与 I/O 不会被隐式绑定到主 actor。
- actor 跳转集中在少量真实接缝，编译器可以验证依赖方向。
- 工具链文档与 build setting 的语言能力一致。

### Negative

- 工具 module 中新增 UI 入口时需要显式声明 `@MainActor`。
- 不再支持使用 Xcode 16 构建。
