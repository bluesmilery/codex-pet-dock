# AC Evidence Topology

> Frozen-candidate evidence for `fix-dock-visibility-menu`. Baseline product SHA:
> `<pre-rewrite-id>` (= `feature/pet-window-adaptation` tip).
> Baseline red executed at `<pre-rewrite-id>` whose
> `Sources/ tests/ docs/` trees are identical to the approved base
> (`git diff <pre-rewrite-id>..<pre-rewrite-id> --stat -- Sources/ tests/ docs/` empty), plus an
> identifiable test-only patch to `tests/main.swift`.
>
> Baseline red provenance: the replayable, non-executable test-only artifact is
> `research/baseline-red-tests-only.patch` (sha256
> `7a625c070b14a1c6ba3dd3034a0369e28d28ab31f8fc2b5583ab0bae3ef95f04`), generated
> relative to the approved base and touching only `tests/main.swift` (+203 lines).
> It contains no `PetSourceRouter` / `SelectionResult.source` usage. Do NOT apply the
> current candidate `tests/main.swift` diff to the base — it compile-depends on the new
> API; the standalone artifact above is the replayable baseline evidence.

| Symptom / AC | Evidence type | Trigger / disturbance | Approved baseline / result | Production consumer / path | Final owner / assertion | Command / result | Manual gap |
| --- | --- | --- | --- | --- | --- | --- | --- |
| AC1 baseline red (menu misfollow) | behavior | candidate snapshot: container 800x1600 layer3 + transient menu-shaped generic window (wid 541, layer 25, 220x260) while accepted container pet rect stays | base green pre-check `make test-ui` 556/0; artifact replay on clean detached base `<pre-rewrite-id>...`: **T-mr0b FAIL** (actual frame `(660,420)` == menu-expected; selected=[nil,nil,541]), **T-mr0c FAIL** (two long jumps on open/close); all other checks green | `PetTracker.selectPet` generic fallback (base order: selectPet incl. generic first, container only when pet==nil) -> `Follower.decide` -> `FollowLayoutPass.placeDock` -> `DockPanel.placeBelow` inside real `FollowTickScheduler` tick closure | actual `DockPanel.frame` under menu, not under container pet rect | replay commands below (exit 2, 557 passed / 2 failed) | real-device sanitized trigger replay (QA) |
| AC2 container pet visible | behavior | container candidate only (no menu); first locate in-flight -> observation accepted | T-mr0a PASS on base (coverage gap for symptom pair; container path intact) | `ContainerPetProbe.locate` -> `onObservationChanged` -> `FollowTickScheduler.requestWake` -> tick -> `Follower.decide` -> `DockPanel.placeBelow` -> `showIfNeeded` | T-mr0a: `dock.isVisible`, actual frame `(80,690,200,48)` == pet-expected, routes=[container,container] | `make test-ui PYTHON=.venv/bin/python` (candidate) | ScreenCaptureKit/TCC equivalence on real host (QA) |
| AC3 menu open ignored | behavior | menu-shaped generic window added to candidate snapshot; container + accepted pet rect unchanged | T-mr0b FAIL on base (see AC1); PASS on candidate | same tick closure consumes production `PetSourceRouter.resolve` (test asserts route label `container` while raw `selectPet` still selects wid 541 — trigger equivalence for the independent-window class) | T-mr0b: actual frame stays `(80,690)` (pet-expected), NOT menu-expected `(660,420)`; `dock.isVisible` | `make test-ui PYTHON=.venv/bin/python` (candidate) | user opens real Codex menu on exact candidate; sanitized runtime outcome (QA) |
| AC4 menu close | behavior | transient generic window removed from snapshot | T-mr0c FAIL on base (frame jump back); PASS on candidate | resolver + existing container cache/generation -> tick -> `DockPanel.placeBelow` | T-mr0c: frame unchanged from menu-open phase, `lastWID == nil`, probe cache intact (`hasObservation`), selected last == nil | `make test-ui PYTHON=.venv/bin/python` (candidate) | user closes real menu (QA) |
| AC5 compatibility | behavior | strong Mascot + container; Mascot hysteresis; non-Mascot hysteresis; generic-only (no container); none-only | covered by T-mr1..T-mr8 + all 556 pre-existing tests green at base and on candidate | `PetTracker.selectPet` typed source -> `PetSourceRouter.resolve` -> existing primary/container layout channels | T-mr1/2 Mascot strong and beats container; T-mr3/4 hysteresis classification; T-mr6 generic kept without container; T-mr8 none -> hidden; existing Mascot/bubble/control/CS/anchor suites unchanged | `make test-ui PYTHON=.venv/bin/python` (candidate) | cross-display + feel (QA) |
| AC5b absence/wiring guards | static | source guards on router, production tick and diagnose | new on candidate | `PetSourceRouter` (FollowTickPlan.swift) must not parse `reason`/`hitFlags`; main.swift tick + `runDiagnoseAndExit` must consume the same resolver and drop legacy order + `lastWID = sel.selected?.wid` + diagnose `channel = "primary"` direct report | T-mr9 absence guard; T-mr10 wiring guard; T-mr11..13 diagnose routing/guard | `make test-ui PYTHON=.venv/bin/python` (candidate) | none |
| AC6 gates | build / test | frozen full candidate SHA | pending freeze | release build / all test entrypoints | `swift build -c release` 0 warnings; `make test` green; Review P0/P1/P2=0 | see delivery report | none |
| AC7 real-device | QA | normal pet -> open menu -> submenu (if any) -> close menu on exact candidate | pending QA | real CGWindowList/ScreenCaptureKit/TCC path | visible UI plus sanitized runtime outcome, reported separately from automated evidence | pending QA | inherently manual Codex menu action by user/QA |
| AC8 CPU / UX | QA | container channel active >= 60s; pet move; menu open/close | pending QA | production capture cadence (untouched: ContainerPetChannel thresholds/cadence not modified) | stable CPU within accepted tier; no jitter/long slide | pending QA | real-device measurement |

## Baseline replay commands (executed 2026-09-01, fresh temp detached worktrees; since cleaned up)

```text
git worktree add --detach <tmp-baseline-gen> <pre-rewrite-id>
# insert baseline-only C8 block into <tmp-baseline-gen>/tests/main.swift (old base tick order mirror,
# no new API), then: git -C <tmp-baseline-gen> diff -- tests/main.swift > research/baseline-red-tests-only.patch
git worktree add --detach <tmp-baseline-replay> <pre-rewrite-id>
git -C <tmp-baseline-replay> apply --check research/baseline-red-tests-only.patch   # ok
git -C <tmp-baseline-replay> apply research/baseline-red-tests-only.patch          # +203 lines, only tests/main.swift
cmp <tmp-baseline-gen>/tests/main.swift <tmp-baseline-replay>/tests/main.swift      # identical
make -C <tmp-baseline-replay> test-ui PYTHON=<project-python>
```

Actual replay result: **exit 2**; `=== 总计 557 passed, 2 failed ===`; failing checks:
`T-mr0b 菜单打开` (frame `(660,420)` == menu-expected, selected=[nil,nil,541]) and
`T-mr0c 菜单关闭` (frame jumps back to `(80,690)`); `T-mr0a` and all 556 pre-existing
checks green. Both temp worktrees removed afterwards (`git worktree remove --force`,
dirty state was only the patch-applied `tests/main.swift`, byte-preserved in the artifact).

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
