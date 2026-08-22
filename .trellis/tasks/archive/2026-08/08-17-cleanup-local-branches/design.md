# Design — 本地分支与 worktree 清理

## Safety Model

清理分为四个阶段：只读审计 → 独立 Review → 精确删除 → 独立 QA。删除目标使用创建计划时解析出的 ref 集合，不使用宽泛 shell glob 直接定位文件系统目录。

## Branch Classification

| Class | Count | Action |
| --- | ---: | --- |
| 保留 | 2 | `main`、`dev` 不动 |
| 已包含于 main/dev | 48 | worktree 移除后安全删除 branch |
| 不可达但内容已被净化/等价提交承接 | 18 | 记录完整 SHA 后删除 |
| 明确放弃的控制按钮候选 | 1 | 记录 `afa5f42...` 后删除，不合入 dev |

不可达 refs 的记录是恢复索引，不创建 backup tag，避免清理后又留下大量临时 tags。Git 对象短期仍可能通过 reflog 存在，但恢复依据以 task research 中的完整 SHA 为准。

## Dirty Worktree Handling

`codex/reorganize-project-docs-0817` 的 tracked diff 只有：

```diff
-# Codex Pet Dock — 数据层（P1）
+# Codex Pet Dock — 数据层
```

该旧路径已从当前 `dev` 删除并迁移，内容无需提交。执行时先写入 research，再用 path-limited `git stash push` 保存，禁止直接 restore/reset；stash 保留到任务结束，作为恢复手段。

## Worktree Removal

- 对明确的 pycache 使用 `/usr/bin/trash`，可从回收站恢复。
- clean linked worktree 使用 `git worktree remove <absolute-path>`。
- 忽略的 build/QA 产物随 worktree 移除；主项目已保存用户需要的 app candidate 和 diff HTML 核心产物。
- AO orchestrator worktree tracked clean，随其本地 branch 一并移除；不修改 AO 外部配置文件。

## Verification

清理前后分别记录：

- `git rev-parse main dev`
- `git for-each-ref refs/heads`
- `git worktree list --porcelain`
- `git status --porcelain=v1 --untracked-files=all`
- `git rev-parse origin/main v0.1.0`
- 对应 cleanup stash 的 message/stat

最终 QA 可以临时建立 detached worktree 或短生命周期 QA 分支；若建立分支，主管在 QA 后删除并再次核对最终仅 main/dev。

## Rollback

- 已删除 branch 可用 research 中完整 SHA重新 `git branch <name> <sha>`。
- dirty diff 可由保留的 stash恢复。
- 移入回收站的 pycache 无需恢复；需要时 Python 可重新生成。
- worktree 可从保留/恢复的 branch重新创建。
