# ADR-0006: 仅支持 Apple Silicon

- Status: Accepted
- Date: 2026-08-26
- Amended by: [ADR-0010](0010-require-package-per-tool-isolation.md)

## Context

ASCII 工坊依赖 Metal 实时预览和全尺寸离屏导出。OneBox 当前是个人工具台，没有已发布的 Intel 用户兼容承诺；同时维护 Intel 路径会扩大 GPU 差异、CI 和性能验收矩阵，却不产生当前用户价值。

## Options considered

### Universal Binary

覆盖 Intel Mac，但需要双架构构建、Metal 兼容验证和独立性能门槛。

### Apple Silicon only

统一为 arm64，使用同一 GPU 能力基线验证交互延迟、帧率、内存和导出耗时。

## Decision

- OneBox 从本变更起仅构建 `arm64`，最低系统保持 macOS 15。
- `project.yml` 锁定最终 OneBox App 和 Xcode 集成 target 的 `ARCHS: arm64`；本地 package 声明 macOS 15+，并只在受支持的 arm64 开发、CI 和发行环境中验收。
- CI 和发布验收必须运行在 Apple Silicon；无 Metal 设备的环境只允许显式跳过像素集成测试，不得替代本机验收。

## Consequences

### Positive

- 渲染实现和性能预算只有一个硬件架构基线。
- 不需要维护 Intel 特有降级、兼容 Shader 或双架构发布物。

### Negative

- Intel Mac 无法安装或运行 OneBox。
- 如果未来出现真实 Intel 支持需求，需要新 ADR 重新打开架构和性能矩阵。
