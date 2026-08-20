# Implement Plan — 恢复连续历史并净化提交

## Phase A — Preflight and Freeze

- [ ] 在 `dev-fix` 专用 worktree 核对 branch/HEAD/clean/唯一性；固定 `/opt/homebrew/bin/git` 或记录实际 Git 版本。
- [ ] 再次验证 `main=dev=6a3a6e5...`、`origin/main=030fb9f...`、root/count/ancestry/无 merge。
- [ ] 生成并校验 80 行 source manifest：29 original + 26 continuous + 1 duplicate-skip + 24 orphan descendants。
- [ ] 将 research findings 转为私有机器可读 offender manifest；真实值不得进入 task/public docs。
- [ ] 建立可复用 staged tree + commit-message 历史隐私扫描器；禁止读取 3 个 restricted JSONL 旧 blob。
- [ ] 验证 `dev-fix` 当前仍为 `030fb9f...`；任何漂移停止。

## Phase B — Recovery Assets

- [ ] 用 expected-empty `git update-ref` 创建 6 个 `refs/private-backup/...`，逐个验证 SHA。
- [ ] `umask 077` 在仓库外创建 bundle，包含所有备份 refs；执行 `git bundle verify`。
- [ ] 创建权限 0600 的 mapping/offender/log 目录；确认不会被 Git 跟踪。
- [ ] 冻结恢复命令和 expected-old SHA；禁止 gc/prune/reflog expire。

## Phase C — Reconstruct Detached Candidate

- [ ] 在 `dev-fix` worktree detach 到干净 root `fcd817e...`，不移动 `dev-fix` ref。
- [ ] 保留 root 精确 SHA，写 mapping row 1。
- [ ] 顺序重放原 GitHub 后继 28 commits；对 H1–H6 首次引入点净化。
- [ ] 顺序重放 `030fb9f..b4b8a5e` 的 26 commits；前移净化导致空提交时保留 empty。
- [ ] 为 `c2b3456` 写 `duplicate-skip` row，验证当前 tree 等于经批准 checkpoint tree/差异清单。
- [ ] 顺序重放 `c2b3456..6a3a6e5` 的 24 commits。
- [ ] 在首次引入时从 schema/test expectations 生成 3 份最小 synthetic JSONL；不得打开旧 blob。
- [ ] 每个 commit 提交前执行 staged/message privacy gate；每个提交后记录 mapping 与 patch/tree 证据。
- [ ] 候选完成后核对 79 commits、80 mapping rows、单根、无 merge、orphan root 非祖先。

## Phase D — Implementation Self-check

- [ ] 对 candidate 每个 commit/tree/message 做完整 history privacy scan，分类高置信命中与允许占位符。
- [ ] 比较 `dev` 与 detached candidate tree；仅 restricted fixtures/批准净化可不同，逐路径记录。
- [ ] 验证全部 author 为公开身份、无 Co-Authored-By、无 replace refs。
- [ ] 运行 `git diff --check`、docs gate、`swift build -c release` 0 warning、项目 Python 下 `make test`。
- [ ] 所有自检通过后，使用 expected-old `git update-ref` 原子移动 `dev-fix` 到 candidate；切回 `dev-fix` 并确认 clean。
- [ ] 再次确认 `main/dev/origin/main/tag` 冻结值未变；不 push/tag/release。

## Phase E — Independent Review (before QA)

- [ ] 创建全新 `gpt-5.6-sol + high` Review Agent 和独立 branch/worktree，绑定最终完整 SHA。
- [ ] 一次性完成：拓扑、80-row mapping、offender manifest、全 history privacy、tree allowed-diff、identity、refs freeze、tests evidence 审查。
- [ ] Reviewer 完整审完后统一交付 findings；不得边发现边触发修复。
- [ ] 若 P0/P1/P2 非零，集中修复全部 findings，生成新 SHA 后重新做一次完整 Review。
- [ ] 仅 Review APPROVED/P0=P1=P2=0 后进入 Phase F。

## Phase F — Independent QA

- [ ] 创建全新 `gpt-5.6-sol + high` QA Agent 和独立 branch/worktree，绑定 Review 通过的同一 SHA。
- [ ] 运行项目 Python 环境下 docs gate 与完整 `make test`。
- [ ] 运行 `swift build -c release`，要求 0 warning。
- [ ] 重新跑候选可达历史隐私扫描、拓扑/commit count/mapping/tree/ref freeze 验证。
- [ ] 不运行 App/TCC/ScreenCaptureKit/网络；如行为差异需要真机 QA，停止并请求另行授权。
- [ ] QA ACCEPTED 后只交付本地 `dev-fix`、比较报告、恢复资产位置和未验证项。

## Required Evidence

- 开始/结束 `main`、`dev`、`origin/main`、`dev-fix`、tag SHA。
- 80 行 old→new/private mapping 与 79-commit candidate count。
- 根/merge-base/no-merge/orphan-exclusion 命令结果。
- 每类 H1–H6 的 sanitized count 与零残留结果（真实值脱敏）。
- restricted fixture 的“不读取旧 blob”执行记录与 synthetic schema/test 证据。
- `dev` vs `dev-fix` 逐路径允许差异。
- release 0 warning、tests、Review、QA 的完整 SHA 绑定结果。

## Explicitly Forbidden

- 修改/移动/reset/rebase `main` 或 `dev`。
- `--allow-unrelated-histories`、filter-branch、共享仓库 `filter-repo --force`、replace/graft。
- tag、push、`--force`、`--force-with-lease`、`--all`、`--mirror`。
- 读取旧 restricted JSONL、auth/token/邮箱/会话正文或 Chrome Profile。
- 将 mapping/offender 原文/private refs 加入候选。
- 在 Review 完整清零前启动 QA。
- 在恢复窗口运行 gc/prune/reflog expire。
