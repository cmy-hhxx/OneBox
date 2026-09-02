# ADR-0011: 在偏好中缓存公开行情 provider 标识

- Status: Accepted
- Date: 2026-09-01
- Amends: [ADR-0009](0009-use-onebox-grdb-database-and-one-time-import.md)

## Context

股票看盘以 `InstrumentID` 作为稳定领域标识，但东方财富的美股行情接口需要 provider 自有的 `secid`。这个值不能从所有美股代码可靠推导；fallback 首次使用某个标的时，需要通过公开搜索接口解析。若每次启动都重新解析，会增加延迟和不必要的网络请求；若把 provider 标识永久视为有效，provider 调整标识后又会让该标的一直 fallback 失败。

provider 标识是从公开行情响应派生的缓存，不属于观察列表、提醒或用户账户数据，也不应成为数据库中的领域身份。

## Options considered

### 每次 fallback 都重新搜索

不需要本地状态，但重复请求会增加刷新延迟和公开端点负担，并扩大短暂搜索故障对行情刷新的影响。

### 把 provider 标识写入股票数据库

可以与标的一起查询，但会把外部服务的可失效实现细节引入持久 schema、旧库导入和数据库迁移边界。

### 在 OneBox 偏好中缓存并在请求失败后重新解析一次

保持领域数据与 provider 缓存分离；通常避免重复搜索，同时允许服务端标识变化后自动恢复。

## Decision

- A 股和港股继续使用可确定推导的 provider 标识，不持久化。
- 只有通过公开搜索解析得到的美股东方财富标识会缓存到 OneBox `UserDefaults` 的 `onebox.stockWatch.eastMoneyIdentifiers` 键。
- 缓存是以稳定 `InstrumentID.rawValue` 为键、provider `secid` 为值的字典。读取时必须同时校验稳定标识和 provider 标识格式；无效条目不得进入行情请求。
- 进程内缓存优先于偏好读取。新解析出的有效标识同时更新进程内缓存和偏好。
- 使用缓存标识的东方财富行情请求失败时，客户端删除对应的进程内和偏好条目，通过公开搜索重新解析一次，并最多重试一次行情请求。取消不得触发搜索或重试。
- 该缓存不进入股票数据库、旧库导入、导出数据或 `InstrumentID`，也不改变 ADR-0009 规定的数据库所有权与布局。
- 删除该偏好键可以安全丢弃全部缓存；后续需要 fallback 时会重新解析。

## Consequences

### Positive

- 常规启动和刷新不必重复搜索已经解析过的美股标的。
- provider 更换标识后，第一次失败即可淘汰旧值并尝试自动恢复。
- 外部服务细节不污染数据库 schema、领域身份和一次性旧库导入。

### Negative

- OneBox 偏好中增加一个可失效的 provider 缓存，需要在隐私说明和删除说明中持续记录。
- provider 行情与搜索同时不可用时，单次 fallback 可能多发起一次搜索，但不会无限重试。
