# Design

## A. TokenUsageLogReader v3 尾部增量

### 缓存格式

```
CacheEntry v3 = { size: Int64, parsedBytes: Int64, points: [TokenUsagePoint] }
```

- `parsedBytes` 语义：**恰好消费到最后一个完整 `\n` 之后**的字节偏移（换行对齐不变量；
  0 = 尚未消费）。未完成尾行（无结尾换行）不消费、不产点，下次继续。
- v2 条目（无 `parsedBytes` 字段）解码为 `parsedBytes = 0`；缓存命中条件从
  `size 相等` 收紧为 `size 相等 && parsedBytes > 0`。效果：v2 points 先供展示，
  下一次刷新全量重解析一次并落 v3（一次性后台成本），避免跨版本边界丢行/重复。

### 统一分块行解析器

全量与增量走同一路径：`FileHandle` seek 到起始偏移 → 按块（如 1MB）读取 → 在字节层找
`0x0A` 组行（UTF-8 行内容用 `String(decoding:as:)` 按完整行构造）→ 只消费完整行 →
返回 (points, 新 parsedBytes)。内存上界 = 最长单行 + 块大小。

- 全量解析 = 从偏移 0 起的同一路径；删除现有 `Data(contentsOf:) + String(data:)` 整载实现。
- 增量条件：`entry.size < 当前 size && entry.parsedBytes > 0 && entry.parsedBytes <= entry.size`
  → 从 parsedBytes 续读；`当前 size < entry.parsedBytes` 或 v2（parsedBytes=0）→ 全量。
- 行级解析复用既有 `parseLine`（timestamp + last_token_usage.total_tokens，隐私边界不动）。
- 测试计数器：保留 `debugFilesParsed`（全量），新增 `debugIncrementalParses`（增量轮数）。

### 不变项

`candidateFiles(from:to:)` 窗口扫描、淘汰逻辑、persist 落盘节奏、symlink/权限守卫、
maxCacheBytes 上限均不变。

## B. BubbleVisibilityProbe 心跳 + 共享枚举

### 心跳门控（state 内新增 `identityDirty: Bool = true`）

```
effectiveInterval = identityDirty ? minInterval(0.1) : stableProbeInterval(1.0)
due = !inFlight && time - lastCaptureAt >= effectiveInterval
```

- `probe` 检测到 `windowIdentityChanged` → 置 `identityDirty = true`；一轮捕获启动时清 false。
- 被门控挡下时 `pendingRetryAt = lastCaptureAt + effectiveInterval`（沿用既有 hint 机制）。
  `isDue` 同步更新语义。
- 粘性语义不变：纯 bounds 变化不置 dirty，拖动期间靠 sticky cache + 1s 心跳纠偏。

### 每轮共享 SCShareableContent

```
typealias BubbleCapturerFactory = @Sendable () async -> BubbleCapturer
```

- `BubbleVisibilityProbe` 持有 `makeCapturer`（工厂），`Task.detached` 每轮先
  `await makeCapturer()` 一次，再对 N 个候选复用返回的 capturer。
- 默认工厂：macOS14+ 先取一次 `SCShareableContent.excludingDesktopWindows`，
  返回按候选查窗口的闭包；取失败/低版本返回恒 `.unavailable`（保守 visible 语义不变）。
  `captureStats` 改为接收 `content` 参数（窗口查找与 unavailable/targetMissing 语义不变）。
- 兼容：init 保留便捷参数或由测试直接改传工厂（`tests/main.swift` 机械更新调用点）。

## C. 启动首刷延迟

- `FollowTickPlan.swift` 新增纯策略（随 test-ui 目标编译）：
  `initialDelay = 5.0` + 判定「首个 petVisible 上升沿后是否走延迟调度」。AppState 持有
  `hasCompletedFirstRefresh`，在首个 refresh 完成回调置 true。
- `main.swift` 接线：`plan.resumeData` 且未完成首刷 → 用既有 `dataTimer` one-shot 调度
  `initialDelay` 后 `refreshData()`；否则立即 `refreshData()`。`plan.pauseData` → 既有
  `stopDataRefresh()`（取消在途延迟调度）。

## 文件改动清单（白名单）

- `Sources/PetDock/Data/TokenUsageLogReader.swift`
- `Sources/PetDock/BubbleVisibility.swift`
- `Sources/PetDock/FollowTickPlan.swift`
- `Sources/PetDock/main.swift`
- `tests/DataTests.swift`
- `tests/main.swift`
