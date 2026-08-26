# AC Evidence Topology — 08-26-perf-startup-idle-cpu

## Provenance

- Approved baseline: `a7639db` (clean baseline; no implementation files changed).
- Approved planning commit: `9e7b68a`.
- First implementation candidate: `b85f11051527e823ae754d80403b9b448444e26f`.
- Review-fix round: frozen as `8dc8f48` (delta below, on top of `b85f110`).
- Review-fix delta:
  - `TokenUsageLogReader` rejects a short incremental/full read and, after a
    failed fallback parse, leaves the previous cache entry unchanged instead of
    persisting a metadata size observed before concurrent truncation.
  - Added deterministic short-read fixture injection, the `size >= parsedBytes`
    shrink case, and the fixed-identity scheduler one-shot test.
  - Updated the three bubble-probe cadence contracts in user/architecture docs.
- Moving-watchdog round (review r2 P0 drag-freeze): frozen as `58e2ce3`. That
  round also cleared two review P2s: the missing P0 drag-freeze section below
  and the `lifecycleScheduler.stop()` indentation noise in `tests/main.swift`.
- Stable-backoff round (approved plan B): frozen as `b51ab9e`. It introduced
  the stationary backoff with a 0.5s floor, which came from a spec typo in the
  supervisor task brief (the user-approved floor is 0.2s); review r3 returned
  NOT APPROVED for that reason.
- Review-fix round r3 (this work tree, on top of `b51ab9e`, not yet frozen):
  corrects the floor to the user-approved 0.2s (F24-F26, T-sch6b, comments and
  docs), reroutes T-sch6c through the production `Follower.decide`
  material-change path, and syncs this evidence file. Conclusions below apply
  only to the tree frozen from this round.
- r3 was frozen as `f66ba58`. R6 round (this work tree, on top of `f66ba58`,
  not yet frozen): per the user's field feedback the 0.2s stable-backoff floor
  is withdrawn (constant 0.1s again) and window enumeration switches to
  `.optionOnScreenOnly`; see the R6 section below. Conclusions in the
  stable-backoff section above are superseded by R6.
- R6-QA fix round (same work tree, on top of the R6 changes, not yet frozen):
  startup 100% CPU regression traced to the 1 MiB cache-size gate rejecting a
  legitimately grown v3 cache; see the R6-QA section below.

## Baseline and gates

| Evidence | Command / source | Result |
| --- | --- | --- |
| Approved baseline full gate | Supervisor rerun before review fixes | `make test` green: UI 392 / Data 135 / Shell 99; `swift build -c release` exit 0 with 0 warnings |
| P1 red test | `make test-data` before the short-read guard, with deterministic fixture injection | `T3g` FAIL: `points=[100, 100]`, cached size `245`, `inc=1`, `opens=2` |
| P1 green test | `CLANG_MODULE_CACHE_PATH=/tmp/petdock-clang-module-cache make test-data` after the fix | `T3g` PASS: `points=[]`, cached size `121`, `full=2`, `inc=0`, `opens=3`; Data suite 137 passed / 0 failed |
| Release gate | `swift build -c release` on the final work tree | See “Final gate result” below |
| Full gate | `make test PYTHON=<conda-base-python>` on the final work tree | See “Final gate result” below |

All source, tests, fixture constructors, and fake clocks referenced below are
read from this work tree. No conclusion depends on chat history.

## Evidence topology

| Symptom / AC | Trigger / disturbance | Production consumer / callback-scheduler chain | Final owner / assertion | Evidence |
| --- | --- | --- | --- | --- |
| A1 unchanged file does no parse | Two reads of the same real fixture files, with the v3 cache round-tripped through disk | `TokenUsageLogReader.readPoints` → file metadata/cache lookup → `TokenWindow` | Returned `TokenWindow` still totals 710 and `debugFilesParsed == 0` on the second reader instance | `T3a`, `T3b`, `T3c`; `make test-data` |
| A2 append-only tail parsing | Real `.jsonl`: write complete line + incomplete prefix → append suffix completing that line plus another complete line → refresh again | `readPoints` → cache miss/full parser → next refresh enters `parseFile(startingAt: parsedBytes)` → line assembler → `parseLine` → v3 `memCache`/private cache | Points are exactly `[100, 200, 300]`; full-parse count remains 1 while incremental count becomes 1 | `T3d1`, `T3d2`; `make test-data` |
| A3 shrink rollback (both required cases) | Case 1: shrink below `parsedBytes`; Case 2: new size is `< hit.size` but `>= parsedBytes` | `readPoints` observes metadata size → incremental eligibility fails → `parseFile(startingAt: 0)` → replaces cache entry/cursor | Case 1 returns no complete point, full parse advances and resets the cursor; Case 2 returns the retained complete `[100]` point without an incremental round | `T3e`, new `T3e0`; `make test-data` |
| A4 v2 → v3 migration | Decode a legacy v2 cache entry (`size` + `points`, no `parsedBytes`) over a real file, then append and refresh | Cache decoder defaults cursor to 0 → first refresh calls production full parser → v3 cache → append refresh uses cursor parser | First read `[100]` with one full parse; second read `[100, 200]` with one incremental parse and no second full parse | `T3f`; `make test-data` |
| A5 bounded chunked parsing | Fixture files larger than one parser line, including an unfinished tail and appended tail | `parseFile` opens a handle, seeks to cursor, reads at most `parseChunkSize`, assembles complete newline-delimited lines, and consumes only through the final newline | Parser result/cursor and memory behavior; the only whole-file `Data(contentsOf:)` is the separately bounded cache reader (`<= 8 MiB` since the R6-QA cap fix, after type/mode/size guards), not rollout parsing | `T3d*`, `T3e*`, `T3f`, `T3g`, `T3h`, `T3i`; production code in `Sources/PetDock/Data/TokenUsageLogReader.swift`; zero-warning build |
| A6 privacy boundary unchanged | Fixture lines include unrelated numeric/body bait; cache key/path and symlink/permission fixtures are exercised | `parseLine` reads only top-level timestamp and numeric token fields → cache encoder persists only opaque key, size/cursor, and token points → guarded private cache read/write | Token result omits the body bait; v1/pathful and invalid keys are dropped; symlink cache is not read; storage modes remain 0700/0600 contract | `T10`, `T-cache-privacy`, cache-key tests, `T-storage-privacy`; `make test-data` + `make test-privacy` |
| B1 stable 1.0-second heartbeat | Same WID and non-bounds identity for every probe; fake monotonic clock advances 0.5s then 1.0s from first capture | `BubbleVisibilityProbe.probe` → identity comparison → `identityDirty=false` cadence gate → optional background capture factory/capturer → generation-checked cache write | Factory/capture count stays at 1 after 0.5s and becomes 2 at 1.0s; gated tick records `pendingRetryAt == lastCaptureAt + 1.0` | `T-bv13a`, new `T-sch4g`; `make test-ui` |
| B2 identity change restores 0.1s path | Same WID changes non-bounds identity (title/alpha in fixture), first at 0.05s and again at 0.101s after prior capture | `probe` detects identity before cadence gate → sets `identityDirty=true`/invalidates generation → fast-path due check starts one capture | Calls remain 2 when gated at 0.05s and become 3 by 0.101s | `T-bv13b`; `make test-ui` |
| B3 one enumeration per round | One probe round receives two bubble candidates; injected factory returns one capturer used by both | `probe` → one `Task.detached` capture round → one `makeCapturer()` call → shared capturer/capture-stats lookup for each candidate | Factory count 1 and per-candidate capture count 2 for that round | `T-bv13c`; `make test-ui` |
| B4 old probe semantics retained | Existing fixtures mutate clock, WID sets, bounds, permissions, in-flight completion, outcomes, and visibility state | Production `probe`/completion lock → `onVisibilityChange` → `FollowTickScheduler` coalescer → `FollowLayoutPass` → real `DockPanel.placeBelow` | Reset, empty, strict single-flight, unavailable→visible, sticky drag cache, stale-generation rejection, wake coalescing, and final panel frame assertions remain green | `T-bv5*`, `T-bv6`–`T-bv16`, `T-bv38*`–`T-bv45*`, `T-sch4*`; `make test-ui` |
| C1 startup first-refresh delay | Pure plan inputs flip `petVisible`; static production wiring uses the resulting plan on `AppDelegate.tick` | First resume edge → `provider.resume()` → one-shot `dataTimer` at 5s → `refreshData()` → provider completion sets `hasCompletedFirstRefresh`; pause edge → `stopDataRefresh()`; later resume calls `refreshData()` immediately | Strategy returns 5 before and 0 after first completion; timer/provider state is the final scheduling owner; UI snapshot owner updates only after provider callback | `P10a`, `P10b`; production wiring in `Sources/PetDock/main.swift`; manual launch-log gap below |
| D quality gates | Build all production sources; run docs, privacy, UI, data, and shell suites | Swift compiler, executable test binaries, docs/privacy Python gates | Release output has zero warnings; every suite exits 0 and reports zero failures | `swift build -c release`; `make test PYTHON=<conda-base-python>` |

## P0 拖动冻结：根因链、修复映射与 stable 退避 AC

### P0 根因链与修复映射

- Root cause chain: since `f62bfd9` (coalesced display-synced dock updates),
  the moving state's only beat source is the window-bound `NSWindow.displayLink`
  (macOS 14+) with no fallback timer. After a screen sleep/wake the link dies
  silently — the panel stays visible, the system stops driving the callback,
  and the scheduler gets no reconfigure opportunity — so the only moving beat
  source starves and the dock freezes while dragging.
- Fix mapping: `58e2ce3` adds the 0.25s moving watchdog. A healthy display link
  re-arms it every beat and it never fires; if no tick arrives within the
  window, the scheduler degrades to a repeating Timer and latches the
  degradation for the rest of the moving episode (no create/invalidate churn).
- Evidence: `T-sch5a0`/`T-sch5a`/`T-sch5b`/`T-sch5b2`/`T-sch5c`/`T-sch5c2`/
  `T-sch5c3` — real `NSPanel` + real `CADisplayLink` + real runloop `Timer`;
  `orderOut` provides the deterministic silent-link reproduction.

### 本轮 stable 渐进退避 AC 与证据（方案 B，用户已批准；已被 R6 撤销）

Contract: stationary <1s keeps the 0.1s interval (identical to the previous
behavior, preserving "just stopped and moves again" sensitivity); stationary
>=1s backs off to a 0.2s floor (5Hz; worst-case start-detection delay 0.2s,
exactly the user-approved +0.1s over the status quo); any material change
still transitions to the moving cadence (display link / fallback path
unchanged).

| AC | Trigger / disturbance | Production consumer / chain | Final owner / assertion | Evidence |
| --- | --- | --- | --- | --- |
| S1 backoff pure mapping | Stationary durations 0.9s / 1.5s / boundary 1.0s | `Follower.stableProbeInterval` (pure function, same monotonic clock domain as `decide`) | 0.9s→0.1s; 1.5s→0.2s; boundary 1.0s→0.2s; 0.2s floor still probes faster than hidden 1.0s | `F24`, `F25`, `F26`; `make test-ui` |
| S2 scheduler wiring (real runloop Timer) | Production-shaped interval hint (stationary duration from the material-change timestamp → pure mapping) consumed by `FollowTickScheduler.scheduleStableTick` | one-shot `Timer` factory → coalescer → follow tick | Ticks stay ≈0.1s apart while stationary <1s; after ≥1s the actual tick gaps fall in [0.15, 0.3]s | `T-sch6a`, `T-sch6b`; `make test-ui` |
| S3 material-change recovery through the production decision chain | After backoff is active, a >tolerance pet-bounds disturbance is injected right after a stable tick and keeps drifting each tick (simulated drag) | `runTick` calls the real `Follower.decide` with test-held `stationaryAnchor`/`lastMaterialChangeAt` (same shape as the `main.swift` wiring) → `.moving` → scheduler moving source (display link / repeating fallback, unchanged) | The first moving tick lands within the 0.2s floor plus tolerance (asserted <=0.3s; breaking the floor back to 0.5s turns this assertion red), then moving beats return to the 60Hz fallback cadence with a repeating source active | `T-sch6c`; `make test-ui` |
| S4 probe retry hint still wins | `stableIntervalHint=0.2` coexists with a probe `pendingRetryAt` hint of 0.05s | `scheduleStableTick` keeps `min(deadline - now, retryAfter)` | The one-shot takes the earlier probe retry (0.05s), preserving the "take the earlier" contract | `T-sch6d`; `make test-ui` |

Production wiring (`Sources/PetDock/main.swift`, `followScheduler` initializer):
after the tick completes and `lastMaterialChangeAt` is updated, the hint derives
the current stationary duration on the same monotonic clock and applies the pure
mapping. Consumers without the hint (all pre-existing T-sch suites) keep the
0.1s semantics, which is why `T-sch1*`, `T-sch4*`, and `T-sch5c2` pass unchanged.

Expected stationary-CPU effect: once stationary ≥1s, the full `CGWindowList`
enumeration drops from 10Hz to 5Hz (a 0.2s floor). With bubbles present the probe
`pendingRetryAt` can still pull individual ticks earlier, and the 1s capture
heartbeat itself is unchanged. Real-machine stationary CPU sampling remains QA
work (headless suites cannot claim it).

## R6 撤销 stable 退避 + onscreenOnly 枚举瘦身（当前轮）

### R6 决策链（用户实测反馈驱动）

- 用户实测：0.2s 退避封底的最坏起步检测延迟（静止 ≥1s 后开始拖动，底座最长
  ~0.2s 才起跟）体验不可接受，要求回到 0.1s。
- 主管实测定位正解：`PetTracker.infosProvider` 用 `[]` 选项枚举全部 602 窗口
  （8.6ms），但 `selectPet` 内部 `filter(\.isOnscreen)`、`obstaclesNear` 前置
  `c.isOnscreen`，气泡探测又只消费 obstaclesNear 输出——offscreen 窗口全是
  白算；`.optionOnScreenOnly` 实测 1.26ms/56 窗口（约 7 倍便宜）。
- 结论：枚举变便宜后 0.2s 退避不再必要，直接撤销，回到恒定
  `Follower.stableInterval = 0.1s`；上一节的 S1–S4 契约整体作废。

### R6 AC 与证据映射

| AC | Trigger / disturbance | Production consumer / chain | Final owner / assertion | Evidence |
| --- | --- | --- | --- | --- |
| R6-A1 识别链不消费 offscreen | 全量形状 mock infos 混入 offscreen 宠物形窗口（kCGWindowIsOnscreen=false，经 infosProvider 注入） | `unionCandidates`（PID+ownerName 通道）→ `selectPet` → `filter(\.isOnscreen)` | offscreen 宠物形窗口不被选中（selected=nil）；该安全网在换选项前的基线运行即绿 | `T-enum5` |
| R6-A2 避让链不消费 offscreen | offscreen 气泡形窗口（宠物正下方、几何合规）+ 同形状 onscreen 阳性对照 | `unionCandidates` → `selectPet` → `obstaclesNear`（`c.isOnscreen` 前置）→ `bubbleProbe.probe`（只吃 obstaclesNear 输出） | offscreen 气泡不进障碍集；onscreen 同形状被纳入（证明排除确由 isOnscreen 前置造成，非几何巧合） | `T-enum5b` |
| R6-A3 onscreenOnly 形状解析 | 含 kCGWindowIsOnscreen=true 的全字段 dict | `enumerate(pids:from:)` → `parse` → `WinCandidate` | wid/ownerPID/ownerName/title/layer/alpha/isOnscreen/sharingState/bounds 全字段 round-trip 正确 | `T-enum6` |
| R6-B1 stable cadence 恒 0.1s | 真实 runloop Timer 连续采样跨过静止 1s 界（旧退避切换点两侧） | `FollowTickScheduler.scheduleStableTick` → one-shot Timer → coalescer → tick | tick gaps 恒 [0.05, 0.15]，无 <1s/≥1s 分层；F24-F26（退避映射）已删除 | `T-sch6a` |
| R6-B2 起步延迟回归护栏 | 静止 ≥1s 后注入宠物 bounds 扰动（模拟开始拖动，拖动期间逐拍持续位移） | 真实 `Follower.decide`（与 main.swift 同构的 anchor/changedAt wiring）→ `.moving` → scheduler repeating 源 | 扰动→首条 moving 拍 ≤0.15s 且 moving 拍回 60Hz fallback 节拍；stable 间隔再被拉长（如 0.2s 封底）时该断言红 | `T-sch6c` |
| R6-B3 probe retry 仍取更早 | probe pendingRetryAt hint 0.05s 与 stable 恒 0.1s 共存 | `scheduleStableTick` 的 `min(deadline - now, retryAfter)` | one-shot 取更早的 0.05s（min 语义保留） | `T-sch6d` |

### R6 涉及文件与 provenance

- 生产：`PetTracker.swift`（infosProvider 选项 + 两处注释）、`Follower.swift`
  （删除 stableBackoffThreshold / stableSettledInterval /
  stableProbeInterval(forStationaryDuration:)）、`FollowTickPlan.swift`（删除
  stableIntervalHint 参数与消费）、`main.swift`（删除 wiring）、`DockPanel.swift`
  （仅注释回 0.1s 口径）。
- 测试：`tests/main.swift` — T-enum5/5b/6 新增（安全网，基线即绿后才换生产
  选项）；F24-F26 删除；T-sch6 系列重写（sch6b 退避断言删除，sch6a/c/d 改恒
  0.1s 契约）；672 行注释同步。
- 文档：双语 README、`docs/architecture/dock-obstacle-avoidance.md`、
  `docs/verification/dev-candidate.md` 回恒 0.1s 口径并新增 onscreenOnly 说明。
- Provenance：用户延迟反馈（0.2s 不可接受）与枚举实测数字（8.6ms/602 →
  1.26ms/56）来自主管 2026-08-26 派发简报；语义安全网在换选项前的基线运行
  （本 worktree，UI 406 passed / 0 failed）先确认全绿，之后才切换生产枚举选项。

## R6-QA 启动 100% CPU 回归（token cache 尺寸门禁）

### QA 实测与根因链

- QA 实测（用户原始症状"启动 100% CPU"复发）：`token-cache.json` 实际
  1,345,292 字节，超过 `maxCacheBytes = 1_048_576`（旧值）；首刷全量重解析
  207 文件 / 613MB 日志约 28 秒，采样 window1-2 内每 10s 窗口约 10s CPU（单核
  打满），期间零 follow-tick 日志。
- 根因链：`readCacheData` 的 `size <= maxCacheBytes` 门禁把超限缓存整体拒绝
  → `memCache` 空 → 每次启动都全量重解析；且 `persist()` 写盘无大小检查，
  首刷后把 >1MiB 的缓存原样写回 → 文件持续超限 → 每次启动重演。
- 尺寸定性：v3 `points` 积累是**合法增长**——`readPoints` 开头的淘汰逻辑会把
  移出扫描窗口的文件条目整体删除，稳态尺寸受窗口跨度约束（实测 1.3MB；重负载
  估算 3-4MB）。旧 1MiB 上限把合法稳态当异常拒掉。

### 修复与 AC 映射

| AC | Trigger / disturbance | Production consumer / chain | Final owner / assertion | Evidence |
| --- | --- | --- | --- | --- |
| QA1 合法超 1MiB 缓存被接受 | 程序化生成 19,709 点的合法 v3 缓存（1,320,616 字节，size/parsedBytes 与磁盘文件一致，JSON 与生产编码同构）经 cacheURL 注入 | `readCacheData` 尺寸门禁 → init 解码 → `readPoints` size 命中 → 复用缓存 points | `debugFilesParsed == 0` 且 19,709 点全部从缓存进入 `TokenWindow` 输出（红：旧门禁下 parsed=1、points=1） | `T3h` |
| QA2 persist 超限跳过落盘 | 种子 8,319,101 字节（≤8MiB 门禁），磁盘文件追加 3,942 行触发 v3 增量 → 编码 8.58MB > 8MiB | `readPoints` 增量解析 → `persist()` 编码超限 guard → 跳过 `writeCache` | 磁盘字节保持种子不变（8,319,101 == 8,319,101）；进程内缓存继续命中（第二次 readPoints 同输出，parsed=0、inc=1）（红：旧实现把 264,300 字节重解析缓存写回） | `T3i` |

### 修复内容与 provenance

- `maxCacheBytes` 1_048_576 → 8_388_608：定位为防损坏护栏而非配额，注释说明
  合法增长有界的原因（窗口淘汰 + 实测 1.3MB / 重负载估算 3-4MB）。
- `persist()` 增加编码后超限跳过落盘的 guard，降级语义：进程内缓存继续工作，
  磁盘保留上一次合法写入，下次启动顶多一次全量解析，不再白写注定被拒的文件。
- 种子缓存由测试侧镜像 Codable（与生产 `CacheEntry`/`TokenUsagePoint` 同形状）
  + 默认 `JSONEncoder` 生成，保证磁盘格式与生产编解码一致；红→绿均在本
  worktree 实跑（红：`T3h`/`T3i` FAIL 2 条；绿：0 FAIL，节内 2 passed）。
- 尺寸/耗时数字（1,345,292 bytes、28s、~10s/10s 窗口、207 文件/613MB）来自主管
  2026-08-26 QA 简报；本修复轮未重采样真机 CPU（headless 无法覆盖，QA 复测项）。

## R9 SC 枚举 onScreenOnly 瘦身（当前轮）

### R9 研究数据（主管实测，实现轮仅复核代码链）

- 稳态 sample：`SCShareableContent.excludingDesktopWindows(false,
  onScreenWindowsOnly: false)` 每轮探测（稳定身份 1Hz）拉全量 610 窗口清单，
  XPC 回复解码 + 逐窗构建 SCWindow/SCRunningApplication 占稳态 CPU 6.2%（sample 246/3968，
  XPC 解码+SC 对象构建的合计采样口径；QA 稳态总采样 ~16% 其余来自 follow tick 与截屏本身）。
- 实测对比：全量 117.4ms/call / 610 窗；`onScreenWindowsOnly: true`
  29.5ms/call / 57 窗（约 4 倍便宜）。

### R9 语义安全论证（代码链复核）

- probe 候选唯一来源：`tick()` → `PetTracker.unionCandidates()`
  （`infosProvider` 自 R6 起 `CGWindowListCopyWindowInfo([.optionOnScreenOnly],
  ...)`）→ `selectPet` → `obstaclesNear`（前置 `c.isOnscreen` 且强制同
  owner）→ `bubbleProbe.probe`。候选必然在 CG onscreen 集内且 owner 与宿主一致。
- 主管实测：CG onscreen 59 窗中仅 1 个（Window Server/StatusIndicator，
  owner="Window Server"）不在 SC onscreenOnly 清单；它在 SC 全量清单里也不存在，
  且 owner 不可能是宿主（obstaclesNear 同 owner 前置），永远不会成为候选。
- `main.swift` 的全量 `CGWindowListCopyWindowInfo([], ...)` 仅存在于
  `--diagnose` 诊断模式（打印数量后退出），不进运行时候选链。
- wid 查不到时行为不变：`captureStats` 返回 `.targetMissing` →
  `BubbleVisibilityClassifier.classify`：同 generation 已成功观察 → hidden，
  从未观察 → 保守 visible。

### R9 改动

- `Sources/PetDock/BubbleVisibility.swift` `defaultMakeCapturer`：
  `onScreenWindowsOnly: false → true`；注释记录候选必在屏（上游 CG
  onscreenOnly）、实测数字（117.4ms/610 窗 vs 29.5ms/57 窗、sample 6.2%）与
  wid 缺失时的既有保守语义。

### R9 测试边界（诚实说明）

- headless 无法构造 `SCShareableContent`（真实 SC 系统服务对象），真实枚举
  行为不可测，不硬造 fake 宣称覆盖；`defaultMakeCapturer` 是系统集成点，
  rg 全库确认无测试断言其行为（仅源码定义与 init 引用），无需同步测试。
- wid 缺失路径由既有 T-bv 系列覆盖：T-bv5c（首次 targetMissing → 保守
  visible）、T-bv39f2/f3/f5a（targetMissing 生命周期与回基础位）、T-bv42a/c
  （targetMissing → callback → coalescer → 提前完整 tick → 实际 frame 复位）、
  T-re5c（runtime evidence 计数）。本轮测试计数不变（UI 406 / Data 139 /
  Shell 99）。
- 真机 QA 依赖项（同候选 SHA）：（a）气泡在场时 1Hz 稳定心跳探测正常，runtime
  evidence capture outcome 分布不劣化；（b）展开/收起/拖动/Composition Surface
  避让不回归；（c）稳态 CPU 采样确认 ~6.2% 的 SC 清单成分消失；（d）TCC 权限流
  不受影响（枚举失败仍走 unavailable 保守 visible）。

## Manual / device QA gaps

These cannot be truthfully claimed by the headless suites and remain for user
QA on the frozen candidate SHA:

- Warm-cache launch CPU sampling: launch-to-first-refresh must not sustain one
  core at 100%, and Activity Monitor samples should be recorded.
- Log timing: first `refreshData` completion/callback should occur at least 5
  seconds after the first pet-visible edge, with cancellation when the pet
  disappears during the delay.
- TCC and real ScreenCaptureKit pixels: permission flow, real capture outcomes,
  alpha-only processing, and no image/content persistence.
- Stable bubble cadence runtime evidence: with identity stable and bubbles
  present, capture rounds should be at most about 1Hz; identity change should
  immediately return to the 0.1s path.
- Drag feel, multi-screen coordinates, theme/status-bar behavior, and final
  dock/detail visuals.

## Final gate result

To be filled only from the final work-tree commands:

- `swift build -c release`: PASS, 0 warnings.
- `make test PYTHON=<conda-base-python>`: PASS.
- R6 round: UI 406 / Data 137 / Shell 99. R6-QA round (this tree): UI 406
  passed / 0 failed. Data: 139 passed / 0 failed（+2：T3h/T3i）。Shell: 99
  passed / 0 failed。全量日志 `FAIL` 计数 0；docs-check / test-docs /
  test-privacy 均随 `make test` 通过。
- R9 round (this tree, onScreenOnly 瘦身): `swift build -c release` PASS
  0 warnings；`make test PYTHON=<conda-base-python>` PASS：
  UI 406 passed / 0 failed，Data 139 passed / 0 failed，Shell 99 passed /
  0 failed，全量日志 `FAIL` 计数 0，docs-check / test-docs / test-privacy
  均随 `make test` 通过；计数与 R6-QA 基线一致（本轮不新增测试）。
