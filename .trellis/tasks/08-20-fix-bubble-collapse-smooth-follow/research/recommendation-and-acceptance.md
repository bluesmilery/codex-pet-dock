# Research: 最小推荐设计、TDD 切点与验收矩阵

- Query: 基于气泡链路和显示节拍比较，给出最小可落地设计、测试切点、候选改动文件及自动/静态/真机验收矩阵；特别检查 variable refresh 下 stableCount 的语义。
- Scope: internal / mixed
- Date: 2026-08-20

## Findings

### 最小推荐设计（按风险分阶段）

#### 阶段 A：先修“收起后回位”的确定性路径

1. 把当前 `FollowTickWake.visibilityChangeCallback` + `schedule(after: 0)` 收拢成一个主线程 `FollowTickScheduler`（可以先放在 `FollowTickPlan.swift`，职责清晰后再独立文件）。后台只调用 `requestWake()`；主线程入口应：合并同一 run-loop turn 内的多次 wake、invalidate 当前 follow timer、直接执行一次完整 `tick()`（或使用一个带 generation 的 zero-delay task），再由 tick 末尾统一安排下一次 cadence。这样测试能证明的是“wake→真实 tick→layout”，而不是只证明 fake scheduler 被调了一次。
2. 保持“当前候选消失立即 hidden”“capture nil 保守 visible”的现有隐私/安全契约。不要把所有 nil 改成 hidden。对 `preflight`/capture permission 状态导致的缓存从 hidden 变为默认 visible，若产品希望避免底座暂时重叠，增加明确的 `layoutInvalidated` 通知；若保持保守避让，则不发 wake 也可，但必须在验收中声明这是安全优先行为。
3. 给 in-flight 结果增加候选版本（至少是 WID + 几何 fingerprint/候选 generation），或在当前 tick 的候选几何变化时使旧任务失效，避免“同一 WID 仍在集合但捕获的是旧 bounds/旧内容”的 stale visible 写回。只保存匿名状态，不保存 WID/PID/坐标日志。
4. 对真实 collapse 的闭环测量只使用内存计时/计数：从 `probe` due、capture 完成、分类变化、wake 入主线程、`placeBelow` 成功到基础 frame 的阶段耗时；禁止持久化图像、颜色、文字、真实窗口身份。

#### 阶段 B：提高移动跟随的节拍

1. 增加可注入 `FollowTickSource`/`FollowTickScheduler`：
   - macOS 14+ 对当前 dock `NSWindow` 创建 AppKit `displayLink(target:selector:)`，moving 时启用，主线程 callback 只允许执行/请求一个 latest-only tick；窗口隐藏或不在 display 时停止/依赖 fallback。
   - macOS 13 fallback 使用 repeating `Timer`，首选 1/120 秒作为实验上限但只在 moving 运行，`.common` mode、tolerance=0、callback 不补发 missed ticks。若实测 CGWindowList 长尾导致主线程预算超标，fallback 可降到 60Hz；频率不是硬编码的用户承诺。
   - stable/hidden 保持低频 Timer，避免 display link 空转；visibility wake 走同一个 scheduler coalescer。
2. 不用 `CVDisplayLink`（当前 SDK 从 macOS 15 起弃用且会触发 warning），不使用 `NSWindow.animator()`/隐式动画连续追赶外部窗口。
3. 只有在显示链路稳定、真机拖拽仍有采样跳变时，再增加纯函数插值：以上一份/最新 `WinCandidate` 快照及 display timestamp 计算位置，限制快照年龄和最大 extrapolation；只覆盖 latest，禁止动画队列。第一阶段不要同时改变气泡 classifier、几何障碍规则和插值，便于定位回归。

#### 阶段 C：修正稳定判定语义

将 `stableCount` 从“样本次数”改为时间量（如 `stableElapsed`/`lastMaterialChangeAt`），或让 `Follower.decide` 接收 `elapsed` 并基于固定 stationary window 判定 stable。这样 60Hz、120Hz、VRR 或 Timer 延迟不会改变“多久算静止”的产品语义。保留日志里的计数仅作诊断时，必须明确它已不是稳定阈值本身。

### TDD 测试切点

#### BubbleVisibility / layout invalidation

- same-WID、缓存 visible、fake capturer 返回 close stats：断言 `cached=hidden`、只通知一次；随后 fake full tick 重新读取 visibility 并回到基础 frame。
- same-WID、fake capturer 返回 nil 或滞回中间 stats：断言仍 visible 且不发“回位”通知，防止破坏保守避让。
- 候选消失（空候选/换候选）立即使旧 visibility hidden；in-flight 完成不能复活旧障碍。
- same-WID 几何 fingerprint 变化或内容变化期间旧 in-flight 完成：断言旧结果被丢弃/标记 stale，下一 probe 能重新捕获。
- `canCapture` 从 true→false、hidden cache 被清除的策略（发 wake 或保守不发）必须用 fake provider 明确测试，不留隐含语义。

#### Scheduler / full tick

- fake Timer/RunLoop source：wake 在普通 timer 到期前到达、到期后到达、连续多次到达三种顺序；断言最多一次 pending tick、不会丢掉一次 cache-change layout、不会堆积历史 ticks。
- scheduler callback 标记 `Thread.isMainThread`，并让 fake full tick 走 `PetTracker`→`obstaclesNear`→`BubbleVisibilityProbe.visibility`→`Geometry.safeDockFrame`→`DockPanel` fake sink；不要只测 scheduler counter。
- hidden/stable/moving 状态切换时 source start/stop 只发生一次；退出/宠物消失时旧 display/timer callback 不再触碰 UI。

#### Follow cadence / VRR

- 纯函数用固定 monotonic timestamps 测 `Follower`: stationary window 在 60/120/30 的回调序列下都保持相同 elapsed 语义；移动后立即回 moving，首帧仍 setFrame。
- fake display source：可注入 60Hz、120Hz、可变 delta、长 tick；断言 latest-only（没有 frame backlog）和每次 frame callback 不重复历史位置。
- fallback Timer：验证 `.common` mode、timer invalidation、missed fire 只执行一次下一 tick、无 one-shot drift；不要在测试中依赖实际睡眠。
- 可选 `interpolateFrame` 纯函数测试：正常区间、停住、跨屏/大跳变、过期样本都不 overshoot；若第一阶段不实现插值，记录为未覆盖而不是伪造通过。

### 可能修改文件（最小边界）

- `Sources/PetDock/FollowTickPlan.swift`：wake/scheduler/coalescing 纯状态机或协议；若 display link adapter 独立，新增明确职责文件并同步 `Makefile:test-ui` 源文件列表。
- `Sources/PetDock/main.swift`：持有 scheduler/display link、启动/停止 cadence、让 wake 走 full tick；保持所有 panel 操作主线程。
- `Sources/PetDock/Follower.swift`：moving cadence 与 elapsed stable contract；不要在此文件引入 AppKit。
- `Sources/PetDock/BubbleVisibility.swift`：候选版本/stale in-flight 或 layout invalidation 状态；保持 alpha-only 内存计算。
- `Sources/PetDock/DockPanel.swift`：可选 last-applied-frame 去重；不要缓存避让偏移，仍以当前几何重算。
- `tests/main.swift`：UI 纯函数、probe fake、scheduler fake、elapsed/VRR 测试。
- `docs/architecture/dock-obstacle-avoidance.md`、`docs/verification/dev-candidate.md`、README（若公开 cadence/回位保证变化）：记录新的“捕获等待 vs wake 重排”边界和真机证据。`Docs Impact` 应为 `update`，不是 `none`。

### 自动 / 静态 / 真机验收矩阵

| 类别 | 必验项目 | 证据口径 |
| --- | --- | --- |
| 自动 | `swift build -c release` 0 warning；`make docs-check`、`make test-docs`、`make test` 全绿；scheduler/probe/follower elapsed fake tests；`git diff --check` | 命令退出码、实际 PASS 计数；不含真实窗口身份、图像或会话正文 |
| 静态 | macOS 13 availability 分支；macOS 14 AppKit displayLink symbol；无 CVDisplayLink deprecation warning；所有 `setFrame` 在 main；latest-only/no backlog；privacy scan | 源码/SDK header 证据，不能称真实 display callback 已运行 |
| 真机 macOS 14+ | TCC 已授权；同一真实气泡展开→收起→再次展开；capture success/nil/中间统计；收起后 latency 分段；拖动中 60/120/VRR；事件跟踪/菜单/详情展开；CPU 与主线程长尾 | 必须运行精确候选 `.app`；未执行即标为未验证；不记录 WID/PID/坐标/内容 |
| 真机 macOS 13 | 无 displayLink 时 fallback Timer；TCC/SC 不可用仍保守避让；宠物隐藏/重现；拖动与多屏负坐标 | 逐项记录 OS、显示器刷新能力和结果；不可用纯编译替代 |
| 真机多屏/权限边界 | 宠物跨屏、显示器移除/VRR、屏幕录制拒绝/中途变化、capture window 暂缺；底座不重叠且失败安全 | 观察结果与未验证项分开；避免权限/会话内容进入日志 |

### 成功判定与回滚边界

- “分类变化后零延迟唤醒”验收必须拆成：收起→下一次有效 capture 的时间、classification→main callback、main callback→基础 frame 的时间。只有最后一段可称 zero-delay wake。
- 若 display link 引入新 warning、macOS 13 fallback 不稳定或主线程扫描超过帧预算，先保留 scheduler/wake 修复，回滚 display link 适配，不回滚气泡安全契约。
- 若第二轮正式 Review 仍有实质 finding，按项目 Trellis 规则执行 break-loop，不继续叠加 120Hz/插值等 speculative 改动。

## Code patterns

- `Sources/PetDock/main.swift:179-186` — 当前 one-shot Timer 入口，适合替换为可注入 source。
- `Sources/PetDock/main.swift:210-295` — full tick 的唯一布局编排边界。
- `Sources/PetDock/FollowTickPlan.swift:3-10` — 现有 wake bridge 的最小替换点。
- `Sources/PetDock/Follower.swift:25-61` — cadence 与 material-change 纯函数，适合 elapsed 参数化。
- `Sources/PetDock/BubbleVisibility.swift:114-175` — probe 结果提交/通知，适合 stale token 与 invalidation。
- `Sources/PetDock/DockPanel.swift:67-79` — frame 写回，可做 last-frame 去重但不能保留旧 offset。
- `tests/main.swift:785-888` — 已有 bridge/transition/stale fake 切点。

## External references

- Apple [`Timer`](https://developer.apple.com/documentation/foundation/timer)：repeating fire date 不漂移、RunLoop 忙时可能迟到且跳过错过 firing。
- Apple [`CADisplayLink`](https://developer.apple.com/documentation/quartzcore/cadisplaylink)：display-synchronized callback、timestamp/targetTimestamp、invalidate。
- Apple [`NSWindow.displayLink(target:selector:)`](https://developer.apple.com/documentation/appkit/nswindow/displaylink%28target%3Aselector%3A%29)、[macOS 14 AppKit release notes](https://developer.apple.com/documentation/macos-release-notes/appkit-release-notes-for-macos-14)：AppKit display link availability/跨屏跟踪。
- Apple [`CVDisplayLink`](https://developer.apple.com/documentation/corevideo/cvdisplaylink-k0k)：高优先级线程及弃用替代关系。
- Apple [`kAXWindowMovedNotification`](https://developer.apple.com/documentation/applicationservices/kaxwindowmovednotification)：事件在移动结束时通知，不能当连续采样。

## Related specs

- `.trellis/spec/macos/appkit-conventions.md` — 主线程 UI、Timer completion、AppKit 坐标。
- `.trellis/spec/macos/quality-guidelines.md` — 0 warning、TDD、真机边界、Docs Impact。
- `.trellis/spec/macos/privacy-guidelines.md` — BubbleVisibility 内存 alpha 隐私、不得记录真实身份/内容。
- `docs/architecture/dock-obstacle-avoidance.md`、`docs/verification/dev-candidate.md` — 产品障碍契约与自动/真机验收事实源。

## Caveats / Not Found

- 以上是源码/SDK/文档推导；没有在真实 `.app` 上测量 collapse latency、display callback cadence、CPU 或拖拽体感。
- `stableElapsed` 的具体 stationary window（毫秒）尚未由产品确认；实现前应保持现有体感目标并用回归测试锁定，而不是从 tick 数字直接推断。
- 未建议新增 Accessibility 权限或读取目标应用会话内容；AX 仅作为被否决的可选 wake hint。
