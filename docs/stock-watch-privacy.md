# 股票看盘隐私说明

股票看盘面向单个本机用户。它不要求账户，不上传整份观察列表，也不提供云同步、遥测、下单或交易能力。

## 本地数据

股票看盘把下列内容保存在本机：

| 内容 | 位置 |
| --- | --- |
| 有序观察列表、最近交易日行情与分钟缓存、provider 来源和时间、百分比提醒、每标的目标价 | `~/Library/Application Support/OneBox/StockWatch/marketsprite.sqlite` |
| 刷新间隔、牛叫开关、熊吼开关 | OneBox `UserDefaults` 中的 `onebox.stockWatch.*` 键 |
| 数据库、刷新和批量应用耗时 | macOS Unified Logging signpost；只记录固定区间名，不记录代码、搜索词、URL 查询或绝对用户路径 |

行情缓存用于在请求失败或尚未刷新时显示上次成功数据。界面会把缓存、旧响应和刷新失败标为 stale 或错误；本地存在数据不代表数据仍然及时。

## 一次性旧数据导入

如果 OneBox 新库不存在，而下面的独立应用数据库存在，股票看盘会尝试一次导入：

```text
~/Library/Application Support/MarketSprite/marketsprite.sqlite
```

导入过程以只读方式打开旧库，校验数据库身份、schema、完整性和领域数据，再通过 SQLite backup 写入 OneBox 目录的临时文件。临时副本复验成功后才在同一目录原子发布为新库。失败时不会启用半成品新库。

为避免只读打开也参与仍在活动的 WAL，导入前只要发现旧库旁存在 `-wal` 或 `-shm`、存在非空 `-journal`，或者数据库头仍声明 WAL 模式，股票看盘就会拒绝导入。此时应完全退出 MarketSprite，使用它正常 checkpoint，并把数据库切回非 WAL 模式后再重试；OneBox 不会自行删除或修改这些文件。

股票看盘绝不写入、移动、归档或删除这个独立应用旧库。新库一旦存在，后续启动不再导入或合并旧库；两个应用之后的数据也不会同步。OneBox 的对应偏好键不存在时，还会只读旧偏好域 `io.github.cmy-hhxx.marketsprite` 的刷新间隔与两个声音开关，并把有效值复制到 OneBox 键；不会修改旧偏好。

## 网络访问

只有股票看盘被选中并挂载后，用户搜索、首次刷新、手动刷新或可见期间的定时刷新才会联网。切换到其他工具、使股票看盘视图 task 取消后，搜索和刷新会停止。窗口仅被其他窗口遮挡、失去焦点或最小化而内容仍挂载时，不等同于切换工具。

所有请求使用 HTTPS GET。公开 provider 会看到正常网络元数据，例如 IP 地址，以及固定桌面 `User-Agent` 和 `Referer: https://quote.eastmoney.com/`。业务查询如下：

| 端点 | 何时访问 | 发送内容 |
| --- | --- | --- |
| `searchapi.eastmoney.com/api/suggest/get` | 用户提交搜索；美股 fallback 需要解析 provider 标识时也可能访问 | 用户输入的名称或代码；固定 `type=14`、`count=20` 和公开 provider token |
| `web.ifzq.gtimg.cn/appstock/app/minute/query` | 每个观察标的的首选行情请求 | 单个标的的 provider `code` |
| `push2delay.eastmoney.com/api/qt/stock/trends2/get` | 腾讯请求失败且未取消后的分时 fallback | 单个标的的 `secid`；固定 `fields1`、`fields2`、`iscr=0`、`ndays=1` |

客户端拒绝 HTTP 重定向，避免查询或标的标识被转发到表格之外的地址。请求不发送 OneBox 账户、密码、设备通讯录、交易指令或整份观察列表。一次行情请求只带一个标的标识；搜索请求会发送用户刚输入的查询。OneBox 不控制这些公开 provider 如何处理服务器日志，使用前应同时考虑其公开政策。

## 提醒和声音

提醒在本机根据新接受的行情计算，并只显示在当前 OneBox 内容中。牛叫和熊吼 WAV 随应用打包并在本机播放。股票看盘不发送系统通知，不在工具离屏后继续后台监控，也不向服务器上传提醒阈值或目标价。

## 删除数据

- 只删除行情缓存：在股票看盘检查器的“数据”区选择“清空缓存”。观察列表和提醒设置会保留。
- 删除某个标的：在检查器移除它；该标的的目标价和行情缓存会一起删除。
- 删除全部股票看盘数据库：先退出 OneBox，再在 Finder 删除 `~/Library/Application Support/OneBox/StockWatch/`。
- 删除股票看盘偏好：退出 OneBox 后执行：

  ```sh
  defaults delete com.cmy.OneBox onebox.stockWatch.refreshInterval
  defaults delete com.cmy.OneBox onebox.stockWatch.bullSoundEnabled
  defaults delete com.cmy.OneBox onebox.stockWatch.bearSoundEnabled
  ```

删除 OneBox 数据不会删除独立应用的 `~/Library/Application Support/MarketSprite/` 或其偏好。如果只删除 OneBox 新库并再次打开股票看盘，因新库重新变为不存在，仍保留的独立应用旧库会再次满足导入条件；如果只删除 OneBox 偏好键，仍保留的三个旧偏好值也会再次复制。只有在不再需要独立应用及其回退数据，并且不希望重新导入时，用户才应另行移走或删除旧库和对应旧偏好。

## 行情风险

三个端点都是 OneBox 无法控制的公开服务，没有 OneBox 提供的可用性、时效或准确性 SLA。网络、provider、交易时段和解析变化都可能造成延迟、中断、缺失、旧数据或错误数据；fallback 和缓存只能改善可见性，不能证明行情正确。

股票看盘及其提醒只用于信息展示，不构成投资建议、报价承诺或买卖信号。用户不应仅依赖本工具作出投资决定。
