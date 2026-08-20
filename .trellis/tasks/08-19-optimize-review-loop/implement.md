# 优化开发审查闭环：实施计划

## 执行级别

- 本任务：L1 治理 / 文档。
- 执行：主会话直接编辑。
- 验证：自动化静态检查 + 一次全新 `luna + max` Agent 只读一致性检查。
- 不创建实现、修复或 QA worktree；若实际需要修改可执行脚本、Hook、测试逻辑或 PetDock 行为，停止并升级为 L2。

## 1. 基线与范围冻结

- [ ] 记录 `dev` 当前完整 HEAD、tracked diff 和所有未跟踪路径。
- [ ] 确认除当前 task 外的未跟踪任务/archive/`design/` 均为用户或其他任务内容，不修改、不暂存。
- [ ] 保存当前 Review 自修复语义的负向基线：
  - `.trellis/workflow.md` 的 `fix directly` / `Auto-fix`；
  - `.agents/skills/trellis-check/SKILL.md` 的 `fix them directly`；
  - `.codex/agents/trellis-check.toml` 的 `self-fix` / `workspace-write`；
  - `.trellis/agents/check.md` 的 `self-fix`。

## 2. 主会话最小修改

- [x] 修改 `.trellis/workflow.md`：
  - no-task 阶段允许 L0 直接回答；
  - planning 阶段记录 Workflow Level；
  - in-progress 阶段先按 L1/L2 路由；
  - L1 使用主会话 + 静态检查 + 一次只读一致性检查；
  - L2 使用原实现者 `trellis-check` skill 自检 → readiness/frozen SHA → 全新只读 Agent 完整 Review；首轮清零直接 QA，否则 repair batch → final Review → QA；需要第三轮时进入 break-loop；
  - 加入项目本地升级说明：`trellis update --dry-run` → `trellis update --create-new` → 人工合并，禁止 `trellis update --force`。
- [ ] 修改 `AGENTS.md`，在 Trellis managed block 外持久化 L0/L1/L2、L1 例外和 L2 自检/正式 Review/QA 分工。
- [ ] 修改 `docs/development/trellis.md`，补充分级流程、`trellis-check` 用法和升级合并说明。
- [ ] 确认 Trellis 管理面不包含 `.trellis/workflow.md` 之外的修改，并且正式任务提交不包含 `.trellis/spec/**`、`.agents/**`、`.codex/**` 或 `.trellis/agents/**`。
- [ ] 不修改 `.trellis/.template-hashes.json`。

## 3. 目标静态验证

使用项目 Python 环境；本任务不运行或修改 PetDock 测试逻辑。

- [ ] `git diff --check`
- [ ] `make docs-check`
- [ ] `make test-docs`
- [ ] `python ./.trellis/scripts/get_context.py --mode phase`，确认 Phase Index 可解析且 L0/L1/L2 路由可见
- [ ] 正向搜索确认所有必需语义存在：
  - `L0` / `L1` / `L2`
  - `Review Readiness`
  - 完整范围 / 不提前结束
  - repair batch / 批量修复
  - 需要第三轮 / `trellis-break-loop`
  - Review 清零后正式 QA
  - `trellis-check` 仅为实现者自检
  - `dry-run` / `create-new` / 禁止 `--force`
- [ ] `python ./.trellis/scripts/task.py validate 08-19-optimize-review-loop`

## 4. 一次独立只读一致性检查

- [ ] 派发一个全新 `gpt-5.6-luna + max` Agent。
- [ ] 明确禁止写文件、提交、合并、构建 `.app` 或执行发布操作。
- [ ] 检查完整 diff 是否满足 PRD/设计、L1 是否可能绕过 L2 门禁、实现者自检是否与正式 Review 清晰分离、Trellis update 合并风险是否如实记录。
- [ ] Reviewer 必须一次性报告全部经验证 findings、未覆盖项和命令结果。
- [ ] 若有 findings，由主会话一次性批量修正并重跑第 3 节静态检查；不派发第二轮 Agent，除非发现改动实际升级为 L2。

## 5. 交付与提交边界

- [ ] 回读所有修改文件，列出实际 diff、验证结果、失败项和未验证项。
- [ ] 将当前 task 文件与规则修改从既有未跟踪路径中精确分离。
- [ ] 按 Trellis Phase 3.4 给出一次性 commit 计划；未经用户确认不提交、不 push。
- [ ] 不向 `main` push，不创建 tag/release，不运行 `make app`。

## 回滚点

- 静态检查或只读检查表明路由不安全时，停止提交；只回退本任务修改的治理文件。
- 若任何必要改动触及可执行 Hook/脚本、测试逻辑或 PetDock 运行行为，停止 L1 实施，修订 PRD/设计并按 L2 重新规划。
