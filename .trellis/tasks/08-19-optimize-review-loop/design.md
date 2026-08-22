# 优化开发审查闭环：技术设计

## 1. 设计目标

在不削弱 PetDock 应用代码、隐私、真机 QA 和发布门禁的前提下，将工作按风险分成 L0/L1/L2 三条路径，并把 L2 的问题发现从串行后置改为前置准入、完整审查和批量修复。

## 2. 路由模型

| 级别 | 典型工作 | 执行者 | 验证 | 是否进入完整 loop |
|---|---|---|---|---|
| L0 | 解释、讨论、状态查询、只读检查 | 主会话 | 必要的只读证据 | 否 |
| L1 | 流程规则、说明文档、task/spec、AI agent 提示或沙箱配置 | 主会话 | 目标静态检查 + 一次独立只读一致性检查 | 否 |
| L2 | Swift/测试逻辑、构建/发布、可执行脚本/Hook、PetDock 运行时、隐私/TCC/ScreenCaptureKit | 独立实现 Agent | Review Readiness + 独立完整 Review + 正式 QA | 是 |

跨级请求按最高风险级别处理；无法确认是否影响运行行为时 fail closed 到 L2。

## 3. L1 执行契约

1. L1 可以使用轻量 Trellis task 保存需求和证据，但不要求实现、修复、QA worktree。
2. 主会话获得规划批准后直接编辑治理文件。
3. 执行与改动范围匹配的静态检查；本任务不增加或修改测试逻辑。
4. 使用一个全新 `luna + max` Agent 对当前 diff 做一次只读一致性检查。该 Agent 不修改文件，也不触发修复 loop。
5. 若检查发现问题，主会话一次性批量修正并重跑静态检查；若问题表明改动触及 L2，立即停止并升级为完整流程。

## 4. L2 执行契约

### 4.1 Review Readiness Gate

正式 Review 前，实现负责人必须：

- 将每条验收标准映射到自动测试、静态证据或真机 QA；
- 搜索相关调用点、同类状态和传播位置；
- 完成目标测试、release 构建、全量测试、diff、文档和隐私自检；
- 冻结并报告完整候选 SHA。

实现者在冻结 SHA 前读取并执行现有 `trellis-check` skill/checklist，在自己的 worktree 内修复机械问题并重跑门禁。该步骤是自检，不是独立 Review，不得给出 APPROVED 或 P0/P1/P2 清零结论；不得另派一个可写 `trellis-check` 子 Agent 进入同一任务。

### 4.2 Review Campaign

- 正式 Reviewer 使用全新的 `luna + max` 只读 Agent 审查明确 SHA，不使用可写 `trellis-check` 子 Agent；除候选不可构建或关键证据缺失导致无法继续外，不得在首个 finding 后停止。
- 报告必须说明已覆盖范围、未覆盖范围及原因，并一次性列出全部经验证的 P0/P1/P2。
- 高风险候选可拆成互不重叠的审查视角并行执行；主 Agent 去重后形成一份 repair batch。

### 4.3 Repair Batch 与熔断

- 原实现负责人按根因聚类，搜索同类位置，一次性修复完整清单并补回归证据。
- 新 SHA 使旧验收结论失效。
- 第一轮清零时直接进入 QA；只有第一轮有 findings 时才在 repair batch 后执行第二轮最终 Review。若第二轮仍有新的实质问题、意味着需要第三轮 Review，停止逐项补丁，执行 `trellis-break-loop` 并回到规划。

### 4.4 QA 后移

正式 QA 只对 Review P0/P1/P2 清零、代码冻结的 SHA 执行。开发中的目标测试不冒充正式 QA；自动验证、静态推断、真机 QA 继续分栏报告。

## 5. 实现边界

Trellis 管理或生成的文件中只修改：

- `.trellis/workflow.md`：Phase Index、no-task、planning、in-progress 和 Phase 2 详细步骤同步风险路由；区分实现者自检与正式 Review；记录 Trellis 升级合并步骤。

在 Trellis 管理范围外同步：

- `AGENTS.md`：持久保存 L0/L1/L2 边界、L1 例外以及 L2 自检/Review/QA 责任分离；
- `docs/development/trellis.md`：向贡献者解释分级流程、`trellis-check` 用法和升级合并步骤。

不修改：

- `.trellis/spec/**`；
- `.agents/**`、`.codex/**`、`.trellis/agents/**`；
- `.trellis/.template-hashes.json`、`.trellis/.runtime/`；
- 全局 npm、`node_modules` 或 Trellis 上游源码；
- PetDock Swift 源码、测试逻辑、Makefile、Hook/脚本、构建或发布文件。

## 6. 一致性契约

workflow 必须明确：

1. 原实现者使用 `trellis-check` skill 做可写自检，但该步骤不是正式 Review；
2. 正式 Review 使用全新只读 Agent，完整覆盖且除阻断条件外不因首个 finding 提前结束；
3. findings 一次性汇总给同一实现负责人批量修复；
4. 新 SHA 的旧结论失效；
5. 第二轮仍有实质问题、需要第三轮时触发 `trellis-break-loop`；
6. 正式 QA 在 Review 清零之后。

本任务使用临时可重复的 `rg`/TOML 解析/Markdown gate 检查上述契约，不新增测试文件，以保持 L1 边界。

## 7. Trellis Update 兼容性

`.trellis/workflow.md` 在 `.trellis/.template-hashes.json` 中登记。修改后 `trellis update` 会把它识别为本地定制。workflow 本身必须保留一个项目本地升级说明：先 `trellis update --dry-run`，再 `trellis update --create-new`，人工比较 `.new` 并合并；禁止使用 `trellis update --force` 覆盖本地流程。哈希文件由 Trellis 管理，本任务不手工同步。

## 8. 风险与回滚

- **语义漂移**：通用 `trellis-check` 仍然可写；workflow 必须明确它只服务于原实现者自检，正式 Review 使用另一名全新只读 Agent。
- **L1 被滥用**：分类不清或跨级时强制按 L2；L1 明确排除可执行脚本、测试逻辑和 PetDock 运行行为。
- **升级覆盖**：只有 workflow 是 Trellis 模板定制面；`AGENTS.md` 的项目规则写在 managed block 外，`docs/development/trellis.md` 是普通项目文档。workflow 使用 `--create-new` 人工合并并回跑静态检查，禁止 `--force`。
- **回滚**：仅回退本任务修改的治理文件；不触碰现有未跟踪任务、archive 或 `design/` 内容。
