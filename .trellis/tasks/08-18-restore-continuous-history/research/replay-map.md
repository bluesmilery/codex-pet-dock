# 原历史到当前 dev 的重放映射（findings frozen）

## Topology Evidence

- `origin/main`：29 commits，根 `f412693725bd99d7429e751fb198823d3537a7a8`，tip `37fb66b70c39336ce886d7615d64aa19ac6a0c9a`。
- orphan `dev`：25 commits，根 `fd17217ba79b762c8eefaf188a2a17b7d4d9ffb9`，tip `68129dda36cd28b67849f27cd47eed5d4b1573b0`。
- 两者无 merge-base。
- `c2b3456` tree `d48b22411028512d057e56db83702e6f832f502d` 与旧对象 `d4914a0fbe07fdd7477d2e475c9bea8c254020af` tree 完全相同；内容可由 `origin/main` 后的旧连续开发链解释，不需要保留 orphan 根。
- 目标当前 `dev` tree：`720ba3d407a4d6b7a45eec7db291bfa7e2d592a6`。

## Rebuild Principles

- 不 cherry-pick `c2b3456` 根快照，不使用 `--allow-unrelated-histories`。
- 净化原 GitHub 历史后，按逻辑批次重建；隐私修复前移至首次引入点，不保留“先泄露后删除”的 tree。
- 仅对审计干净、边界独立的产品提交考虑顺序 cherry-pick；反复修正/计数/Review-gap 提交按终态 squash/recreate。
- 过程分支、旧 patch 等价提交和被最终链替代的 refs 全部 skip。

## Recommended Logical Batches

1. 净化原 GitHub 历史：保留干净提交顺序，改写 H1–H6 的首次引入点、trees 和 messages。
2. 重建 `c2b3456` 来源链的公开规则、产品可靠性、Trellis/日志、测试与文档，checkpoint tree 应为 `6fecdc...`（除受限 fixtures 重生造成的显式差异）。
3. 布局/BubbleVisibility 终态：`df77fbf + 8269cb9 + 2e3e0cf`。
4. Logger/Geometry 测试稳定化：`4dd7cb2 + 16d58ef`。
5. Agent/worktree 规则：`d269ce1`。
6. AppIcon：`74b4825`，以 blob/hash 单独验证。
7. Codex/Trellis 集成：`42536cf + e43aceb`。
8. 文档目录与架构：`de88e67 + 3cc67e5`。
9. 离线文档门禁：`3ed4e87 + 04d0a79 + 6a268a8`。
10. 运行时隐私安全：`d069d28 + 4227aed + 19dbe26 + 0a1ead2`。
11. Trellis task/path containment：`2634830 + ea63a4f + 1581f66 + 96979c7 + ec27b17 + 6a3a6e5`。

## Orphan Commit Actions

- `c2b3456`：recreate；不得成为 parent/merge parent。
- `df77fbf`、`8269cb9`、`2e3e0cf`：squash 为一个安全布局批次。
- `4dd7cb2`、`16d58ef`：squash 为测试稳定化批次。
- `d269ce1`：独立重放。
- `74b4825`：独立重放并验证二进制资源 hash。
- `42536cf`、`e43aceb`：squash。
- `de88e67`、`3cc67e5`：squash。
- `3ed4e87`、`04d0a79`、`6a268a8`：squash。
- `d069d28`、`4227aed`、`19dbe26`、`0a1ead2`：squash。
- `2634830`、`ea63a4f`、`1581f66`、`96979c7`、`ec27b17`、`6a3a6e5`：squash。

## Skip Set

- reflog/过程分支中已被最终链相同 patch 或修订版本替代的提交，包括 `866a874`、`969924c`、`3feede4`、`edff33b`、`1a289b0`、`3c33357` 等。
- 与当前 GitHub 链 stable patch-id 等价的旧 SHA 仅作为 provenance，不二次重放。

## Expected Tree

- 若仅改写历史中间态且重生 fixtures 与当前 synthetic 语义一致，最终候选应与当前 `dev` 产品 tree 等价。
- 首选验收：`git diff --exit-code dev dev-fix`。
- 若重生 3 个 restricted fixtures 导致必要差异，必须逐路径记录并独立验证 tests；不得把其他差异归因于冲突。

## High-risk Conflict Areas

- `.trellis/.template-hashes.json` 与生成文件。
- 文档目录重组和旧 README/test-count patch 的 rename/delete 冲突。
- 运行时隐私批次跨 `.trellis`、`.codex`、README、tests、docs。
- AppIcon 二进制资源。
- 受限 fixtures 的重生与 DataTests 语义。
