# Root-cause research

## Permission prompt loop

- `Sources/PetDock/main.swift` explicitly requests screen capture once at launch when preflight is false.
- `Sources/PetDock/BubbleVisibility.swift` independently runs `SCShareableContent` and `SCScreenshotManager` from a probe that can be scheduled every 0.5 seconds.
- The probe has no preflight gate today. Therefore a not-yet-effective or denied grant can still reach ScreenCaptureKit repeatedly after the one explicit launch request.
- Preserve the existing status-bar warning and nil=>visible privacy/safety behavior; stop the repeated API entry, not the conservative fallback.

## Bubble collapse lag/stickiness

- Layout consumes `bubbleProbe.visibility(for:)` only during follow ticks.
- The asynchronous capture updates cache without waking the follow loop. In stable state the next layout read can be delayed by the 0.5-second stable timer.
- If capture cannot run, nil intentionally remains visible forever while the candidate exists. Permission gating must prevent prompts, while a successful collapsed capture must promptly wake the existing layout path.

## Drag latency

- `Follower.stableInterval` is 0.5 seconds, so initial drag detection can lag by that amount.
- `Follower.movingInterval` is 0.05 seconds (20 Hz), visibly below display cadence.
- A timer-only change is the smallest public-API solution. Global input monitors would add an unrelated permission/risk surface and are out of scope.

## Contracts not to regress

- Candidate disappearance via `knownWids` immediately returns hidden.
- Capture failure remains visible conservatively.
- Reset/generation prevents stale async writes; strict single-flight remains bounded.
- All AppKit frame changes stay on the main thread.

