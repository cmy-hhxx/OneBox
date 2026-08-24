# 运行时日志规范

日志用于回答：哪个模块的哪次操作，在什么阶段因为什么失败。当前尚无业务日志实现；第一个真实运行时日志调用出现时，再按本规范建立一个统一的窄入口。工具不得直接写 stdout、文件或自建日志器，默认不远程上传。

## Unified Logging 映射

发布环境使用 macOS Unified Logging：

- 系统负责时间戳、持久化和日志级别，不在应用消息中重复写 `timestamp` 或时区字段。
- subsystem 使用应用 bundle identifier；category 使用稳定的 `module.id`。
- 应用语义 `debug`、`info`、`warn`、`error` 分别写入 `Logger.debug`、`Logger.info`、`Logger.notice` 和 `Logger.error`。
- 事件字段通过固定消息模板和带隐私标记的插值写入，不把任意字典整体编码为字符串。
- 本规范定义字段语义，不要求额外 JSON、文件 sink 或 Observability 框架。

## 应用字段

| 字段 | 要求 |
| --- | --- |
| `event.name` | 必填、稳定、低基数事件名 |
| `message` | 简短的人类说明，不承担错误分类 |
| `app.version` | 宿主版本；统一入口自动补充 |
| `module.id` | 工具 ID；宿主使用 `onebox.host`，并映射为日志 category |
| `operation.id` | 一次用户操作或后台工作链路的会话内关联 ID |
| `duration_ms` | 完成或失败事件按需提供，单位固定为毫秒 |
| `error.type` | 失败事件的稳定错误分类 |
| `attributes` | 少量、预先定义、低基数的附加键值 |

同一字段在所有模块中必须保持相同类型和单位。字段未被真实查询或诊断使用前，不预先增加。

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

需要关联的标识使用会话内随机 ID。只有确有跨会话诊断需求且完成隐私评估后，才允许使用不可逆摘要。错误进入日志前必须统一脱敏。

## 记录规则

- 同一操作链路复用一个 `operation.id`。
- 每个失败只在拥有恢复决策的层记录一次；下层返回类型化错误，不逐层重复打印。
- `info` 只记录生命周期和重要操作结果；可恢复降级使用 `warn`，当前操作失败使用 `error`。
- 用户界面解释发生了什么和下一步，日志记录模块、阶段和错误类型。
- 统一入口必须显式标记每个插值的隐私级别；默认按私有数据处理。

字段设计参考 [OpenTelemetry Logs Data Model](https://opentelemetry.io/docs/specs/otel/logs/data-model/)，但当前不引入 OpenTelemetry SDK 或传输器。

## 存储位置

应用运行时日志只进入 macOS Unified Logging，不在源码仓库或应用工作目录创建日志文件。工程构建与测试日志不属于应用运行时日志，由 `./scripts/test.sh` 写入 `.build/Logs`；测试结果写入 `.build/TestResults`。两者均为本地可再生成产物并受 `.gitignore` 管理。
