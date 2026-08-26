# 架构决策记录

| 编号 | 标题 | 状态 |
| --- | --- | --- |
| [ADR-0001](0001-use-static-module-registration.md) | 使用静态模块注册 | Accepted |
| [ADR-0002](0002-select-desktop-stack.md) | 选择 Swift macOS 技术栈 | Accepted |
| [ADR-0003](0003-enforce-module-dependencies-with-targets.md) | 用 Xcode target 强制模块依赖 | Accepted |
| [ADR-0004](0004-keep-app-specific-platform-code-in-app.md) | 应用专属平台代码保留在 App target | Accepted |
| [ADR-0005](0005-scope-default-actor-isolation-by-target.md) | 按 target 设置默认 actor isolation | Accepted |
| [ADR-0006](0006-require-apple-silicon.md) | 仅支持 Apple Silicon | Accepted |

- `Proposed`：仍在讨论，不是当前约束。
- `Accepted`：当前实现必须遵守。
- `Superseded`：上下文改变后被新 ADR 替代；旧文件保留历史，但旧实现不并行维护。

一个 ADR 只记录一个影响结构、接口、权限、数据布局、依赖或构建方式的长期决定。编号递增且不复用。
