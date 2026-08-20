# 原 GitHub 历史隐私审计（findings frozen）

## Scope

- Reachable range: `f412693725bd99d7429e751fb198823d3537a7a8..37fb66b70c39336ce886d7615d64aa19ac6a0c9a`，含根提交。
- 29/29 commits、29/29 trees、890 tree entries、38 unique paths。
- 127 unique blobs / 1,030,360 bytes：124 个允许读取的 blob 完成内容扫描；3 个 session-like JSONL 仅查 path/hash/size/history，未读正文。
- 未扫描 dangling/unreachable objects；未读取 auth/token/邮箱/会话正文/Chrome Profile。

## Must Rewrite

### H1 — 旧私有 bundle ID

- 最早引入：`d775346fed4cec16cafad6f009fce7a084e0f5cc`。
- 路径：`Makefile`、`build-resources/Info.plist`、`docs/success-criteria.md`。
- 最后仍存在：`37fb66b70c39336ce886d7615d64aa19ac6a0c9a` 的 `docs/final-success-criteria.md` 迁移引用。
- 处置：从首次引入 tree 和相关 commit message 起替换为公开 ID/泛化说明；不得让旧 ID 出现在候选可达历史。

### H2 — 真实窗口、坐标和屏幕几何

- 最早引入：`d775346fed4cec16cafad6f009fce7a084e0f5cc`。
- 路径：`docs/pet-window-detection.md`、`docs/success-criteria.md`。
- 另一组重捕窗口数据：`505fc726113077be8719c6604abb7137205dcf79` 起见于 `docs/final-success-criteria.md`。
- `709054f9fe9746e38153d1d3e959c0df196cb766` 才从当时当前树删除，但旧 trees 仍污染。
- 处置：首次引入即改为占位符/合成值，删除“先泄露后删除”的中间历史。

### H3 — 真实运行水位与环境指纹

- 涉及 `505fc726113077be8719c6604abb7137205dcf79`、`833d740ea3851f1fa22552f804e55c45acf593ce`、`9089bac7c54513f6ffe29338b171e8acd9c767f9`、`426afd33128a3dfb2acc6658ce532f3b924dbe47`、`62b761b16056adc1110eed82b678292a0edab248`。
- 内容类型：真实 session 文件数、sample 数、窗口统计、额度百分比、本机 Node 版本。
- 处置：泛化为不含真实水位/版本的验收说明；同步净化相关 commit body。

### H4 — 旧 SHA、私有 refs 与内部 worker/task provenance

- `docs/final-success-criteria.md` 曾包含旧切片 SHA、base/修复/QA SHA，以及私有 ref 名 `release-candidate`、`fix-codex-path`。
- 相关历史区间从 `c1da6aff8fbf91f3a111aa75d4c3257e2805c4ee` 等引入，至 `a663af365211329f9ee025d893ca53b7c0d0e1b6` 仍存在。
- commit message 含旧 SHA：`91e6306`、`144acda`、`58e4a91`、`eae78ac`、`2759aa3`、`4e602b0`、`b3a5492`、`030fb9f`。
- commit message 含内部任务/worker 名：`0032a4f`、`58e4a91`、`171c65b`、`2759aa3`、`b3a5492`。
- 处置：重写文档和 commit message；映射表存于本地 task artifact，不进入公开候选历史。

### H5 — 构建指纹

- `27ee0c127cea9665ce3e10c696def213c8e17dce` commit body 含真实 CDHash 前缀。
- Tree 中相关值已为占位/概念说明。
- 处置：仅净化该 commit message；保留通用 CDHash/TCC 概念说明。

### H6 — provenance 不明确的早期 quota fixture

- `tests/DataTests.swift` 从 `9d3ab2c23d34c452b0372502c8d1ad966b9ba1c6` 至 `3dd7acf51334b45e47cd55ad09ebcddd62d22a5a` 使用生产风格 plan/epoch。
- `1131b83f6472426e84a38ae43721fef938ebf6ba` 才替换为明确 synthetic 值。
- 处置：候选的每个早期 tree 从首次引入即使用明确 synthetic 数据，不保留 provenance 不明的中间值。

## Metadata-only Restricted Fixtures

以下 blob 未读取正文：

- `tests/fixtures/sessions/2026/08/02/rollout-test-b.jsonl`（240 bytes，首次 `bceda743...`）
- `tests/fixtures/sessions/2026/08/03/rollout-test-a.jsonl`（967 bytes，首次 `bceda743...`）
- `tests/fixtures/sessions/2026/08/05/rollout-test-c.jsonl`（512 bytes，首次 `91e6306...`）

三者 blob 引入后未变化。路径与测试意图表明是 synthetic fixture，但禁读边界下不能认证正文；推荐从明确 synthetic 模板重新生成，而不是复制旧 blob。

## Clean / False-positive Results

- 真实 `/Users/<name>`：0。
- 个人邮箱：0；29/29 author/committer 均为公开 GitHub noreply 身份。
- 高置信 credential/JWT/private-key/API-key：0。
- UUID、真实 session/conversation/transcript ID：0。
- `.claude/`、`.trellis/workspace`、`.trellis/.runtime` tracked 文件：0。
- Co-Authored-By / Signed-off / Reviewed-by / Tested-by：0。
- 明确 synthetic PID/WID/坐标、占位路径和公共 bundle ID 可保留。

## Limitations

- `gitleaks` / `trufflehog` / `detect-secrets` 不可用；凭证结论来自高置信模式扫描。
- 未读取 3 个受限 fixture 正文。
- 未扫描 unreachable/dangling objects；公开候选验收只以 `dev-fix` 可达图为准，仓库对象库残留需在推送/发布策略中另行说明。
