# 发布上线流程

> 本文档是从 v0.1.0–v0.4.0 实际发布过程沉淀的执行清单，描述 feature 合入到 GitHub Release 公开的完整流程。规则边界（L2 闭环、签名策略、隐私要求）见项目 `AGENTS.md` 与 `.trellis/spec/macos/`；候选归档格式见 [dev 候选验收](../verification/dev-candidate.md)。

## 前提

- 功能已在 `feature/<slug>` 分支停放：独立 Review 与 QA 清零、验收通过、accepted SHA 已是该分支祖先。
- 用户已明确授权合入 `dev` 与上线（tag / push / Release 均需人工确认，见 `AGENTS.md` 第 1、6 节）。

## 1. 合入会话（专门开设，不与其他任务混做）

1. **只读预检**：`git fetch origin`；确认 `dev`、`feature/<slug>`、`origin/main` 状态与预期一致；`git merge-base dev feature/<slug>` 确认分叉点；列出两侧独有提交与重叠文件（comm 两个 name-only diff），预判冲突面。
2. **no-ff 合并**：`git merge --no-ff feature/<slug>`。冲突按 `AGENTS.md` 第 1 节语义合并——双方已验收内容都保留；任务工件（task.json / evidence 等）的 add/add 冲突通常取 feature 侧最终版（那是验收时的真实快照），不得机械 ours/theirs 整文件覆盖。
3. **合并 SHA 是新候选**：旧 SHA 的 Review / 测试 / QA 结论一律不复用，全部门禁对新 SHA 重跑。

## 2. 任务收尾提交（journal / 归档等 chore，全部在门禁之前完成）

**所有会产生新提交的工作都在敏感扫描与门禁之前做完**：

- journal 记录本次发布会话（add_session.py，内容写到合入/脱敏为止；Release 发布是机械步骤，由 gh 输出与第 10 步终态验证留痕，不必等它存在）。
- 任务归档（task.py archive）及其他 .trellis chore。

原因：敏感扫描与全量门禁验证的必须是**最终树**。任何后补提交（哪怕只是 journal）都会让"扫描过/门禁过"的结论指向旧 SHA，同时打破 tag 四处同指。chore 全部前置后，扫描与门禁之后零新提交（bump 除外，见第 5 步说明）。

## 3. 敏感扫描与脱敏（公开发布的硬前提）

对**全部新增 history** 扫描，不是只看最终树：

```sh
git diff <merge-base>..dev | grep -nE '^\+.*(<绝对home路径前缀>|真实用户名|工号|@|wid=[0-9]{3,}|0x[0-9a-f]{8,})'
```

- 命中项用稳定占位符脱敏（如 `<conda-base-python>`），脱敏形成新提交。
- 任务 evidence 文档是最常见泄漏点：本机解释器路径、测试命令行、绝对路径都会被带进来；发布前必须 `git grep '<home-user>' -- .trellis` 复查。
- 发布 bundle 本身也要字节扫描：`grep -rIq '/Users/' build/candidates/<dir>/PetDock.app/` 必须无命中。

## 4. 脱敏后复扫清零

脱敏本身产生新提交，完成后对`<merge-base>..dev` 全区间**再扫一次**确认零命中；同批顺带确认 docs gate：`make docs-check`（脱敏用到的占位符若含路径样式也会被拦）。

## 5. 全量门禁（对脱敏后的最终树，最后执行）

```sh
swift build -c release        # 0 warning 硬前提
make test                     # test-ui + test-data + test-shell 全绿（系统 python3 缺 pytest 时用 conda base）
```

门禁放在 chore 与脱敏**之后**：它验证的就是将要发布的最终树（bump 之前的内容最后状态）。任一失败停止发布，修复形成新 SHA 后**回到第 2 步**（新提交可能引入新的敏感内容或需要新的 journal 记录，不能直接回到本步）。

## 6. 版本 bump

按语义化判断 minor / patch；性能优化、行为变化、缓存格式升级用 minor。bump 面清单：

- `build-resources/Info.plist`：`CFBundleShortVersionString`
- `README.md` / `README.zh-CN.md`：下载文件名
- `pyproject.toml`：`version`

bump 形成独立提交（`chore(release): bump version to X.Y.Z`）。

## 7. 构建与归档发布候选

```sh
make app    # 稳定签名，无证书即失败（不回落 ad-hoc）
```

归档到主工作树 `build/candidates/YYYY-MM-DD-HHmmss-release-vX.Y.Z-<shortSHA>/`，验证：

- `codesign --verify --deep --verbose=2` 通过；`defaults read .../Info.plist CFBundleShortVersionString` 等于目标版本。
- 在归档目录内打 zip：`zip -qr CodexPetDock-X.Y.Z-macOS-arm64.zip PetDock.app`，记录 SHA-256。

## 8. 同步 refs

发布基线对齐原则：**发布完成后本地 main、本地 dev、远程 main、tag 四处指向同一提交**（chore 已在第 2 步前置完成；扫描/门禁验证的就是最终内容树）。

推送注意（本仓库 pre-push hook 只允许 `git push origin main` 单 ref）：

- **tag 推送 / 删除会被 hook 拦截**。远程 tag 操作一律走 GitHub API：`gh api -X POST repos/<owner>/<repo>/git/refs -f ref=refs/tags/vX.Y.Z -f sha=<sha>` 创建；`gh api -X DELETE repos/<owner>/<repo>/git/refs/tags/vX.Y.Z` 删除后重建实现移动。Release 元数据里的 `targetCommitish` 是创建时快照，tag 移动后不需要改它。
- 不要尝试 `--force`（会被安全钩子拦截）或绕过钩子；API 路径就是常态通道。

## 9. GitHub Release

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

## 10. 收尾（零新提交）

本步骤不产生任何新提交；对齐在第 8 步已天然成立。

1. 核对四处引用一致：本地 main / 本地 dev / 远程 main / tag 指向同一 SHA（git rev-parse + git ls-remote）。
2. `gh release view` 终态确认（draft=false / prerelease=true / 简约标题 / 资产在位）。
3. 清理检查：worktree 无脏文件、无遗留子 agent / channel、运行实例与发布版本对齐（或明确告知用户差异）。
4. 若此时发现必须修改的内容（含本文档），属于新会话工作：修复合入后再走第 8 步 API 路径重指 tag——这是补救通道，不是常规路径。

## 常见坑（实战记录）

- pre-push hook 只放行 main 单 ref；tag 全走 GitHub API。
- `gh release create` 不带 `--prerelease` 会停在草稿态；不带 `--title` 时标题取 tag 名。
- evidence 文档里的本机路径是最高频泄漏点；第 3 步的 history 级扫描不能省。
- chore（journal/归档）、脱敏、门禁的顺序：chore → 扫描 → 门禁（第 2→3→5 步）。门禁必须对最终树最后执行；chore 后置会让扫描/门禁结论指向旧 SHA，发布后后补则要走 API 删建 tag 的补救通道——v0.4.0 两个坑都实际踩过。
