# Codex Pet Dock — 数据层（P1）

> 范围严格限定为两项数据：**WEEK LEFT**（官方周额度剩余）、**WEEK TOKENS**（本机本周 Token 统计）。
> 仅数据模型 / 服务 / fixture 测试 / 文档；**不做** UI / 主题 / 登录自启 / 安装包。
> **不修改 Codex**，**不直接读取 / 复制 `auth.json`、token、邮箱**，**不读取 / 记录 / 输出会话正文**。

## 数据契约（均已在本机实证）

### WEEK LEFT — 官方 app-server 能力

来源：`codex app-server`（codex-cli ≥0.145，experimental）的 JSON-RPC，经 stdio。

| 项 | 值 |
| --- | --- |
| 握手 | `initialize`（`clientInfo` + `capabilities.experimentalApi=true`）→ `notifications/initialized` |
| 方法 | `account/rateLimits/read`（请求 `GetAccountParams`，不主动 `refreshToken`） |
| 响应 | `GetAccountRateLimitsResponse` → `rateLimits: RateLimitSnapshot` |
| 周窗口 | `rateLimits.primary: RateLimitWindow`（`usedPercent` / `resetsAt` / `windowDurationMins`） |
| 推送 | `account/rateLimits/updated`（滚动 sparse 更新，可合并） |

实证探测（脱敏，仅状态 / 比例 / 重置时间；下列为示例，非真实账户数据）：`primary` 窗口
`windowDurationMins=10080`（= 7×24×60 = **一周**，公开协议常量），`usedPercent` / `resetsAt` / `planType` 因账户而异（已脱敏）。

> 合规：鉴权由 `codex` 进程在其可信环境内完成（它自管 `auth.json`）。本进程仅经 stdio 收发
> JSON-RPC 文本，只解析 `usedPercent` / `resetsAt` / `windowDurationMins` / `planType`，**不碰凭证**。

协议 schema 可本地复现：`codex app-server generate-json-schema --out <dir>`。

### WEEK TOKENS — 本机会话日志

来源：`~/.codex/sessions/YYYY/MM/DD/rollout-<ts>-<uuid>.jsonl`（JSONL，按日期分桶，文件名含时间戳）。

| 字段 | 路径 | 说明 |
| --- | --- | --- |
| 时间戳 | 行顶层 `timestamp`（string，ISO8601，可含高精度小数） | 归入时间窗口 |
| Token 增量 | `payload.info.last_token_usage.total_tokens`（number） | **单次增量** |

计数口径已验证：**Σ `last_token_usage.total_tokens`（单次增量） = `total_token_usage.total_tokens`
最终累计值**（同一会话内实测 Σ last = total 末值 = <N>）。因此跨会话对 `last_token_usage` 求和
不会重复计数。`total_token_usage` 是会话累计，**不可**直接跨行求和。

> 合规：仅提取 `timestamp` + `last_token_usage.total_tokens` 两个数值字段；损坏行 / 无 token 行 /
> 无 timestamp 行一律跳过。缓存也只持久化这两个数值，**不含正文**。

## 数据模型（`Sources/PetDock/Data/Models.swift`）

- `WeekLeft`：`usedPercent` / `remainingPercent`(=100-used) / `resetsAt` / `windowMinutes` / `isWeekly`(≥10080) / `planType`。
- `WeekTokens`：`totalTokens` / `windowStart` / `windowEnd` / `sampleCount`。
- `TokenUsagePoint`：`timestamp` + `tokens`（Codable，可缓存）。
- `DataResult<T>` / `DataError`：统一结果（仅可读信息，无凭证 / 正文）。
- `Backoff.nextDelay(afterFailures:)`：纯函数退避。

## 服务与接口

| 文件 | 角色 |
| --- | --- |
| `CodexExecutableResolver.swift` | codex 绝对路径解析，不依赖交互 shell：env 覆盖（先展开 `~`，随后必须绝对，否则 `overrideNotAbsolute`）> `PATH`（仅绝对目录，跳过空/相对）> `~/.local/bin` / nvm(语义版本降序) / `~/.volta/bin` / 可注入系统候选(brew)；符号链接跟随到目标。 |
| `RateLimitClient.swift` | `RateLimitFetching` 协议 + `RateLimitClient`（resolver + Process executableURL + stdio JSON-RPC）。`parse(_:)`、`childEnvironment(_:)` 纯函数。 |
| `TokenUsageLogReader.swift` | `TokenLogReading` 协议 + `TokenUsageLogReader`（按日期桶扫描、只取数值、增量缓存）。`parseLine`/`parseISO` 纯函数。 |
| `PetDockDataService.swift` | 顶层服务：组合两数据源、各自退避计数、`pause()`/`resume()`（宠物不可见时暂停）。 |

### 增量缓存

`TokenUsageLogReader` 按「文件路径 → {size, points}」缓存整文件解析结果：`size` 不变则复用，
变化则重读全文件（rollout 文件均 <5MB）。缓存可落盘（`cacheURL`）以跨进程复用；**只存 timestamp+tokens**。
进程内增量经 mutating `readPoints` 维护，跨进程经落盘文件。

### 退避（WEEK LEFT / WEEK TOKENS 各自独立）

| 连续失败次数 | 下次刷新间隔 |
| --- | --- |
| 0（成功） | 5 分钟 |
| 1 | 15 分钟 |
| 2 | 30 分钟 |
| ≥3 | 60 分钟 |

### 暂停

`PetDockDataService.pause()` / `resume()` / `isPaused`：宠物不可见时集成层调用 `pause()`，
刷新直接返回「已暂停」错误；可见时 `resume()` 恢复。本层不自行启动定时器（保持可测、可注入时钟）。

## 构建与测试

```sh
make build        # 完整构建（P0 源码 + Data/ 数据层）。数据层子目录被 PetDock target 自动包含，无需改 Package.swift。
make test-data    # 数据层测试（独立入口 tests/DataTests.swift + tests/fixtures/，不联网 / 无需屏幕录制权限）
```

测试覆盖（`tests/DataTests.swift`，26 项）：周窗口聚合 Σ、只用 `last_token_usage`、脱敏（结果不含
正文诱饵）、增量缓存命中（跨实例 `debugFilesParsed=0`）、缓存往返一致、`parseLine` 鲁棒性、`WeekLeft`
解析与周窗口判定、退避表、`pause` 语义、服务端到端 `fetchWeekTokens`、服务退避计数。

## 真实验证结果（脱敏）

- **WEEK LEFT**（app-server）：成功返回周窗口 `windowDurationMins=10080`、有 `resetsAt`
  （`usedPercent` / `planType` 因账户而异，已脱敏）。
- **WEEK TOKENS**（真实日志最近 7 天）：返回非占位正值（`sampleCount` / `totalTokens` 因本机而异，已脱敏）。
  仅数值聚合，无任何 timestamp / 正文输出。

## 边界与集成约定（供并行集成）

- **未修改** `DockPanel.swift` / `PetTracker.swift` / `Geometry.swift` / `main.swift`。
- 数据层全部位于 `Sources/PetDock/Data/`；**未改 `Package.swift`**；`Makefile` 仅新增 `test-data` 目标。
- 暴露的集成入口：`PetDockDataService(rateLimit:tokenLog:now:)` 的 `fetchWeekLeft()` /
  `fetchWeekTokens()` / `weekLeftNextDelay` / `weekTokensNextDelay` / `pause()` / `resume()`。

## 风险

1. **app-server 为 experimental**：协议（`account/rateLimits/read` 字段、`experimentalApi` 握手）可能随
   codex 版本变化；`RateLimitClient.parse` 只取稳定子集（`usedPercent`/`resetsAt`/`windowDurationMins`/`planType`），
   缺失字段降级（`usedPercent` 缺省 0、`resetsAt`/`windowMinutes` 为 nil）。
2. **codex 不在默认 PATH（.app 由 launchd 启动）**：`RateLimitClient` 经 `CodexExecutableResolver`
   解析 codex 绝对路径（env `CODEX_PET_DOCK_CODEX_PATH` 覆盖 > `PATH` > `~/.local/bin` /
   `~/.nvm/versions/node/*/bin`（语义版本降序）/ `~/.volta/bin` / `/opt/homebrew/bin` / `/usr/local/bin`），
   用 `Process.executableURL` 直接启动（**不经 `/bin/sh -lc`**，规避 launchd 环境无 nvm、非交互 shell
   不读 `~/.zshrc`）。找不到时返回可解释错误（WEEK TOKENS 不受影响，仍由本机日志独立工作）。
   **子进程 PATH prepend**：`RateLimitClient.childEnvironment` 把 codex 父目录 prepend 到子进程 `PATH`
   （去重、保留原 PATH），使 codex 脚本 `#!/usr/bin/env node` 能在子进程找到同目录的 node（nvm：
   codex 与 node 同在 `~/.nvm/versions/node/*/bin`）。
3. **日志格式漂移**：`last_token_usage.total_tokens` 路径或 `timestamp` 精度变化时，`parseLine` 返回 nil
   并跳过（不崩溃）；`parseISO` 已兼容纳秒精度与无小数秒两种形态。
4. **TCC / 进程权限**：数据层本身不需屏幕录制权限；但 WEEK LEFT 依赖 codex 已登录（`auth.json` 有效），
   未登录时 app-server 返回错误 → 计入失败退避（不影响 WEEK TOKENS 本机统计）。
5. **退避为接口语义**：本层只提供 `nextDelay` 与失败计数；实际定时调度由集成层（未来 `main.swift`）驱动。
