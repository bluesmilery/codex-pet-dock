# AC Evidence Topology

> Frozen-candidate evidence for `fix-dock-visibility-menu`. Baseline product SHA:
> `<pre-rewrite-id>` (= `feature/pet-window-adaptation` tip).
> Baseline red executed at `<pre-rewrite-id>` whose
> `Sources/ tests/ docs/` trees are identical to the approved base
> (`git diff <pre-rewrite-id>..<pre-rewrite-id> --stat -- Sources/ tests/ docs/` empty), plus an
> identifiable test-only patch to `tests/main.swift`.

| Symptom / AC | Evidence type | Trigger / disturbance | Approved baseline / result | Production consumer / path | Final owner / assertion | Command / result | Manual gap |
| --- | --- | --- | --- | --- | --- | --- | --- |
| AC1 baseline red (menu misfollow) | behavior | candidate snapshot: container 800x1600 layer3 + transient menu-shaped generic window (wid 541, layer 25, 220x260) while accepted container pet rect stays | base `<pre-rewrite-id>...` green pre-check `make test-ui` 556/0; test-only patch at `<pre-rewrite-id>...`: **T-mr0b FAIL** (actual frame `(660,420)` == menu-expected; selected=[nil,nil,541]), **T-mr0c FAIL** (two long jumps on open/close), exit 2 | `PetTracker.selectPet` generic fallback -> `Follower.decide` -> `FollowLayoutPass.placeDock` -> `DockPanel.placeBelow` inside real `FollowTickScheduler` tick closure | actual `DockPanel.frame` under menu, not under container pet rect | `make test-ui PYTHON=.venv/bin/python` (exit 2, 557 passed / 2 failed at baseline) | real-device sanitized trigger replay (QA) |
| AC2 container pet visible | behavior | container candidate only (no menu); first locate in-flight -> observation accepted | T-mr0a PASS on base (coverage gap for symptom pair; container path intact) | `ContainerPetProbe.locate` -> `onObservationChanged` -> `FollowTickScheduler.requestWake` -> tick -> `Follower.decide` -> `DockPanel.placeBelow` -> `showIfNeeded` | T-mr0a: `dock.isVisible`, actual frame `(80,690,200,48)` == pet-expected, routes=[container,container] | `make test-ui PYTHON=.venv/bin/python` (candidate) | ScreenCaptureKit/TCC equivalence on real host (QA) |
| AC3 menu open ignored | behavior | menu-shaped generic window added to candidate snapshot; container + accepted pet rect unchanged | T-mr0b FAIL on base (see AC1); PASS on candidate | same tick closure consumes production `PetSourceRouter.resolve` (test asserts route label `container` while raw `selectPet` still selects wid 541 — trigger equivalence for the independent-window class) | T-mr0b: actual frame stays `(80,690)` (pet-expected), NOT menu-expected `(660,420)`; `dock.isVisible` | `make test-ui PYTHON=.venv/bin/python` (candidate) | user opens real Codex menu on exact candidate; sanitized runtime outcome (QA) |
| AC4 menu close | behavior | transient generic window removed from snapshot | T-mr0c FAIL on base (frame jump back); PASS on candidate | resolver + existing container cache/generation -> tick -> `DockPanel.placeBelow` | T-mr0c: frame unchanged from menu-open phase, `lastWID == nil`, probe cache intact (`hasObservation`), selected last == nil | `make test-ui PYTHON=.venv/bin/python` (candidate) | user closes real menu (QA) |
| AC5 compatibility | behavior | strong Mascot + container; Mascot hysteresis; non-Mascot hysteresis; generic-only (no container); none-only | covered by T-mr1..T-mr8 + all 556 pre-existing tests green at base and on candidate | `PetTracker.selectPet` typed source -> `PetSourceRouter.resolve` -> existing primary/container layout channels | T-mr1/2 Mascot strong and beats container; T-mr3/4 hysteresis classification; T-mr6 generic kept without container; T-mr8 none -> hidden; existing Mascot/bubble/control/CS/anchor suites unchanged | `make test-ui PYTHON=.venv/bin/python` (candidate) | cross-display + feel (QA) |
| AC5b absence/wiring guards | static | source guards on router and production tick | new on candidate | `PetSourceRouter` (FollowTickPlan.swift) must not parse `reason`/`hitFlags`; main.swift must consume resolver and drop legacy order + `lastWID = sel.selected?.wid` | T-mr9 absence guard; T-mr10 wiring guard | `make test-ui PYTHON=.venv/bin/python` (candidate) | none |
| AC6 gates | build / test | frozen full candidate SHA | pending freeze | release build / all test entrypoints | `swift build -c release` 0 warnings; `make test` green; Review P0/P1/P2=0 | see delivery report | none |
| AC7 real-device | QA | normal pet -> open menu -> submenu (if any) -> close menu on exact candidate | pending QA | real CGWindowList/ScreenCaptureKit/TCC path | visible UI plus sanitized runtime outcome, reported separately from automated evidence | pending QA | inherently manual Codex menu action by user/QA |
| AC8 CPU / UX | QA | container channel active >= 60s; pet move; menu open/close | pending QA | production capture cadence (untouched: ContainerPetChannel thresholds/cadence not modified) | stable CPU within accepted tier; no jitter/long slide | pending QA | real-device measurement |

## Trigger provenance note

- Established planning evidence: installed v0.5.0 ships no container channel, so the
  screenshot-recorded menu-triggered relocation necessarily came from an independent
  CGWindowList window selected by the generic primary fallback (`independent-window`
  class). The regression injects exactly that class of candidate (small non-main
  onscreen window that satisfies `isReasonablePet`); T-mr4b asserts the raw selection
  would pick it while T-mr0b/T-mr5 prove the production resolver rejects it when a
  container candidate exists.
- The regression tick closure mirrors `AppDelegate.tick` and is driven by a real
  `FollowTickScheduler` (fake timers fired manually; probe observation wake wired to
  `scheduler.requestWake`). Assertions land on actual `DockPanel.frame` / visibility.
  `AppDelegate.tick` itself is not compiled into the test entry (app bootstrap), so the
  shared decision is the production `PetSourceRouter` consumed by both.
