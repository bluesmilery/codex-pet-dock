# Technical Design

## Scope and boundaries

当前 v5 campaign 从精确产品候选 `585b9a4b4e2eef291755d5bc8971294e32feafa9` 继续，先只补墙钟 absence guard 与 `targetMissing` 生产组合证据。只有批准基线上的真实生产链测试失败时，才修改被证明有缺陷的最小生产边界；现有窗口选择/障碍几何、0.1 秒 cadence、FollowTickScheduler、Follower 稳定判定、插值语义、数据刷新、主题和权限请求策略保持不变。

## Root-cause model

### Bubble collapse

当前生产链为：follow tick 枚举 CGWindowList 候选 → `BubbleVisibilityProbe.probe` 按 0.1 秒单调 cadence 发起后台捕获 → ScreenCaptureKit 清单/截图/alpha 分类 → cache 变化通知 → latest-only 主线程 tick → `FollowLayoutPass` 重算障碍 → DockPanel 写回 frame。

真机复测显示底座在完整隐藏后仍随宠物改变绝对位置，却保持旧避让间距。这使“scheduler 未 tick / frame 完全 stale”的后验概率很低，最强假设是障碍仍被判 visible。当前 `BubbleCapturer` 的 `BubbleAlphaStats?` 把以下状态压成同一个 `nil`：SCK 清单获取失败、清单成功但目标 WID 不存在、截图失败。分类器对所有 `nil` 都返回 visible；若 CGWindowList 在窗口 teardown 后短暂保留旧几何，`knownWids` 仍包含该 WID，旧障碍便不会失效。

实现前先在批准基线上运行生产链症状测试，区分该假设与“另一个透明 wrapper/control 仍满足障碍几何”。只有测试证明“同一 CG 候选 + 先成功捕获 + 后续 SCK 清单成功但目标缺失”仍会保留 stale obstacle，才修改 typed outcome；若基线已经通过，则只补证据，不改 alpha 阈值或其他产品逻辑。

最小捕获契约：

- `.stats(BubbleAlphaStats)`：标记该 WID 已成功观察，并沿用现有滞回分类。
- `.targetMissing`：仅当该 WID 在当前 generation 内已有成功 `.stats` 观察时分类 hidden；从未成功观察的目标缺失仍按 unavailable/visible，避免把不支持捕获的可见窗口误判为隐藏。
- `.unavailable`：TCC、macOS 13、SCK 清单获取、截图或统计失败，始终保守 visible。

默认 capturer 只有在 `SCShareableContent` 调用成功后找不到目标 WID 才返回 `.targetMissing`；所有 `try?`/截图失败路径返回 `.unavailable`。成功观察集合与 cache 一起在 reset、候选消失、generation 变化和权限 false 路径清理。异步写回继续检查 generation 和当前 `knownWids`，不新增第二个 capture 或 Timer。

## Follow scheduler

保留 `d8538a5` 已实现的职责单一 follow scheduler，其三类输入为：

1. `moving`：macOS 14+ 从底座 `NSWindow` 获取 `CADisplayLink`，随窗口跨屏自动切换节拍；每个 display callback 请求 coalesced main tick。
2. `stable` / `hidden`：保留低频 one-shot Timer，分别按 Follower 决策的 0.1 秒/1 秒触发。
3. `wakeNow`：气泡分类变化请求立即 tick；取消低频 timer 或把已有待执行 tick 提前，但不重复排队。

Break-loop 后 stable 不再携带旧 cadence phase：每次完整 tick 以自身的单调开始时间 `tickStartedAt` 计算 `tickStartedAt + 0.1s` deadline。外部 off-grid wake 自然重置相位；下一次启动不晚于 `max(deadline, workCompletedAt)`。若串行主线程工作结束时已经跨过 deadline，coalescer 只保留一个在完成后立即执行的 latest-only tick，不补发历史 deadline，也不再额外等待 0.1 秒。

第二次 break-loop 统一时间域：scheduler tick、BubbleVisibility capture cadence 与 pending retry deadline 全部由同一个可注入单调时钟提供，生产默认 `ProcessInfo.systemUptime`。`Date()` 仅表示墙上时间，不得参与节流或 deadline 比较；系统时间前跳/后跳不应在 cadence 数据流中有输入通道。

macOS 13 回退使用 repeating Timer，周期取当前屏幕 `maximumFramesPerSecond` 的倒数并以 120 Hz 为实验上限；无有效屏幕能力时回退 60 Hz。repeating Timer 以原始 fire schedule 为基准，避免现有“工作耗时 + interval”的累积漂移。回退仍加入 `.common` run-loop mode。

Scheduler 维护一个 `tickPending`/执行门闩：display link 或 timer 只提交请求；若主线程已有待执行/正在执行 tick，新节拍不追加。tick 完成后根据最新 Follower 决策切换 cadence，保证最终状态优先于过期帧。

Window-bound display link 只有在 dock `isVisible && screen != nil` 时可用。DockPanel 对自身 window screen 变化提供主线程通知，AppDelegate 将其路由到同一 coalesced wake；外接屏移除或窗口暂时失去 screen 时，即使 display link 已停止回调，通知仍能驱动一次 tick 切换到 Timer fallback，screen 恢复后再重新评估 display link。

不使用 `CVDisplayLink`，因为当前 SDK 已将其在 macOS 15 标为 deprecated；不使用固定 120 Hz，因为普通屏没有收益且窗口枚举有长尾。

## Bounded linear frame interpolation

现有 `DockPanel.placeBelow` 每次完整 tick 直接 `setFrame` 到最新目标；display link 只提高采样频率，视觉仍是离散跳到采样点。新增放在 `DockPanel.swift` 内的纯值 `DockFrameInterpolator`，不创建独立计时器，不使用 `NSAnimationContext`：

- 状态只保存 `renderedFrame`、`segmentStartFrame`、`targetFrame`、`segmentStartedAt`，时间源为注入的单调时钟。
- 线性段固定最大 `0.032s`。求值为 `lerp(start, target, clamp((now-startedAt)/0.032, 0...1))`；`now >= end` 必须精确返回 target，禁止过冲。
- 宠物发生实质位移且目标变化时，先在 `now` 求出旧段当前 frame，再从该 frame 重定向到最新目标；历史目标不入队。
- `Follower.shouldSetFrame == true` 表示宠物位移引起的 retarget。`shouldSetFrame == false` 且目标与当前 segment target 相同，则继续采样未完成的段；若目标不同，说明障碍/屏幕/布局状态变化，立即 snap 而不动画。
- 首次显示、隐藏、无有效 screen、几何返回 nil、跨屏 screen identity 变化，以及气泡/控制障碍导致的目标变化都 reset/snap。`hideIfNeeded` 清空插值状态。
- 当前 moving→stable 至少保留约 66.7ms 的 display cadence，长于 32ms，因此最后一个插值段可在降频前完成。实际写回发生在下一个可用 display beat；主线程忙时不补历史帧。

`DockPanel.placeBelow` 增加最小的 `movementChanged` 与单调 `now` 输入，先计算唯一目标 Quartz/AppKit frame，再由 interpolator 决定本拍写回 frame。`main.swift` 只传入已有 `d.shouldSetFrame` 和共享 `followMonotonicNow()`；`DetailPanel` 继续读取实际 `dock.frame`，自然跟随已插值后的 frame。

32ms 是最大视觉拖尾而非额外 sleep。它在 60 Hz 约两个显示周期、120 Hz 约四个周期，可柔化 CGWindowList 离散更新；代价是持续拖动时约一个上限窗口的空间滞后，须在真机体感中单独验收。

## Follower state semantics

`d8538a5` 已把旧 `stableCount` 改为基于单调时钟的连续无实质位移时长，并保留名义 60 Hz 下 `4 / 60 ≈ 66.7ms` 的兼容阈值。本轮保持以下语义不变：

- 首次捕获/发生实质位移：清空 stable 起点，进入 moving；
- 未发生实质位移：记录或沿用 stable 起点；
- 连续稳定达到既定时间阈值后进入 stable；
- 既有测试继续覆盖 60、120 和不规则节拍。

实际状态以时长为准，日志只记录非敏感 cadence/state，不记录窗口身份或坐标。

## Bubble visibility scheduling

`BubbleVisibilityProbe` 保留 generation、knownWids、single-flight 和保守 unavailable 分类。0.1 秒 cadence 不变：

- 当前候选包含 visible/未分类气泡：下一次 probe 最迟 0.1 秒可启动；
- 捕获在途：新请求直接合并；
- 分类结果变化：只触发一次 `wakeNow`；
- 候选消失：同一枚举 tick 内 knownWids 立即生效并布局；
- TCC false/capture unavailable：不声称收起已识别。
- 仅“当前 generation 已成功观察过的 WID 后续从成功 SCK 清单缺失”可转 hidden 并唤醒布局。

Probe 的 `lastCapture` 与 pending retry 保存为单调 instant。若完整布局在 cadence 尚差少量时间时到达，probe 暴露绝对单调 due instant；scheduler 在 tick 完成后用同一时钟动态计算剩余等待，已跨 due 时只保留一次立即 follow-up。

同 WID、同几何但内容在 capture in-flight 期间变化时，没有公开的无权限事件可使旧截图自动失效；本轮依靠 single-flight 后的 0.1 秒再探测限制额外等待。若真机仍证明该长尾不可接受，持续 `SCStream` 属于需要重新规划的下一阶段，不在本轮暗中扩张。

## Compatibility and privacy

- macOS 13：Timer fallback；BubbleVisibility 继续无法像素捕获时保守避让。
- macOS 14+：公开 AppKit CADisplayLink + 现有 ScreenCaptureKit。
- 所有 NSPanel 操作在主线程；后台探测只提交无参数失效通知。
- 不保存或输出 alpha 统计、截图、真实窗口标识、坐标或内容。

## Fourth break-loop evidence contract

第二轮正式 Review 对 `24b9732` 的产品静态结论为 P0=0/P1=0，但发现两个测试没有穿过其声称覆盖的生产边界。新 campaign 以该 SHA 为产品基线，先补证据，不预设生产代码必须变化。

墙钟独立性不再用未被 SUT 读取的局部变量模拟。cadence 的生产契约是“只接受单调时钟”，因此证据由两部分组成：现有可注入单调时间线继续覆盖 phase/off-grid/overrun/retry；新增可执行 source/API guard 直接扫描负责 cadence 的生产文件并在出现墙钟 API 时失败。不得为了让测试有 wall provider 而向生产 scheduler/probe 携带无业务用途的第二时钟。

`targetMissing` 集成测试必须从 typed capturer 结果开始，经 `BubbleVisibilityProbe.onVisibilityChange`、`FollowTickScheduler.visibilityChangeCallback`、coalesced main tick 和 `FollowLayoutPass`，最终调用一个未展示的真实 `DockPanel.placeBelow` 并断言其 `frame`。测试还要证明 stable one-shot 被提前失效、只产生一次 follow-up tick，重复 `targetMissing` 不积累 wake。现有 helper-only fixture 保留用于分类邻接态，但不再承担 AC2b 的端到端证明。

如果这两个测试在 `24b9732` 上直接通过，则下一候选仅包含测试、task/spec 和必要事实文档；如果真实红测暴露生产接线错误，才做该边界内的最小修复。任何需要启动 App、修改 TCC 或引入新时钟框架的方案都重新回到规划。

## Rollout and rollback

`24b9732` 的最终 Review 结论为 P0=0/P1=0/P2=2，问题均为证据没有穿过生产边界，QA 未启动且旧结论不可复用。用户最新指定本任务后续子 Agent 统一使用全新 `zhipu/glm-5.3 + max`；实施前仍须预检实际模型与 worktree，失败即停派、不换模型。若基线证据暴露范围外根因，或需要预测/持续 SCStream，必须再次回到规划。
