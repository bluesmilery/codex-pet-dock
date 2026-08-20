# Research: 气泡收起调度链路

- Query: 审查 expanded→collapsed 的窗口候选、分类、异步捕获、通知、主线程调度和完整布局路径，解释零延迟唤醒后仍可能不立即回位的原因。
- Scope: mixed（仓库源码、测试、项目文档；Apple SDK 头文件/API 交叉核对）
- Date: 2026-08-20

## Findings

### 完整链路（当前实现）

1. `AppDelegate.tick()` 在主线程调用 `PetTracker.unionCandidates()`，用同一份 `CGWindowList` 快照选择宠物，再按 `obstaclesNear` 的 owner/layer/alpha/几何规则筛选障碍（`Sources/PetDock/main.swift:210-214`, `Sources/PetDock/main.swift:242-258`, `Sources/PetDock/PetTracker.swift:220-255`）。
2. `obstacleKind` 只做纯几何分类；bubble 候选送入 `BubbleVisibilityProbe.probe`，control 候选直接视为占位（`Sources/PetDock/main.swift:254-263`, `Sources/PetDock/PetTracker.swift:258-287`）。
3. `probe` 每次先同步覆盖 `knownWids`，之后受 `minInterval = 0.5s`、`inFlight` 和 `CGPreflightScreenCaptureAccess()` 门控；捕获在 `Task.detached` 中逐候选串行执行，结果再经 generation 校验写回（`Sources/PetDock/BubbleVisibility.swift:69-73`, `Sources/PetDock/BubbleVisibility.swift:114-175`）。
4. 分类函数对达到 close 阈值的 alpha 统计返回 `.hidden`，open 阈值返回 `.visible`，中间区间沿用 previous；`nil`（macOS 13、TCC 尚未生效、SC 窗口缺失或捕获失败）固定返回 `.visible`（`Sources/PetDock/BubbleVisibility.swift:36-52`）。
5. 只有缓存值确实变化且 WID 仍在 `knownWids` 时才触发 `onVisibilityChange`（`Sources/PetDock/BubbleVisibility.swift:165-175`）。生产回调把通知异步投递到主线程，再调用 `schedule(after: 0)`（`Sources/PetDock/FollowTickPlan.swift:3-10`, `Sources/PetDock/main.swift:48-51`）。
6. 下一次完整 tick 会重新枚举、重新分类、重读 probe 缓存，并将当前可见障碍传给 `DockPanel.placeBelow`；`safeDockFrame` 每次从 `pet.maxY + gap` 重新算 y，因此不应复用上一次的下移量（`Sources/PetDock/main.swift:260-294`, `Sources/PetDock/Geometry.swift:56-103`, `Sources/PetDock/DockPanel.swift:62-79`）。

### 已证实的延迟/缺口（不依赖真机）

- “零延迟”只覆盖捕获任务已经返回 `.hidden` 之后的主线程重排；它不覆盖收起到下一次 `probe` 的等待。当前 probe 最长每 0.5 秒才启动一次，并且同一批候选在一个 detached task 中串行捕获，`SCShareableContent`/截图耗时还会叠加（`BubbleVisibility.swift:73`, `BubbleVisibility.swift:144-175`, `BubbleVisibility.swift:209-219`）。因此同一 WID 仍被 `obstaclesNear` 保留时，收起后至少可能等待下一个 probe，且可能被前面候选阻塞。
- `nil` 和滞回中间区间不会产生 hidden 变化：`nil` 强制 visible；中间统计沿用 previous。真实收起如果保留阴影/抗锯齿 alpha 落在中间区间，或 SC 窗口暂时不可见，缓存不会降为 hidden，也就没有通知（`BubbleVisibility.swift:36-52`）。这符合当前“失败保守避让”契约，但会表现为底座不回位。
- 候选从 `obstaclesNear` 消失时，`knownWids` 在当前 tick 已同步失效，`visibility(for:)` 立即返回 hidden；同一 tick 的布局会使用空障碍并回到基础 frame。这条路径不依赖 capture nil，也不需要 wake（`BubbleVisibility.swift:114-142`, `BubbleVisibility.swift:179-186`, `main.swift:252-266`）。
- `probe` 的 generation 只在候选集合/`reset` 等路径变化时失效；同一 WID 的旧几何或旧屏幕内容在异步任务结束前变化，不会使 in-flight 结果失效。旧截图可能在收起之后才写回 visible，之后要等下一次 due probe 才能纠正（`BubbleVisibility.swift:80-85`, `BubbleVisibility.swift:164-174`）。这是可由注入的慢 capturer + 同 WID 内容变化复现的时序缺口，真实窗口是否命中需真机确认。
- 当 preflight 从可用变为不可用时，`probe` 会清缓存并使当前候选默认 visible，但该分支没有调用 `onVisibilityChange`；如果此前缓存是 hidden，底座可能保持基础位置直到下一次普通 follow tick。该行为可由 `canCapture` 注入序列复现；生产是否会发生 TCC 中途变化需真机确认（`BubbleVisibility.swift:121-142`）。

### 调度审查结论：什么已证实，什么尚未证实

- 已证实测试只覆盖“桥接回调在主线程调用 scheduler(0)”以及“纯几何重新计算”，没有调用真实 `AppDelegate.tick`、`Timer`、`DockPanel.placeBelow` 的完整生产对象链。`T-bv38d`/`T-bv39c` 只观察 fake scheduler 的计数和线程，`T-bv39d` 直接调用 `Geometry.safeDockFrame`；这不足以证明真实 `.app` 的 run-loop 排序与 panel frame 回写（`tests/main.swift:785-860`）。
- 当前 bridge 复用一个 `DispatchWorkItem`，重复提交本身不会只执行一次（已用独立 Dispatch 试验确认）；因此“第一次通知后 work item 永久失效”不是根因。真正可见的调度成本是每次通知都 `invalidate` 当前 one-shot Timer 并重新创建一个零间隔 Timer（`FollowTickPlan.swift:5-10`, `main.swift:179-186`）。它可能造成重复 tick/Timer churn，但在主线程串行语义下，若旧 timer 已开始执行，该 tick 自己仍会读取新缓存；若尚未执行则应被 invalidate。静态代码和现有测试未证明它会稳定丢失布局。
- `DispatchQueue.main.async` 在主线程被 event-tracking/modal callout 占用时，可能晚于预期；follow Timer 加入 `.common` mode，而 main queue block 是否及时服务没有同等保证。该差异是可复现的 run-loop 模式假设，但需要带真实拖拽/事件跟踪的 `.app` 才能判定对用户场景是否造成可见延迟（`main.swift:179-186`, `FollowTickPlan.swift:8-10`）。
- 因此，当前最强的“收起后不立即回位”解释是 capture 采样/分类阶段（2Hz、串行、nil/中间滞回、in-flight 旧结果），而不是已被测试证明的主线程 wake 失效。必须把“捕获成功后重排”与“从用户收起到成功 hidden”分开测量。

### 当前自动证据

- `swift build -c release` 在本机 SDK 下完成且无 warning。
- `make test-ui` 实际输出为 190 passed、0 failed；这些是纯函数/fixture 与 fake capturer 测试，不能替代 TCC、ScreenCaptureKit 或真实窗口验证。

## Code patterns

- `Sources/PetDock/BubbleVisibility.swift:114-175` — knownWids 同步事实、capture gate、single-flight、generation 和 change-only notification。
- `Sources/PetDock/BubbleVisibility.swift:179-186` — 当前候选之外立即 hidden；当前候选缺 cache 默认 visible。
- `Sources/PetDock/main.swift:210-295` — 完整主线程 tick、障碍合并、布局及下一次调度。
- `Sources/PetDock/FollowTickPlan.swift:3-10` — 后台通知到主线程的 wake bridge。
- `Sources/PetDock/Geometry.swift:66-103` — 从基础 y 重新计算的链式避让，不保存上帧偏移。
- `tests/main.swift:622-764` — 候选消失、旧 cache/in-flight、nil 保守语义回归。
- `tests/main.swift:785-888` — bridge/transition/stale generation 测试，但没有真实 AppDelegate/timer/panel 集成。

## External references

- 当前本机 SDK：`xcrun --sdk macosx --show-sdk-version` 输出 26.5；SwiftPM deployment target 为 macOS 13（`Package.swift:6`）。
- 当前 SDK `AppKit.framework` 头文件明确把 `NSWindow/NSView/NSScreen.displayLink(target:selector:)` 标为 `API_AVAILABLE(macos(14.0))`（`.../AppKit.framework/Versions/C/Headers/NSWindow.h:818-825`, `NSView.h:609-616`, `NSScreen.h:127-134`）。
- Apple 文档：[NSWindow.displayLink(target:selector:)](https://developer.apple.com/documentation/appkit/nswindow/displaylink%28target%3Aselector%3A%29) 说明 callback 与窗口所在显示器同步；[AppKit macOS 14 release notes](https://developer.apple.com/documentation/macos-release-notes/appkit-release-notes-for-macos-14) 说明 display link 会跟随 view/window 的显示器并在不在显示器时暂停。

## Related specs

- `.trellis/spec/macos/appkit-conventions.md` — 所有 `setFrame`/panel UI 必须在主线程；Timer/completion 回主线程。
- `.trellis/spec/macos/quality-guidelines.md` — TDD、0-warning release build、自动/静态/真机证据分离。
- `.trellis/spec/macos/privacy-guidelines.md` — BubbleVisibility 只能在内存计算 alpha，不保存图像、不 OCR、不记录颜色/文字。
- `docs/architecture/dock-obstacle-avoidance.md:32-46` — 当前气泡分类、2Hz、保守 nil 与 wake 契约。
- `docs/verification/dev-candidate.md:42-59` — 展开→收起、TCC、真实多屏和跟随体感均是独立真机项目。

## Caveats / Not Found

- 未运行真实候选 `.app`，未取得任何真实 WID/PID/坐标或会话内容；未验证当前用户报告的具体收起动作究竟是“候选消失”“same-WID capture 仍 visible”还是 `nil`/中间滞回。
- ScreenCaptureKit 真实捕获长尾、TCC 中途变化、事件跟踪 run-loop 排序、面板实际重排延迟均未在当前环境验证。
- 不应把 `make test-ui` 的 transition fake 结果写成真实气泡已回位。
