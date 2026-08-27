# Execution Plan

前置：worktree codex-pet-dock-worktrees/cs-live-layer-anchor（分支 codex/cs-live-layer-anchor，基线 ba8b87f）。所有命令在 worktree 内执行；禁止进入其他 worktree。

## 步骤

1. 红测先行：按 design.md 新增"死层排前 + Mascot 参照"生产组合 fixture。
   - verify：在未修改基线运行目标测试入口 → 新测试失败、既有测试全绿；记录命令与输出（AC1 基线证据）。
2. 最小实现：按 design.md 修改 PetTracker / FollowTickPlan / BubbleVisibility（以实际最小改动面为准）；匹配现有中文注释风格。
   - verify：红转绿；既有 T-cs 系列全绿。
3. 边界与回退测试（AC3 / R3）：窗口上/下界、全部候选出窗、观察不可用。
   - verify：新增测试绿，无跳过。
4. Docs 同步：检索 docs/ 中 CS 代表选择/锚定语义描述，最小更新（Docs Impact: update）。
   - verify：make docs-check 与 make test-docs 绿。
5. 全量门禁：swift build -c release 0 warning；make test 全绿（系统 python3 缺 pytest 时按项目惯例用 miniconda python，以 Makefile 实际要求为准）。
   - verify：命令实际输出记录。
6. trellis-check 自检（可写）+ 填写 research/ac-evidence-topology.md（覆盖 AC1–AC4）→ 冻结完整 40 位 SHA，向主 Agent 交付：修改文件、关键 diff、命令输出、失败项、未验证项、commit。
7. 主 Agent 流程：核验 AC 证据 → 派发全新只读 Review（同 SHA）→ 有 finding 则一轮批量修复 + 新 SHA 复审 → Review 清零后 QA（真机，AC5）→ accepted 后按分支规则停放 feature/。

## 风险文件

- Sources/PetDock/PetTracker.swift
- Sources/PetDock/FollowTickPlan.swift
- Sources/PetDock/BubbleVisibility.swift
- Tests/main.swift

## 回滚点

单逻辑提交；git revert 即完整回滚。无数据迁移、无配置变更。

## Follow-up（2026-08-27 体验回归）

在 HEAD `7bfe9a9`（QA SHA `23678f6` 为其祖先）上最小修复，不要 rebase/amend 已 Review 的提交。

1. 红测：稳定身份多 CS fixture 证明参考通道当前会捕获 CS（或 0.1s 节奏）。基线（当前 HEAD 未改产品前）失败。
2. 最小实现：`updateReferences([mascot])` only；参考 cadence = identityDirty ? 0.1s : 1.0s；活层判定读主导 `observation(for:)` 的 CS contentBottom + 参考通道的 Mascot 脚底。
3. AC1/AC2/AC3 既有 T-cla/T-cs 保持；captureCallCount 类断言按"主导 CS + 参考仅 Mascot"改写并注明。
4. 全量门禁 + 5× UI 稳定性；`DockPanel.swift`/`Follower.swift` 相对 ba8b87f 仍为 0 diff。
5. 更新 ac-evidence-topology AC6 行。
