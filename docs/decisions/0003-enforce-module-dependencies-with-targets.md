# ADR-0003: 用 Xcode target 强制模块依赖

- Status: Accepted
- Date: 2026-08-24
- Amended by: [ADR-0004](0004-keep-app-specific-platform-code-in-app.md)

## Context

OneBox 已按 App、Host、Runtime、DesignSystem、Platform 和工具划分目录，但所有源码曾属于同一个应用 target。目录只能表达意图，无法阻止 Host 导入具体工具、工具互相引用或工具直接依赖宿主实现；测试也只能通过整个应用 target 访问代码。

项目仍是单人维护的小型模块化单体，不需要动态插件、独立进程或一套额外的 Swift Package 工作区。

## Options considered

### 继续使用单一应用 target

配置最少，但依赖规则只能靠代码审查维护，越界引用仍能编译。

### 使用本地 Swift Package

也能提供编译期隔离，但会同时维护 XcodeGen 工程和 Package manifest，并增加资源、预览和应用测试的配置面。

### 使用独立静态库 target

沿用现有 XcodeGen 配置和目录，通过 target dependencies 让编译器验证依赖方向；最终仍静态链接为一个应用。

## Decision

App、Host、Runtime、DesignSystem、Platform 和每个工具分别使用独立静态库或应用 target。只有 `OneBox` 应用 target 依赖具体工具；工具只依赖 Runtime 与 DesignSystem；Host 只依赖 Runtime 与 DesignSystem。

测试按被测接口拆成独立 test target。`project.yml` 是工程配置唯一真相源，生成的 `OneBox.xcodeproj` 不进入版本库。

## Consequences

### Positive

- 违规依赖在编译期失败，不再只依赖文档和审查。
- 工具与 Runtime 可以通过各自接口独立测试。
- 生成工程不产生无意义的 pbxproj 差异。

### Negative

- 跨 target 使用的类型需要明确 `public` 接口。
- 新增工具时必须同时更新组合根和 `project.yml`。
- XcodeGen 成为打开工程前的本地工具依赖。
