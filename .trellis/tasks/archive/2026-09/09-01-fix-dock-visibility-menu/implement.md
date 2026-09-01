# Implementation Plan

## 1. Dispatch Preflight

- 本会话所有实现、修复、正式 Review 与 QA 子 Agent 固定使用 `zhipu-bigmodel-coding/glm-5.3`、推理强度 `max`；若运行时不可用，停止并报告，不自动替代。
- 若真机步骤需要电脑操作，使用用户指定的 `kimi-cu`；Codex Computer Use 的安全限制不得通过其他 GUI 自动化绕过。
- 从 `feature/pet-window-adaptation` 的当前完整 tip 创建唯一 `codex/fix-dock-visibility-menu` 分支与相邻仓库 worktree `codex-pet-dock-worktrees/fix-dock-visibility-menu`。
- 记录完整 base commit，确认 worktree 干净、没有同任务活跃实现 Agent；Git identity 使用项目公开身份。
- 把当前 task 工件带入实现候选；不得 merge / rebase / cherry-pick 改写既有 accepted feature 提交。

## 2. Evidence Gate and Baseline

- 在未改产品代码的 feature 基线上运行现有 `test-ui` 与相关容器测试，记录真实结果。
- 先添加仅测试的菜单候选生产链回归，在批准基线上执行：
  - 无菜单容器宠物应显示；
  - 菜单候选出现时旧顺序会选择 generic primary，并使最终 `DockPanel.frame` 错位；
  - 菜单关闭后检查滞回 / cache。
- 取得真机脱敏触发分类：`independent-window` / `container-bbox-change` / `unknown`。只有第一类继续本计划；第二类回到 Phase 1，第三类不得宣称修复。
- 将每条 AC 的基线、触发、生产消费者、scheduler、最终 owner 和手工缺口写入 `research/ac-evidence-topology.md`。

## 3. Minimal Implementation

- 给 primary selection 增加类型化 strong / generic / none 语义，不解析诊断字符串。
- 在生产 tick 中以 `strong primary → container → generic only without container → none` 解析唯一宠物来源。
- 容器候选存在但 observation 尚未接受时保持 hidden 并依赖既有 callback / retry；禁止菜单候选临时接管。
- 保持 primary 的 `FollowLayoutPass` 和 container 的 `DockPanel.placeBelow` 消费链、capture cadence、deadband、origin signal 与 CPU 参数不变。
- 删除本改动造成的未使用符号，不整理相邻代码。

## 4. Verification

- 先运行定向红 / 绿测试，再运行：
  - `make test-ui PYTHON=.venv/bin/python`
  - `swift build -c release`
  - `make test PYTHON=.venv/bin/python`
- 确认 release build 零 warning；记录各 suite 实际通过 / 失败数。
- 在实现 worktree 内按 `trellis-check` skill/checklist 做可写自检和机械修复；冻结完整候选 SHA。
- 主 Agent 逐条审阅 `research/ac-evidence-topology.md`，确认菜单 fake 被生产 resolver 消费、scheduler 真实运行且断言实际 `DockPanel.frame` / visibility。

## 5. Formal Review and Repair Loop

- 对冻结 SHA 派发全新只读 Reviewer（`zhipu-bigmodel-coding/glm-5.3` / `max`），一次性报告全部 P0/P1/P2；实现者不得 Review 自己。
- 首轮有 findings：原实现者在同一 worktree 批量修复并产出新 SHA，旧 Review 全失效。
- 第二轮仍有实质 finding：执行 `trellis-break-loop`，重写不变量并回到规划；不得继续补单一路径补丁。

## 6. Formal QA

- Review 清零后，派发全新 QA Agent 针对同一冻结 SHA。
- `make app` 只在该阶段执行；稳定签名证书不存在或签名失败即失败，不允许 ad-hoc fallback。
- 按 dev-candidate 规则归档全新 candidate，并确认运行中的 app 确实来自该候选。
- 亮屏真机重放：正常宠物、打开右键菜单、打开子菜单（若可用）、关闭菜单、移动宠物；用户执行 Codex 菜单动作，QA 观察同一 SHA 的脱敏 outcome 与实际 UI。
- 至少 60 秒测量容器通道活跃稳定态 CPU；自动、静态、真机和用户体验分别报告。

## 7. Acceptance and Handoff

- 仅在同一 SHA 的 build / tests / Review / QA 全部满足后标记 accepted。
- 将 accepted SHA 以 merge 方式落到现有 `feature/pet-window-adaptation`，不得 rebase 或 cherry-pick 替换历史。
- 本任务不合入 `dev`。输出后续专门集成任务所需的 feature ref、accepted SHA、候选路径、门禁与未验证项。
