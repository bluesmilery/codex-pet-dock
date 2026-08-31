# Implementation plan

## Delivery path

L2. Delivery Path: L2. Full implement -> independent review -> QA loop.

## Workspace

- Worktree: /Users/<user>/workspace/codex-pet-dock-worktrees/pet-window-adaptation
- Branch: codex/pet-window-adaptation (from dev = <pre-rewrite-id>)
- The implement worker edits files ONLY inside this worktree.

## Allowed files (hard boundary)

- Sources/PetDock/ContainerPetChannel.swift (new)
- Sources/PetDock/main.swift (tick integration + diagnose section only)
- Sources/PetDock/DiagnosticFormatter.swift (only if needed for the
  diagnose section)
- Makefile (test-ui source list only)
- tests/main.swift (new test cases only)

Everything else is read-only. In particular do NOT touch BubbleVisibility.swift,
PetTracker.swift, Follower.swift, FollowTickPlan.swift, DockPanel.swift,
DockView.swift, Settings.swift, StatusBar.swift.

## Steps

1. Read context: implement.jsonl manifest files, prd.md, design.md, relevant
   specs (.trellis/spec/macos/appkit-conventions.md, quality-guidelines.md,
   privacy-guidelines.md), and the exact integration points in
   Sources/PetDock/main.swift and tests/main.swift.
2. TDD: add failing pure tests first (selector / captureSize / mapToPetRect /
   probe fake-clock cases) in tests/main.swift, wire
   Sources/PetDock/ContainerPetChannel.swift into the Makefile test-ui list,
   then implement the production file until green.
3. Integrate tick() + diagnose per design.md; keep diffs minimal and traceable
   to PRD R1-R6.
4. Self-check: swift build -c release (0 warnings), make test (all green).
   Run from the worktree root.
5. Report: changed files, key diff summary, executed commands + results,
   failures, unverified items. Do NOT git commit / push / merge.

## Verification commands (from worktree root)

- swift build -c release
- make test

## Commit policy

The supervising main session owns commits. After implement + independent
review are clean, main commits on codex/pet-window-adaptation, then QA runs
on the frozen full SHA.
