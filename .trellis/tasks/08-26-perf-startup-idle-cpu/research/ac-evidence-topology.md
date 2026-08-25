# AC Evidence Topology — 08-26-perf-startup-idle-cpu

## Provenance

- Approved baseline: `a7639db` (clean baseline; no implementation files changed).
- Approved planning commit: `9e7b68a`.
- First implementation candidate: `b85f11051527e823ae754d80403b9b448444e26f`.
- Review-fix round: work tree on top of `b85f110`, without a new commit (this
  implementation agent is forbidden from committing). The supervisor must freeze
  and review the resulting tree as a new complete SHA; conclusions below apply
  only to that frozen tree.
- Review-fix delta:
  - `TokenUsageLogReader` rejects a short incremental/full read and, after a
    failed fallback parse, leaves the previous cache entry unchanged instead of
    persisting a metadata size observed before concurrent truncation.
  - Added deterministic short-read fixture injection, the `size >= parsedBytes`
    shrink case, and the fixed-identity scheduler one-shot test.
  - Updated the three bubble-probe cadence contracts in user/architecture docs.

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
- UI: 393 passed / 0 failed. Data: 137 passed / 0 failed. Shell: 99 passed / 0 failed.
