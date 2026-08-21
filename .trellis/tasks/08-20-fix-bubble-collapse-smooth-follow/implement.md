# Implementation Plan

## Preconditions

- Product base: the committed HEAD of the current `replan_base_ref` recorded in `task.json`. Immediately before dispatch, the main Agent resolves that ref to a full immutable commit SHA, verifies the worktree is clean, and records the full SHA in the assignment/preflight prompt. The tracked plan does not embed its own self-referential commit hash.
- Delivery path: L2.
- Per the user's latest task-level override, implementation, formal code Review, repair recheck and automated gate QA use `zhipu/glm-5.3 + max`; visual/real-device QA that reads the screen and operates the candidate App uses `kimi/k3 + max`. Unavailable routing stops the corresponding dispatch without model downgrade. Each fresh role owns its required isolated branch/worktree and the main session does not edit product code.
- The controlling instructions for the current campaign are under **Seventh break-loop replan after v7 second Review**. Earlier Preconditions text, ordered-work, break-loop sections and Rollout descriptions are historical where incompatible; none overrides the seventh replan.
- Current product scope is compiler-enforced runtime-evidence sink wiring only: private initializer, fixed-sink production factory, compile-flagged test factory, small token/wiring canaries, compile mutations, AC Evidence Topology and directly affected docs. No normal obstacle classification, telemetry schema/flush behavior, layout, scheduler, capture, interpolation or permission behavior may change.

## Historical ordered work (superseded by the fourth replan)

1. Dispatch preflight: verify the resolved model configuration is available, create a fresh clean and unique implementation worktree from the recorded product baseline plus approved planning/governance commits, confirm the public Git identity, and ensure no duplicate implementation owner is active. Old implementation worktrees remain preserved but are not new-version inputs; failure stops dispatch without model substitution.
2. Run typed-capture production-chain tests in `Tests/main.swift` against the approved product baseline before product edits; record the full baseline SHA and exact test-only state. If the baseline already passes, classify this as a coverage-only gap and skip speculative product changes:
   - successful `.stats(visible)` for a WID followed by `.targetMissing` while the same CG candidate remains must reach the actual panel/frame owner; a baseline failure may preserve one obstacle/stale avoided Y;
   - `.targetMissing` without prior successful stats remains visible;
   - `.unavailable` from TCC/list/screenshot failure remains visible;
   - generation reset, candidate disappearance and in-flight completion cannot revive stale state.
3. Only if that production-chain baseline test fails because capture states cannot be distinguished, implement the smallest `BubbleCaptureObservation` (or equivalent) in `BubbleVisibility.swift`: `.stats`, `.targetMissing`, `.unavailable`, plus a per-generation set of successfully observed WIDs. Do not add a generic error hierarchy or expose ScreenCaptureKit objects.
4. Exercise the production composition through `visibility callback → scheduler coalescer → complete FollowLayoutPass → actual DockPanel.frame` for expanded → authoritative missing → hidden wake; assert the real panel reaches the base frame, exactly one latest-only follow-up runs, and repeated hide/show converges. Geometry/helper results may be supplementary assertions only.
5. Linear-interpolation baseline tests for a pure `DockFrameInterpolator` in `Tests/main.swift`; only a demonstrated baseline failure justifies the behavior change:
   - 0ms, 16ms and 32ms samples lie exactly on the segment and 32ms returns target;
   - 60 Hz, 120 Hz and irregular beats share the same monotonic duration semantics;
   - retarget starts from the current sampled frame, only the latest target survives, and no coordinate overshoots;
   - obstacle/screen/hidden safety transitions snap and reset;
   - continuous moving cadence completes the final segment before the existing 66.7ms stable threshold.
6. Only if the approved baseline demonstrates the interpolation behavior gap, add `DockFrameInterpolator` within `DockPanel.swift`; keep all state and `setFrame` calls on main. `placeBelow` accepts only the minimal movement intent/time inputs. First placement and non-movement target changes snap; movement retargets over at most 32ms.
7. Wire `main.swift` with existing `Follower.shouldSetFrame` and the shared monotonic clock. Do not change scheduler source selection, cadence, Follower thresholds, obstacle geometry, alpha thresholds or data/UI behavior.
8. Update only directly affected README/architecture facts. Record actual test counts after execution; do not duplicate candidate artifact instructions.
9. The implementation owner applies the `trellis-check` skill/checklist, fixes mechanical/spec issues, runs targeted tests and all hard gates, commits with public identity, freezes the full SHA, and reports diff, commands, actual results, failures and unverified runtime items.
10. Dispatch a fresh `zhipu/glm-5.3 + max` read-only formal Reviewer in a separate clean worktree for the complete current-campaign diff. Batch all P0/P1/P2 findings once to the same implementer. Any substantive finding in the second full Review triggers `trellis-break-loop`; no third Review loop.
11. Only after Review P0/P1/P2=0, dispatch a fresh `zhipu/glm-5.3 + max` QA Agent against the identical SHA. QA reruns hard gates, executes `make app` for the first time in this repair batch, archives a fresh commit-bound candidate, and verifies signature/source without altering TCC or `/Applications`.
12. The candidate remains pending until exact-app real-device checks separately cover expanded→collapsed, full message/control hide, 60 Hz drag feel, available high-refresh drag feel, TCC/ScreenCaptureKit and available multi-display conditions. Main integrates only an accepted SHA into local `dev`; no push/tag/release.

## Break-loop replan after second Review

The review campaign for `ee759ca` → `6e3536a` is closed and invalid. Before producing a new candidate, the same implementation owner must:

1. Cherry-pick the main-session break-loop/spec commit into the implementation branch.
2. Run baseline-discriminating tests for an off-grid wake whose work crosses the nearest stable deadline, plus work exceeding the interval; assert the next tick starts no later than `max(tickStartedAt + stableInterval, workCompletedAt)`. When work overruns, assert exactly one latest-only tick starts immediately after completion without another full-interval delay. Change product behavior only if the approved baseline fails.
3. Remove carried stable phase state if no longer necessary; calculate stable delay from each tick's monotonic start and schedule immediate latest-only work when the deadline is already missed.
4. Add an injectable screen-liveness lifecycle test: active display link → visible window loses screen and screen-change wake fires → display link invalidates and Timer fallback starts → screen restores and display link can be selected again.
5. Expose only the minimum DockPanel state/event needed: real `panel.screen != nil` eligibility plus screen-change callback. Do not add a general notification abstraction.
6. Re-run `trellis-check`, all gates and simplicity review; freeze a new SHA and start a fresh full formal Review campaign. Any findings follow the normal new-campaign workflow; no old Review approval or QA evidence is reusable.

## Second break-loop replan after wall-clock Review finding

The Review campaign ending at `539009e` is closed and invalid. Before producing another candidate, the same implementation owner must:

1. Cherry-pick the main-session second break-loop/spec commit into the implementation branch.
2. Run baseline-discriminating regressions for wall-time jumps while a separate monotonic clock advances normally, and add an executable guard banning wall-clock APIs from cadence owners. Include premature-recapture and delayed-retry counterexamples only if the approved baseline actually exhibits them; an already-passing baseline is a coverage-only gap.
3. Convert BubbleVisibility cadence state (`lastCapture`, pending retry deadline and comparisons) to the same injected monotonic clock domain used by the scheduler, with production default `ProcessInfo.systemUptime`. Do not bridge wall `Date` into elapsed-time arithmetic.
4. Keep the absolute due-instant retry contract and dynamic consumption from the prior fix; verify `.020 → .110 → .120` and post-probe overrun `.130` regressions still pass under the unified monotonic clock.
5. Preserve reset/empty/TCC false/in-flight/generation hygiene, single Timer source, latest-only coalescing, display-link recovery and capture-rate cap. Do not introduce a clock framework or unrelated timestamp refactor.
6. Re-run `trellis-check`, all gates and simplicity review; freeze a new SHA and start a new full formal Review campaign. No Review or QA evidence from `539009e` is reusable.

## Third break-loop replan after real-device full-hide failure

The Review/QA-approved candidate `91a8fe6ba915f84e35f232943fd1c1c3a558063d` failed real-device acceptance and is not reusable. Before another candidate:

1. Start from `d8538a5` plus the approved planning commits in a fresh clean implementation worktree. Preflight the resolved model configuration; do not substitute a model if routing is unavailable, and do not import old worktree patches.
2. Run a production-chain regression where a bubble remains in the CG candidate set but a successfully fetched SCK window list no longer contains its WID. The test must traverse hidden notification, coalesced scheduling, a complete tick and the actual `DockPanel.frame`; record whether the approved baseline preserves one obstacle/stale avoided Y or already passes. Add the adjacent failure case where SCK list/capture is unavailable and conservative visible remains required.
3. If and only if the approved baseline production-chain test fails because it cannot distinguish the observed states, replace the optional capture payload with the smallest typed outcome (`stats`, `targetMissing`, `unavailable` or equivalent). Only `targetMissing` may classify hidden; retain generation, identity, known-candidate and strict single-flight guards before notification/cache writes. If the baseline passes, keep product code unchanged and close only the evidence gap.
4. Extend the full `FollowLayoutPass → Geometry → frame sink` harness through hidden notification and assert the final obstacle set is empty and the dock returns to base frame. Repeated full hide/show cycles must not accumulate wakes or stale targets.
5. Use the user-approved 32ms maximum window for baseline pure tests at 60 Hz, 120 Hz and irregular beats: latest-target retargeting, no overshoot, no history queue, exact final snap, and immediate safety snap. Wire the smallest main-thread interpolation owner at the DockPanel/frame boundary only for a demonstrated behavior gap.
6. Do not change alpha thresholds, CG obstacle geometry, permissions, capture cadence, scheduler source architecture, or introduce prediction, spring animation, implicit AppKit animation or continuous SCStream unless the production-chain baseline evidence disproves the typed-outcome hypothesis and planning is reopened.
7. Apply `trellis-check`, rerun every hard gate, freeze a new SHA and begin a new full Review campaign. The prior `d8538a5` Review/QA evidence is invalid after any change.

## Required validation

```bash
swift build -c release
make docs-check
make test-docs
make test
git diff --check <base-sha>..<candidate-sha>
```

`make app` and `codesign --verify --deep --strict build/PetDock.app` run only in QA after formal Review clears the exact SHA.

Additional targeted tests must cover scheduler coalescing, repeated visibility transitions, time-based stable semantics, typed target-missing versus capture-unavailable behavior, generation/single-flight, candidate disappearance, and bounded interpolation.

## Fourth break-loop replan after evidence-only final Review findings

The Review campaign `0e6439b` -> `585b9a4b4e2eef291755d5bc8971294e32feafa9` is closed. Its final Review reported P0=0/P1=0/P2=2, so QA did not start and no third patch/Review round is allowed. Begin a fresh campaign only after approval:

1. Create a fresh `zhipu/glm-5.3 + max` implementation owner/worktree from `24b9732` plus the approved break-loop/spec and evidence-topology governance commits. Do not reuse v4 Review or implementation worktrees as a new version.
2. Replace the ineffective wall-jump fixture with two real evidence edges:
   - keep behavioral scheduler/probe tests driven only by their injected monotonic clock;
   - add an executable source/API guard covering the cadence-owning production files and fail on `Date`, `CFAbsoluteTime`, or equivalent wall-clock inputs used for deadline/throttle/retry logic.
   Do not add a second production clock that exists only for tests.
3. Add a discriminating `targetMissing` production-composition test that starts with `.stats(expanded)`, schedules an unexpired stable one-shot, then returns authoritative `.targetMissing` and observes `onVisibilityChange -> scheduler coalescer -> full FollowLayoutPass -> actual DockPanel.placeBelow/frame`. Assert exactly one early tick, zero final obstacles, base frame, invalidated old stable timer, and no repeated wake for unchanged hidden state.
4. Keep adjacent conservative cases for never-observed targetMissing and unavailable capture. The helper-level Geometry fixture may remain, but it cannot be the AC2b evidence owner.
5. Run the two tests against unmodified `24b9732` first. If they pass, make no product-code change. If one fails, change only the proven production boundary and add the red/green evidence; do not reopen scheduler architecture, alpha thresholds, permissions, geometry, interpolation semantics, or clock design.
6. Apply `trellis-check`, map every AC to `source event -> production consumer -> observable`, run all hard gates, freeze a new SHA, and start a new Review campaign. No Review/QA evidence from `24b9732` is reusable.

## Fifth break-loop replan after real-device v5 failure

The v5 frozen candidate passed its automated gates and formal Review but failed the user's real image 3 full-hide flow: the cards and controls disappeared while the dock retained the old avoidance gap. The v5 `.targetMissing` regression therefore remains plumbing-only. Start a fresh campaign from the committed v6 planning baseline:

1. Preflight a fresh `zhipu/glm-5.3 + max` implementation owner, unique clean branch/worktree and exact base commit. The first v6 implementation is diagnostic-only; do not reuse v5 implementation/Review/QA agents or their approvals.
2. Before editing, read `break-loop-5-2026-08-21.md` and the updated AppKit, privacy, quality and cross-layer specs. Search existing diagnostics/private-storage owners before adding code; keep each metric at its production fact owner.
3. Add the smallest default-off runtime evidence aggregate covering obstacle kind counts, capture outcome / visibility counts, identity-change / wake callback counts, visible obstacle count and anonymous dock dy bucket relative to the no-obstacle base frame. No identifier, title, owner, screen, exact coordinate, alpha value, color, text, image or per-window event sequence may enter the model or output.
4. Enabling must be explicit and QA-only. Disabled mode creates no file and no extra capture/timer. If persisted, use the existing private Application Support boundary with 0700 directory, 0600 no-follow file semantics; add executable privacy guards for field names, permissions and disabled behavior.
5. Add tests that prove every aggregate input is consumed by the production owner and that the output cannot distinguish a real window. These tests validate instrumentation only; they must not be labeled as proof of the image 3 fix.
6. Apply `trellis-check`, run targeted tests plus `swift build -c release`, `make test`, docs/privacy gates and diff checks, update AC Evidence Topology with diagnostic-only/manual gaps, commit and freeze the diagnostic SHA.
7. A fresh `zhipu/glm-5.3 + max` read-only formal Reviewer must clear P0/P1/P2 on the exact diagnostic SHA. Only then may a fresh `zhipu/glm-5.3 + max` automated QA Agent build/archive an exact diagnostic candidate.
8. After automated QA, a fresh `kimi/k3 + max` visual QA Agent closes the currently running failed candidate, launches the exact diagnostic candidate, performs the user's image 1→2→3 flow, and records only the allowed aggregate plus UI outcome. The main Agent independently verifies the exact process path, operation sequence and captured UI evidence. Repeat enough times to distinguish transient from stable branch behavior.
9. Replan from the observed branch. Add a production-equivalent baseline regression; only a failing baseline authorizes the smallest behavior change. Any change creates a new SHA and restarts full Review/QA and three-round real-device validation.

## Sixth break-loop replan after v6 second Review

The v6 second formal Review ended with P0=0/P1=0/P2=4, so the campaign is closed without QA and no third patch/Review round is allowed. Start a fresh v7 implementation campaign from the committed v7 planning baseline:

1. Preflight one fresh `zhipu/glm-5.3 + max` implementation owner in a unique clean worktree at the exact planning SHA. Do not reuse v6 implement/Review agents or approvals.
2. In `DockPanel.placeBelow`, keep the requested/interpolated frame for the existing `setFrame` call, then read the actual panel frame back after the side effect and use only that owner value for dy telemetry. Add a fractional boundary regression and a source mutation guard that fail if telemetry is changed back to the request value.
3. Replace the async capturer semaphore wait with a test-only continuation/async-safe gate that suspends without blocking an executor and resumes exactly once. Add warnings-as-errors to the existing test-ui `swiftc` command; record a semaphore mutation compile failure and run test-ui repeatedly without warnings.
4. Change the runtime constructor privacy guard to recursively enumerate `Sources/PetDock/**/*.swift`, prove the sole production constructor remains in main, and assert its output is `PrivateStorage.diagnosticsURL` plus the fixed evidence filename. Record nested-constructor and non-private-sink mutation failures.
5. Tighten runtime evidence provenance to exactly 40 lowercase hex characters. Update parser comments, positive/negative boundary tests and directly affected docs together; reject 7/39/41/64, uppercase and non-hex values.
6. Do not alter telemetry fields, flush cadence, capture/generation semantics, obstacle classification, alpha thresholds, scheduler, interpolation, permissions or UI behavior. Existing image3 tests remain plumbing-only.
7. Update AC Evidence Topology with each baseline/mutation, production consumer, final owner and actual command result. Apply `trellis-check`, run release/test/docs/privacy/diff gates, freeze a new SHA and hand off to a fresh full formal Review campaign.
8. Review clear → fresh zhipu automated QA builds/archives exact candidate → fresh `kimi/k3 + max` visual QA performs image 1→2→3 and main independently verifies process path, operation sequence and evidence. No image3 fix claim before runtime sampling.

## Seventh break-loop replan after v7 second Review

The v7 second formal Review ended with P0=0/P1=0/P2=2, so v7 is closed without QA and no third patch is allowed. Start a fresh v8 campaign from the committed v8 planning baseline:

1. Preflight one fresh `zhipu/glm-5.3 + max` implementation owner in a unique clean worktree at the exact planning SHA. Do not reuse v7 implementation/Review agents or approvals.
2. Before implementation, reproduce both old-guard holes on the approved base: an unflagged definition-file factory accepting a URL and a comment-split constructor must leave the v7 privacy gate green. Record them as red baselines proving the old defense layer is hollow, then remove all constructor-spelling regex, alias/metatype/typed-init enumeration, comment normalization and constructor-argument parsing.
3. In `RuntimeEvidence.swift`, make the designated initializer `private`. Add a same-file `production(candidateSHA:flushNow:)` factory with no URL parameter and a fixed `PrivateStorage.diagnosticsURL` + filename sink. Add `forTesting(candidateSHA:outputURL:flushNow:)` only inside `#if PETDOCK_TESTING`; do not move files or add `@testable`/new targets.
4. Change `main.swift` to the production factory. Add `-DPETDOCK_TESTING` only to the existing test-ui swiftc recipe and rewrite existing runtime-evidence test fixtures to the test factory without changing their assertions or timing.
5. Replace the deleted regex family with W0–W6 compiler-first canaries from `break-loop-7-2026-08-22.md`: line-anchored declaration shape/count for private-init and production factory (accidental drift only), test-factory token location and flag region, release Package absence, exactly one test-ui flag wiring, and a pinned identifier-boundary `URL|NSURL|CFURL` allowlist outside the test region. Keep aggregate-only/privacy field guards and exact ASCII SHA tests; no textual canary may be reported as the access-control proof.
6. Record release compile mutations for direct, explicit/comment-split and test-factory construction plus an invalid production `outputURL:` argument; record wiring mutations for Package flag, duplicate/moved Makefile flag, outside-region URL API and unwrapped test factory. For private-init removal, use the same external constructor probe as a contrast: correct tree fails compilation, removing `private` makes the probe compile while W0 fails, and restoration returns to compile-fail/W0-pass. The main admission must inspect compiler evidence and wiring canaries rather than only test counts.
7. Run trellis-check, release 0 warning, full tests/docs/privacy/diff/task gates and repeated test-ui, update AC Evidence Topology, freeze a new SHA, then start a fresh formal Review campaign. Any source change invalidates all prior evidence.
8. Review clear → fresh zhipu automated QA builds/archives the exact candidate → fresh `kimi/k3 + max` visual QA performs image 1→2→3 and records the same candidate's privacy-safe runtime aggregate. Until that sampling, image3 remains unresolved and all fake outcome tests remain plumbing-only.

## Review focus

- No timer/display-link retain cycle, duplicate source, post-quit callback, or main-thread backlog.
- AppKit display link availability is guarded for macOS 14; no deprecated `CVDisplayLink` and release build remains 0 warning.
- Variable refresh cannot shorten the intended moving→stable elapsed time.
- Bubble polling cannot start overlapping captures or let generic capture/TCC failure masquerade as authoritative target disappearance.
- Interpolation cannot overshoot, queue stale targets, delay safety reset, mutate off the main thread, or exceed the approved trailing window.
- No new permission, private API, screenshot persistence, OCR, content logging, real WID/PID/coordinates, or unrelated refactor.

## Runtime QA matrix

- Exact candidate executable and commit provenance.
- Bubble expanded→collapsed with pet stationary; repeat at least three cycles.
- Expanded→collapsed and complete message/control hide tested separately; authoritative target missing and generic capture failure distinguished.
- Drag on a 60 Hz display and, if available, a high-refresh display; record observed smoothness separately from automated cadence tests.
- Multi-display crossing/negative coordinates if safely available.
- TCC/ScreenCaptureKit status and Instruments CPU/memory only when actually exercised; otherwise explicitly `未验证`.

## Rollback points

- Scheduler can fall back to the no-drift Timer path without reverting time-based stability or bubble wake.
- Bubble cadence can revert independently if Instruments shows unacceptable cost; the original 2 Hz behavior must not be silently restored while claiming immediate collapse.
- Any need to change alpha thresholds or adopt continuous `SCStream` returns the task to planning.
