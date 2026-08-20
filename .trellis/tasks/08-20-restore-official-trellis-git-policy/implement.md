# 实施计划

## Phase 0：派发前预检

- [ ] 确认任务仍为 L2，实施、正式 Review、QA 分别使用全新 `gpt-5.6-luna`、`max` Agent。
- [ ] 以当前 `dev` 完整 SHA 为 base，创建唯一实现分支和干净独立 worktree；记录任务名、角色、worktree、分支、base、文件范围、验收标准和目标 commit。
- [ ] 确认没有其他 Agent 负责同一任务，且不超过并发上限。
- [ ] 清点源工作区未跟踪 `.trellis/tasks/**`、`.trellis/workspace/**` 和精确 `.claude/` 文件；保留无关 `design/`，不得纳入任务或复制到实现 worktree。
- [ ] 将任务范围内未跟踪输入复制到实现 worktree，并以文件清单和校验值验证完整性；不创建含未脱敏内容的临时 commit。

## Phase 1：隐私迁移

- [ ] 只输出文件名和计数，复核 task/workspace 中真实本机路径、本机用户名、私钥、凭据、token、认证数据和会话正文模式。
- [ ] 对确认的 task 文件做最小占位符替换，保留 task 状态、需求、验收、结论和引用关系。
- [ ] 确认 workspace 文件无需或已经完成同等级脱敏。
- [ ] 对候选内容重新扫描；除公开 Git 身份和明确政策术语外不得有未解释命中。

## Phase 2：恢复官方边界

- [ ] 将 `.trellis/.gitignore` 恢复为 Trellis 0.6.14 官方模板边界。
- [ ] 将 `.trellis/config.yaml` 的有效配置改为 `session_auto_commit: true`。
- [ ] 保留 `.gitattributes` 中 workspace journal 的 union merge 规则。
- [ ] 从根 `.gitignore` 移除 `.claude/` 整目录忽略。

## Phase 3：文档与资料同步

- [ ] 更新 `AGENTS.md` 的 Trellis Git/隐私边界和 `.claude/` 说明，不改动 L0/L1/L2、Review、QA、发布规则。
- [ ] 更新 `.trellis/spec/macos/privacy-guidelines.md`，将隐私规则表达为内容级扫描/脱敏。
- [ ] 更新 `docs/development/trellis.md`，统一 task、workspace journal、runtime identity 和当前平台说明。
- [ ] 搜索其他直接矛盾表述，只做必要的最小同步。
- [ ] 将全部 `.trellis/tasks/**`、`.trellis/workspace/**` 纳入候选；确认无 `?? .trellis/tasks/...`，且无关 `design/` 未暂存。

## Phase 4：实现负责人自检

- [ ] 使用 `trellis-check` skill/checklist 做可写自检和机械修复。
- [ ] 核对官方模板差异、`git check-ignore` 正反例、有效 config 和 `trellis update --dry-run`。
- [ ] 执行候选内容隐私扫描，仅报告文件名和计数。
- [ ] 执行 `git diff --check`、`make docs-check`、`make test-docs`。
- [ ] 执行 `swift build -c release`，确认 0 warning。
- [ ] 执行 `make test`，确认 test-ui、test-data、test-shell 全绿。
- [ ] 使用 `bluesmilery <19263500+bluesmilery@users.noreply.github.com>` 提交，commit body 不含 `Co-Authored-By`；报告完整 SHA、修改文件、关键 diff、命令结果、失败项和未验证项。

## Phase 5：正式 Review、修复熔断与 QA

- [ ] 冻结完整候选 SHA，由全新只读 Review Agent 完整检查 P0/P1/P2。
- [ ] 首轮有 findings 时由原实现负责人集中修复并提交新 SHA，旧 Review/测试/QA 结论全部失效。
- [ ] 第二轮仍有实质 finding 时执行 `trellis-break-loop`，重新分析和规划后再继续。
- [ ] Review 清零后，由全新 QA Agent 对同一完整 SHA 复验配置、Git 边界、隐私、文档、release build 和 `make test`。
- [ ] 只有 Review P0/P1/P2=0 且 QA 全绿的 SHA 可标记 accepted。

## Phase 6：集成与本机清理

- [ ] 对源工作区将被 accepted 提交覆盖的未跟踪 task/workspace 文件重新清点；若存在实施派发后新增或变化的内容，停止集成并报告。
- [ ] 将这些未跟踪输入移动到任务专属临时备份目录，以清单和校验值确认 accepted 候选已完整保留，再把 accepted SHA 集成到 `dev`；不得触碰无关 `design/`。
- [ ] 在当前项目根目录再次确认 `.claude/` 仍只有 `settings.local.json`，不读取正文；删除文件和空目录，安全钩子拦截时移动到回收站。
- [ ] 验证 `dev` 的完整 SHA、工作区状态、`.claude/` 不存在、task/workspace 均被 Git 管理且隐私扫描为零。
- [ ] 不执行 push、PR、`main`、tag 或 Release；临时备份在完整性确认前不得清理。
