# Implementation Plan

## Preconditions

- Base branch: `dev` at the exact SHA verified before dispatch.
- Delivery path: L2.
- Per the user's task-specific override, every implementation, formal Review, repair recheck and QA sub-agent for this task uses `gpt-5.6-sol + high` instead of the project default; each fresh role owns its required isolated branch/worktree and the main session does not edit product code.
- Allowed product scope is limited to follow scheduling, the minimal DockPanel display-link adapter, bubble probe cadence/wake integration, Follower state, corresponding UI tests, Makefile source list if a focused scheduler file is added, and directly affected docs.

## Ordered work

1. Dispatch preflight: verify `gpt-5.6-sol + high`, clean unique worktree/branch from current `dev`, public Git identity, no duplicate active owner, and record full base SHA.
2. Red tests for end-to-end wake: model an existing stable timer, successful visible→hidden classification, scheduler wake, complete layout tick, and repeated transitions; prove current callback-only coverage is insufficient.
3. Red tests for cadence coalescing: dense display callbacks produce at most one pending tick; busy main-loop periods drop stale beats; wakeNow advances stable/hidden scheduling without duplicate execution.
4. Red tests for time-based stability: identical elapsed-time sequences at 60 Hz, 120 Hz and irregular cadence preserve the current nominal 4/60-second stationary threshold and resume moving on material change.
5. Implement the smallest scheduler abstraction:
   - macOS 14+ window-bound AppKit `CADisplayLink` in moving;
   - macOS 13 screen-capability repeating Timer fallback;
   - stable/hidden one-shot Timer;
   - main-thread coalescing and lifecycle stop/invalidate.
6. Replace tick-count stability with injected monotonic elapsed-time semantics; keep existing geometric tolerance and hidden behavior.
7. Reduce visible bubble probe scheduling wait to at most 0.1 seconds while preserving permission gate, single-flight, generation, knownWids and nil=>visible contracts; route actual result changes to scheduler `wakeNow`.
8. Wire AppDelegate to the scheduler without changing unrelated data/UI behavior; ensure quit/hidden/lifecycle paths invalidate display link and timers.
9. Update affected English/Chinese README and architecture/verification facts. Do not duplicate candidate artifact procedure. Record actual test counts only after running them.
10. Implementer applies `trellis-check` skill/checklist in its own worktree, fixes mechanical/spec issues, then commits with public identity and reports full SHA, diff, commands, failures and unverified runtime items.
11. Freeze SHA and dispatch a fresh `gpt-5.6-sol + high` read-only formal Reviewer in its own branch/worktree. Batch all P0/P1/P2 findings back to the same implementer. If second full Review has any substantive finding, run `trellis-break-loop` and replan.
12. Only after Review P0/P1/P2=0, dispatch a fresh `gpt-5.6-sol + high` QA Agent against the identical SHA. QA runs all automated gates, builds the ad-hoc app only now, archives a fresh commit-bound candidate, verifies signature/source, and performs safe runtime checks that do not alter TCC or `/Applications`.
13. Main session accepts and integrates only the exact reviewed/QA SHA into local `dev`; no push/tag/release. Preserve unrelated untracked content. Cleanup only after read-only dirty/pre-commit checks and backup of any unmerged ref.

## Required validation

```bash
swift build -c release
make docs-check
make test-docs
make test
git diff --check <base-sha>..<candidate-sha>
make app
codesign --verify --deep --strict build/PetDock.app
```

Additional targeted tests must cover scheduler coalescing, repeated visibility transitions, time-based stable semantics, permission/capture fallback, generation/single-flight, and candidate disappearance.

## Review focus

- No timer/display-link retain cycle, duplicate source, post-quit callback, or main-thread backlog.
- AppKit display link availability is guarded for macOS 14; no deprecated `CVDisplayLink` and release build remains 0 warning.
- Variable refresh cannot shorten the intended moving→stable elapsed time.
- Bubble polling cannot start overlapping captures or weaken nil/TCC conservative behavior.
- No new permission, private API, screenshot persistence, OCR, content logging, real WID/PID/coordinates, or unrelated refactor.

## Runtime QA matrix

- Exact candidate executable and commit provenance.
- Bubble expanded→collapsed with pet stationary; repeat at least three cycles.
- Bubble candidate disappearance and capture-nil fallback distinguished.
- Drag on a 60 Hz display and, if available, a high-refresh display; record observed smoothness separately from automated cadence tests.
- Multi-display crossing/negative coordinates if safely available.
- TCC/ScreenCaptureKit status and Instruments CPU/memory only when actually exercised; otherwise explicitly `未验证`.

## Rollback points

- Scheduler can fall back to the no-drift Timer path without reverting time-based stability or bubble wake.
- Bubble cadence can revert independently if Instruments shows unacceptable cost; the original 2 Hz behavior must not be silently restored while claiming immediate collapse.
- Any need to change alpha thresholds or adopt continuous `SCStream` returns the task to planning.
