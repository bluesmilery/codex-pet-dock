# 恢复连续历史并净化提交

## Goal

在不移动本地 `main`、`dev` 的前提下，以 GitHub `main` 的原始提交链为祖先，在本地 `dev-fix` 上重建当前有效功能，并仅改写确有隐私问题的历史内容，使最终候选既保持连续祖先关系，又满足公开分发隐私要求。

## Background

- GitHub `main` / `origin/main` 当前为 `37fb66b70c39336ce886d7615d64aa19ac6a0c9a`，根提交为 `f412693725bd99d7429e751fb198823d3537a7a8`。
- 本地 `main`、`dev` 当前均为 `68129dda36cd28b67849f27cd47eed5d4b1573b0`，根提交为独立的 `fd17217ba79b762c8eefaf188a2a17b7d4d9ffb9`，与 GitHub 历史没有共同祖先。
- 用户预期不是保留 orphan 公共基线，而是在原 GitHub 历史上净化含隐私的 commit，并保持历史连续。
- 本地 `dev-fix` 已从 `origin/main` 创建；`main`、`dev` 必须保持不变，供用户比较。
- 全量研究已冻结：原 GitHub 可达链共 29 个 commit，存在旧私有 bundle ID、真实窗口/坐标/运行水位、旧 SHA/私有 ref、commit-message 构建指纹和 provenance 不明确 fixture；因此未改写的 `origin/main` tip 不能成为最终候选祖先。
- 原连续开发对象仍可追溯：`c2b3456` tree 与旧链提交 `d4914a0fbe07fdd7477d2e475c9bea8c254020af` tree 完全一致，可从 GitHub 原链连续重建后跳过重复 orphan 根。

## Requirements

- R1. 所有审计、重写和重放只发生在 `dev-fix` 及其专用 worktree；不得移动或提交到本地 `main`、`dev`。
- R2. 在实现前一次性完成原 GitHub 历史、当前 `dev` 历史和两棵树差异的全量审计，冻结完整 findings；不得发现一个就立即修一个。
- R3. 隐私审计覆盖所有将进入候选历史的 commit/tree，至少检查真实 `/Users/<user>` 路径、窗口 ID、坐标、CDHash、凭证/令牌、会话标识、Co-Authored-By、私有 refs/bundle 分叉与不应公开的 Trellis 本机状态；不读取真实 auth/token/会话正文。
- R4. 对确有隐私问题的历史内容做最小、可解释的改写；无隐私问题的原始提交保持内容、顺序、author 与 message，父 SHA 连锁变化导致的新 commit SHA 不视为额外内容改写。
- R5. 将当前 `dev` 相对原 GitHub 历史的有效产品、测试、文档、Trellis 与运行时隐私改动按逻辑批次重放到 `dev-fix`；不得把旧 orphan 根提交作为父提交或 merge parent。
- R6. 最终 `dev-fix` 必须以经审计干净的 GitHub 原始根 `fcd817e...` 为祖先，且与 `origin/main` 存在共同祖先；由于原链首个产品提交已污染，未改写的 `origin/main` tip 不得成为候选祖先。不得使用 `--allow-unrelated-histories` 生成双根 merge。
- R7. 建立可恢复点和完整映射：记录改写前 refs、每个原提交到新提交/替代批次的对应关系、丢弃项及理由；任何远端 force push 都不在本任务自动授权范围内。
- R8. Review 必须先完成全范围审查并一次性交付 findings；只有 Review 达到 P0/P1/P2=0 后才启动独立 QA。后续子 Agent 临时使用 `gpt-5.6-sol` + `high`。
- R9. 最终候选不得自动覆盖 `main`、`dev`，不得 push、tag、release 或运行真实 App/TCC；由用户比较并另行批准。
- R10. 三个禁止读取正文的 session-like fixture 不复制旧 blob；从明确 synthetic 模板重新生成，并将由此产生的最终 tree 差异列入允许差异清单。
- R11. 历史粒度采用用户确认的一对一方案：保留原 GitHub 链 29 个 commit、`030fb9f..b4b8a5e` 连续开发链 26 个 commit、`c2b3456..dev` 后继 24 个 commit；重复 orphan 根 `c2b3456` 仅记录 skip 映射。除隐私净化或变为空提交外，不 squash/split/drop 原提交。

## Acceptance Criteria

- [ ] AC1. `git rev-parse main` 与 `git rev-parse dev` 从任务开始到结束均保持 `68129dda36cd28b67849f27cd47eed5d4b1573b0`。
- [ ] AC2. `dev-fix` 从 `37fb66b70c39336ce886d7615d64aa19ac6a0c9a` 建立作为隔离 worktree；重建后 `git merge-base --is-ancestor f412693725bd99d7429e751fb198823d3537a7a8 dev-fix` 成功、`git merge-base dev-fix origin/main` 非空、`origin/main` tip 不是 `dev-fix` 祖先、候选仅有一个根且没有新 merge commit。
- [x] AC3. 完整隐私 findings 与重放研究已在实现前冻结于 task `research/`；没有边审边修。
- [ ] AC4. 最终 `dev-fix` tree 与目标当前产品树的预期差异逐项有依据；任何有意不重放内容均有记录。
- [ ] AC4a. 私有 old→new 映射恰好 80 行：29 个原 GitHub commit、26 个连续开发 commit、1 个重复 orphan 根 skip、24 个 orphan 后继；候选可达 commit 恰好 79 个，且无静默 drop/squash/split。
- [ ] AC5. 对 `fcd817e..dev-fix` 的全历史隐私扫描无未豁免真实敏感命中；扫描不读取禁止内容。
- [ ] AC6. `swift build -c release` 0 warning，项目 Python 环境下 `make test` 全绿，`git diff --check` 通过。
- [ ] AC7. 完整 Review 先行且 P0/P1/P2=0；随后全新独立 QA 绑定最终完整 SHA 并 ACCEPTED。
- [ ] AC8. 任务结束时仅交付本地 `dev-fix` 候选和比较/恢复说明；未移动 `main`、`dev`，未 push/tag/release，未启动 App/TCC。

## Out of Scope

- 更新 GitHub `main`、强制推送、修改分支保护规则。
- 覆盖本地 `main` 或 `dev`。
- 真机 TCC、ScreenCaptureKit、多显示器行为验证及发布打包；如最终变更涉及这些行为，另行授权。

## Key Decisions

- KD1. 用户确认采用一对一保留 commit 粒度方案，不采用约 11 个逻辑 squash 批次。
- KD2. 原 GitHub tip 已含隐私，最终候选保留干净根 `fcd817e`，从首个受影响提交开始重放/净化；未改写的 `030fb9f` 不作为候选祖先。
- KD3. 重复 orphan 根 `c2b3456` 不重放；以 tree 等价的旧连续提交 `b4b8a5e` 作为 provenance checkpoint。
- KD4. 三个受限 session-like fixture 从明确 synthetic 最小模板重新生成，不读取或复制旧 blob。
- KD5. Review 完整清零后才启动 QA；不对每个中间 commit 反复执行 Review/QA。

## Open Questions

None.
