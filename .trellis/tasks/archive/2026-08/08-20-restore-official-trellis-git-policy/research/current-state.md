# 当前状态与官方默认差异

## 官方基线

本机安装的 Trellis 版本为 0.6.14。随包官方模板具有以下边界：

- `.trellis/spec/`、`.trellis/tasks/`、`.trellis/workspace/`、`workflow.md`、`config.yaml` 和 `scripts/` 是仓库持久化内容。
- `.trellis/.developer`、`.trellis/.current-task`、`.trellis/.runtime/`、临时文件、备份和 Python cache 被忽略。
- `session_auto_commit` 默认开启，`task.py archive` 和 `add_session.py` 可创建 bookkeeping commits。
- developer journal 使用 `.gitattributes` 的 `merge=union` 降低并行追加冲突。

## 项目差异

- `.trellis/.gitignore` 额外忽略 `spec/backend/`、`spec/frontend/` 和 `workspace/`。
- `.trellis/config.yaml` 显式设置 `session_auto_commit: false`。
- `AGENTS.md`、privacy spec 和 `docs/development/trellis.md` 将 workspace/journal 描述为不入库的个人态。
- `.trellis/tasks/` 未被忽略，但历史上采用了不一致的提交策略，导致部分 task 已跟踪、部分 task 未跟踪。
- 根目录 `.claude/` 只包含被忽略的本机 `settings.local.json`；用户已确认该平台当前不再使用，应删除目录并移除整目录忽略。

## 当前文件状态

- 任务创建并开始规划时的基线：`.trellis/tasks/` 61 个文件，17 个已跟踪；此后本任务新增的规划文件也属于待跟踪资料。
- 基线清点：`.trellis/workspace/` 2 个文件，0 个已跟踪。
- 未跟踪 task 目录包括活动任务和归档任务；它们不得删除或强制归档。
- 内容级初筛发现 6 个 task 文件含真实本机路径或本机用户名模式；没有文件命中邮箱或典型凭据赋值模式。
- 若干 task 文件提到 `auth.json` 或“会话正文”，上下文是隐私约束和审计结论，不代表文件含认证数据或原始正文；实施时仍需逐文件验证并保持不回显原值。

## 迁移约束

1. 先脱敏，再加入 Git。
2. 路径使用 `<user>`、`<worktree>`、`<repo>` 等稳定占位符，不改变相对仓库路径或 task 引用。
3. 公开 Git 身份允许保留；本机账户名和绝对 home 路径不允许保留。
4. 不读取认证文件或原始会话 transcript。
5. 只修改本任务直接要求的治理、配置、task/workspace 内容，不清理其他脏路径。
6. `.claude/` 清理必须精确限定到已核实的目录；若安全钩子阻止删除，则移动到系统回收站，不绕过钩子。
