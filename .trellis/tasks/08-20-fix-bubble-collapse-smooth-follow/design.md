# Technical Design

## Scope and boundaries

本次只改 follow 调度、气泡探测节流/失效唤醒、Follower 稳定判定、对应测试与事实文档。现有窗口选择、几何放置、数据刷新、主题和权限请求策略保持不变。

## Root-cause model

### Bubble collapse

生产链为：follow tick 枚举候选 → `BubbleVisibilityProbe.probe` 受 0.5 秒最小间隔约束 → 后台 ScreenCaptureKit 捕获/分类 → cache 变化通知 → 主线程 `schedule(0)` → 新 tick 重新计算障碍与 frame。

上一版测试证明了“成功分类后的通知桥接”，但没有证明端到端延迟或真实调度器替换已有 timer 后执行完整 tick。用户可见延迟仍包含探测等待和捕获耗时；若 TCC/capture 失败则按契约一直保守 visible，不能承诺回位。

本次保留 one-shot screenshot 架构，仅把有 visible 气泡候选时的探测 cadence 提升到不高于 0.1 秒，并把布局唤醒接入新的 coalesced scheduler。single-flight 使实际捕获频率自动受捕获耗时上限约束，不产生截图任务积压。

## Follow scheduler

引入职责单一的 follow scheduler，区分三类输入：

1. `moving`：macOS 14+ 从底座 `NSWindow` 获取 `CADisplayLink`，随窗口跨屏自动切换节拍；每个 display callback 请求 coalesced main tick。
2. `stable` / `hidden`：保留低频 one-shot Timer，分别按 Follower 决策的 0.1 秒/1 秒触发。
3. `wakeNow`：气泡分类变化请求立即 tick；取消低频 timer 或把已有待执行 tick 提前，但不重复排队。

macOS 13 回退使用 repeating Timer，周期取当前屏幕 `maximumFramesPerSecond` 的倒数并以 120 Hz 为实验上限；无有效屏幕能力时回退 60 Hz。repeating Timer 以原始 fire schedule 为基准，避免现有“工作耗时 + interval”的累积漂移。回退仍加入 `.common` run-loop mode。

Scheduler 维护一个 `tickPending`/执行门闩：display link 或 timer 只提交请求；若主线程已有待执行/正在执行 tick，新节拍不追加。tick 完成后根据最新 Follower 决策切换 cadence，保证最终状态优先于过期帧。

不使用 `CVDisplayLink`，因为当前 SDK 已将其在 macOS 15 标为 deprecated；不使用固定 120 Hz，因为普通屏没有收益且窗口枚举有长尾；不做 frame 插值，因为它会引入尾随、预测误差和跨屏复杂度。

## Follower state semantics

现有 `stableCount` 把稳定判定绑定到 tick 次数；切换到 60/120 Hz 或可变刷新后，同样的 4 tick 分别约为 67/33ms，会改变行为。将稳定条件改为基于单调时钟的连续无实质位移时长，并用现有名义 60 Hz 下 `4 / 60 ≈ 66.7ms` 作为兼容阈值：

- 首次捕获/发生实质位移：清空 stable 起点，进入 moving；
- 未发生实质位移：记录或沿用 stable 起点；
- 连续稳定达到既定时间阈值后进入 stable；
- 测试注入时间，覆盖 60、120 和不规则节拍。

实际状态以时长为准，日志只记录非敏感 cadence/state，不记录窗口身份或坐标。

## Bubble visibility scheduling

`BubbleVisibilityProbe` 保留 generation、knownWids、single-flight 和保守 nil 分类。受控 cadence 只改变“何时允许下一次捕获”，不改变分类阈值或缓存语义：

- 当前候选包含 visible/未分类气泡：下一次 probe 最迟 0.1 秒可启动；
- 捕获在途：新请求直接合并；
- 分类结果变化：只触发一次 `wakeNow`；
- 候选消失：同一枚举 tick 内 knownWids 立即生效并布局；
- TCC false/capture nil：不声称收起已识别。

同 WID、同几何但内容在 capture in-flight 期间变化时，没有公开的无权限事件可使旧截图自动失效；本轮依靠 single-flight 后的 0.1 秒再探测限制额外等待。若真机仍证明该长尾不可接受，持续 `SCStream` 属于需要重新规划的下一阶段，不在本轮暗中扩张。

## Compatibility and privacy

- macOS 13：Timer fallback；BubbleVisibility 继续无法像素捕获时保守避让。
- macOS 14+：公开 AppKit CADisplayLink + 现有 ScreenCaptureKit。
- 所有 NSPanel 操作在主线程；后台探测只提交无参数失效通知。
- 不保存或输出 alpha 统计、截图、真实窗口标识、坐标或内容。

## Rollout and rollback

实现分为调度状态机、气泡 cadence、运行时接线三个可审查批次，但冻结为一个完整候选 SHA。若 display link 路径出现兼容问题，可回退到无漂移 Timer scheduler 而不回退气泡唤醒和时间型稳定判定。任何分类阈值变化或持续 SCStream 方案都超出本设计，必须重新规划。
