# 优化开发审查闭环

## Goal

减少“实现 → Review 发现单个问题 → 修复 → 再 Review”的串行往返，同时保留应用代码、运行行为、隐私与发布变更的独立验收强度；不涉及开发的工作使用与风险匹配的轻量流程。

**Delivery Path: L1**

**Docs Impact: update**（同步项目持久规则 `AGENTS.md` 和人类可读说明 `docs/development/trellis.md`。）

## Background

- 当前项目要求实现、独立 Review、QA 分别使用全新子 Agent、分支和 worktree，并将验收绑定完整 commit SHA。
- 当前 Trellis `trellis-check` 通用定义允许检查者直接修复，与项目要求的“正式 Review 只读、问题退回实现者”冲突。
- 当前规则没有明确规定 Review 必须覆盖完整范围、集中报告全部 findings、批量修复，也没有审查轮次熔断机制。
- 用户明确要求：纯说明、只读检查、规划讨论以及其他不涉及开发的工作，不应强制执行完整开发闭环。

## Requirements

### R1. 风险分级路由

工作开始前必须先分类，并选择最小充分流程：

1. **L0 对话 / 只读**：解释、讨论、状态查询、只读检查，不写仓库文件；不创建实现分支、worktree 或 Review/QA loop，Trellis 任务可按现有 no-task 规则跳过。
2. **L1 治理 / 文档**：只修改流程规则、说明文档、任务/spec、AI agent 提示或沙箱配置等项目治理文件，不改变应用代码、构建产物、可执行脚本/Hook、测试逻辑、PetDock 运行时配置、隐私边界或发布状态；允许主会话直接实施，执行目标静态检查和一次独立只读一致性检查，不进入实现→修复→Review→QA 完整循环。
3. **L2 开发 / 高风险**：任何应用代码、测试逻辑、构建/签名/发布、可执行脚本或 Hook、PetDock 运行时配置、隐私/TCC/ScreenCaptureKit 行为变化；必须执行完整开发闭环。

分类不明确时必须 fail closed，按更高一级处理。

### R2. Review Readiness Gate

L2 实现候选进入正式 Review 前，实现负责人必须完成需求到证据映射、相关调用点/同类实现搜索、目标测试、release 构建、全量测试、diff/文档/隐私自检，并冻结完整候选 SHA。

### R3. 完整且批量的正式 Review

- 正式 Review 必须只读；除非候选无法构建或证据不足导致无法继续，否则不得在发现首个问题后提前结束。
- Reviewer 必须覆盖完整分配范围，一次性报告并验证全部 P0/P1/P2 findings。
- 高风险候选允许按需求/架构、测试/边界、macOS/隐私等互不重叠视角并行只读审查；主 Agent 去重并形成一份修复清单。

### R4. 批量修复与回归

- 同一实现负责人按根因聚类并一次性处理完整 findings 清单。
- 修复前搜索同类位置；每类行为缺陷增加回归测试或可执行检查。
- 修复产生新 SHA 后，旧验收结论失效；最终候选重新执行规定门禁。

### R5. 最多两轮 Review 与熔断

- 第一轮用于完整发现问题；若第一轮清零，直接进入正式 QA，不为满足轮次而重复 Review。
- 第一轮存在 findings 时，批量修复后执行第二轮最终 Review。
- 若第二轮仍出现新的实质问题、意味着需要第三轮 Review，停止逐项补丁，执行 `trellis-break-loop`，回到需求、设计或测试矩阵重新规划；不得降低质量门禁或带问题通过。

### R6. QA 后移

- L2 正式 QA 只对 Review 已清零、代码冻结的 SHA 执行。
- 开发中使用目标测试快速反馈；全量构建、全量测试、候选归档和真机 QA 按候选里程碑执行。
- 自动验证、静态推断、真机 QA 继续分开报告。

### R7. 实现者自检与正式 Review 分离

- `trellis-check` 的 checklist/skill 用于原实现负责人在自己的 worktree 内做可写自检和机械修复；它不是独立 Review，不产生批准结论。
- 主 Agent 不再为正式 Review 派发可写的 `trellis-check` 子 Agent；正式 Review 使用全新的 `luna + max` 只读 Agent，对冻结的完整 SHA 做完整范围审查。
- 自检结束并冻结 SHA 后才能开始正式 Review；Review findings 必须退回原实现负责人批量修复。

### R8. Trellis 管理边界与升级合并

- Trellis 管理或生成的文件中只修改 `.trellis/workflow.md`，不修改 `.trellis/spec/**`、`.agents/**`、`.codex/**`、`.trellis/agents/**`、Hook、脚本或测试。
- Trellis 管理范围外同步 `AGENTS.md` 和 `docs/development/trellis.md`，分别保存项目持久约束与人类可读流程说明。
- `.trellis/workflow.md` 内必须明确记录：该文件包含项目本地 Review 流程定制，后续升级先运行 `trellis update --dry-run`，再使用 `trellis update --create-new` 生成 `.new`，人工合并并保留本地规则。
- 项目禁止对该本地定制使用 `trellis update --force`；不手工修改 `.trellis/.template-hashes.json`。

## Acceptance Criteria

- [ ] AC1：规则可将典型请求稳定分类为 L0/L1/L2，模糊或跨级请求按最高风险级别处理。
- [ ] AC2：L0 明确不进入完整开发 loop；L1 明确使用轻量实施与目标检查；L2 保留独立 worktree、完整 SHA、独立 Review 和 QA。
- [ ] AC3：L2 工作流明确包含 Review Readiness Gate、完整 Review、集中 findings、批量修复、两轮熔断和 QA 后移。
- [ ] AC4：workflow 明确区分“原实现者使用 `trellis-check` skill 自检”和“全新只读 Agent 正式 Review”，且只有正式 Review 能给出 P0/P1/P2 结论。
- [ ] AC5：workflow 通过可重复静态验证确认状态块、阶段正文、自检/Review/QA 顺序和升级说明一致。
- [ ] AC6：现有 `swift build -c release`、`make test`、真机 QA、隐私和发布授权门禁不被削弱。
- [ ] AC7：最终任务提交只包含 `.trellis/workflow.md`、`AGENTS.md` 和 `docs/development/trellis.md`；Trellis 管理面除 workflow 外无修改，且未修改全局 npm、`node_modules`、`.trellis/.runtime/` 或 `.trellis/.template-hashes.json`。
- [ ] AC8：交付报告区分自动验证、静态结论和未验证项，并列出未来 `trellis update` 风险。
- [ ] AC9：workflow 内记录 `dry-run → create-new → 人工合并` 的升级步骤，并明确禁止 `trellis update --force` 覆盖本地定制。

## Out of Scope

- 不修改 PetDock 应用功能、Swift 源码或产品行为。
- 不修改 `.trellis/spec/**`、`.agents/**`、`.codex/**` 或 `.trellis/agents/**`。
- 不推送 `main`、不创建 tag/release、不构建或启动 `.app`。
- 不修改 Trellis npm 上游源码或发布模板。
- 不移除完整 SHA 绑定、独立 Review、真机 QA 或隐私门禁。

## Key Decision

- 用户确认本次以及后续 L1 流程/文档治理变更采用“主会话直接编辑 + 自动化静态检查 + 一次独立只读一致性检查”。L1 不创建实现/修复/QA worktree，不进入反复修复 loop；若检查发现问题，由主会话在当前 L1 任务内一次性修正并重新执行目标静态检查，不升级为完整 L2，除非发现实际变更触及 L2 边界。
- 用户澄清：“只修改 workflow”限定的是 Trellis 管理/生成文件；因此该范围内只修改 `.trellis/workflow.md`，同时应在管理范围外同步 `AGENTS.md` 和 `docs/development/trellis.md`。升级合并风险必须记录在 workflow 与人类文档中。`trellis-check` 保留为原实现者的可写自检能力，不作为正式 Review Agent。
