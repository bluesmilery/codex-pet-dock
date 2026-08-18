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

## 文档门禁与 Docs Impact

公开文档目录入口是 [`docs/README.md`](../README.md)，其中记录 architecture、development、verification 文档的事实来源和更新触发条件。规则与事实分离：`.trellis/spec/macos/` 只保存开发门禁，单次任务的需求和证据保存在 `.trellis/tasks/`。

每个实现任务在规划和 Review 中填写 `Docs Impact: none | update | new`。行为、接口、数据边界、验证状态或开发流程变化时，必须在同一提交中同步相关文档，不能以 README 重复数字代替测试源码或验收记录。

提交文档或行为变更前运行：

```sh
make docs-check
make test-docs
```

`make test` 会先执行这两个 docs gate，再执行 test-ui、test-data、test-shell；当前测试数字和证据以 [`docs/verification/dev-candidate.md`](../verification/dev-candidate.md) 为准，文档测试另计。检查器只读仓库内公开 Markdown，不联网，也不读取认证文件、会话正文或浏览器 Profile。

## 日常检查

```sh
trellis platforms
trellis update --dry-run
git status --short
```

检查结果应显示 Codex active，且工作树只包含本次任务明确允许的文件。不要提交开发者身份、session/journal、runtime 指针或平台私有配置；不要把本地认证文件、会话正文或用户路径写入文档。

## Runtime 隐私边界

`.trellis/.runtime/sessions/` 只写入由 session/conversation/transcript 派生的 opaque context key 与最小工作流元数据；原始身份值和 transcript 路径不会持久化。runtime 与 session 目录使用 0700，JSON 以 0600 临时文件 fsync 后 atomic replace。JSONL context 引用必须是仓库内相对路径，读取前 canonical containment 检查会拒绝绝对路径、`..` 和逃逸 symlink。
