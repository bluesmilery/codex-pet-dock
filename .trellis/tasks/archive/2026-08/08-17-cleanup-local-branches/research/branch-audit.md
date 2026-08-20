# Branch Audit Snapshot

## Refs

- Captured date: 2026-08-17 Asia/Shanghai
- `main`: `e88940b6ea336de38a821de87a8fbc41ce1ffa88`
- `dev`: `3cecbcdf3cd4c67e491159ca3898db59e8b83bf6`
- `origin/main`: `37fb66b70c39336ce886d7615d64aa19ac6a0c9a`
- `v0.1.0`: `37fb66b70c39336ce886d7615d64aa19ac6a0c9a`
- Original local branches: 69 total; preserve 2; delete 67 (`ao/*`=56, `codex/*`=11).
- The live view currently adds three temporary task refs. `codex/cleanup-local-branches-review-0817`, `codex/cleanup-local-branches-implement-0817`, and `codex/cleanup-local-branches-rereview-0817` are explicitly excluded from the original 67 and must not be deleted by the cleanup snapshot.
- Delete candidates: 48 reachable from main/dev; 19 refs at 10 unreachable tips.

## Exact Delete-Candidate Ref Snapshot

This is the complete original 67-ref set, captured with full object IDs from:

```sh
git for-each-ref --format='%(refname:short) %(objectname)' refs/heads/ao refs/heads/codex
```

The three temporary refs named above were excluded before counting. Any later check/QA ref created for this task must likewise be excluded by its exact name and removed separately at the end of its phase; do not expand the original snapshot by recursively listing every future `codex/cleanup-local-branches-*` ref. No wildcard is used to identify an individual deletion target; the following branch names and SHAs are the frozen recovery/deletion index.

### Reachable from `main` only (12, safe deletion class)

| Branch | Tip SHA |
| --- | --- |
| `ao/codex-pet-do-orchestrator` | `e88940b6ea336de38a821de87a8fbc41ce1ffa88` |
| `ao/codex-pet-dock-17/root` | `e88940b6ea336de38a821de87a8fbc41ce1ffa88` |
| `ao/codex-pet-dock-18/root` | `e88940b6ea336de38a821de87a8fbc41ce1ffa88` |
| `ao/codex-pet-dock-19/root` | `e88940b6ea336de38a821de87a8fbc41ce1ffa88` |
| `ao/codex-pet-dock-21/root` | `e88940b6ea336de38a821de87a8fbc41ce1ffa88` |
| `ao/codex-pet-dock-22/root` | `e88940b6ea336de38a821de87a8fbc41ce1ffa88` |
| `ao/codex-pet-dock-23/root` | `e88940b6ea336de38a821de87a8fbc41ce1ffa88` |
| `ao/codex-pet-dock-24/root` | `e88940b6ea336de38a821de87a8fbc41ce1ffa88` |
| `ao/codex-pet-dock-25/root` | `e88940b6ea336de38a821de87a8fbc41ce1ffa88` |
| `ao/codex-pet-dock-26/root` | `e88940b6ea336de38a821de87a8fbc41ce1ffa88` |
| `ao/codex-pet-dock-27/root` | `e88940b6ea336de38a821de87a8fbc41ce1ffa88` |
| `ao/codex-pet-dock-28/root` | `e88940b6ea336de38a821de87a8fbc41ce1ffa88` |

### Reachable from `dev` only (36, safe deletion class)

| Branch | Tip SHA |
| --- | --- |
| `ao/codex-pet-dock-37/clean-candidate` | `fd17217ba79b762c8eefaf188a2a17b7d4d9ffb9` |
| `ao/codex-pet-dock-40/root` | `fd17217ba79b762c8eefaf188a2a17b7d4d9ffb9` |
| `ao/codex-pet-dock-41/root` | `82e6f70e80eedcef2b441cd2f9f713c80c56118c` |
| `ao/codex-pet-dock-42/root` | `fd17217ba79b762c8eefaf188a2a17b7d4d9ffb9` |
| `ao/codex-pet-dock-43/root` | `fd17217ba79b762c8eefaf188a2a17b7d4d9ffb9` |
| `ao/codex-pet-dock-44/root` | `fd17217ba79b762c8eefaf188a2a17b7d4d9ffb9` |
| `ao/codex-pet-dock-45/root` | `fd17217ba79b762c8eefaf188a2a17b7d4d9ffb9` |
| `ao/codex-pet-dock-46/root` | `fd17217ba79b762c8eefaf188a2a17b7d4d9ffb9` |
| `ao/codex-pet-dock-49/root` | `fd17217ba79b762c8eefaf188a2a17b7d4d9ffb9` |
| `ao/codex-pet-dock-50/root` | `fd17217ba79b762c8eefaf188a2a17b7d4d9ffb9` |
| `ao/codex-pet-dock-51/root` | `fd17217ba79b762c8eefaf188a2a17b7d4d9ffb9` |
| `ao/codex-pet-dock-53/root` | `fd17217ba79b762c8eefaf188a2a17b7d4d9ffb9` |
| `ao/codex-pet-dock-54/root` | `fd17217ba79b762c8eefaf188a2a17b7d4d9ffb9` |
| `ao/codex-pet-dock-55/root` | `fd17217ba79b762c8eefaf188a2a17b7d4d9ffb9` |
| `ao/codex-pet-dock-55/tdd-fix-df77fbf` | `9b2733bfa183d489e07b048230c7e2dbad6ea843` |
| `ao/codex-pet-dock-56/root` | `fd17217ba79b762c8eefaf188a2a17b7d4d9ffb9` |
| `ao/codex-pet-dock-57/root` | `fd17217ba79b762c8eefaf188a2a17b7d4d9ffb9` |
| `ao/codex-pet-dock-57/tdd-fix-8269cb9` | `8c161d0aa47f802dba76e944348359866164cf7d` |
| `ao/codex-pet-dock-58/root` | `fd17217ba79b762c8eefaf188a2a17b7d4d9ffb9` |
| `ao/codex-pet-dock-59/root` | `fd17217ba79b762c8eefaf188a2a17b7d4d9ffb9` |
| `ao/codex-pet-dock-60/root` | `8c161d0aa47f802dba76e944348359866164cf7d` |
| `ao/codex-pet-dock-61/control-reset-fix` | `8c161d0aa47f802dba76e944348359866164cf7d` |
| `ao/codex-pet-dock-61/root` | `8c161d0aa47f802dba76e944348359866164cf7d` |
| `ao/codex-pet-dock-62/root` | `8c161d0aa47f802dba76e944348359866164cf7d` |
| `ao/codex-pet-dock-63/root` | `8c161d0aa47f802dba76e944348359866164cf7d` |
| `ao/codex-pet-dock-64/root` | `8c161d0aa47f802dba76e944348359866164cf7d` |
| `ao/codex-pet-dock-65/root` | `8c161d0aa47f802dba76e944348359866164cf7d` |
| `codex/dev-trial-build-0813` | `a2f20adb063a9998fd62db1183a676d70b48343d` |
| `codex/diff-page-resize-0814` | `e34b57e267754b315f3f644ecbd5c9f0bf49b5c3` |
| `codex/diff-page-resize-qa-0814` | `e34b57e267754b315f3f644ecbd5c9f0bf49b5c3` |
| `codex/reorganize-project-docs-0817` | `e34b57e267754b315f3f644ecbd5c9f0bf49b5c3` |
| `codex/trellis-reconfig-final-qa-0813` | `e34b57e267754b315f3f644ecbd5c9f0bf49b5c3` |
| `codex/trellis-reconfig-final-review-0813` | `e34b57e267754b315f3f644ecbd5c9f0bf49b5c3` |
| `codex/trellis-reconfig-reqa-0813` | `cc62434c533a80287a2ea9c011177a4c20aad100` |
| `codex/trellis-reconfig-rereview-0813` | `cc62434c533a80287a2ea9c011177a4c20aad100` |
| `codex/trellis-reconfigure-0813` | `e34b57e267754b315f3f644ecbd5c9f0bf49b5c3` |

### Reachability cross-check

| Class | Count | Deletion rule |
| --- | ---: | --- |
| `main` only | 12 | The tip is an ancestor of preserved `main`; remove only after its exact worktree is removed. |
| `dev` only | 36 | The tip is an ancestor of preserved `dev`; remove only after its exact worktree is removed. |
| Both | 0 | No branch falls into this class. |
| Reachable total | 48 | Verify the ancestor relation again immediately before deletion. |

The 48 reachable refs are safe to delete based on ancestry, but the deletion pass must still use the frozen, exact branch-name list. If `git branch -d` needs a different current base for the `main`-only class, first re-check the recorded ancestry and use the explicit ref; never replace this with an unreviewed wildcard or a force delete without evidence.

### Unreachable refs (19, force deletion only after SHA record)

| Branch | Tip SHA | Tip group / decision |
| --- | --- | --- |
| `ao/codex-pet-dock-16/root` | `6ef83bd8f6254796c348b12806afea23379cbdd0` | obsolete initial Trellis web bootstrap; superseded |
| `ao/codex-pet-dock-20/root` | `b3bd775e791f9283ecf0b90ed745183ab48d2e6a` | tree equals sanitized `911c084` |
| `ao/codex-pet-dock-21/candidate` | `870b2a033b2c81e381ca311ac781d6cbb21037ae` | old pre-squash chain included in public baseline |
| `ao/codex-pet-dock-26/fix-logger-verbose` | `3724bf7b76a57ce29d46fc8911cafe5f0f57d452` | old pre-squash chain included in public baseline |
| `ao/codex-pet-dock-29/root` | `3724bf7b76a57ce29d46fc8911cafe5f0f57d452` | old pre-squash chain included in public baseline |
| `ao/codex-pet-dock-30/root` | `9b8a133ef575270c25644677a1a5d3a6c2d0bd1f` | equivalent tree/patch exists as later `dd04930` |
| `ao/codex-pet-dock-31/root` | `3038d72740fed4e19be0c1a321b3eafad43b138a` | patches equal later `c9976c5`/`4b1fffe` |
| `ao/codex-pet-dock-32/root` | `3724bf7b76a57ce29d46fc8911cafe5f0f57d452` | old pre-squash chain included in public baseline |
| `ao/codex-pet-dock-33/root` | `bf18a8e4153c3e7d227ffc184efcfae51ebfcbcc` | old pre-squash chain included in public baseline |
| `ao/codex-pet-dock-34/root` | `3724bf7b76a57ce29d46fc8911cafe5f0f57d452` | old pre-squash chain included in public baseline |
| `ao/codex-pet-dock-35/root` | `3724bf7b76a57ce29d46fc8911cafe5f0f57d452` | old pre-squash chain included in public baseline |
| `ao/codex-pet-dock-35/test-count-fix` | `d4914a0fbe07fdd7477d2e475c9bea8c254020af` | tree exactly equals dev ancestor `c2b3456` |
| `ao/codex-pet-dock-36/root` | `3724bf7b76a57ce29d46fc8911cafe5f0f57d452` | old pre-squash chain included in public baseline |
| `ao/codex-pet-dock-37/root` | `3724bf7b76a57ce29d46fc8911cafe5f0f57d452` | old pre-squash chain included in public baseline |
| `ao/codex-pet-dock-38/root` | `3724bf7b76a57ce29d46fc8911cafe5f0f57d452` | old pre-squash chain included in public baseline |
| `ao/codex-pet-dock-39/root` | `3724bf7b76a57ce29d46fc8911cafe5f0f57d452` | old pre-squash chain included in public baseline |
| `codex/trellis-reconfig-qa-0813` | `21f1a20cf5225a328d031f692efebbd4d0d2beee` | tree exactly equals dev ancestor `42536cf`; pre-amend identity version |
| `codex/trellis-reconfig-review-0813` | `21f1a20cf5225a328d031f692efebbd4d0d2beee` | tree exactly equals dev ancestor `42536cf`; pre-amend identity version |
| `ao/codex-pet-dock-62/ctrl-obstacle-fix` | `2f790414b8724533c6ffd068a124813d1ddb5168` | explicitly abandoned control-button avoidance candidate; out of scope |

The unreachable group has 19 refs at 10 unique tips. These refs may be removed only after the complete branch/SHA table above is persisted; use `git branch -D -- <exact-name>` one name at a time. The `afa5f42` candidate is intentionally not merged because the user excluded dock-base/control-button avoidance from this task.

## Unreachable Tip Index

| Tip | Branch count | Decision |
| --- | ---: | --- |
| `6ef83bd8f6254796c348b12806afea23379cbdd0` | 1 | obsolete initial Trellis web bootstrap; superseded |
| `b3bd775e791f9283ecf0b90ed745183ab48d2e6a` | 1 | tree equals sanitized `911c084` |
| `870b2a033b2c81e381ca311ac781d6cbb21037ae` | 1 | old pre-squash chain included in public baseline |
| `3724bf7b76a57ce29d46fc8911cafe5f0f57d452` | 9 | old pre-squash chain included in public baseline |
| `9b8a133ef575270c25644677a1a5d3a6c2d0bd1f` | 1 | equivalent tree/patch exists as later `dd04930` |
| `3038d72740fed4e19be0c1a321b3eafad43b138a` | 1 | two patches equal later `c9976c5`/`4b1fffe` |
| `bf18a8e4153c3e7d227ffc184efcfae51ebfcbcc` | 1 | old pre-squash chain included in public baseline |
| `d4914a0fbe07fdd7477d2e475c9bea8c254020af` | 1 | tree exactly equals dev ancestor `c2b3456` |
| `21f1a20cf5225a328d031f692efebbd4d0d2beee` | 2 | tree exactly equals dev ancestor `42536cf` |
| `2f790414b8724533c6ffd068a124813d1ddb5168` | 1 | explicitly abandoned control-button candidate |

## Dirty Diff Backup Record

Worktree: `<worktree>/.codex/worktrees/codex-pet-dock-reorganize-project-docs-0817`

```diff
diff --git a/docs/data-layer.md b/docs/data-layer.md
--- a/docs/data-layer.md
+++ b/docs/data-layer.md
@@
-# Codex Pet Dock — 数据层（P1）
+# Codex Pet Dock — 数据层
```

Current dev replacement begins with `# Codex Pet Dock — 数据层架构`; no merge is required. Before removing that worktree, preserve this one-line change with a path-limited stash and retain the stash as the recovery copy.

## Worktree/Ref Safety Boundary

- The original 12 linked worktrees and 67 branch refs are the only cleanup targets in this snapshot.
- The implement, Review, and rereview worktree/branches are temporary task infrastructure, not original candidates. Any later check/QA worktree/branch created for this task must be excluded by its exact ref/path name, verified separately, and removed after its phase; none may be added to the original 67-target snapshot.
- Re-enumerate exact refs and worktrees immediately before each destructive pass. Any count, SHA, path, or tracked/untracked status drift is a stop condition.
- Generated `__pycache__` paths are disposable only after explicit inspection; if a safety hook blocks removal, move the exact path to the macOS Trash with `/usr/bin/trash`. Do not use recursive deletion or broad filesystem globs.
