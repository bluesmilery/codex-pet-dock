# Design — 恢复连续历史并净化提交

## 1. Scope / Trigger

本任务修复 Git 提交图与公开隐私边界：本地 `dev` 使用独立 orphan 根，而用户要求保留原 GitHub 单根历史，只改写含隐私的 commit。实现只移动本地 `dev-fix` 与私有备份 refs；`main`、`dev`、`origin/main`、tag 和远端保持冻结。

## 2. Frozen Inputs

| Name | SHA / Count | Role |
|---|---:|---|
| GitHub root | `f412693725bd99d7429e751fb198823d3537a7a8` | 已审计干净，候选唯一根 |
| `origin/main` tip | `37fb66b70c39336ce886d7615d64aa19ac6a0c9a` | 原 GitHub 29-commit 链的旧 tip；因祖先含隐私，不能成为候选祖先 |
| Continuous checkpoint | `d4914a0fbe07fdd7477d2e475c9bea8c254020af` | `origin/main` 后 26 commits 的 tip；tree 等于 orphan 根 tree |
| Orphan root | `fd17217ba79b762c8eefaf188a2a17b7d4d9ffb9` | 重复 tree，仅做 skip 映射 |
| Current product tip | `68129dda36cd28b67849f27cd47eed5d4b1573b0` | `main`/`dev` 冻结值与目标功能树 |
| Source mapping | 80 rows | 29 + 26 + 1 skip + 24 |
| Candidate commits | 79 | 1 preserved root + 28 + 26 + 24 |

实现前再次核对所有 SHA、count、线性 ancestry 和无 merge；任何漂移立即停止。

## 3. Reconstruction Architecture

```text
fcd817e (preserve exact clean root)
  └─ replay/sanitize original GitHub commits 2..29
      └─ replay/sanitize 030fb9f..b4b8a5e (26)
          ├─ map c2b3456 as duplicate-skip
          └─ replay/sanitize c2b3456..6a3a6e5 (24)
              └─ candidate tip → atomic update of dev-fix only
```

不使用 merge、`--allow-unrelated-histories`、graft 或 replace ref。候选在 detached HEAD 上构造，全部验证通过后才用带 expected-old 的 `git update-ref refs/heads/dev-fix <candidate> <old-dev-fix>` 原子移动 `dev-fix`。

## 4. Private Recovery Assets

实现前以 `git update-ref <ref> <sha> 000…000` 创建仅本地 refs：

- `refs/private-backup/08-18-restore-continuous-history/main`
- `refs/private-backup/08-18-restore-continuous-history/dev`
- `refs/private-backup/08-18-restore-continuous-history/origin-main`
- `refs/private-backup/08-18-restore-continuous-history/dev-fix-before`
- `refs/private-backup/08-18-restore-continuous-history/continuous-tip`
- `refs/private-backup/08-18-restore-continuous-history/orphan-root`

以 `umask 077` 在仓库外创建 bundle，并执行 `git bundle verify`。私有 mapping、offender manifest 和扫描日志放仓库外或 `.git/private-rewrite/`，权限 0600；不得进入候选 commit 或 push。恢复窗口禁止 `gc`、`prune`、`reflog expire`。

## 5. Replay Contract

### Source manifest

冻结一个有序 manifest，恰好 80 行：

```text
sequence old_sha source_range expected_parent action privacy_class
```

`action` 仅允许：`preserved-root`、`replayed`、`sanitized`、`preserved-empty`、`duplicate-skip`。

### Per-commit flow

1. `cherry-pick --no-commit <old_sha>` 应用单个原提交。
2. 仅当 offender manifest 指定时，净化 staged tree 或 commit message。
3. 在提交前扫描 staged tree、路径和待提交 message；命中未豁免模式则停止。
4. clean commit 以 `git commit -C <old_sha>` 保留 author、author date 和 message。
5. sanitized commit 保留公开 author/date，仅替换 manifest 指定内容/message。
6. 若因前移净化而变为空提交，使用 `--allow-empty` 保留一对一映射。
7. 记录 `sequence old_sha new_sha action reason patch_id_equal tree_scan_status`。

冲突只能按冻结 manifest 与相邻原提交语义解决；出现范围外冲突或需要自由重构时停止，不现场扩大设计。

## 6. Sanitization Contracts

| Class | Required rewrite | Validation |
|---|---|---|
| H1 old private bundle ID | 首次引入即使用公开 ID/泛化迁移说明 | 每个候选 tree/message 无旧 ID |
| H2 real WID/coordinates/screen geometry | 使用 `<wid>`、`<qx>`、`<ay>`、`<screenHeight>` 等占位符 | 无高置信真实窗口/坐标命中 |
| H3 runtime/account watermarks | 泛化为 synthetic/不含真实数值的验证说明 | 无真实 sample/window/quota/runtime 组合 |
| H4 old SHA/private refs/worker provenance | 从公开 docs/message 删除；仅私有 mapping 保留 old SHA | 候选 message/docs 无内部 refs/失效 SHA |
| H5 CDHash prefix | commit message 改为概念描述 | 无真实 CDHash |
| H6 quota fixture provenance | 从首次引入使用明确 synthetic plan/epoch | 测试与隐私扫描通过 |
| restricted JSONL | 不读旧 blob；从测试 schema 生成最小 synthetic JSONL | 路径保留、正文明确 synthetic、测试通过 |

## 7. Validation & Error Matrix

| Condition | Behavior |
|---|---|
| `main`/`dev`/`origin/main`/tag 漂移 | 立即停止，不创建候选 |
| backup ref 已存在 | 失败退出，不覆盖 |
| source manifest count/ancestry 不符 | 失败退出 |
| staged/message privacy scan 命中 | 不提交；记录 offender 并回到冻结 manifest 审核 |
| cherry-pick 范围外冲突 | `cherry-pick --abort`，保留证据并停止 |
| mapping 非 80 行或候选非 79 commits | Review 阻断 |
| orphan root 成为 ancestor | Review 阻断 |
| candidate tree 有非批准差异 | Review 阻断 |
| Review P0/P1/P2 非零 | 不启动 QA |
| QA 失败或 SHA 改变 | 不交付；新 SHA 重新 Review 后再 QA |

## 8. Good / Base / Bad Cases

- Good：根 `fcd817e` 精确保留，79 个单根线性 commit，80 行完整映射，只有 H1–H6/受限 fixtures 产生批准差异。
- Base：前移净化使某个后续 cleanup commit 为空；保留 empty commit 并记录映射。
- Bad：让 `030fb9f` 成为祖先、merge 两个根、复制受限旧 JSONL、把 private mapping 写入 repo、移动 `main/dev`、Review 未清零即 QA。

## 9. Review and QA Separation

实现 Agent 完成全部 79-commit 候选与自检后停止。独立 Review Agent 一次性审完整拓扑、映射、隐私和 tree 差异，完整报告 P0/P1/P2；findings 集中修复后重新 Review。仅 Review APPROVED 才创建全新 QA Agent执行 release build、完整测试和最终候选扫描。

## 10. Rollback

- detached 构造失败：`git cherry-pick --abort`；不移动 `dev-fix`。
- `dev-fix` 已原子移动但候选失败：先为失败 tip 创建私有 checkpoint ref，再用 expected-old `git update-ref` 恢复 `dev-fix-before`。
- 不依赖 reflog 作为唯一恢复手段，不使用 `reset --hard` 操作 `main/dev`。
- private backup refs 和 bundle 保留到用户确认候选/远端策略后；清理需另做只读预检。

## 11. Rejected Alternatives

- `filter-repo --force` / filter-branch：会在共享仓库扩大 ref 影响面，不适合只动 `dev-fix`。
- `rebase --root --onto`：根快照 add/add 冲突大，逐提交映射和定向净化不透明。
- `git replace` / graft：隐式视图易污染验收，且仍需永久化。
- `--allow-unrelated-histories`：保留双根，直接违反目标。
- 逻辑 squash：用户已选择一对一保留 commit 粒度。

## 12. Public Docs Impact

Docs Impact 为 `update`：最终只更新公开候选验证状态与新提交 SHA；不得把 old→new mapping、真实 offender 值、私有 backup ref 或本机路径写入公开文档。
