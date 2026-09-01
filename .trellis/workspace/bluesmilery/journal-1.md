# Journal - bluesmilery (Part 1)

> AI development session journal
> Started: 2026-08-13

---



## Session 1: Reorganize project documentation

**Date**: 2026-08-17
**Task**: Reorganize project documentation
**Branch**: `dev`

### Summary

Reorganized docs into architecture/development/verification, updated Trellis Codex guidance and dev validation boundaries, and passed independent review plus QA.

### Git Commits

| Hash | Message |
|------|---------|
| `85e2c9d7389a06990f997835c432aa100c63898e` | (see git log) |
| `42ddf19dc47a90db6bfd3eb07553777daa76d2a6` | (see git log) |

### Status

[OK] **Completed**


## Session 2: Add docs-as-code governance

**Date**: 2026-08-17
**Task**: Add docs-as-code governance
**Branch**: `dev`

### Summary

Added a documentation catalog, Trellis documentation rules, offline docs checker, regression tests, and Make quality gates; passed independent review and QA.

### Git Commits

| Hash | Message |
|------|---------|
| `102652f4500b5cad39165f7f6c5b5e773c78b806` | (see git log) |
| `22140c736c3989dfa863d5ced19930dfc5afdacb` | (see git log) |
| `3cecbcdf3cd4c67e491159ca3898db59e8b83bf6` | (see git log) |

### Status

[OK] **Completed**


## Session 3: 审计并清理本地分支与 worktree

**Date**: 2026-08-17
**Task**: 审计并清理本地分支与 worktree
**Branch**: `dev`

### Summary

确认无待合入 dev 内容；删除 67 个旧本地分支和 12 个旧 worktree，保留唯一 dirty diff 的恢复 stash；独立 Review 与 QA 均通过。

### Main Changes

- 仅保留 main 与 dev，本地主 worktree 唯一。
- main/dev/origin-main/v0.1.0 SHA 未漂移，未 push、未修改远端或 tag。

### Git Commits

(No commits - planning session)

### Testing

- [OK] 独立 Review APPROVED，P0/P1/P2=0；独立 QA ACCEPTED。

### Status

[OK] **Completed**

### Next Steps

- 后续如需恢复旧标题差异，使用保留的 cleanup-local-branches stash。


## Session 4: Harden runtime privacy boundaries

**Date**: 2026-08-18
**Task**: Harden runtime privacy boundaries
**Branch**: `dev`

### Summary

Hardened Trellis path/runtime boundaries, private diagnostics and logs, child-process environment trust, and path-free token cache; independent Review approved and QA accepted.

### Git Commits

| Hash | Message |
|------|---------|
| `e7a4bf8c7ed180f81f9dbccdbc2fbf1e808c386a` | (see git log) |
| `f59c7253354f1efc0681473b24aece5486745aa2` | (see git log) |
| `91120a1a5792cf0f09534ecb120ba6f2ae4bcc3e` | (see git log) |
| `1e6debbc243df5f07e3a8c27d2152717312c9063` | (see git log) |
| `77aa9c40db0e8ae4ad9dc63864c000d2580081a5` | (see git log) |
| `58d1bbb7c776b555df6a65f86f816f24a4642737` | (see git log) |
| `1801bcff7474bf6555a1d43ebc93a6683007efd8` | (see git log) |
| `c14d411749e24836de41053cefe21a118645f85b` | (see git log) |
| `0af2fe79aaa481015a8d9ecf074ad0cc46797511` | (see git log) |
| `68129dda36cd28b67849f27cd47eed5d4b1573b0` | (see git log) |

### Status

[OK] **Completed**


## Session 5: 修复录屏权限与底座跟随

**Date**: 2026-08-19
**Task**: 修复录屏权限与底座跟随
**Branch**: `dev`

### Summary

屏幕录制未就绪时门控 ScreenCaptureKit，气泡收起后立即唤醒布局，并将拖动跟随提升到约 60 Hz；独立 Review 与 QA 通过。

### Main Changes

- 加入进程内 permission request gate 与 preflight capture gate
- 气泡可见性变化通过主线程零延迟 bridge 唤醒布局
- moving 约 60 Hz、stable 0.1 秒并同步文档

### Git Commits

| Hash | Message |
|------|---------|
| `6e5081269af5f58969dd170ae84a06ef6cd9168e` | (see git log) |
| `255cb9e9722f635f3ac3978978c748bb6fce8271` | (see git log) |
| `8d23119b3dafd1066f8c83e8ca9763080bdfa614` | (see git log) |
| `eb0f25c496dde35a3d3bacfeb03c87592f865b6a` | (see git log) |

### Testing

- [OK] release build 0 warning；450 项自动检查通过；ad-hoc app 签名验证通过

### Status

[OK] **Completed**

### Next Steps

- 真实 TCC、ScreenCaptureKit、拖动体感、多屏、macOS 13 与 Instruments 仍需真机验证


## Session 6: 恢复 Trellis 官方 Git 管理策略

**Date**: 2026-08-20
**Task**: 恢复 Trellis 官方 Git 管理策略
**Branch**: `dev`

### Summary

恢复官方 ignore 和自动提交边界，纳入并脱敏 task/workspace 资料，经 Grok Review 与 QA 通过后集成到 dev，并清理未使用的 .claude 本机文件。

### Git Commits

| Hash | Message |
|------|---------|
| `09991023f5e75e873f6c7957834f99145c9b72e3` | (see git log) |
| `566c1921a34f1e021a989f55786034bec29755b1` | (see git log) |
| `d82f6b28e149348fef56a05963390d9e7c11dd1c` | (see git log) |
| `3fa834980db46cb00c20d0dc8182234cb6aadfff` | (see git log) |

### Status

[OK] **Completed**


## Session 7: 调整子 Agent 模型选择规则

**Date**: 2026-08-20
**Task**: 调整子 Agent 模型选择规则
**Branch**: `dev`

### Summary

允许任务显式指定子 Agent 模型和推理强度，未指定项默认使用 luna 和 max；同步 AGENTS 与 Trellis workflow，并通过文档检查和独立只读复核。

### Git Commits

| Hash | Message |
|------|---------|
| `cd38b03` | (see git log) |

### Status

[OK] **Completed**


## Session 8: 完成底座统计与详情卡视觉优化

**Date**: 2026-08-21
**Task**: 完成底座统计与详情卡视觉优化
**Branch**: `dev`

### Summary

完成 Week Tokens 下部垂直居中、详情卡居中与紧凑双列表格；修复点击贴边 clamp 和动态 note 高度。候选 fdef0e09 经 Review 清零、完整自动门禁和真机展开收起重开视觉 QA 后集成 dev；同时补充活跃子 Agent 不催促及五分钟轮询规则。

### Git Commits

| Hash | Message |
|------|---------|
| `bc3c52f` | (see git log) |
| `f547229` | (see git log) |
| `ff098a4` | (see git log) |
| `22fad6d` | (see git log) |
| `835588f` | (see git log) |
| `f81d27e` | (see git log) |
| `66750f4` | (see git log) |
| `9556ba0` | (see git log) |
| `2db5466` | (see git log) |

### Status

[OK] **Completed**


## Session 9: perf-startup-idle-cpu L2 delivery

**Date**: 2026-08-26
**Task**: perf-startup-idle-cpu L2 delivery
**Branch**: `codex/perf-startup-idle-cpu`

### Summary

Token v3 tail-incremental parsing (207-entry migration verified), bubble 1s stable heartbeat + shared SCShareableContent, 5s first-refresh delay. R1 NOT APPROVED (P0 evidence/P1 short-read+docs/P2 tests) -> fixed -> R2 APPROVED P0P1P2=0. Runtime QA: pet-visible stationary CPU 0.0% (was 20-30%), 5-min incremental refresh no spike, TCC carried. Candidate 2026-08-26-004500-perf-startup-idle-cpu-8dc8f48 left running for user acceptance. Feature parked at feature/perf-startup-idle-cpu.

### Git Commits

| Hash | Message |
|------|---------|
| `8dc8f48ed67fdd391964b34178c47111417c625d` | (see git log) |

### Status

[OK] **Completed**


## Session 10: drag-freeze fix + stable backoff rounds

**Date**: 2026-08-26
**Task**: drag-freeze fix + stable backoff rounds
**Branch**: `codex/perf-startup-idle-cpu`

### Summary

P0 drag freeze root-caused to baseline display-link starvation (f62bfd9), fixed with 0.25s moving watchdog (58e2ce3, r2 APPROVED). Stable backoff shipped at approved 0.2s floor after r3 caught 0.5s supervisor spec typo; T-sch6c reworked through real Follower.decide chain as regression guard; r5 APPROVED. Stationary CPU 28%->17.6%; remaining cost is per-tick CGWindowList dictionary parsing, future enum-slimming candidate. All sub-agents used native multi-agent spawn (no child sessions) per user instruction.

### Git Commits

| Hash | Message |
|------|---------|
| `1a8432311aba77d1729faa1f1a9a909587c7bc55` | (see git log) |

### Status

[OK] **Completed**


## Session 11: onscreen enumeration + cache cap rounds R6-R8

**Date**: 2026-08-26
**Task**: onscreen enumeration + cache cap rounds R6-R8
**Branch**: `codex/perf-startup-idle-cpu`

### Summary

User rejected 0.2s backoff latency; reverted to 0.1s and slimmed enumeration to optionOnScreenOnly (8.6ms/602 to 1.26ms/56, offscreen windows proven unconsumed via T-enum safety nets). QA then caught v3 cache 1.29MB exceeding the 1MiB read cap reproducing the original 28s 100% startup; raised cap to 8MiB with persist guard (T3h/T3i). Final QA: launch 13-15% incl first refresh, steady ~13% at 10Hz. r6/r7/r8 APPROVED; feature parked at 3eee158.

### Git Commits

| Hash | Message |
|------|---------|
| `3eee15895f98174c34459c2df77e954f75da9444` | (see git log) |

### Status

[OK] **Completed**


## Session 12: SC onscreen-only probe list R9-R10

**Date**: 2026-08-26
**Task**: SC onscreen-only probe list R9-R10
**Branch**: `codex/perf-startup-idle-cpu`

### Summary

Research round sampled remaining steady CPU: SCShareableContent full-window list (610 windows, 117ms/call) spent 6.2% building SCWindow objects for windows that can never be probe candidates (same-owner rule + upstream onscreenOnly). Switched to onScreenWindowsOnly (57 windows, 29.5ms); sample share dropped to 1.0%, steady CPU 16-18% -> ~15%. Remaining cost is captureImage pixels at the 1Hz heartbeat floor. r10 APPROVED; feature parked at e808b52.

### Git Commits

| Hash | Message |
|------|---------|
| `e808b52a27c6a778b418a95216b520ec425cab70` | (see git log) |

### Status

[OK] **Completed**


## Session 13: v0.4.0 release: merge, gates, privacy scrub, publish

**Date**: 2026-08-26
**Task**: v0.4.0 release: merge, gates, privacy scrub, publish
**Branch**: `codex/perf-startup-idle-cpu`

### Summary

Dedicated merge session: feature/perf-startup-idle-cpu (16 commits) merged into dev with no-ff (single add/add conflict on task.json resolved to feature side); merged gates re-run green (406/139/99, 0 warnings); scrubbed 4 local interpreter paths from evidence docs; bumped 0.4.0; release candidate archived 2026-08-26-183000-release-v0.4.0-3db4476, stable-signed, bundle clean of local paths; main fast-forwarded and pushed via hook-compliant single-ref push; v0.4.0 tag created via GitHub API release; asset SHA-256 verified byte-identical (4b9c8a5d...).

### Git Commits

| Hash | Message |
|------|---------|
| `3db44765f268dda13f43b32db94453c081214c47` | (see git log) |

### Status

[OK] **Completed**


## Session 14: v0.4.0 history scrub: rewrite instead of follow-up commits

**Date**: 2026-08-26
**Task**: v0.4.0 history scrub: rewrite instead of follow-up commits
**Branch**: `dev`

### Summary

User identified that follow-up scrub commits leave leaks in ancestor trees (28 commits on remote main contained local paths; net-diff scanning cannot catch them). Executed history rewrite per v0.2.0 precedent: backup tag + external bundle, filter-branch placeholder substitution on a7639db..main (28 commits), per-commit tree scan all clean, final-tree diff limited to placeholder lines (product code untouched, zip asset still valid), force-with-lease push, tag repointed via API (release re-published after tag recreation flipped it to draft), stale branches/worktree cleaned. Release doc rewritten: section 3 per-commit tree scanning, section 4 leak remediation = history rewrite never follow-up commits, seven-step procedure recorded.

### Git Commits

| Hash | Message |
|------|---------|
| `0dc2df4c02fd520c8de53d9e6fc814397ab11ccf` | (see git log) |

### Status

[OK] **Completed**


## Session 15: English-only commit messages: rule + full-history rewrite

**Date**: 2026-08-26
**Task**: English-only commit messages: rule + full-history rewrite
**Branch**: `dev`

### Summary

User set a new rule: commit messages must be English-only, and asked history to comply. Scanned all 212 commits on main: subjects were already English but 41 messages (v0.1.0-v0.3.0 era) carried Chinese subjects/bodies. Translated all 41 via a verified exact-match mapping (41/41 hit before rewrite), rewrote with filter-branch --msg-filter on a temp branch: 212 commits checked zero CJK, tree diff empty vs old chain, merges preserved 5/5. Added the English-message rule to AGENTS.md, force-pushed (force-with-lease), repointed all four tags via GitHub API with tree+subject-verified mapping, re-published releases (tag recreation flips drafts), cleaned backups per user preference.

### Git Commits

| Hash | Message |
|------|---------|
| `e6f5e80401f1115b69105447f41f53d23a36a5b6` | (see git log) |

### Status

[OK] **Completed**


## Session 16: Park CS live-layer anchor on feature/cs-live-layer-anchor

**Date**: 2026-08-27
**Task**: Park CS live-layer anchor on feature/cs-live-layer-anchor
**Branch**: `feature/cs-live-layer-anchor`

### Summary

Accepted live-layer CS dock anchor with idle-CPU follow-up; parked 85d8352 on feature/cs-live-layer-anchor after Review P0/P1/P2=0 and real-device GO. Not merged to dev.

### Main Changes

- Select live CS via Mascot consistency window; reference channel captures Mascot only at 1Hz when stable
- Keep DockPanel/Follower smoothness and idle cadence; do not double-capture CS

### Git Commits

| Hash | Message |
|------|---------|
| `85d83529fbc76ff1da4f2dfa9f690a1c4b3a709c` | (see git log) |

### Testing

- [OK] UI 5x414/0; release 0 warning; real-device AC5/AC6 GO on archived 85d8352 app

### Status

[OK] **Completed**

### Next Steps

- Dedicated integration session: serial merge feature/cs-live-layer-anchor into local dev


## Session 17: Merge CS live-layer anchor into local dev for release

**Date**: 2026-08-28
**Task**: Merge CS live-layer anchor into local dev for release
**Branch**: `dev`

### Summary

no-ff merged feature/cs-live-layer-anchor into local dev. Merge SHA 4061f03 is a new candidate; parked accepted SHA 85d8352 is now a dev ancestor. Release scan/gates still pending on the final tree after this journal.

### Main Changes

- git merge --no-ff feature/cs-live-layer-anchor; no overlapping files, no conflicts

### Git Commits

| Hash | Message |
|------|---------|
| `4061f0311a8eda7a2917c6f96015f6f08265830d` | (see git log) |

### Testing

- [OK] not re-run yet; merge SHA is a new candidate per release.md section 1.3

### Status

[OK] **Completed**

### Next Steps

- Sensitive scan of merge-base..dev, then full gates, then version bump and GitHub Release after user confirmation of tag/push


## Session 18: Release v0.6.0: pet-window-adaptation

**Date**: 2026-08-31
**Task**: Release v0.6.0: pet-window-adaptation
**Branch**: `codex/pet-window-adaptation`

### Summary

Container-channel pet tracking for the post-update Codex host: 1Hz region-tracked one-shot capture, 8px bbox + 6px placement deadbands, cubic-Bezier glide; 26 review rounds + 13 QA runs; merged to dev and main, tagged v0.6.0, GitHub release published

### Git Commits

| Hash | Message |
|------|---------|
| `<pre-rewrite-id>` | (see git log) |

### Status

[OK] **Completed**


## Session 19: Release v0.5.0 wrap-up: pet-window-adaptation shipped

**Date**: 2026-09-01
**Task**: Release v0.5.0 wrap-up: pet-window-adaptation shipped
**Branch**: `main`

### Summary

v0.5.0 released (pet-window adaptation for the post-update Codex host): version history renumbered per user decision (0.6.0 bump dropped, v0.4.0 published as prerelease), privacy history rewrite completed (33 leaking commits scrubbed, 261 commits rescan-clean), feature parked, candidate archived, worktrees and temp branches cleaned

### Git Commits

| Hash | Message |
|------|---------|
| `<pre-rewrite-id>` | (see git log) |

### Status

[OK] **Completed**


## Session 20: 修复底座消失与菜单误跟随

**Date**: 2026-09-01
**Task**: 修复底座消失与菜单误跟随
**Branch**: `feature/pet-window-adaptation`

### Summary

在容器宠物存在时以类型化来源路由压制通用菜单窗口，保持底座稳定锚定真实宠物；完成可重放基线红测、独立 Review、签名候选、CPU 采样及用户三态验收。

### Git Commits

| Hash | Message |
|------|---------|
| `<pre-rewrite-id>` | (see git log) |
| `<pre-rewrite-id>` | (see git log) |
| `<pre-rewrite-id>` | (see git log) |
| `<pre-rewrite-id>` | (see git log) |

### Status

[OK] **Completed**
