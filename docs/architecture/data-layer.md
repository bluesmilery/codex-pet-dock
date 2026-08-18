# Codex Pet Dock — 数据层架构

> 数据层只提供两项数据：**WEEK LEFT**（官方周额度剩余）和 **WEEK TOKENS**（本机本周 Token 统计）。
> 本文描述数据模型、读取边界、并发约定和可重复验证方式；UI、主题、登录自启与安装包不属于本层。

数据读取遵守隐私边界：不修改 Codex，不直接读取或复制 `auth.json`、token、邮箱，不读取、记录或输出会话正文。

## 数据契约

### WEEK LEFT：官方 app-server 能力

来源是 `codex app-server`（codex-cli 的 experimental 能力）的 stdio JSON-RPC。

| 项 | 约定 |
| --- | --- |
| 握手 | `initialize`（`clientInfo` + `capabilities.experimentalApi=true`）→ `notifications/initialized` |
| 方法 | `account/rateLimits/read`（请求 `GetAccountParams`，不主动 `refreshToken`） |
| 响应 | `GetAccountRateLimitsResponse` → `rateLimits: RateLimitSnapshot` |
| 周窗口 | 从 `primary` / `secondary` 中选择 `windowDurationMins` 最接近 10080 的窗口 |
| 推送 | `account/rateLimits/updated`（滚动 sparse 更新，可合并） |

`RateLimitClient` 只解析 `usedPercent`、`resetsAt`、`windowDurationMins` 和 `planType`。鉴权由 `codex` 子进程在其可信环境中完成；本进程只经 stdio 收发 JSON-RPC 文本，不碰凭证。协议 schema 可用以下命令在本地复现：

```sh
codex app-server generate-json-schema --out <dir>
```

### WEEK TOKENS：本机会话日志

来源是 `~/.codex/sessions/YYYY/MM/DD/rollout-<timestamp>-<uuid>.jsonl`。

| 字段 | 路径 | 说明 |
| --- | --- | --- |
| 时间戳 | 行顶层 `timestamp`（ISO8601 字符串） | 归入时间窗口 |
| Token 增量 | `payload.info.last_token_usage.{total_tokens,input_tokens,cached_input_tokens,output_tokens}`（number） | 单次增量；缺失字段按 0 |

计数口径是同一会话内分别对 `last_token_usage` 的四个数值字段求和；`total_tokens` 是总量，`total_token_usage` 是会话累计值，不能直接跨行求和。损坏行、无 token 行或无 timestamp 行均跳过。

仅提取 `timestamp` 与 `last_token_usage` 的 total/input/cached/output 四个数值字段，缓存也只持久化这五个字段，不含正文。

## 数据模型与服务

`Sources/PetDock/Data/Models.swift` 定义：

- `WeekLeft`：`usedPercent`、`remainingPercent`（`100 - used`）、`resetsAt`、`windowMinutes`、`isWeekly`（≥10080）、`planType` 和 `fetchedAt`。
- `WeekTokens`：`totalTokens`、`inputTokens`、`cachedInputTokens`、`outputTokens`、`windowStart`、`windowEnd`、`sampleCount`、`sessionFileCount` 和 `fetchedAt`。
- `TokenUsagePoint`：可缓存的 `timestamp` + `tokens`、`input`、`cached`、`output` 四个 Int64 数值。
- `DataResult<T>` / `DataError`：统一结果类型，仅承载可读错误，不承载凭证或正文。
- `Backoff.nextDelay(afterFailures:)`：纯函数退避表。

| 文件 | 责任 |
| --- | --- |
| `CodexExecutableResolver.swift` | 解析 codex 绝对路径：环境变量覆盖（展开 `~` 且必须绝对）→ 绝对目录 `PATH` → `~/.local/bin`、nvm 语义版本降序、`~/.volta/bin` 与可注入的系统候选；校验 canonical target、owner、普通可执行文件和 group/world writable 状态，同时保留安全 nvm/npm symlink 启动 URL。 |
| `RateLimitClient.swift` | 通过 `Process.executableURL` 启动 codex，完成 stdio JSON-RPC；`parse(_:)` 与 `childEnvironment(_:)` 为纯函数，子进程 PATH 会以前置 codex 父目录并保留原 PATH 条目（不做绝对路径过滤）。 |
| `TokenUsageLogReader.swift` | 按日期桶扫描日志，只取数值并维护增量缓存；`parseLine` / `parseISO` 为纯函数。落盘 key 为 `v2:` + sessionsRoot 相对路径 SHA-256，旧格式安全失效，cache 位于私有目录。 |

### 私有存储与 helper 边界

PetDock 的日志、诊断和 token cache 位于 `~/Library/Application Support/PetDock/` 下的私有子目录（目录 0700、文件 0600）。日志使用 no-follow 打开并去除 WID/PID；默认 `--diagnose` 只持久化脱敏结构统计，不保存标题、owner、真实窗口标识或精确坐标。Codex app-server 通过无 shell 的 `Process.executableURL` 启动，子环境只保留 HOME/TMPDIR/locale、非秘密 CODEX_HOME 和受控 PATH，不传递认证、cookie 或代理凭证。
| `PetDockDataService.swift` | 组合两数据源，分别维护退避计数，并提供 `pause()` / `resume()`。 |
| `LiveDockProvider.swift` | 在主线程缓存快照，后台刷新后映射为 UI 数据。 |

### 增量缓存

`TokenUsageLogReader` 按「文件路径 → `{size, points}`」维护进程内缓存：文件大小不变时复用，变化时重读该文件；当前扫描范围之外或已删除的条目会被淘汰。若提供 `cacheURL`，同一结构以 JSON 原子写入供跨进程复用；每个 point 只含 timestamp 与四个 token 数值。未提供 `cacheURL` 时仅使用进程内缓存。

### 退避与暂停

WEEK LEFT 与 WEEK TOKENS 的失败计数相互独立：成功后 5 分钟，连续失败 1/2/3 次分别为 15/30/60 分钟，更多失败保持 60 分钟。

`PetDockDataService.pause()` 在宠物不可见时由集成层调用；暂停期间两个读取入口均返回“已暂停”错误。`resume()` 恢复读取。本层不启动定时器，以保持时钟可注入、逻辑可测试。

## 隐私与错误边界

- `TokenUsageLogReader` 不解析会话正文；格式漂移时 `parseLine` 返回 nil 并跳过，不因单行损坏崩溃。
- `RateLimitClient` 找不到 codex、app-server 退出或超时时返回可读错误并进入退避；WEEK TOKENS 仍可独立工作。
- app-server 协议为 experimental，字段可能随 codex 版本变化；缺失字段按稳定子集降级（例如 `usedPercent` 默认 0，`resetsAt` / `windowMinutes` 可为 nil）。
- 屏幕录制权限不属于数据层前提；WEEK LEFT 仍要求 codex 已登录，但本进程不读取登录文件。

## 可重复验证

```sh
make build
make test-data
```

`make test-data` 使用 `tests/DataTests.swift` 与脱敏 fixture，不联网且不需要屏幕录制权限。当前公开口径为 **test-data 123 项**，覆盖周窗口聚合、四项 token 数值与脱敏、增量缓存与淘汰、`parseLine` 鲁棒性、WeekLeft 窗口与重置时间、退避、暂停、服务组合、LiveDockProvider 映射、并发安全、codex 路径解析、子进程 PATH、LineReader、日期 fixture 以及 rpc stdio fixture。细分编号以测试入口源码为准，避免文档数字随新增用例漂移。

集成入口为 `PetDockDataService(rateLimit:tokenLog:now:)` 的 `fetchWeekLeft()`、`fetchWeekTokens()`、`weekLeftNextDelay`、`weekTokensNextDelay`、`pause()` 和 `resume()`。
