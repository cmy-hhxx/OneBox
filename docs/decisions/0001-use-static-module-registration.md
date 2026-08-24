# ADR-0001: 使用静态模块注册

- Status: Accepted
- Date: 2026-08-24

## Context

OneBox 的工具由同一个作者开发、编译和发布。目标是复用宿主、UI 和工程基础设施，同时隔离各工具的业务、状态、数据和生命周期。当前没有第三方分发或远程代码加载需求。

## Options considered

### 独立应用

隔离最强，但会重复宿主、设计系统、日志、设置和发布流程，不能解决每个工具都要重新起项目的问题。

### 动态插件

允许独立安装，但会引入代码签名、来源信任、兼容性、权限、升级、卸载和供应链安全，而当前没有对应需求。

### 静态注册的模块化单体

工具以类型安全的注册值进入宿主组合根，随 OneBox 一起构建并按需激活。它满足当前隔离和复用需求，且接口最小。

## Decision

OneBox 的内置可信工具使用静态注册的模块化单体。宿主组合根显式绑定工具身份、展示名称、激活时机和 factory；不使用 JSON manifest、磁盘扫描或远程代码加载。

## Consequences

### Positive

- 注册信息与实现一起接受编译器检查，没有第二份配置真相源。
- 工具共享宿主和工程能力，同时禁止彼此直接依赖。
- 未激活工具不产生业务 I/O 或后台资源消耗。

### Negative

- 更新任意工具都需要重新构建和发布 OneBox。
- 同进程工具仍可能通过 fatal crash 或主线程阻塞影响整个应用。
- 依赖注入和权限约束不构成恶意代码安全沙箱。

## Sources

- [VS Code Extension Host](https://code.visualstudio.com/api/advanced-topics/extension-host)
- [VS Code Activation Events](https://code.visualstudio.com/api/references/activation-events)
- [Tauri Capabilities](https://v2.tauri.app/security/capabilities/)
- [Electron Process Model](https://www.electronjs.org/docs/latest/tutorial/process-model)
