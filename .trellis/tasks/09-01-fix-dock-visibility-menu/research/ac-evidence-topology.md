# AC Evidence Topology

> Planning skeleton. Implementation and formal QA must replace `pending` with exact commands and same-candidate evidence.

| Symptom / AC | Evidence type | Trigger / disturbance | Approved baseline / result | Production consumer / path | Final owner / assertion | Command / result | Manual gap |
| --- | --- | --- | --- | --- | --- | --- | --- |
| AC1 baseline: dock absent without menu | runtime + behavior | host exposes large container but no Mascot | `v0.5.0`; current diagnostic selects none | `CGWindowList → PetTracker.selectPet → Follower` | installed dock remains hidden | diagnostic confirmed `no-pet`; product-test baseline pending | exact candidate bright-display replay |
| AC2 container pet visible | behavior | accepted container observation | feature baseline pending | `ContainerPetProbe callback → FollowTickScheduler → resolver → Follower → FollowTickPlan` | actual `DockPanel.frame` visible below pet | pending | ScreenCaptureKit/TCC equivalence |
| AC3 menu ignored | behavior + runtime | transient generic menu candidate appears while container pet remains | feature baseline pending | `CGWindowList → primary/container resolver → scheduler tick` | same visible `DockPanel.frame`, not menu frame | pending | user opens menu; runtime trigger class |
| AC4 menu close | behavior + runtime | transient candidate disappears | feature baseline pending | resolver + existing container cache/generation → scheduler tick | frame remains/restores below pet without stale hysteresis | pending | user closes menu |
| AC5 compatibility | behavior | Mascot present; generic-only legacy; container pending; pet move | feature baseline pending | production resolver and existing layout channels | actual frame / visibility owner | pending | cross-display and feel |
| AC6 gates | build / test / review | frozen full candidate | pending | build and test entrypoints | zero warning; all suites green; P0/P1/P2=0 | pending | none |
| AC7 real-device | QA | normal → menu open → menu close on exact candidate | pending | real CGWindowList/SCK/TCC path | visible UI plus sanitized runtime outcome | pending | inherently manual Codex action |
| AC8 CPU / UX | QA | container active for at least 60 seconds | existing tier only; new candidate pending | production capture cadence and layout | average CPU within accepted tier; no long jump/jitter | pending | subjective smoothness |
