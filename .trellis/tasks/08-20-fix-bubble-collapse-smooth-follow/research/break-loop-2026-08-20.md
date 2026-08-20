# Bug Analysis: stable cadence phase and display-link liveness

## Evidence and Bayesian update

| Hypothesis | Prior | Discriminating evidence | Updated confidence |
| --- | ---: | --- | ---: |
| H1: probe/classifier alone causes remaining latency | 35% | 0.1s probe unit tests passed, but off-grid scheduler counterexample still exceeds 0.1s | 10% |
| H2: scheduler phase model omits external wake timing | 40% | 90ms wake + 20ms work crosses the 100ms phase deadline and schedules at 200ms | 80% |
| H3: display source is always live while panel is visible | 25% | AppKit contract says a window display link does not callback when the window is on no display | 10% as a valid assumption; 90% confidence the assumption must be removed |

The two second-review findings are supported by deterministic state examples and SDK contracts. Real-device frequency and frequency of occurrence remain unverified, but the recovery paths are structurally incomplete, so code changes are warranted.

## 1. Root Cause Category

- **Category**: D - Test Coverage Gap; E - Implicit Assumption; B - Cross-Layer Contract.
- **Specific Cause**: cadence tests covered phase-aligned starts but not an asynchronous visibility wake crossing a deadline. The AppKit adapter treated `isVisible` as proof that a window-bound display source remained live, although source liveness depends on `window.screen` and screen-change events.

## 2. Why Fixes Failed

1. **First candidate (`ee759ca`)**: changing the probe interval and adding a coalescer fixed callback backlog but not the after-work one-shot cadence. It addressed the symptom after classification, not the end-to-end scheduling bound.
2. **Second candidate (`6e3536a`)**: carrying a stable phase fixed phase-aligned work and ordinary missed deadlines, but the test state space omitted off-grid external wake. The fallback tests covered display-link creation failure, not an already-active link that silently stops receiving callbacks.
3. **Mental model error**: the review focused on which source was selected, not whether the selected source retained a future event capable of re-evaluating itself.

## 3. Prevention Mechanisms

| Priority | Mechanism | Specific Action | Status |
| --- | --- | --- | --- |
| P0 | Architecture | Compute stable deadline from each full tick's monotonic start; require next start by `max(deadline, workCompletedAt)`, with a missed deadline becoming one immediate latest-only tick | PLANNED |
| P0 | Runtime recovery | Require `panel.screen != nil` for display link and route window-screen changes into the coalesced wake path | PLANNED |
| P0 | Test matrix | Cover phase-aligned/off-grid wake × short/crossing/overrun work duration | PLANNED |
| P1 | Lifecycle tests | Cover active display link → no-screen fallback → display link recovery | PLANNED |
| P1 | Documentation | Record cadence and source-liveness contracts in macOS AppKit spec | DONE |

## 4. Systematic Expansion

- **Similar Issues**: any one-shot timer scheduled after work cannot claim a start-to-start upper bound; any AppKit source selected only from `isVisible` may lack a recovery event.
- **Design Improvement**: every scheduler state must answer both “which source is selected?” and “what future event proves it can recover if that source stops?”
- **Process Improvement**: formal timing reviews need a cross-product test matrix rather than isolated interval constants; display-source reviews need active-loss/recovery, not only factory-failure fallback.

## 5. Knowledge Capture

- [x] Updated `.trellis/spec/macos/appkit-conventions.md` with monotonic deadline, off-grid wake and display-source liveness requirements.
- [x] Updated task PRD/design/implementation plan and both context manifests.
- [x] Confirmed the generic template sync path `src/templates/markdown/spec/` does not exist in this application repository; no template copy is applicable.
- [ ] Implement red tests and minimal runtime changes in the existing implementation worktree.
- [ ] Start a fresh complete Review campaign on the new frozen SHA before QA.
