# Design: Container pet channel

## Overview

Add a fallback "container channel" next to the existing Mascot-window channel.
When the primary channel finds no pet, select the host pet-container window
(huge, transparent, layer >= 2) and derive a synthetic pet rect from its
in-memory alpha bbox. The synthetic rect feeds the existing
Follower/FollowTickPlan/DockPanel pipeline unchanged.

## New source file: Sources/PetDock/ContainerPetChannel.swift

All new production code lives in this single file (surgical boundary).

### Thresholds: enum ContainerPetHeuristics

- `minLayer = 2`
- `minArea: CGFloat = 1_000_000` (probe-measured container ~772x2549)
- `opaqueFractionGate: Double = 0.01` (probe-measured 0.0019)
- `petMinSide: CGFloat = 20`, `petMaxSide: CGFloat = 400` (mapped-rect sanity)
- `stableCaptureInterval: TimeInterval = 1.0`
- `movingCaptureInterval: TimeInterval = 0.1`
- `movingHoldDuration: TimeInterval = 2.0` (bbox changed -> fast cadence hold)

### Pure selection: enum ContainerPetSelector

`static func selectContainer(candidates: [WinCandidate]) -> WinCandidate?`
- filter: `isOnscreen`, `!isLikelyMainWindow`, `layer >= minLayer`,
  `area >= minArea`
- multiple matches -> largest area (deterministic tie-break: smaller wid)

### Pure stats + mapping

`struct ContainerAlphaStats`: nonTransparentPixelCount, minX/minY/maxX/maxY
(capture pixel coords), captureWidth, captureHeight.

`enum ContainerCaptureOutcome`: `.stats(ContainerAlphaStats)`,
`.targetMissing`, `.unavailable`.

`static func captureSize(width:height:) -> (Int, Int)?`: downsample longest
side to <= 400 (mirror BubbleVisibility.downsampleCaptureSize pattern; local
implementation, no coupling to bubble thresholds).

`static func mapToPetRect(stats:captureWidth:captureHeight:containerBounds:)
-> CGRect?`: gates are opaque fraction <= opaqueFractionGate AND mapped
width/height within [petMinSide, petMaxSide]; maps capture bbox to global
Quartz rect using containerBounds (CGWindowList bounds) as the single
authoritative origin/size source.

### Probe: final class ContainerPetProbe

Mirrors BubbleVisibilityProbe structure (NSLock state, single-flight,
Task.detached capture, generation on reset):

- Injectables: `capturer: @Sendable (WinCandidate, CGSize) async ->
  ContainerCaptureOutcome` (size = downsample target), `canCapture: () ->
  Bool = { CGPreflightScreenCaptureAccess() }`, `monotonicNow`, and
  `onFirstObservation: (@Sendable () -> Void)?` (wake scheduler once when the
  first valid observation lands).
- Default capturer factory: one
  `SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly:
  true)` per round; find SCWindow by windowID;
  `SCContentFilter(desktopIndependentWindow:)`;
  `SCScreenshotManager.captureImage`; compute full opaque bbox in memory
  (alpha > 0.04, same threshold as BubbleVisibility.computeAlphaStats).
- `func locate(container: WinCandidate) -> ContainerPetOutcome`: synchronous.
  - canCapture() false -> .unavailable (also drops stale cache)
  - identity (wid) change or reset -> clear cache
  - returns cached mapped pet rect (`.bounds`) or `.empty` when nothing yet
  - starts a background capture when cadence allows: interval = bbox changed
    since last capture (movingUntil active) ? movingCaptureInterval :
    stableCaptureInterval; single-flight guard; capture result cached only if
    generation still current.
  - first valid observation fires onFirstObservation once per disappearance
    episode.
- `func reset()`: pet/container disappearance path clears cache + generation++.
- Privacy: alpha-only in-memory stats; no image persistence, no OCR, no
  colors/text (same contract as BubbleVisibility; header comment states it).

## Integration: Sources/PetDock/main.swift (tick)

`private lazy var containerProbe = ContainerPetProbe(
    monotonicNow: followMonotonicNow,
    onFirstObservation: { [weak self] in self?.followScheduler.requestWake() })`

tick() changes (no state-machine fork):

```swift
let wins = PetTracker.unionCandidates()
let sel = PetTracker.selectPet(candidates: wins, lastWID: lastWID)
var petRect = sel.selected?.bounds
if petRect == nil, let container = ContainerPetSelector.selectContainer(candidates: wins) {
    if case .bounds(let rect) = containerProbe.locate(container: container) {
        petRect = rect
    }
}
let d = Follower.decide(pet: petRect, ...)
```

- `lastWID` stays nil on the container channel (sel.selected == nil); primary
  channel recovery keeps working if a Mascot window returns.
- Placement: existing `if let mascot = sel.selected` branch untouched. Add a
  sibling branch for the container channel: compute
  `scr = Geometry.screenContaining(...)` from the synthetic rect, then
  `dock.placeBelow(petQuartzRect: petRect, avoiding: [], visibleScreen: scr,
  movementChanged: d.shouldSetFrame, monotonicNow: followMonotonicNow(),
  evidence: runtimeEvidence)`; true -> showIfNeeded (+ detail reposition),
  false -> hideIfNeeded + detail.close. Obstacles stay empty here: the old
  obstacle windows no longer exist in the new host structure and the captured
  content bbox already includes pet + bubble content.
- Hidden path: add `containerProbe.reset()` next to `bubbleProbe.reset()`.

## Diagnostics: runDiagnoseAndExit + DiagnosticFormatter

Add a container-channel section: matching container candidates (count +
DiagnosticFormatter-style shape summaries, no user content), whether the
opaque-fraction gate would apply, and which channel produced the final
selection. Reuse existing redaction style; no raw coordinates of user
content.

## Build/test wiring

- Package.swift auto-includes Sources; no change needed for swift build.
- Makefile test-ui compiles an explicit source list: ADD
  `Sources/PetDock/ContainerPetChannel.swift` to the test-ui recipe (keep
  alphabetical order with the other Sources entries).

## Test plan (tests/main.swift, PETDOCK_TESTING entry)

Follow existing test helper/fixture patterns:

1. Selector: accepts new-structure fixture candidate (layer 3, huge, onscreen,
   non-main); rejects layer-0 windows, normal-size helper windows, offscreen
   ones; multiple matches -> largest area, wid tie-break.
2. captureSize: aspect-preserving downsample; nil below threshold.
3. mapToPetRect: probe-derived golden case (121x400 capture, bbox
   (54,194)-(61,209), container 772x2549 at (1482,-267) -> (1776,918,51,101));
   rejects fraction > gate, no-opaque, sides out of range, single-pixel
   rounding.
4. Probe with fake capturer + fake clock: cadence (stable 1s / moving 0.1s
   after bbox change), single-flight (in-flight capture not duplicated),
   generation invalidation on reset and wid change, .unavailable when
   canCapture false, onFirstObservation fires once.
5. Tick orchestration (existing app-delegate level tests if present; else
   plan-level): hidden -> petVisible on container observation; disappearance
   -> hidden + reset. Reuse existing FollowTickPlan tests as the pattern.

## Non-goals

- No changes to BubbleVisibility.swift, PetTracker.swift, Follower.swift,
  FollowTickPlan.swift, DockPanel.swift.
- No obstacle construction from container content (phase 2).
- No settings/UI surface.

## Correction (2026-08-28, post-implementation)

The probe-derived golden case above mixed coordinate sources: its literal
origin came from SCWindow.frame while its size scaling used CGWindowList
bounds — no affine mapping of the stated inputs can reproduce (1776, 918,
51, 101) exactly. The normative rule (containerBounds as the single
authoritative origin/size source) governs. Test T-cp13 asserts the
authoritative mapped result; the ~50 px origin difference vs the original
probe output is expected and is exactly the PRD-flagged risk that AC6
on-device verification must resolve.

## Addendum (2026-08-28, R7 responsive container channel)

User acceptance testing found dock re-anchoring on bubble/control
appearance noticeably less smooth than the pre-update obstacle-window
channel (PRD R7). Root cause: content changes are observed only at the
stable capture cadence (1 s) and the tick samples the result, so detection
latency averaged 0.5 s and peaked at 1 s before the 200 ms glide.

Changes:

1. `ContainerPetHeuristics.stableCaptureInterval` 1.0 -> 0.33 (3 Hz;
   p95 detection <= 0.4 s per R7). Moving hold unchanged (0.1 s for 2 s
   after any bbox change).
2. Replace `onFirstObservation` with edge-triggered
   `onObservationChanged`: fires when an accepted observation rect changes
   vs the last delivered rect (none->rect and rect->different-rect), not on
   unchanged re-captures. Generation/WID invalidation resets the baseline.
3. main.swift wires `onObservationChanged` to
   `followScheduler.requestWake()` (coalesced) so an accepted change is
   placed immediately at the current tick cadence instead of waiting up to
   one stable interval for the next tick.
4. RuntimeEvidence gains `containerObservationChangeCount` (sanitized
   count, same dirty-suppression style) so QA can verify change cadence and
   wake behavior from candidate-bound evidence.

Expected behavior: bubble/control toggle -> capture lands within 0.33 s ->
edge fires -> wake -> tick places with a single 200 ms glide. Steady CPU is
a gate (R7): QA measures; if the budget fails, report tradeoffs (e.g. 0.4 s
cadence) rather than shipping over budget.

## Addendum 2 (2026-08-29, QA-driven capture pivot: SCStream low-fps)

Real-device QA of affee8ea measured 3 Hz one-shot SCScreenshotManager
polling at 12.0% average CPU - far above the R7 budget (<= 5%, target
<= 2%). One-shot capture carries a large fixed per-call cost (content
filter construction, full-window composite, transfer) that dominates at
any cadence. Separately, the opaque-fraction gate at 0.01 was measured
fluctuating between 0.0090 and 0.0102 across frames (pet sprite
antialiasing/animation), making channel validity flicker.

Changes:

1. Capture pivot: replace one-shot polling with a managed low-fps SCStream
   per container window.
   - `SCStreamConfiguration`: downsample to longest side <= 400 (as before),
     `minimumFrameInterval` = 0.33 s (3 fps), queue-delivered frames.
   - Frame processing is latest-wins: if a frame arrives while the previous
     bbox computation is still running, drop it (no queuing), matching the
     project's latest-only philosophy.
   - Lifecycle: stream starts when a container candidate is first selected
     (first locate with that WID) and stops on reset-with-absence, WID
     change, permission loss, probe deinit, and app quit. Exactly one live
     stream at a time.
   - macOS 14+ for streams (unchanged requirement); macOS 13 falls back to
     the old one-shot path at the conservative 1 s cadence (acceptable:
     0% CPU priority on an OS that cannot run the new host structure
     anyway).
   - Edge semantics (onObservationChanged), generation/WID invalidation,
     gated reset, and telemetry counters are unchanged; frames replace
     one-shot results as their input.
2. Gate headroom: `opaqueFractionGate` 0.01 -> 0.02. Rationale: measured
   channel-active fraction sits at 0.009-0.0102 and flickers across 0.01;
   a normal opaque app window is >10x above the new gate, so rejection
   power is preserved while boundary flicker is eliminated.
3. CPU expectation: SCStream cost scales with frame rate; at 3 fps the
   projected steady CPU is ~0.5-1.5% (vs 12% measured for 3 Hz one-shot).
   QA re-measures on the frozen SHA; the R7 budget (<= 5%, target <= 2%)
   is unchanged.

## Addendum 3 (2026-08-29, stream start-health watchdog)

Real-device QA of <pre-rewrite-id> uncovered a silent-start failure mode: the
app's SCStream existed but never delivered a single frame for 27+ minutes
(lsof: zero capture handles), so the channel delivered nothing and the
dock stayed hidden - with no log, counter, or wake signaling the failure.
Separately, a CLI probe on the same host showed SCK delivery is
nondeterministic across process attempts (0 frames vs 3.2 fps vs 60 fps
with identical configs), so start failures WILL happen and must be
recovered from, not just detected.

Changes:

1. First-frame watchdog: when a stream becomes active, require the first
   frame within `streamFirstFrameTimeout` = 2 s (about 6 expected frames
   at 3 fps). If no frame arrives in time: stop/retire the stream (same
   teardown as didStop), record a start-failure, and schedule a retry.
2. Retry backoff: consecutive failed starts back off exponentially
   (2 s -> 4 s -> 8 s, cap 8 s); any delivered frame resets the backoff.
   Backoff state is in-stream-runtime (reset on WID change/reset).
3. Failure visibility: count start failures in runtime evidence
   (`containerStreamStartFailureCount`, sanitized int, same conventions)
   and log each retirement via the existing logger. A silent hidden dock
   must never be the only symptom.
4. Frames-are-truth: mid-stream frame stalls are NOT watchdog-killed
   (a fully static window may legitimately deliver sparsely; observations
   are retention-based). Only the first-frame path is health-checked.

CPU note: watchdog + backoff add no steady-state cost (one monotonic
deadline check per locate). R7 budget unchanged; QA re-measures.

## Addendum 4 (2026-08-30, break-loop round 2: revert to one-shot)

Second consecutive substantive-finding round on the SCStream lifecycle
(R14: stale-snapshot race; R15: reset two-section gap + non-red test +
undeclared delta) despite the R10 lock-protocol redesign. Decision
(user-approved): abandon the managed SCStream transport; revert the
container capture to the simple one-shot design as of affee8ea
(R6/R12-approved lineage), with:

- stableCaptureInterval = 1.0 s (R7-amended tier; CPU ~4% expected,
  detection <= 1.2 s worst case; escalation tiers documented in PRD R7).
- KEPT from the SCStream era: opaqueFractionGate 0.02 (measured flicker
  fix), hidden-branch evidence flush, lifecycle logging (verbose-only),
  fresh-enumeration-per-attempt semantics (inherent to one-shot rounds),
  gate/edge/telemetry tests adapted to the one-shot path.
- REMOVED: managed SCStream transport, first-frame watchdog, retry
  backoff, streamEpoch identity machinery, stream lifecycle tests
  (T-cp83-99, T-cp109-117) - replaced by one-shot-path equivalents.
- The spec lock-protocol invariant (appkit-conventions.md) remains: it
  documents why the simpler transport won.

Implementation source of truth: the one-shot-era capture file is at
<pre-rewrite-id>:Sources/PetDock/ContainerPetChannel.swift (state as of affee8ea).
