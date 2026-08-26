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
| A5 bounded chunked parsing | Fixture files larger than one parser line, including an unfinished tail and appended tail | `parseFile` opens a handle, seeks to cursor, reads at most `parseChunkSize`, assembles complete newline-delimited lines, and consumes only through the final newline | Parser result/cursor and memory behavior; the only whole-file `Data(contentsOf:)` is the separately bounded cache reader (`<= 1 MiB` after type/mode/size guards), not rollout parsing | `T3d*`, `T3e*`, `T3f`, `T3g`; production code in `Sources/PetDock/Data/TokenUsageLogReader.swift`; zero-warning build |
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

### 本轮 stable 渐进退避 AC 与证据（方案 B，用户已批准）

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
- UI: 407 passed / 0 failed. Data: 137 passed / 0 failed. Shell: 99 passed / 0 failed.
