# ADR-0009: 使用 OneBox 命名空间的 GRDB 数据库并一次性导入独立应用数据

- Status: Accepted
- Date: 2026-08-28
- Amended by: [ADR-0010](0010-require-package-per-tool-isolation.md)

## Context

股票看盘需要持久保存有序自选、最新行情缓存、提醒配置和每个标的的目标价。迁移前的独立应用可能已经在 `~/Library/Application Support/MarketSprite/marketsprite.sqlite` 保存这些数据；OneBox 不能继续把旧产品目录当作自己的可写存储，也不能破坏用户仍可用的独立应用数据。

当前 schema 校验、SQLite backup、串行数据库访问和关闭语义已经建立在 GRDB 上。数据切换必须能拒绝未知或损坏的旧库，并避免留下被误认作成功的新库。

## Options considered

### 继续读写独立应用数据库

不需要复制，但两个应用共享写入所有权，OneBox 也会永久保留旧产品命名空间和 schema 耦合。

### 直接移动或复制数据库文件

实现简单，但移动会破坏旧应用；在 WAL 或并发写入存在时直接复制单个文件也不能保证一致快照。未经校验的副本可能成为 OneBox 的正式库。

### 只读校验后在新目录原子导入

以 OneBox 路径取得单一写入所有权；通过 SQLite backup 生成一致临时快照，复验后再原子切换，同时保留原文件。

## Decision

- 股票看盘唯一可写数据库固定为：

  ```text
  ~/Library/Application Support/OneBox/StockWatch/marketsprite.sqlite
  ```

- SQLite 接缝使用 GRDB，并由 Swift Package Manager 精确固定 7.11.1。该版本使用 MIT 许可证；完整文本记录在 [THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md)。
- 本 ADR 接受时，Xcode 不会把 GRDBSQLite 的 Clang module map 传播给 `StockWatchTool` 静态库，因此股票 target 曾使用局部 `OTHER_SWIFT_FLAGS`。ADR-0010 将 StockWatch 迁入独立 package 后，manifest 直接依赖 GRDB 与 GRDBSQLite products，并删除股票路径的 DerivedData 相对 workaround；PodPin 在完成同类 package 迁移前仍保留其必要设置。
- 数据库以单一 actor/queue 收敛 schema 初始化、查询、写入、迁移、备份和 close。schema 身份、结构、约束和领域数据在进入正常运行前校验。
- 只有 OneBox 新库不存在且独立应用旧库存在时，才尝试一次导入：
  1. 在打开旧库前确认不存在 `-wal` 或 `-shm`、不存在非空 `-journal`，且数据库头没有声明 WAL 模式；命中任一条件就拒绝导入，要求用户先完全退出 MarketSprite、正常 checkpoint 并切回非 WAL 模式；
  2. 以只读配置打开 `~/Library/Application Support/MarketSprite/marketsprite.sqlite`；
  3. 校验数据库身份、schema、完整性、自选、行情和提醒数据；
  4. 再次检查上述活动 sidecar 和 WAL 标记；
  5. 用 SQLite backup 写入 OneBox 目录中的唯一临时文件；
  6. 只读复验临时副本；
  7. 再次确认正式新库仍不存在，然后用同目录移动原子发布。
- 任一步失败都删除临时 OneBox 文件、保持正式新库不存在并报告启动错误；不得静默丢弃旧数据后创建空库。
- 导入过程绝不写入、移动、归档或删除独立应用旧数据库及其 sidecar。成功后所有写入只进入 OneBox 新库；因为新库已经存在，后续启动不再读取或合并旧库。
- 移除 GRDB 不只是删除包依赖；必须重写数据库边界、schema 与迁移、SQLite 一致快照以及并发 open/write/flush/close 验证。

## Consequences

### Positive

- OneBox 和独立应用拥有不同的可写数据库，旧数据保持可回退和可手工删除。
- 校验、临时导入和原子发布避免半成品被当作正式库。
- 精确版本和完整许可证让构建与分发依赖可追踪。

### Negative

- 首次迁移会暂时占用新旧两份数据的磁盘空间。
- 旧库仍处于 WAL 模式或带有活动 sidecar 时，用户必须先让 MarketSprite 完成 checkpoint 并切回非 WAL 模式；OneBox 不会尝试替用户恢复或清理旧库。
- 迁移后两个应用的数据独立变化，不提供双向同步或再次合并。
- GRDB 成为股票看盘数据库实现的高删除成本依赖；package manifest 和最终 App 图都必须持续验证 GRDBSQLite 的 module map 与链接结果。
