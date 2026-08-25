# PRD：优化启动与静止 CPU 性能

## 背景（现场症状与测量）

1. **启动耗时十几秒、期间 CPU 持续 100%**。只读诊断确认根因在 WEEK TOKENS 首刷：
   `TokenUsageLogReader` 按「整文件读入 + 全量行解析」处理 `~/.codex/sessions`，
   本机近 7 天实测 **205 个文件 / 共 612.9MB / 最大单文件 286.6MB**，远超代码注释
   假设的 "<5MB"。缓存未命中时单线程全量解析 613MB 把单核打满 10+ 秒，且
   `Data + String` 整载带来数百 MB 内存尖峰；活动会话文件每次变大都会整文件重解析，
   每 5 分钟刷新周期重复一次。
2. **日常底座静止时 CPU 维持 20%-30%**。两个叠加源：
   - `BubbleVisibilityProbe.minInterval = 0.1`：只要宠物附近存在会话气泡 /
     Composition Surface（日常挂机常态），每 100ms 一轮 ScreenCaptureKit 截屏 +
     alpha 统计，且每个候选各自调一次 `SCShareableContent.excludingDesktopWindows`
     （昂贵枚举），可见性稳定后也无任何跳过机制。
   - （不在本任务范围）stable tick 10Hz `CGWindowList` 枚举，用户决定暂缓。

## 目标

- 启动（含 warm cache）不再出现长时间单核 100%；首次数据刷新延后，不与启动/首帧竞争 CPU。
- 活动会话文件增长后只解析新增字节（append-only 尾部增量），消除每 5 分钟的整文件重解析尖峰与内存尖峰。
- 气泡可见性在窗口身份稳定时按低频心跳复检（默认 1.0s），身份变化立即恢复 0.1s 快速节奏；
  每轮探测共享一次 `SCShareableContent` 枚举。

## 范围

**做：**

- A. `TokenUsageLogReader` v3 尾部增量解析（含 v2 缓存迁移、分块读取有界内存）。
- B. `BubbleVisibilityProbe` 稳定心跳 TTL + 每轮共享 SCShareableContent 枚举。
- C. 启动首次数据刷新延迟（默认 5s），宠物不可见时取消，首次完成后恢复既有立即语义。
- 上述项对应的单元测试与 fixture。

**不做（明确出范围）：**

- stable tick 10Hz → 更低频率 / 渐进退避（用户明确暂缓，另任务处理）。
- `RateLimitClient` / `codex app-server` 子进程启动开销。
- `FollowTickScheduler` / `Follower` 状态机节拍改动。

## 验收标准（AC）

每条 AC 必须给出证据链：触发 → 生产消费者 → 调度/回调链 → 最终状态所有者。
helper/纯函数证据只能补充，不能替代穿过生产实现的证据。

### A. Token 日志尾部增量解析

- **A1 未变文件零解析**：size 未变的文件命中缓存完全不重解析（保持既有 T3b 语义）。
  证据：`tests/DataTests.swift` fixture 真实文件经生产 `TokenUsageLogReader.readPoints`。
- **A2 增长文件尾部增量**：文件追加字节后仅解析新增**完整行**；跨越上次边界的未完成
  尾行在本次完成后被正确纳入（不丢行、不重复计数）；`debugFilesParsed`（全量解析计数）
  不增加且有独立的增量解析计数 ≥1。证据：fixture 写入→读取→追加（含跨边界行）→再读取，
  断言 points 与计数器。
- **A3 收缩/回绕回退全量**：文件 size < 已解析偏移时回退全量重解析并重置增量游标。
- **A4 v2 缓存迁移**：旧 v2 缓存条目（无 parsedBytes）载入后仍可用于窗口展示，但下一次
  刷新触发一次全量重解析，之后进入 v3 增量路径（一次性成本，后台发生）。
- **A5 全量/增量统一分块读取**：解析路径按块读取 + 行组装，禁止单文件整载
  `Data(contentsOf:)` + `String(data:)`（消除 286MB 级内存尖峰）。证据：代码审查 +
  构建通过；行为正确性由 A2/A3 fixture 覆盖。
- **A6 隐私边界不变**：仍只提取顶层 timestamp 与 token 数值字段，缓存仍不持久化原始路径，
  既有 symlink/权限守卫测试全绿。

### B. 气泡探测稳定心跳 + 共享枚举

- **B1 稳定心跳**：窗口身份未变化时，捕获节奏从 0.1s 降到
  `stableProbeInterval`（默认 1.0s）：fake clock 下 t=0 捕获、t<1.0 不捕获、
  t≥1.0 捕获。证据：`tests/main.swift` 经生产 `BubbleVisibilityProbe.probe` 真实状态机。
- **B2 身份变化恢复快速节奏**：identity 变化（wid 集合或非 bounds 身份字段）后回到
  `minInterval=0.1` 节奏，保证新气泡/气泡消失快速被观察到。
- **B3 每轮共享枚举**：一轮探测（N 个候选）只调用一次 capturer 工厂（默认工厂内一次
  `SCShareableContent` 枚举），逐候选复用。证据：mock 工厂调用计数 == 轮数。
- **B4 既有语义不回归**：sticky 拖动、reset、strict single-flight、probe(empty)、
  visibility-change wake、保守降级（unavailable→visible）等既有测试全部保持绿。

### C. 启动首刷延迟

- **C1**：首次数据刷新在首个 petVisible 上升沿后延迟 `initialDelay`（默认 5s）触发；
  延迟期间 petVisible 下降沿取消调度；宠物重新可见时重新调度；首个刷新周期完成后，
  后续 resume 沿恢复既有立即刷新语义。证据：策略纯函数单测（生产文件内）+ main.swift
  接线审查 + 真机 QA（日志时间戳：launch → first refresh ≥5s）。

### D. 质量门禁

- `swift build -c release` 0 warning（-warnings-as-errors 等级）。
- `make test` 全绿（test-ui + test-data + test-shell）。
- 独立 Review（全新只读子 Agent、完整 SHA）P0/P1/P2 清零后才进入 QA。

### E. 真机 QA（Review 清零后）

- 启动（warm cache）无明显长时单核 100%；Activity Monitor 抽样 CPU 显著低于现状。
- 宠物静止 + 气泡在场：探测/捕获节奏 ≤ ~1Hz（`--runtime-evidence` 计数或日志证据）。
- 底座跟随、气泡避让、主题、状态栏行为不回归；TCC 授权流程不受影响。

## 依赖与风险

- rollout 文件按 append-only 假设设计；非 append 场景（收缩/截断）由 A3 全量回退兜底。
- stable 心跳 1.0s 意味着“窗口身份不变、仅内容 alpha 变化”的可见性变化最迟 1s 内被
  纠正（现状 0.1s）；新气泡窗口出现（wid 变化）仍走 0.1s 快速路径。该权衡已获用户同意。
- v2→v3 迁移会带来一次性后台全量重解析（每文件一次），发生在首刷延迟之后，可接受。
