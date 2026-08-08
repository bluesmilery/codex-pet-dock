# Trellis 接入说明

本项目用 [Trellis](https://github.com/mindfold-ai/trellis)（v0.6.14）做 AI 辅助开发流程编排。

接入原则：**仓库不含 `.claude/`**（项目规则「`.claude/` 永不上传 GitHub」），平台文件由各贡献者本地 `trellis init` 生成；仓库只入库 Trellis 内部模板/scripts（`trellis update` 自检通过）和 Swift/AppKit spec，移除机器身份与隐私风险。

## 新克隆者使用步骤

### 1. 全局安装 Trellis CLI（一次性）

```bash
npm i -g @mindfoldhq/trellis
trellis --version   # 应输出 0.6.14 或更高
```

### 2. 克隆后初始化（每个贡献者本地执行，必须）

仓库 **不含** `.claude/` 平台文件，克隆后必须本地生成。仓库 `.template-hashes.json` 故意不含 `.claude/` 条目（否则 `trellis init` 会误判「Claude Code already configured」并跳过生成）。运行：

```bash
trellis init --claude -u <你的名字> -y
```

- `--claude`：生成 `.claude/` 平台文件（agents / commands / hooks / skills / settings.json）。
- `-u <你的名字>`：创建 `.trellis/workspace/<你的名字>/`（journal / session 痕迹，**本地私有，已被 .gitignore 排除**）。
- `-y`：非交互。

> **切勿加 `-s`（skip-existing）**：fresh clone 无 `.claude/`，`-s` 在此无害但易误导以为「仓库里有文件可跳过」。正确心智是「仓库无 `.claude/`，init 会全新生成」。
> **切勿加 `-f`（force）**：它会覆盖仓库已入库的 `.trellis/` 配置（config.yaml / spec / AGENTS.md managed block）。

> **init 还会重新生成默认 web spec**：`trellis init` 会写入 `.trellis/spec/backend/` 与 `.trellis/spec/frontend/`（Trellis 内置的通用 web/backend 模板）。它们对 macOS 项目无用，且**未入库**——`.trellis/.gitignore` 已精确忽略这两个目录，`git add` 不会误提交。本项目唯一 tracked 的项目规范是 `.trellis/spec/macos/`。

init 会把 `.claude/` 条目写回**本地** `.template-hashes.json`（使 `platforms` 探测正常），但**仓库的** hashes 不含这些条目——本地与仓库 hashes 故意不同步，这是设计（具体条目数随 Trellis 版本变化，不固定）。

### 3. 验证

```bash
trellis platforms          # 应显示 Claude Code (claude-code) — .claude
trellis update --dry-run   # 见下方说明
```

> **`trellis update --dry-run` 的真实表现**（v0.6.14 实测）：绝大多数模板标 `Unchanged`；`AGENTS.md` 标 `Modified by you`（managed block 已在仓库，保留勿覆盖）；`.trellis/config.yaml` 可能标 `Template updated (will auto-update)`——这是 CLI 内嵌 hash 与仓库记录 hash 的计算口径略有差异所致，但实际 `trellis update` 执行后 `config.yaml` 内容**不变（幂等无害）**。看到 config.yaml 待更新不必紧张，它不会改动 tracked 文件内容。

## 已入库的内容（仓库跟踪）

| 路径 | 说明 | Trellis 管理 |
|------|------|--------------|
| `.trellis/scripts/` | Python 运行时脚本（task/context/developer） | ✅ vendoring，`trellis update` 可更新 |
| `.trellis/agents/` `workflow.md` `config.yaml` | 工作流定义 | ✅ vendoring |
| `.trellis/.template-hashes.json` `.version` | 模板校验（**不含 .claude/ 条目**，防 init 误判） | ✅ vendoring |
| `.trellis/spec/macos/` | Swift/AppKit/macOS spec（本项目唯一 tracked 的项目规范，替换默认 web spec） | ❌ User data，本地维护 |
| `.trellis/spec/guides/` | 通用思维指南 | User data |
| `.trellis/workspace/index.md` | 空索引模板（"(none yet)"，不含身份） | 模板 |
| `AGENTS.md` | 公开版项目规则 + Trellis managed block | managed block 由 Trellis，外部由项目 |

## 不入库的内容（隐私 / 机器身份 / 平台本地）

| 路径 | 原因 |
|------|------|
| `.claude/`（整个目录） | **项目规则永不上传 GitHub**；平台文件各贡献者本地 `trellis init --claude` 生成；AO 本地 hooks（settings.local.json）亦在此 |
| `.trellis/spec/backend/` `.trellis/spec/frontend/` | `trellis init` 生成的默认 web 模板（对 macOS 项目无用）；`.trellis/.gitignore` 已忽略，仅 `spec/macos/` 入库 |
| `.trellis/workspace/<developer>/` | 开发者机器身份、journal、session 痕迹 |
| `.trellis/tasks/` | 任务实例（各克隆者本地） |
| `.trellis/.developer` `.current-task` `.runtime/` | 本地运行时状态（`.trellis/.gitignore` 已排除） |

## 关键配置

- `.gitignore` 忽略整个 `.claude/`（恢复 C12 之前的项目规则）。
- `config.yaml` 设 `session_auto_commit: false`：journal 不自动提交（隐私）。
- 仓库未入库默认 web backend/frontend spec，项目规范只用 `.trellis/spec/macos/`（directory-structure / appkit-conventions / quality / privacy）。注意 `trellis init` 会**重新生成** `spec/backend/` 与 `spec/frontend/`（默认 web 模板），`.trellis/.gitignore` 已忽略它们，勿提交。
- `AGENTS.md` 顶部含 `<!-- TRELLIS:START/END -->` managed block，外部内容（项目规则）由项目维护。
- `trellis init --claude -u <name>` 会在本地写回 `.claude/` 到 hashes 使 `platforms` 正常；仓库 hashes 保持不含 `.claude/`。