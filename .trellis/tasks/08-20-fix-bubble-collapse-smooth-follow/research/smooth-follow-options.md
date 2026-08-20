# Research: 跟随平滑度与显示节拍方案

- Query: 比较 120Hz Timer、无漂移 repeating Timer、macOS 14+ AppKit CADisplayLink（macOS 13 fallback）、CVDisplayLink、插值/动画和 Accessibility 事件；按本项目 macOS 13 target、主线程、CGWindowList 长尾、0 warning、CPU/隐私及可测试性评估。
- Scope: mixed（仓库实现、Apple SDK 26.5 头文件和官方文档）
- Date: 2026-08-20

## Findings

### 现状与瓶颈

- `Follower.movingInterval` 为 1/60 秒，`stableInterval` 为 0.1 秒；`AppDelegate.schedule` 每次 tick 都创建并安装一个 non-repeating Timer，因此下一次 fire date 以“本次 tick 完成后”为基准，CGWindowList 枚举、选择、障碍分类和 panel frame 写回的耗时会累积为节拍漂移（`Sources/PetDock/Follower.swift:25-53`, `Sources/PetDock/main.swift:179-186`, `Sources/PetDock/main.swift:210-294`）。
- 当前 tick 的 `unionCandidates()` 在主线程做一次全局窗口枚举；后续 `DockPanel.placeBelow` 每次都 `setFrame(..., display: true)`，即使 `Follower.decide` 返回 `shouldSetFrame == false`，调用方也没有使用这个信号来跳过写回（`Sources/PetDock/PetTracker.swift:220-233`, `Sources/PetDock/main.swift:242-270`, `Sources/PetDock/DockPanel.swift:67-79`）。因此盲目把 polling 改成 120Hz 会把主线程扫描和 AppKit frame 操作大致加倍，不保证真实显示更顺滑。
- 当前采样是“最新窗口矩形直接对齐”而非动画：目标在两次 CGWindowList 快照之间移动时，dock 只能跳到下一份快照；提高调用频率只能减少采样间隔，不能消除外部窗口更新/CGWindowList 长尾造成的抖动。

### 方案比较

| 方案 | macOS 13 / API | 优点 | 主要风险与结论 |
| --- | --- | --- | --- |
| 写死 120Hz one-shot Timer | 可用 | 改动极小，测试常量简单 | 仍有当前 one-shot 漂移；Timer 不是实时机制，主线程长调用会晚触发；双倍 CGWindowList 与 `setFrame` CPU/电量；120Hz 显示器、60Hz 显示器和 VRR 都被同一常量误配。只能作为短期实验或 macOS 13 fallback，不应作为最终节拍。 |
| 120Hz repeating `Timer`（`.common`，tolerance=0） | 可用 | Foundation repeating Timer 以原始 scheduled fire date 计算下一次 firing，跳过错过的 firing，不会像“每次重新 schedule”一样漂移；仍在主线程，易注入 fake scheduler | 仍非 vsync，callback 会在主线程忙时延迟/合并；高频 CGWindowList 长尾仍会丢帧；状态切换要 invalidate/重新安装，wake 与 repeating timer 竞态需 coalesce；VRR 不匹配。适合作为 macOS 13 fallback，但应只在 moving 状态运行、latest-only、不得排队补帧。 |
| macOS 14+ `NSWindow/NSView/NSScreen.displayLink`（`CADisplayLink`） | AppKit headers 为 `API_AVAILABLE(macos(14.0))`；macOS 13 必须 `if #available` fallback | Callback 与窗口/视图所在显示器同步；窗口跨屏时可自动跟踪显示器；系统 cadence 适配 60/120/VRR；callback 可读取 timestamp/targetTimestamp 做时间积分，显示链路更自然 | API 是 target/selector，需主线程对象或 proxy、防 retain cycle；display link 在窗口不在显示器/隐藏时不回调，hidden 状态仍需低频 Timer；macOS 13 代码必须有 availability 分支；真实 `CADisplayLink` 难以单测，需抽象 `DisplayTickSource`。这是 macOS 14+ 的首选高频驱动。 |
| `CVDisplayLink` | API 自 macOS 10.4；当前 SDK 标记 `API_DEPRECATED_BEGIN(..., macos(10.4, 15.0))` | 传统 display-vsync，callback 在 Core Video 高优先级线程 | callback 不在主线程，不能直接 `setFrame`/AppKit；需要原子 latest-only gate + main dispatch，容易积压；当前 Xcode/SDK 会产生弃用 warning，违反项目 release 0-warning 硬门禁；Apple 明确建议改用 AppKit displayLink。排除。 |
| 手写插值（display tick + 最新/前一份窗口快照） | 与驱动无关；可在 macOS 13 fallback 使用 | 在 120Hz/VRR 屏上让位置连续；纯函数可测；可以限制最大 extrapolation/样本年龄 | 外部窗口更新不是匀速；目标停下/跳转/跨屏时插值会 overshoot 或滞后；必须用 monotonic/display timestamp，且只保留 latest sample，不能积累动画队列。可作为第二阶段增强，不作为先修复气泡的必要条件。 |
| `NSAnimationContext`/`window.animator()` 隐式动画 | 可用 | 代码短，视觉上有过渡 | 每个 tick 产生一个动画，拖拽期间会排队/追赶旧目标；收起/候选消失要求立即回位，动画会与安全避让冲突；难测且可能扩大 AppKit work。不要用于连续跟随。 |
| Accessibility `AXObserver`/`kAXWindowMovedNotification` | 公开 API；额外 Accessibility 信任状态 | 事件可作为“开始/结束移动”的 wake hint，降低空闲 polling | `kAXWindowMovedNotification` 是窗口移动结束时的通知，不是每帧；Codex/Electron helper 是否暴露目标 AX 元素未知；需要 Accessibility 权限和 AX 错误降级，增加隐私/安装面；仍必须用 CGWindowList 校验几何。不能替代 display/timer 跟随，也不应为此任务新增权限。 |

### SDK 可用性证据

- `xcrun --sdk macosx --show-sdk-version` 为 26.5；`Package.swift:6` 仍将 deployment target 设为 macOS 13.0。
- 本机 SDK 的 `NSScreen.h:127-134`、`NSView.h:609-616`、`NSWindow.h:818-825` 均把 AppKit `displayLink(target:selector:)` 标为 macOS 14.0 可用，并说明 callback 与所在 display 同步。
- 本机 SDK 的 `NSScreen.h:96-124` 显示 `maximumFramesPerSecond`、`minimumRefreshInterval`、`maximumRefreshInterval`、`displayUpdateGranularity`、`lastDisplayUpdateTimestamp` 自 macOS 12.0 可用；这些值适合记录/决策，不能取代 display link。
- 本机 SDK `QuartzCore/CADisplayLink.h:19-21` 将 `CADisplayLink` 标为 macOS 14.0；`CoreVideo/CVDisplayLink.h:51` 开始的整段 API 标为 macOS 10.4→15.0 deprecated。

### 变量刷新率与稳定判定

现有 `stableThreshold = 4` 的含义是“4 次 tick”，不是时长（`Follower.swift:28-53`）。若移动 tick 变成 120Hz，稳定会在约半数时间内被判定；若 display link 因 VRR 在较慢 cadence 回调，稳定时间又会变长。必须把 stable 判定改为累计 monotonic/display elapsed（例如 `stableElapsed >= stationaryWindow`），或明确记录采样时间并保留产品期望的时长。不要在切换 cadence 后继续把 `stableCount` 当作固定毫秒数。

### 主线程与无积压约束

- 所有 `CGWindowList` 读取可以保持在主线程以最小化跨线程状态，但高频调用必须测量长尾；若未来移到后台，只能发布不可变、脱敏的最新 `WinCandidate` 快照，panel 写回仍回主线程，并在候选/PID generation 变化时丢弃旧快照。
- display/timer callback 只允许设置一个 `tickPending` 或覆盖一个 latest snapshot；前一 tick 未完成时不再排队下一 tick。错过的显示帧应跳过，不补发历史帧。
- `setFrame` 可先与上一次应用的目标 frame 做相等/像素容差比较，减少无变化写回；但布局必须仍在每个需要的 wake 中从当前障碍集合重算，不能缓存上一次避让偏移。

## Code patterns

- `Sources/PetDock/Follower.swift:25-53` — 当前 moving/stable/hidden cadence 与 tick-count stable semantics。
- `Sources/PetDock/main.swift:179-186` — one-shot Timer 重排，当前 drift/ wake 竞合位置。
- `Sources/PetDock/main.swift:210-294` — 主线程 CGWindowList、布局、show/hide 和下一 tick。
- `Sources/PetDock/DockPanel.swift:67-79` — 每次 placeBelow 都 `setFrame`，尚无 last-frame 去重。
- `Sources/PetDock/PetTracker.swift:220-233` — 每 tick 单次全局窗口枚举 + PID TTL cache。
- `Sources/PetDock/FollowTickPlan.swift:3-10` — 当前后台→main wake bridge，可作为调度抽象入口。
- `tests/main.swift:208-269` — Follower 目前仅断言 60Hz 常量和 tick-count，不覆盖 elapsed/VRR。
- `tests/main.swift:785-888` — bridge/visibility transition fake tests，可扩展为 scheduler coalescing 测试。

## External references

- Apple [`Timer`](https://developer.apple.com/documentation/foundation/timer) 文档：repeating Timer 以 scheduled fire date 为基准、跳过错过的 firing；Timer 不是 realtime，RunLoop 忙时会晚触发；tolerance 默认 0 但系统仍可能施加小 tolerance。
- Apple [`CADisplayLink`](https://developer.apple.com/documentation/quartzcore/cadisplaylink) 文档：以显示刷新同步，使用 `timestamp`/`targetTimestamp`/`duration` 做时间计算，需加到 RunLoop，结束时 `invalidate()`。
- Apple [`NSWindow.displayLink(target:selector:)`](https://developer.apple.com/documentation/appkit/nswindow/displaylink%28target%3Aselector%3A%29) 与 [macOS 14 AppKit release notes](https://developer.apple.com/documentation/macos-release-notes/appkit-release-notes-for-macos-14)：窗口 display link 与所在屏幕同步并随屏幕移动；不在 display 时不回调/自动暂停。
- Apple [`CVDisplayLink`](https://developer.apple.com/documentation/corevideo/cvdisplaylink-k0k)：Core Video link 使用高优先级线程；创建、callback、start/stop 等 API 已弃用，替代为 AppKit display link。
- Apple [`kAXWindowMovedNotification`](https://developer.apple.com/documentation/applicationservices/kaxwindowmovednotification)：窗口移动通知在移动操作结束时发送；[AXObserverCreate](https://developer.apple.com/documentation/applicationservices/1460133-axobservercreate) / AXUIElement 文档说明观察器和 Accessibility API 的信任/错误边界。

## Related specs

- `.trellis/spec/macos/index.md` — macOS 13+、AppKit 单体应用、ScreenCaptureKit 14+。
- `.trellis/spec/macos/appkit-conventions.md` — UI/frame 只能主线程；Timer completion 切回主线程。
- `.trellis/spec/macos/quality-guidelines.md` — release 0 warning、纯函数 TDD、自动/真机证据分离。
- `.trellis/spec/macos/privacy-guidelines.md` — 不使用私有 CGS/SPI；BubbleVisibility 不保存图像/文字；新增 Accessibility 权限需谨慎。
- `docs/verification/dev-candidate.md:42-59` — 拖拽、多屏、跟随体感、ScreenCaptureKit 都必须真机验证。

## Caveats / Not Found

- 本机只有 SDK 头文件/文档证据，没有在真实 60/120/VRR 屏、事件跟踪或目标 Electron 窗口上测量 callback cadence、CGWindowList 长尾或 CPU。
- 不应把 AppKit display link 的“同步回调”当成 CGWindowList 内容也按同一 cadence 更新；外部窗口快照仍可能滞后。
- Accessibility 目标是否暴露可观察的 window element、是否需要用户授权、事件是否覆盖宠物内部拖拽，均未在真实 Codex 环境确认。
