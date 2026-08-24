# 运行时日志规范

日志用于回答：哪个模块的哪次操作，在什么阶段因为什么失败。发布环境使用统一结构化日志入口；工具不得直接写 stdout、文件或自建日志器。默认不远程上传。

## 字段

| 字段 | 要求 |
| --- | --- |
| `timestamp` | `Asia/Shanghai` 时区的 RFC 3339 时间，必须携带 `+08:00` 偏移 |
| `level` | `debug`、`info`、`warn` 或 `error` |
| `event.name` | 必填、稳定、低基数事件名 |
| `message` | 简短的人类说明 |
| `app.version` | 宿主版本 |
| `module.id` | 工具 ID；宿主使用 `onebox.host` |
| `operation.id` | 一次用户操作或后台工作链路的关联 ID |
| `duration_ms` | 完成或失败事件按需提供 |
| `error.type` | 失败事件的稳定错误分类 |
| `attributes` | 少量、已定义、低基数的附加字段 |

字段语义稳定比 JSON 编码本身更重要。同一字段在所有模块中必须保持相同类型和单位。

## 事件命名

使用 `<领域>.<对象>.<阶段>`：

```text
module.activation.started
module.activation.failed
stock.quotes.refresh.completed
blog.audio.playback.failed
window.focus.permission.denied
```

股票代码、URL、路径、错误文本和用户输入不得进入 `event.name`。高频循环只记录聚合结果或状态变化。

## 隐私

任何级别都禁止记录：

- token、cookie、密码、授权头和密钥；
- 券商账户、持仓、个人资产或完整交易信息；
- 完整博客正文、音频、剪贴板或请求正文；
- 辅助功能读取的窗口标题、控件文本或其他应用内容；
- 完整 URL 查询参数、本机用户名和绝对用户目录。

需要关联的标识使用会话内随机 ID 或不可逆摘要。错误进入日志前必须统一脱敏。

## 记录规则

- 同一操作链路复用一个 `operation.id`。
- 每个失败只在拥有恢复决策的层记录一次；下层返回类型化错误，不逐层重复打印。
- `info` 只记录生命周期和重要操作结果；可恢复降级使用 `warn`，当前操作失败使用 `error`。
- 用户界面解释发生了什么和下一步，日志记录模块、阶段和错误类型。

字段设计参考 [OpenTelemetry Logs Data Model](https://opentelemetry.io/docs/specs/otel/logs/data-model/)。
