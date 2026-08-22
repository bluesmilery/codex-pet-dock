# Research: review-loop optimization affected surfaces

- Query: Map the smallest local file set for the agreed review-loop optimization, including Review Readiness Gate, exhaustive batched read-only Review, one consolidated repair batch, two-round fuse with break-loop escalation, QA only after review clearance, separation from auto-fixing `trellis-check`, and the confirmed L1 lightweight path.
- Scope: internal
- Date: 2026-08-19

## Findings

### Current contract and direct conflicts

| Surface | Evidence | Implication |
| --- | --- | --- |
| Project policy | `AGENTS.md:32-46` makes the main session an orchestrator, requires independent implement/Review/QA agents, and says formal Review is read-only (`:40-42`); `AGENTS.md:55-62` makes release build, `make test`, P0/P1/P2 clearance, SHA binding, and real-device QA gates. | This is the durable project contract to extend with L1/L2 classification, readiness, batched findings, repair batching, round fuse, and QA ordering. |
| Shared workflow | `.trellis/workflow.md:152-156` only triages simple/complex requests; `:187-228` defines one `in_progress` flow and dispatches `trellis-implement -> trellis-check`; `:469-557` has 2.1 implement, 2.2 repeatable check, and a final full-scope pass. | The workflow does not distinguish L1 vs L2, does not define a readiness gate, and currently says the check agent auto-fixes (`:534-542`). Add the decision and round boundaries here first; keep workflow-state tag text synchronized with the phase body. |
| Generic check skill | `.agents/skills/trellis-check/SKILL.md:39-41` says to fix check failures; `:96-98` says “fix them directly” and rerun checks. | This is the exact source of the auto-fix/formal-review collision. It is present in `.trellis/.template-hashes.json:4-11`, so editing it is an upstream-template conflict. Prefer keeping it as a mechanical/self-check capability and route formal Review through a separate read-only contract. |
| Codex reviewer | `.codex/agents/trellis-check.toml:1-5` describes a workspace-write self-fixing reviewer; `:26-39` requires direct fixes. | Current Codex auto mode needs a local reviewer instruction change (or a new project-local reviewer role) so formal Review cannot mutate the candidate. This file is already marked user-modified by `trellis update --dry-run`; preserve the existing model/recursion guard while changing only review behavior. |
| Native vs generic hook paths | Native Codex context is only a wrapper at `.codex/hooks/inject-subagent-context.py:875-893`; it does not add self-fix instructions. The generic hook path builds self-fixing check prompts at `:667-699` and selects that path at `:1124-1133`. | For the active Codex native path, `.codex/agents/trellis-check.toml` plus workflow is the minimal runtime change. If the project promises the other generated platforms too, update `build_check_prompt` and the corresponding agent cards; otherwise they will still auto-fix. |
| Channel reviewer | `.trellis/agents/check.md:23-30` and `:40-48` explicitly self-fix. | Optional channel workers remain inconsistent with a read-only formal Review. Update this only if the project will use `trellis channel spawn --agent check`; it is a separate platform-neutral card, not the native Codex agent. |
| Resume/entry routing | `.agents/skills/trellis-continue/SKILL.md:30-45` routes solely by status and artifact presence; `.agents/skills/trellis-start/SKILL.md:41-50` treats PRD-only as “lightweight” only for planning. `.codex/hooks/session-start.py:287-304` emits the same planning-only distinction and `:513-518` only says optional artifacts are skipped for lightweight tasks. | L1 bypass cannot be inferred from current status. Add an explicit planning field/decision (for example `Delivery path: L1 | L2`, defaulting to L2 when absent/ambiguous) and synchronize continue/start/session guidance. Do not add a custom task status unless also changing the route table and hook contract. |
| Task metadata | `task_store.py:216-239` only documents PRD-only lightweight tasks; `:410-434` creates `dev_type: null` and arbitrary `meta`; `task.py:551-555` exposes `set-meta`. | A metadata marker is available without schema changes, but current compact context does not print all metadata (`session_context.py:682-705`; record mode includes it at `:813-837`). A human-readable PRD field is the smallest safe first version. If machine-enforced routing is required, add a typed execution-path field plus context/hook tests as a separate change. |

### Recommended ownership and minimal edit set

**Required durable surfaces for the active Codex project (L1/L2 semantics):**

1. `AGENTS.md` — define the two paths and fail-closed rule; add the Review Readiness Gate; require a frozen complete SHA before formal Review; require the reviewer to exhaust the whole assigned scope and report all P0/P1/P2 findings in one batch; return one consolidated repair list to the original implementer; allow at most two formal Review rounds; on a new substantive finding in round three, invoke `trellis-break-loop` and revisit design/requirements/tests; run formal QA only after Review is clear; state that L1 uses direct main-session edits, automated static checks, and exactly one independent read-only consistency check.
2. `.trellis/workflow.md` — change Phase 2 from the current single implement/check loop to: classify path in planning → L1 direct edit/static/one read-only consistency check, or L2 readiness → implementation → mechanical self-check → frozen SHA → exhaustive read-only Review → one batched repair → final read-only Review → formal QA. Update Phase 3.2 to be the round-fuse escalation rather than only a retrospective. Update `[workflow-state:in_progress]` and `in_progress-inline` bodies because the breadcrumb is the per-turn source of truth (`.trellis/workflow.md:99-121`, `:653-671`). Keep Phase 3.4 commit reachable for both paths.
3. `.trellis/spec/macos/quality-guidelines.md` — encode the executable quality boundary: `Docs Impact`, release/docs gates, L1 vs L2 evidence, read-only formal Review, and the rule that automated checks and static conclusions are distinct from true QA. This is an un-hashed project spec and is the right place for durable quality constraints, not the bundled skill.
4. `docs/development/trellis.md` — document the user-facing path selection and what “lightweight” means; link to the canonical rules instead of duplicating product facts. `docs/README.md` already lists this page as the single source (`:9-15`), so no catalog change is needed if the path remains the same.

**Codex formal-Review surface:**

- Minimal current-platform option: update `.codex/agents/trellis-check.toml` so the dispatched profile is a report-only, exhaustive formal reviewer; retain the bundled `trellis-check` skill as mechanical/self-check only and state this separation in the workflow. This is the least moving parts for the active native Codex hook path.
- Stronger isolation option: add a project-local `trellis-review` agent/skill with read-only sandbox and route only formal Review to it. This requires synchronizing `.codex/hooks.json` (matcher currently only accepts implement/check/research at `:14-23`) and `.codex/hooks/inject-subagent-context.py` agent constants/context dispatch (`:65-72`, `:920-941`, `:1124-1133`), so it is not the minimal change. Use it only if an independently named role is required.

**Only if non-Codex or channel parity is in scope:**

- `.trellis/agents/check.md` (channel worker) and `.codex/hooks/inject-subagent-context.py` generic `build_check_prompt` need the same report-only/exhaustive wording.
- Other platform agent files are not present in this checkout; do not invent `.claude/` files (at that baseline, the project ignored them). `docs/development/trellis.md:3-5` confirms Codex is the active tracked platform.

**Avoid changing unless automation is explicitly requested:**

- `.trellis/scripts/common/session_context.py`, `task.py`, `task_store.py`, or `inject-workflow-state.py`. A new machine-readable execution status would require these files plus fixtures/contract tests and would expand the task from process guidance into Trellis runtime behavior. The existing arbitrary task `meta` and PRD are sufficient for a fail-closed human/planning gate.
- Do not add a new task status such as `in-review` for this optimization. The route table in `.agents/skills/trellis-meta/references/customize-local/change-workflow.md:46-61` and the workflow-state hook would both need extension; round evidence can live in task artifacts/Review reports instead.

### L1/L2 classification and fail-closed bypass

Use an explicit field in the planning artifact (recommended wording: `Delivery path: L1 | L2`) and require the main session to restate it before `task.py start`.

- **L1 (lightweight/non-development):** docs/spec/workflow/process-only edits with no production source, tests that define runtime behavior, Makefile/build script, hook/runtime script, API/data contract, privacy/security boundary, or user-visible app behavior. The main session edits directly; run targeted automated/static checks; then use one independent read-only consistency check over the complete diff. No implement/fix/QA worktree loop and no dev-candidate claim.
- **L2 (full development):** any Swift/source/test runtime change, Makefile/build or hook/script behavior, API/data/schema/contract change, privacy/security/TCC/ScreenCaptureKit change, cross-layer change, release/distribution artifact, or uncertain scope. Use the complete readiness → batched Review → repair → final Review → formal QA loop.
- **Fail closed:** absent, ambiguous, or stale path classification defaults to L2. If an L1 diff later touches an L2 path, promote the task immediately and invalidate the L1 check. A failed targeted check, a consistency finding, or a dirty/unrecognized path also blocks bypass until the main session resolves it and reruns the applicable gate.
- `docs/verification/dev-candidate.md:13-30` and `:201-203` remain L2 candidate gates; an L1 process/doc change is not a dev candidate and must not be reported as having passed independent Review + QA.

### Validation and test infrastructure

Run these after implementation, matching the actual changed surfaces:

1. Workflow parsing/routing: `python3 ./.trellis/scripts/get_context.py --mode phase`; `python3 ./.trellis/scripts/get_context.py --mode phase --step 2.2 --platform codex` (and each newly added step); verify every `[workflow-state:STATUS]` has matching tags and required steps remain reachable.
2. Docs/spec: `PYTHONDONTWRITEBYTECODE=1 make docs-check`; `PYTHONDONTWRITEBYTECODE=1 make test-docs`; `git diff --check`. `Makefile:57-68` defines the offline docs gates and `make test` composition. `docs-check` scans public README/docs/spec Markdown only; it will not validate `AGENTS.md`, `.trellis/workflow.md`, `.agents/skills`, or `.codex/agents` semantics.
3. Codex/platform: `trellis platforms`; `trellis update --dry-run`; inspect the generated-file conflict report and ensure no `.new`/overwrite was accepted. For TOML/hook edits, run the applicable Python import/fixture tests (`PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q tests/test_runtime_privacy.py`) and a read-only smoke invocation of the hook with fixture input if added.
4. Full L2 gate remains `swift build -c release`, `make docs-check`, `make test-docs`, `make test`, plus real-device QA; these are stated in `.trellis/spec/macos/quality-guidelines.md:7-13` and `docs/verification/dev-candidate.md:13-30`.

There is no dedicated workflow-contract test in this checkout: only `tests/test_check_docs.py` and `tests/test_runtime_privacy.py` were found. If workflow-state or hook code is changed, add a focused parser/route fixture test or record that the semantic review is static-only.

### Generated/customization boundaries and update risk

- `.trellis/.template-hashes.json:4-11,50-60,89` tracks the bundled skills, Codex agents, hooks, and workflow. `.agents/skills/trellis-check`, `.agents/skills/trellis-start`, `.agents/skills/trellis-continue`, `.codex/agents/trellis-check.toml`, `.codex/hooks/inject-subagent-context.py`, `.trellis/agents/check.md`, and `.trellis/workflow.md` are therefore update-sensitive. `.trellis/spec/**`, `AGENTS.md`, and `docs/**` are project-owned and not hash entries.
- `trellis update --dry-run` (CLI 0.6.14; npm latest reported 0.6.15) made no changes. It reported generated template updates for `.codex/hooks/session-start.py`, `.codex/hooks/inject-subagent-context.py`, `.codex/hooks/inject-workflow-state.py`, `.trellis/config.yaml`, and scripts; it reported `.codex/agents/trellis-check.toml`, `.codex/agents/trellis-implement.toml`, `.codex/agents/trellis-research.toml`, `AGENTS.md`, and `.trellis/.gitignore` as “modified by you”. Do not run a non-dry update during this task. If a hashed file is changed, expect a future keep/overwrite/new conflict and preserve local intent explicitly.
- `.agents/skills/trellis-meta/references/customize-local/change-workflow.md:3-28`, `change-agents.md:3-48`, and `local-architecture/generated-files.md:50-80` confirm the edit order and update behavior: shared workflow first, then platform adapters; never hand-edit `.template-hashes.json`; use a project-local skill for durable team behavior instead of customizing a bundled skill when possible.

## Caveats / Not Found

- No implementation was performed; this artifact is planning research only.
- The project currently tracks only Codex platform adapters; parity changes for Claude/Cursor/etc. are out of scope unless the user explicitly requests multi-platform support.
- A truly machine-enforced L1/L2 bypass would need a new execution-path field surfaced by `get_context`/hooks and dedicated tests. This research recommends the smaller explicit-PRD fail-closed gate for the current optimization.
- The exact Codex read-only sandbox enum was not verified from a local schema. If the formal reviewer remains `trellis-check`, validate the accepted `sandbox_mode` value before changing it; otherwise rely on a report-only profile plus the independent SHA/worktree contract.
- The working tree already contains unrelated untracked task/archive/design paths; they must not enter this task's commit.

## Files Read

- `AGENTS.md`
- `.trellis/workflow.md`, `.trellis/config.yaml`, `.trellis/.template-hashes.json`, `.trellis/agents/check.md`
- `.trellis/spec/guides/index.md`, `.trellis/spec/macos/index.md`, `.trellis/spec/macos/quality-guidelines.md`, `.trellis/spec/macos/documentation-guidelines.md`
- `.agents/skills/trellis-check/SKILL.md`, `.agents/skills/trellis-start/SKILL.md`, `.agents/skills/trellis-continue/SKILL.md`, `.agents/skills/trellis-meta/references/customize-local/{change-workflow,change-agents,change-skills-or-commands}.md`, `.agents/skills/trellis-meta/references/local-architecture/{generated-files,workflow,multi-agent-channel}.md`, `.agents/skills/trellis-meta/references/platform-files/{agents,overview}.md`
- `.codex/agents/trellis-{check,implement,research}.toml`, `.codex/hooks.json`, `.codex/hooks/inject-subagent-context.py`, `.codex/hooks/inject-workflow-state.py`, `.codex/hooks/session-start.py`, `.codex/config.toml`
- `docs/README.md`, `docs/development/trellis.md`, `docs/verification/dev-candidate.md`, `Makefile`, `tools/check_docs.py`, `tests/test_check_docs.py`, `tests/test_runtime_privacy.py`
- `.trellis/scripts/common/{task_store,types,session_context,workflow_phase}.py`, `.trellis/scripts/task.py`, `.trellis/scripts/get_context.py`

## Commands Run

- `git status --short --branch`
- `sed`/`nl`/`rg`/`find` reads over the files listed above
- `python3 ./.trellis/scripts/get_context.py --mode packages`
- `python3 ./.trellis/scripts/get_context.py --mode phase --step 2.2 --platform codex`
- `trellis update --dry-run` (read-only; no changes)
- `git diff --check` (no tracked diff; unrelated untracked paths remain)

## Failures / Unverified

- No command failures.
- Not run: `swift build -c release`, `make test`, `make docs-check`, `make test-docs` (no implementation diff exists yet).
- Not verified: actual Codex sandbox enum for a read-only agent, non-Codex/channel parity, and machine-enforced L1/L2 routing.
