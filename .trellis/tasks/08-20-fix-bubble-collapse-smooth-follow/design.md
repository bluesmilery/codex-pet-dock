# Technical Design

## Scope and boundaries

本次只改 follow 调度、气泡探测节流/失效唤醒、Follower 稳定判定、对应测试与事实文档。现有窗口选择、几何放置、数据刷新、主题和权限请求策略保持不变。

## Root-cause model

### Bubble collapse

生产链为：follow tick 枚举候选 → `BubbleVisibilityProbe.probe` 受 0.5 秒最小间隔约束 → 后台 ScreenCaptureKit 捕获/分类 → cache 变化通知 → 主线程 `schedule(0)` → 新 tick 重新计算障碍与 frame。

上一版测试证明了“成功分类后的通知桥接”，但没有证明端到端延迟或真实调度器替换已有 timer 后执行完整 tick。用户可见延迟仍包含探测等待和捕获耗时；若 TCC/capture 失败则按契约一直保守 visible，不能承诺回位。

真机复测补充了一个与像素折叠不同的失败形态：完全隐藏会话 UI 后，底座继续跟随宠物但保持旧避让间距。这反证“调度器完全未 tick”是主因，更符合障碍仍被判定 visible。当前 `BubbleCapturer` 用一个可选 `BubbleAlphaStats?` 同时表达目标不在成功取得的 SCK 窗口清单、清单获取失败、截图失败和像素统计失败；`nil` 又统一按保守 visible 分类。最强假设是 CGWindowList 与 SCK 生命周期短暂不同步时，已消失目标被这个可选值契约保活。实现前必须用独立红测把该假设与几何筛选错误、scheduler/frame stale 区分开；若红测不能复现，停止并回到规划，不改 alpha 阈值。

本次保留 one-shot screenshot 架构和 0.1 秒 cadence。捕获边界改为带来源语义的结果：成功取得 SCK 窗口清单但目标 WID 不存在是 `.targetMissing`，可使当前同身份候选 hidden；权限/清单/截图/统计失败是 `.unavailable`，继续保守 visible；成功统计是 `.stats`，沿用现有 alpha 分类。异步结果仍受 generation、当前候选身份和 strict single-flight 约束。

## Follow scheduler

引入职责单一的 follow scheduler，区分三类输入：

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

现有 `DockPanel.placeBelow` 在每次完整 tick 中直接 `setFrame` 到最新目标，display link 只提高采样/写回频率，视觉仍是离散跳到采样点。新增一个主线程、纯时间驱动的短时线性段：保存当前渲染 frame、最新目标 frame、段起点和单调起止时间；每个 display beat 按 `lerp(start, target, progress)` 写回。目标更新时从当下已渲染位置重定向到最新目标，不排队历史目标；进度到 1 后精确 snap，禁止过冲。

插值上限由用户确认，推荐 32ms。隐藏/显示、跨屏失去有效 screen、几何返回 nil，以及气泡 hidden 后的安全复位可直接 snap，避免动画延迟正确避让。该方案不预测宠物位置，不使用隐式 AppKit animation，也不改变窗口枚举频率；代价是最多一个配置窗口的视觉拖尾，必须在真机拖动体感中单独验收。

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

Probe 的 `lastCapture` 与 pending retry 保存为单调 instant。若完整布局在 cadence 尚差少量时间时到达，probe 暴露绝对单调 due instant；scheduler 在 tick 完成后用同一时钟动态计算剩余等待，已跨 due 时只保留一次立即 follow-up。

同 WID、同几何但内容在 capture in-flight 期间变化时，没有公开的无权限事件可使旧截图自动失效；本轮依靠 single-flight 后的 0.1 秒再探测限制额外等待。若真机仍证明该长尾不可接受，持续 `SCStream` 属于需要重新规划的下一阶段，不在本轮暗中扩张。

## Compatibility and privacy

- macOS 13：Timer fallback；BubbleVisibility 继续无法像素捕获时保守避让。
- macOS 14+：公开 AppKit CADisplayLink + 现有 ScreenCaptureKit。
- 所有 NSPanel 操作在主线程；后台探测只提交无参数失效通知。
- 不保存或输出 alpha 统计、截图、真实窗口标识、坐标或内容。

## Rollout and rollback

精确候选 `d8538a5` 的自动 Review/QA 结论因真机回归失效，不可复用。第三次 break-loop 后的新候选必须使用全新 `kimi/k3 + max` 实现、Review 和 QA 子 Agent；当前 provider 不可用时保持停派，不换模型。若 typed capture 红测不能证明根因，或插值需要预测/持续 SCStream，必须再次回到规划。
