# Implementation Plan — 本地分支与 worktree 清理

1. 固化 audit research：完整 refs/SHA、分类证据、worktree 状态和 dirty diff。
2. 创建全新只读 Review worktree/branch，由独立 Agent 验证：
   - 无需合入 dev；
   - 历史净化/tree/patch-id等价证据；
   - `afa5f42` 符合用户明确放弃范围；
   - 删除目标和保留边界准确。
3. Review 通过后，由主管在主仓库执行 Git 管理操作：
   - trash 明确生成的 pycache；
   - stash 唯一 dirty diff；
   - 移除 12 个目标 worktree；
   - 删除 67 个本地分支。
4. 创建短生命周期 QA worktree/branch，独立验证 refs/worktrees/SHA/stash/remote/tag/主工作树未跟踪文件；QA 不修改项目内容。
5. QA ACCEPTED 后移除 QA worktree/branch，并由主管最终复核只剩 main/dev。
6. 更新并归档 Trellis task；不产生项目 commit、不 push。

## Exact Ref and Temporary-Branch Boundary

- `research/branch-audit.md` 是本轮删除前的精确 ref 快照，列出原始 67 个待删分支（`ao/*` 56 个、`codex/*` 11 个）及完整 tip SHA。
- 原始集合来自初始 69 个本地分支：保留 `main`、`dev` 两个，删除候选 67 个。当前实现、Review、rereview worktree 会额外出现 `codex/cleanup-local-branches-implement-0817`、`codex/cleanup-local-branches-review-0817`、`codex/cleanup-local-branches-rereview-0817`；三个临时 ref 明确不属于原始 67，也不加入任何删除命令。后续本任务新建的 check/QA 临时分支必须按精确名称排除，只在对应阶段存在，并在该阶段结束后单独移除，不能无限扩展原始快照。
- 删除命令必须先使用审计文件中的精确分支名和 SHA 重建目标列表，并验证计数仍为 67；禁止使用 `ao/*`、`codex/*` 等宽泛 glob 直接删除。计数、SHA、worktree、主/远端/tag 引用任一漂移即停止。

## Reachability-Based Deletion Strategy

- 48 个可达 ref 中，12 个是 `main` only、36 个是 `dev` only、0 个同时可达。它们的 tip 已被保留分支承接，先移除该 ref 对应的精确 linked worktree，再按审计记录逐个执行安全分支删除；删除前再次运行 ancestor 校验。若当前检出分支导致 `git branch -d` 无法直接确认 `main`-only ref，先切换/指定对应保留基线并重新验证，不能因此改用未审查的宽泛 force delete。
- 19 个不可达 ref（10 个 unique tips）只有在完整 SHA 已持久化到 `research/branch-audit.md` 后才允许逐个 `git branch -D -- <exact-name>`。`2f790414b8724533c6ffd068a124813d1ddb5168` 是用户明确暂不处理的 dock 底座/控制按钮避让候选，记录后删除但不合入 `dev`。
- 删除过程中仅操作已核对的本地 `refs/heads`；不得删除 remote-tracking refs、tag 或 release。

## Worktree, Generated-File, and Dirty-Diff Handling

- 只移除审计列出的 12 个目标 linked worktree。`codex/cleanup-local-branches-implement-0817`、`codex/cleanup-local-branches-review-0817`、`codex/cleanup-local-branches-rereview-0817` 以及后续按精确名称创建的 check/QA worktree 属于临时验证设施，分别在自身阶段完成后清理，不混入原始 worktree 计数。
- 先检查并记录生成物；明确的 `__pycache__` 等可丢弃生成物用 `/usr/bin/trash <exact-path>` 移回收站。若安全钩子拦截，仍使用回收站，不用 `rm -rf` 或目录通配符绕过。忽略的 build/QA 产物随其所属 linked worktree 一起移除；主项目需要的 App candidate、diff HTML 已在主目录留存。
- `<worktree>/.codex/worktrees/codex-pet-dock-reorganize-project-docs-0817` 的 tracked diff 只有 `docs/data-layer.md` 一行标题差异。移除该 worktree 前执行 path-limited stash：

  ```sh
  git stash push -m "backup cleanup-local-branches: codex/reorganize-project-docs-0817" -- docs/data-layer.md
  ```

  验证 stash message/stat 后保留 stash，不直接 restore/reset；该 stash 是唯一 dirty diff 的恢复副本。

## Stop Conditions

- Review 发现任何独有内容需要合入 `dev`；
- 任一 worktree 出现审计记录之外的 tracked/untracked 内容；
- main/dev/origin/main/tag SHA 漂移；
- 原始 67 ref、12 worktree 或其精确路径集合在执行前发生变化；
- 临时 implement/Review/rereview/check/QA ref 被误计入删除集合；
- 删除命令被安全钩子阻止且没有项目规则允许的安全替代方案。
