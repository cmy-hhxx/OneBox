# ADR-0004: 应用专属平台代码保留在 App target

- Status: Accepted
- Date: 2026-08-25

## Context

`OneBoxPlatform` 只有窗口比例配置一个实现，并且只有 App 一个调用者。删除该 target 后，复杂度只需移动到 App，不会扩散到多个调用点；独立 target 因此没有形成可替换的接缝，却增加了工程配置和公开接口。

## Options considered

### 保留通用 Platform target

目录看起来整齐，但当前只有一个调用者和一个实现，容易继续吸收彼此无关的 AppKit 能力并形成浅 module。

### 将窗口实现放回 App

窗口几何本来就是应用生命周期的一部分，不需要跨 module 接口。未来工具需要系统能力时，再针对真实能力定义窄接缝。

## Decision

删除 `OneBoxPlatform` target，将窗口级 AppKit 桥接保留在 App target，并保持实现为 internal。

只有出现真实跨模块平台能力，并且存在生产与测试 adapter 或第二个真实消费者时，才建立独立接缝或 target。工具不得通过通用 capability bag 查找平台能力。

## Consequences

### Positive

- 减少一个静态库 target 和一组无收益的公开接口。
- 窗口实现与它的唯一生命周期 owner 保持局部性。
- 后续平台接缝由真实工具需求决定，不预建通用门面。

### Negative

- 首个工具平台 adapter 出现时，需要重新决定实现放置和依赖方向。
