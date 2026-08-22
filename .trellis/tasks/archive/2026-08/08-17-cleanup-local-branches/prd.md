# 审计并清理本地分支与 worktree

## Goal

在不丢失需要进入 `dev` 的内容、不修改远端 refs/tag、不触碰用户主工作树未跟踪文件的前提下，将本地分支收敛为仅 `main` 与 `dev`，并移除对应的旧 worktree。

## Confirmed Inventory

- 当前本地分支共 69 个：保留 `main`、`dev`，目标清理 67 个（`ao/*` 56 个、`codex/*` 11 个）。
- 48 个目标分支的 tip 已可从 `main` 或 `dev` 到达，无独有 commit。
- 19 个目标分支位于 10 个不可达 tip，但均不需要合入 `dev`：
  - `b4b8a5e` 的 tree 与 `c2b3456` 完全相同，而 `c2b3456` 已是 `dev` 祖先；旧 AO 提交链的产品内容已由公开净化基线承接。
  - `000a4c1` tree 与净化后的 `911c084` tree 相同；`edff33b` 的 tree/patch 在后续链以 `dd04930` 等价承接；`3c33357` 与 `1a289b0` 的 patch-id 分别等于后续 `4b1fffe`、`c9976c5`。
  - `9d4eb9f` 与已在 `dev` 历史中的 `42536cf` tree 完全相同，仅是 amend 前身份提交。
  - `175b023` 是已废弃的早期 Trellis web/backend/frontend/workspace bootstrap；当前 `dev` 使用后来重配的 Codex + macOS-only Trellis，不应合入旧内容。
  - `afa5f42` 是控制按钮避让候选；用户此前明确要求忽略并以后重提需求，不合入 `dev`。
- 共有 12 个目标 linked worktree；大多数 tracked clean，仅含可再生的 `.build/`、HTML QA、pycache 或本地 Trellis 状态。
- 唯一 tracked-dirty worktree 为 `codex/reorganize-project-docs-0817`：只把旧 `docs/data-layer.md` 标题删除“（P1）”。当前 `dev` 已迁移为 `docs/architecture/data-layer.md` 且标题为“数据层架构”，语义已包含，不需要提交。
- `codex/trellis-reconfig-review-0813` 只有未跟踪 Python `__pycache__`；属于生成物。
- 主项目 `build/reviews/2026-08-13-main-vs-dev-e43aceb/` 已保存 diff HTML 和核心截图；两个 diff-page worktree 的额外 QA 截图是生成证据，不进入 `dev`。
- `origin/main` 和 `v0.1.0` 均指向 `030fb9f`；本任务不修改远端跟踪 ref 或 tag。

## Requirements

1. 保留且不移动 `main`、`dev`；执行前后完整 SHA 必须不变。
2. 不提交任何候选内容到 `dev`：审计已确认无需要补合入的 commit 或工作树改动。
3. 清理前记录以下恢复信息：
   - 67 个目标分支的名称和完整 tip SHA；
   - 10 个不可达 tip 的完整 SHA与不合入理由；
   - dirty worktree 的完整一行 diff。
4. 对唯一 dirty worktree：
   - 将 diff 记录到当前 Trellis task research；
   - 使用带明确消息的 Git stash 保存未提交内容，使 worktree 可安全移除；
   - 保留该 stash 作为可恢复备份，不在本任务中 drop。
5. 将 pycache 等明确生成物移动到回收站；不读取或备份其内容。
6. 删除除主项目外的 12 个 linked worktree：
   - 不使用 `rm -rf`；
   - clean worktree 使用 `git worktree remove`；
   - 不对未经记录的 dirty worktree使用 force。
7. 删除所有 `ao/*` 与 `codex/*` 本地分支：
   - 已包含分支优先使用安全删除；
   - 不可达但已审计/记录的 refs 才允许强制删除。
8. 完成后只允许存在本地 `main`、`dev`；`git worktree list` 只允许主项目 worktree。
9. 保持 `origin/main`、所有 tags、GitHub/远端分支不变；不 push、不 fetch、不删除 remote ref。
10. 不触碰主工作树现有未跟踪内容：`.trellis/tasks/`、两个 handoff、`design/icon-concepts/`、`build/` 等。

## Acceptance Criteria

- [x] 独立只读 Review 同意“无需再向 dev 合入内容”的结论和清理清单。
- [x] 清理前审计记录包含 67 个目标 refs、完整 SHA和 dirty diff。
- [x] `main`、`dev` SHA 与清理前一致，`dev` 工作树无新增 tracked 修改/commit。
- [x] `git for-each-ref refs/heads` 最终只输出 `main`、`dev`。
- [x] `git worktree list` 最终只包含 `<worktree>/workspace/codex-pet-dock`。
- [x] dirty 一行修改存在可恢复 stash，stash message 与任务对应。
- [x] `origin/main` 与 `v0.1.0` 指向仍为 `37fb66b70c39336ce886d7615d64aa19ac6a0c9a`。
- [x] 主工作树原有未跟踪 handoff/design/build/task 文件均未删除或提交。
- [x] 独立 QA 核对 refs、worktree、stash、main/dev SHA 和主工作树状态后 ACCEPTED。

## Out of Scope

- 删除或修改 remote-tracking refs、GitHub 远端分支、tags、release。
- 合并 `main` 与 `dev` 或改写二者历史。
- 提交/删除主工作树未跟踪 handoff、design、build 或 Trellis task archive。
- 修改业务代码、文档、测试或 Trellis 配置。

## Notes

- Keep `prd.md` focused on requirements, constraints, and acceptance criteria.
- Lightweight tasks can remain PRD-only.
- For complex tasks, add `design.md` for technical design and `implement.md` for execution planning before `task.py start`.
