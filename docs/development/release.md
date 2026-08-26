# 发布上线流程

> 本文档是从 v0.1.0–v0.4.0 实际发布过程沉淀的执行清单，描述 feature 合入到 GitHub Release 公开的完整流程。规则边界（L2 闭环、签名策略、隐私要求）见项目 `AGENTS.md` 与 `.trellis/spec/macos/`；候选归档格式见 [dev 候选验收](../verification/dev-candidate.md)。

## 前提

- 功能已在 `feature/<slug>` 分支停放：独立 Review 与 QA 清零、验收通过、accepted SHA 已是该分支祖先。
- 用户已明确授权合入 `dev` 与上线（tag / push / Release 均需人工确认，见 `AGENTS.md` 第 1、6 节）。

## 1. 合入会话（专门开设，不与其他任务混做）

1. **只读预检**：`git fetch origin`；确认 `dev`、`feature/<slug>`、`origin/main` 状态与预期一致；`git merge-base dev feature/<slug>` 确认分叉点；列出两侧独有提交与重叠文件（comm 两个 name-only diff），预判冲突面。
2. **no-ff 合并**：`git merge --no-ff feature/<slug>`。冲突按 `AGENTS.md` 第 1 节语义合并——双方已验收内容都保留；任务工件（task.json / evidence 等）的 add/add 冲突通常取 feature 侧最终版（那是验收时的真实快照），不得机械 ours/theirs 整文件覆盖。
3. **合并 SHA 是新候选**：旧 SHA 的 Review / 测试 / QA 结论一律不复用，全部门禁对新 SHA 重跑。

## 2. 全量门禁（对合并后的 dev）

```sh
swift build -c release        # 0 warning 硬前提
make test                     # test-ui + test-data + test-shell 全绿（系统 python3 缺 pytest 时用 conda base）
```

任一失败停止发布，修复形成新 SHA 后回到本步。

## 3. 敏感扫描与脱敏（公开发布的硬前提）

对**全部新增 history** 扫描，不是只看最终树：

```sh
git diff <merge-base>..dev | grep -nE '^\+.*(<绝对home路径前缀>|真实用户名|工号|@|wid=[0-9]{3,}|0x[0-9a-f]{8,})'
```

- 命中项用稳定占位符脱敏（如 `<conda-base-python>`），脱敏形成新提交。
- 任务 evidence 文档是最常见泄漏点：本机解释器路径、测试命令行、绝对路径都会被带进来；发布前必须 `git grep '<home-user>' -- .trellis` 复查。
- 发布 bundle 本身也要字节扫描：`grep -rIq '/Users/' build/candidates/<dir>/PetDock.app/` 必须无命中。

## 4. 任务收尾提交（journal / 归档等 chore，必须在 bump 之前完成）

**所有会产生新提交的收尾工作都在版本 bump 之前做完**：

- journal 记录本次发布会话（add_session.py，内容写到脱敏/bump/归档为止；Release 发布本身是机械步骤，由 gh 输出与第 9 步终态验证留痕，journal 不必等它存在）。
- 任务归档（task.py archive）及其他 .trellis chore。

原因：tag 建立后任何新提交都会打破"四处同指"的对齐，而本仓库 tag 通道只走 GitHub API，事后补 chore 意味着再来一次 API 删建 tag 手术。chore 前置后，bump 成为最后一个内容提交，tag 从诞生起就指向最终状态。

## 5. 版本 bump

按语义化判断 minor / patch；性能优化、行为变化、缓存格式升级用 minor。bump 面清单：

- `build-resources/Info.plist`：`CFBundleShortVersionString`
- `README.md` / `README.zh-CN.md`：下载文件名
- `pyproject.toml`：`version`

bump 形成独立提交（`chore(release): bump version to X.Y.Z`）。

## 6. 构建与归档发布候选

```sh
make app    # 稳定签名，无证书即失败（不回落 ad-hoc）
```

归档到主工作树 `build/candidates/YYYY-MM-DD-HHmmss-release-vX.Y.Z-<shortSHA>/`，验证：

- `codesign --verify --deep --verbose=2` 通过；`defaults read .../Info.plist CFBundleShortVersionString` 等于目标版本。
- 在归档目录内打 zip：`zip -qr CodexPetDock-X.Y.Z-macOS-arm64.zip PetDock.app`，记录 SHA-256。

## 7. 同步 refs

发布基线对齐原则：**发布完成后本地 main、本地 dev、远程 main、tag 四处指向同一提交**（chore 已在第 4 步前置完成，bump 即最终提交）。

推送注意（本仓库 pre-push hook 只允许 `git push origin main` 单 ref）：

- **tag 推送 / 删除会被 hook 拦截**。远程 tag 操作一律走 GitHub API：`gh api -X POST repos/<owner>/<repo>/git/refs -f ref=refs/tags/vX.Y.Z -f sha=<sha>` 创建；`gh api -X DELETE repos/<owner>/<repo>/git/refs/tags/vX.Y.Z` 删除后重建实现移动。Release 元数据里的 `targetCommitish` 是创建时快照，tag 移动后不需要改它。
- 不要尝试 `--force`（会被安全钩子拦截）或绕过钩子；API 路径就是常态通道。

## 8. GitHub Release

**惯例（v0.1.0–v0.4.0 确立）**：

- 标题：**简约格式，与 tag 同名**（如 `v0.4.0`，不写产品名 / Preview 后缀——仓库名与 Pre-release 徽章已承载这些信息）。
- 状态：**Pre-release = true**（自签名未公证分发，不标正式版）；Draft = false 直接发布。
- Notes：英文；结构为 Performance / Fixes / Verification 三段，写实测数字与验证边界，不写未验证声明。
- 资产：`CodexPetDock-X.Y.Z-macOS-arm64.zip`。

`gh release create` 时显式带全参数（曾因漏 `--prerelease` 停在草稿态）：

```sh
gh release create vX.Y.Z <zip路径> --title 'vX.Y.Z' --prerelease \\
  --notes '...' --target <commit-sha>
```

发布后验证：

1. `gh release view` 确认 draft=false / prerelease=true / 标题格式。
2. `gh release download` 拉回资产比对 SHA-256 与本地一致。
3. `git ls-remote origin` 核对远程 main 与 tag。

## 9. 收尾（零新提交）

本步骤不产生任何新提交；对齐在第 7 步已天然成立。

1. 核对四处引用一致：本地 main / 本地 dev / 远程 main / tag 指向同一 SHA（git rev-parse + git ls-remote）。
2. `gh release view` 终态确认（draft=false / prerelease=true / 简约标题 / 资产在位）。
3. 清理检查：worktree 无脏文件、无遗留子 agent / channel、运行实例与发布版本对齐（或明确告知用户差异）。
4. 若此时发现必须修改的内容（含本文档），属于新会话工作：修复合入后再走第 7 步 API 路径重指 tag——这是补救通道，不是常规路径。

## 常见坑（实战记录）

- pre-push hook 只放行 main 单 ref；tag 全走 GitHub API。
- `gh release create` 不带 `--prerelease` 会停在草稿态；不带 `--title` 时标题取 tag 名。
- evidence 文档里的本机路径是最高频泄漏点；第 3 步的 history 级扫描不能省。
- journal / 归档等 chore 必须在 bump 之前完成（第 4 步）；发布后再补 chore 就得走 API 删建 tag 的补救通道——v0.4.0 实际踩过这个坑。
