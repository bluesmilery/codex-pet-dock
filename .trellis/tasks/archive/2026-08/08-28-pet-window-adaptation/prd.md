# Adapt pet tracking to post-update Codex window structure

## Goal

PetDock stops showing the dock base after the Codex host app auto-updated
(2026-08-28, ChatGPT.app 26.825.31414 build 7287). Adapt pet detection so the
dock base reappears and follows the pet under the new host window structure,
without regressing the existing standalone-Mascot-window path.

## Problem and evidence

- Old detection contract (PetTracker.selectPet): pet = small non-main window
  (pet-shaped / title contains "Mascot"). After the host update this window no
  longer exists (full CGWindowList enumeration of host pid, onscreen and
  offscreen: no Mascot, no "Codex Pet Composition Surface").
- The pet is still visible on screen. It is now rendered inside a huge host
  overlay window: host pid (bundle com.openai.codex), layer=3,
  approx 772x2549, mostly transparent.
- Feasibility probe (ScreenCaptureKit, in-memory alpha only): capturing that
  container window yields opaque fraction ~0.19%; the single opaque bbox maps
  to the visible pet location. So the pet position is recoverable with the
  same alpha-stats primitive already used by BubbleVisibilityProbe.
- PetDock process/loop itself is healthy: tick ran at hidden-state 1 s cadence
  (process sample), --diagnose reported no-pet:nonmain-notshaped.

## Requirements

- R1 Keep the existing detection chain (Mascot window / pet-shaped candidates)
  as the primary channel; it must keep passing all current tests unchanged.
- R2 Add a fallback container channel: when the primary channel finds no pet,
  locate the host pet-container window and derive a synthetic pet rect from
  its in-memory alpha bbox.
  - Container signature must be derived from observable window facts (host
    owner, onscreen, layer >= 2, non-main, very large area) plus a capture
    validation gate (opaque fraction below a small threshold), so unrelated
    large windows cannot hijack tracking.
  - No OCR, no saving images, no color/text recording: alpha stats only,
    consistent with the existing privacy contract.
- R3 The synthetic pet rect must feed the existing Follower/placement
  pipeline (stationary anchor, placeBelow, hide on disappearance) without
  forking the state machine.
- R4 Capture cadence must preserve the stable-state CPU profile: container
  capture runs on the probe-style cadence (1 Hz stable / event-driven
  retries), not per display-link frame.
- R5 --diagnose output must state which channel produced the selection and
  the container-window facts (no coordinates of user content).
- R6 Old-window structure and new-window structure must both work: if a real
  Mascot window exists, the container channel must not interfere.
- R7 (added 2026-08-28 after user acceptance testing): container-content
  changes (session bubble / control buttons appearing or disappearing inside
  the container window) must re-anchor the dock with detection latency
  <= 0.4 s p95 and a single smooth avoidance/movement glide (<= 200 ms),
  matching the pre-update obstacle-window responsiveness as closely as the
  capture-based channel allows. Steady-state PetDock CPU must stay <= 5%
  (target <= 2%) measured over >= 60 s with the channel active. If latency
  and CPU cannot both be met, STOP and report the tradeoff options instead of
  silently degrading either.
  - User report 2 (2026-08-28, screenshot): during bubble appearance the dock
    pill remains at its pre-bubble position and is occluded by the bubble
    (bubble is content INSIDE the container window - verified live: the host
    exposes no separate bubble window, so window-level avoidance is
    impossible; the dock can only detect growth via pixel capture). The
    detect-then-move transient overlap is inherent; acceptance is the R7
    latency bound plus user confirmation. If still unsatisfactory after R7,
    the next lever is stableCaptureInterval 0.33 -> 0.2~0.25 within the CPU
    budget (QA must measure CPU first).
- R7-amended (2026-08-30, break-loop round 2 decision, user-approved): the
  SCStream transport is abandoned after 3 unresolved P1-class concurrency
  findings across 3 review rounds (R10/R11/R14) plus 2 on-device failures
  (QA-4 CPU 12%, QA-7 silent stream start). The container channel reverts to
  the simple one-shot capture architecture as approved in R12, with
  stableCaptureInterval = 1.0 s: detection latency <= 1.2 s worst case,
  steady CPU expected ~4% (measured 12% at 3 Hz; scales linearly with
  cadence). Escalation path: raising to 1.5 Hz (~0.8 s / ~6% CPU) or 2 Hz
  (~0.6 s / ~8% CPU) is a one-constant change requiring explicit user
  approval since it exceeds the 5% cap. The 0.4 s p95 target is withdrawn.
  - R7-final (2026-08-31, user decision option 1): device QA measured 6.08%
    steady CPU at the 1.0 s tier on the vertical secondary display (region-
    tracked, panel present throughout). The user accepted this tier as-is:
    the container-channel CPU cap is amended to 7% for non-primary displays
    (primary-display operation measured lower), and detection stays at the
    1.0 s cadence. Escalation tiers (1.5 Hz / 2 Hz) remain available but
    require a new explicit decision.

## Acceptance Criteria

- [ ] AC1 Unit (pure): container-window selection accepts the new-structure
      candidate set and rejects main windows / normal-size helper windows /
      windows failing the opaque-fraction gate (mock capture outcomes).
- [ ] AC2 Unit (pure): alpha bbox -> synthetic pet rect mapping matches
      probe-verified geometry (capture-to-window rescale, Quartz mapping),
      including degenerate cases (no opaque pixels, opaque fraction above
      gate, single-pixel bbox).
- [ ] AC3 Unit: end-to-end tick orchestration with injected mock candidates +
      mock capturer shows hidden -> moving on synthetic pet appearance and
      moving -> hidden on disappearance, with plan outputs unchanged.
- [ ] AC4 Regression: all existing PetTracker/Follower/FollowTickPlan tests
      pass unmodified (primary channel semantics intact).
- [ ] AC5 swift build -c release 0 warning; make test green.
- [ ] AC6 Real-device verification on the updated host (26.825.31414): dock
      base reappears below the pet after PetDock launch (and after host
      restart), follows container-content movement at the designed cadence,
      and hides when the pet/container disappears. Explicitly report what was
      and was not verified.
- [ ] AC7 Unit: observation-change edge semantics - none->bounds fires the
      change callback once; bounds->same does not fire; bounds->different
      fires; each fire results in exactly one coalesced scheduler wake.
- [ ] AC8 Device: QA measures steady CPU (>= 60 s average) with the channel
      active, observes capture cadence via telemetry counters, and confirms
      change-driven re-anchor. Final subjective smoothness on bubble/control
      toggle is confirmed by the user (manual).

## Out of scope (this task)

- Pixel-level obstacle/bubble avoidance inside the container window beyond
  what the full-content bbox already provides (old bubble/control/CS obstacle
  windows no longer exist in the new structure). Phase 2 candidate:
  cluster-based obstacles from the same capture.
- High-rate (display-link) following of in-window pet movement; the pet is
  expected to move at capture cadence. (Amended by R7: capture cadence itself
  is now a tunable requirement, not a fixed 1 Hz.)

## Risks / open design points

- SCWindow.frame vs CGWindowList bounds origin mismatch observed during the
  probe (~50 px offset between two probes); design must pin global mapping to
  one authoritative source and verify on-device.
- Container window identity across host restarts (WID churn): revalidation
  via signature + capture gate; stale WID must degrade to hidden, not to a
  wrong anchor.
- Host future updates may change the container again: signature constants
  must live in one testable place (mirroring PetHeuristics).

## Notes

- Keep prd.md focused on requirements, constraints, and acceptance criteria.
- Lightweight tasks can remain PRD-only.
- For complex tasks, add design.md for technical design and implement.md for
  execution planning before task.py start.
