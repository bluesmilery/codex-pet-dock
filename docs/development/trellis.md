# Trellis 开发接入

本项目使用 Trellis **0.6.14** 管理开发流程。当前仓库的活动平台是 **Codex**：`trellis platforms` 应显示 Codex，并指向 `.codex`；Codex 平台同时使用共享的 `.agents/skills/`。

本文只说明项目中已跟踪的 Trellis 结构、项目定制点和本地状态。`.claude/` 是 Trellis 支持的其他可选平台，不是本项目当前必需的平台，也不应被当作仓库配置提交。

## 新克隆初始化

一次性安装 CLI，并在克隆根目录执行：

```sh
npm i -g @mindfoldhq/trellis
trellis --version       # 0.6.14 或兼容的更新版本
trellis init --codex -u <developer> -y
trellis platforms       # 确认 Codex 为 active
```

仓库已经包含 Codex 和 Trellis 的跟踪文件；初始化的作用是补齐本机开发者身份及缺失的标准平台文件。不要使用 force 覆盖项目配置。完成后可用 `trellis update --dry-run` 预览 CLI 模板差异，确认没有把本地状态或项目定制加入提交。

## 三个目录的职责

| 路径 | 标准生成 / 跟踪内容 | 项目定制 |
| --- | --- | --- |
| `.agents/` | Trellis 跨平台共享 skills（当前由 Codex 初始化同时写入 `.agents/skills/`） | 仅在需要项目专属 skill 时增加；现有 Trellis skill 文件保持与 CLI 模板一致。 |
| `.codex/` | Codex agents、hooks wiring 和项目级 config 的平台入口 | `config.toml` 固定项目文档入口和 agent 深度；`hooks/` 中的注入脚本及 `hooks.json` 与本仓库 Trellis workflow 对接。 |
| `.trellis/` | workflow、agents、scripts、版本 / template metadata 和任务运行时使用的目录 | `spec/macos/`、`spec/guides/`、`config.yaml` 与 workflow 体现本项目的 Swift/AppKit、隐私和质量约束；不要把生成的 web spec 当作项目规范。 |

`.trellis/` 的模板文件由 Trellis 维护，项目规则应放在托管区外的 `AGENTS.md`、项目 spec 或显式配置中。修改 `.codex/`、`.agents/` 的生成文件前，先确认是否属于项目定制；否则应通过 Trellis CLI 更新，避免只改一个平台导致漂移。

## 本地状态与忽略边界

下列内容由初始化或任务流程在本机生成，不属于项目配置：

- `.trellis/.developer`：当前开发者身份；
- `.trellis/workspace/<developer>/`：journal、session 记录等开发者机器状态；
- `.trellis/.runtime/`、`.trellis/.current-task`：会话与当前任务指针；
- `.trellis/spec/backend/`、`.trellis/spec/frontend/`：CLI 可能重新生成的默认 web spec，本项目只跟踪 `spec/macos/` 与 `spec/guides/`；
- 根目录 `.claude/`（若某贡献者启用其他平台）：由根 `.gitignore` 忽略，不能提交。

上述目录已由仓库的 Trellis / Git ignore 规则覆盖。`.trellis/tasks/` 是任务工作流产生的本地任务资料，当前不属于本次文档候选；它可能以未跟踪状态出现，提交时不要将其加入候选。项目配置、源码和公开文档仍按正常 Git 跟踪。

## 日常检查

```sh
trellis platforms
trellis update --dry-run
git status --short
```

检查结果应显示 Codex active，且工作树只包含本次任务明确允许的文件。不要提交开发者身份、session/journal、runtime 指针或平台私有配置；不要把本地认证文件、会话正文或用户路径写入文档。
