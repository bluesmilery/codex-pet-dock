# Implementation Plan

## Preconditions

- Product base: exact candidate `91a8fe6ba915f84e35f232943fd1c1c3a558063d`; the v2 implementation branch additionally carries planning/spec commits only. Verify the final planning HEAD before dispatch.
- Delivery path: L2.
- Per the latest project-level `AGENTS.md`, every implementation, formal Review, repair recheck and QA sub-agent for this task uses `luna + max`; unavailable routing stops dispatch without model downgrade. Each fresh role owns its required isolated branch/worktree and the main session does not edit product code.
- Allowed product scope is limited to typed bubble capture outcome/lifecycle invalidation, bounded DockPanel frame interpolation, follow scheduling integration, corresponding UI tests, and directly affected docs.

## Ordered work

1. Dispatch preflight: verify `luna + max` is available, create a fresh clean/unique v3 implementation worktree from the recorded planning HEAD, confirm the public Git identity, and ensure no duplicate implementation owner is active. The interrupted v2 Kimi worktree remains preserved but is not an implementation input; failure stops dispatch without model substitution.
2. Typed-capture red tests in `Tests/main.swift`:
   - successful `.stats(visible)` for a WID followed by `.targetMissing` while the same CG candidate remains must currently preserve one obstacle/stale avoided Y and fail;
   - `.targetMissing` without prior successful stats remains visible;
   - `.unavailable` from TCC/list/screenshot failure remains visible;
   - generation reset, candidate disappearance and in-flight completion cannot revive stale state.
3. Implement the smallest `BubbleCaptureObservation` (or equivalent) in `BubbleVisibility.swift`: `.stats`, `.targetMissing`, `.unavailable`, plus a per-generation set of successfully observed WIDs. Do not add a generic error hierarchy or expose ScreenCaptureKit objects.
4. Extend the production `FollowLayoutPass → visibility cache → Geometry → frame sink` test through expanded → authoritative missing → hidden wake; assert final obstacle count zero, base frame, exactly one latest-only follow-up, and repeated hide/show convergence.
5. Linear-interpolation red tests for a pure `DockFrameInterpolator` in `Tests/main.swift`:
   - 0ms, 16ms and 32ms samples lie exactly on the segment and 32ms returns target;
   - 60 Hz, 120 Hz and irregular beats share the same monotonic duration semantics;
   - retarget starts from the current sampled frame, only the latest target survives, and no coordinate overshoots;
   - obstacle/screen/hidden safety transitions snap and reset;
   - continuous moving cadence completes the final segment before the existing 66.7ms stable threshold.
6. Add `DockFrameInterpolator` within `DockPanel.swift`; keep all state and `setFrame` calls on main. `placeBelow` accepts only the minimal movement intent/time inputs. First placement and non-movement target changes snap; movement retargets over at most 32ms.
7. Wire `main.swift` with existing `Follower.shouldSetFrame` and the shared monotonic clock. Do not change scheduler source selection, cadence, Follower thresholds, obstacle geometry, alpha thresholds or data/UI behavior.
8. Update only directly affected README/architecture facts. Record actual test counts after execution; do not duplicate candidate artifact instructions.
9. The implementation owner applies the `trellis-check` skill/checklist, fixes mechanical/spec issues, runs targeted tests and all hard gates, commits with public identity, freezes the full SHA, and reports diff, commands, actual results, failures and unverified runtime items.
10. Dispatch a fresh `luna + max` read-only formal Reviewer in a separate clean worktree for the complete diff from `d8538a5`. Batch all P0/P1/P2 findings once to the same implementer. Any substantive finding in the second full Review triggers `trellis-break-loop`; no third Review loop.
11. Only after Review P0/P1/P2=0, dispatch a fresh `luna + max` QA Agent against the identical SHA. QA reruns hard gates, executes `make app` for the first time in this repair batch, archives a fresh commit-bound candidate, and verifies signature/source without altering TCC or `/Applications`.
12. The candidate remains pending until exact-app real-device checks separately cover expanded→collapsed, full message/control hide, 60 Hz drag feel, available high-refresh drag feel, TCC/ScreenCaptureKit and available multi-display conditions. Main integrates only an accepted SHA into local `dev`; no push/tag/release.

## Break-loop replan after second Review

The review campaign for `ee759ca` → `6e3536a` is closed and invalid. Before producing a new candidate, the same implementation owner must:

1. Cherry-pick the main-session break-loop/spec commit into the implementation branch.
2. Add red tests for an off-grid wake whose work crosses the nearest stable deadline, plus work exceeding the interval; assert the next tick starts no later than `max(tickStartedAt + stableInterval, workCompletedAt)`. When work overruns, assert exactly one latest-only tick starts immediately after completion without another full-interval delay.
3. Remove carried stable phase state if no longer necessary; calculate stable delay from each tick's monotonic start and schedule immediate latest-only work when the deadline is already missed.
4. Add an injectable screen-liveness lifecycle test: active display link → visible window loses screen and screen-change wake fires → display link invalidates and Timer fallback starts → screen restores and display link can be selected again.
5. Expose only the minimum DockPanel state/event needed: real `panel.screen != nil` eligibility plus screen-change callback. Do not add a general notification abstraction.
6. Re-run `trellis-check`, all gates and simplicity review; freeze a new SHA and start a fresh full formal Review campaign. Any findings follow the normal new-campaign workflow; no old Review approval or QA evidence is reusable.

## Second break-loop replan after wall-clock Review finding

The Review campaign ending at `539009e` is closed and invalid. Before producing another candidate, the same implementation owner must:

1. Cherry-pick the main-session second break-loop/spec commit into the implementation branch.
2. Add red regressions proving the existing `Date()` cadence changes when wall time jumps forward/backward while a separate monotonic clock advances normally; include both premature recapture and delayed retry counterexamples.
3. Convert BubbleVisibility cadence state (`lastCapture`, pending retry deadline and comparisons) to the same injected monotonic clock domain used by the scheduler, with production default `ProcessInfo.systemUptime`. Do not bridge wall `Date` into elapsed-time arithmetic.
4. Keep the absolute due-instant retry contract and dynamic consumption from the prior fix; verify `.020 → .110 → .120` and post-probe overrun `.130` regressions still pass under the unified monotonic clock.
5. Preserve reset/empty/TCC false/in-flight/generation hygiene, single Timer source, latest-only coalescing, display-link recovery and capture-rate cap. Do not introduce a clock framework or unrelated timestamp refactor.
6. Re-run `trellis-check`, all gates and simplicity review; freeze a new SHA and start a new full formal Review campaign. No Review or QA evidence from `539009e` is reusable.

## Third break-loop replan after real-device full-hide failure

The Review/QA-approved candidate `91a8fe6ba915f84e35f232943fd1c1c3a558063d` failed real-device acceptance and is not reusable. Before another candidate:

1. Start from `d8538a5` plus the approved planning commits in a fresh clean v3 implementation worktree. Preflight `luna + max`; do not substitute a model if routing is unavailable, and do not import the interrupted v2 Kimi worktree's uncommitted patch.
2. Add a red production-chain regression where a bubble remains in the CG candidate set but a successfully fetched SCK window list no longer contains its WID. Prove the old optional-nil contract preserves one obstacle and stale avoided Y. Add the adjacent failure case where SCK list/capture is unavailable and conservative visible remains required.
3. If and only if the red test distinguishes the observed states, replace the optional capture payload with the smallest typed outcome (`stats`, `targetMissing`, `unavailable` or equivalent). Only `targetMissing` may classify hidden; retain generation, identity, known-candidate and strict single-flight guards before notification/cache writes.
4. Extend the full `FollowLayoutPass → Geometry → frame sink` harness through hidden notification and assert the final obstacle set is empty and the dock returns to base frame. Repeated full hide/show cycles must not accumulate wakes or stale targets.
5. Use the user-approved 32ms maximum window for red pure tests at 60 Hz, 120 Hz and irregular beats: latest-target retargeting, no overshoot, no history queue, exact final snap, and immediate safety snap. Then wire the smallest main-thread interpolation owner at the DockPanel/frame boundary.
6. Do not change alpha thresholds, CG obstacle geometry, permissions, capture cadence, scheduler source architecture, or introduce prediction, spring animation, implicit AppKit animation or continuous SCStream unless the discriminating red test disproves the typed-outcome hypothesis and planning is reopened.
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

1. Create a fresh Luna Max implementation owner/worktree from `24b9732` plus this break-loop/spec commit. Do not reuse v4 Review or implementation worktrees as a new version.
2. Replace the ineffective wall-jump fixture with two real evidence edges:
   - keep behavioral scheduler/probe tests driven only by their injected monotonic clock;
   - add an executable source/API guard covering the cadence-owning production files and fail on `Date`, `CFAbsoluteTime`, or equivalent wall-clock inputs used for deadline/throttle/retry logic.
   Do not add a second production clock that exists only for tests.
3. Add a discriminating `targetMissing` production-composition test that starts with `.stats(expanded)`, schedules an unexpired stable one-shot, then returns authoritative `.targetMissing` and observes `onVisibilityChange -> scheduler coalescer -> full FollowLayoutPass -> actual DockPanel.placeBelow/frame`. Assert exactly one early tick, zero final obstacles, base frame, invalidated old stable timer, and no repeated wake for unchanged hidden state.
4. Keep adjacent conservative cases for never-observed targetMissing and unavailable capture. The helper-level Geometry fixture may remain, but it cannot be the AC2b evidence owner.
5. Run the two tests against unmodified `24b9732` first. If they pass, make no product-code change. If one fails, change only the proven production boundary and add the red/green evidence; do not reopen scheduler architecture, alpha thresholds, permissions, geometry, interpolation semantics, or clock design.
6. Apply `trellis-check`, map every AC to `source event -> production consumer -> observable`, run all hard gates, freeze a new SHA, and start a new Review campaign. No Review/QA evidence from `24b9732` is reusable.

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
