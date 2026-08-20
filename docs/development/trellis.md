# Trellis 开发接入

本项目使用 Trellis **0.6.14** 管理开发流程。当前仓库的活动平台是 **Codex**：`trellis platforms` 应显示 Codex，并指向 `.codex`；Codex 平台同时使用共享的 `.agents/skills/`。

本文只说明项目中已跟踪的 Trellis 结构、项目定制点和本地状态。当前项目只维护 Codex 平台；未实际启用其他平台时，不生成或维护对应的平台文件。

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

`.trellis/` 的模板文件由 Trellis 维护，项目持久规则优先放在托管区外的 `AGENTS.md`、项目 spec 或显式配置中。`.trellis/workflow.md` 是本项目唯一有意维护的 Trellis 模板定制，用于注入下文的分级交付与 Review 流程；其他 `.trellis/` 模板以及 `.codex/`、`.agents/` 生成文件不为这套流程做本地分叉，避免升级时多面合并。

## 分级交付与审查职责

| 路径 | 适用范围 | 执行与验证 |
| --- | --- | --- |
| L0 | 解释、讨论、状态查询、只读检查 | 主会话直接处理；不创建开发 task/worktree，不进入 Review/QA loop。 |
| L1 | 流程规则、说明文档、task/spec、AI agent 提示或非可执行配置 | 主会话最小修改；目标静态检查；一次全新 `luna + max` Agent 只读一致性检查。无实现、修复、QA worktree。 |
| L2 | 应用代码、测试逻辑、可执行脚本/Hook、构建发布、运行时配置、隐私/TCC/ScreenCaptureKit | 唯一实现负责人 + Review Readiness + 独立完整 Review + 正式 QA；跨级或不明确时按 L2。 |

L2 中，原实现负责人在自己的 worktree 内运行 `trellis-check` **skill/checklist**，结合目标测试、`swift build -c release`、`make test`、diff/隐私检查和相关 package Quality Check 做可写自检。`trellis-check` 自检不产生批准结论，也不替代正式 Review。

自检完成并冻结完整候选 SHA 后，由全新 `luna + max` 只读 Agent 完整审查，不因首个 finding 提前结束。首轮 findings 由主 Agent 去重并一次性退回原实现负责人批量修复；新 SHA 使旧结论失效。第二轮仍有任何实质 P0/P1/P2 时执行 `trellis-break-loop` 并回到规划，不进入第三轮逐项补丁。正式 QA 只在 Review 清零后针对同一冻结 SHA 执行，自动验证、静态推断和真机 QA 分开报告。

`AGENTS.md` 保存上述项目持久边界，`.trellis/workflow.md` 保存可被 Hook 注入的详细阶段和状态提示；两者语义必须保持一致。

## 本地 workflow 升级合并

升级 Trellis CLI 后，不要直接覆盖项目 workflow。先预览，再生成 sidecar 并人工合并：

```sh
trellis update --dry-run
trellis update --create-new
```

比较生成的 `.new` 文件与当前 `.trellis/workflow.md`，合入上游修复，同时保留 L0/L1/L2、实现者 `trellis-check` 自检、只读正式 Review、两轮熔断和 QA 后移规则。合并后重新运行 workflow 解析及文档门禁。禁止对本地 workflow 使用 `trellis update --force`，也不要手工修改 `.trellis/.template-hashes.json`。

## 本地状态与忽略边界

下列内容由初始化或任务流程在本机生成，属于本机 runtime/身份状态，不纳入项目共享配置：

- `.trellis/.developer`：当前开发者身份；
- `.trellis/.runtime/`、`.trellis/.current-task`：会话与当前任务指针；
- 临时文件、备份目录和 Python cache。

上述本机状态由仓库的 Trellis / Git ignore 规则覆盖。`.trellis/spec/`、`.trellis/tasks/`、`.trellis/workspace/`、`workflow.md`、`config.yaml` 和脚本是项目共享资料，按正常 Git 管理。纳入候选前必须做内容级隐私扫描：真实本机路径、用户名和其他本机标识替换为 `<user>`、`<repo>`、`<worktree>` 等稳定占位符，且不得包含本机 auth/token/邮箱/认证数据或会话正文；公开 Git 身份可以保留。扫描只报告文件名和计数，不回显疑似秘密原值。

`config.yaml` 的 `session_auto_commit: true` 允许 Trellis 自动记录 task archive 与 workspace journal；自动提交不绕过上述脱敏和审查。官方 `.trellis/.gitignore` 只负责本机身份、runtime、临时和缓存路径，不能用目录忽略代替内容治理。

## 文档门禁与 Docs Impact

公开文档目录入口是 [`docs/README.md`](../README.md)，其中记录 architecture、development、verification 文档的事实来源和更新触发条件。规则与事实分离：`.trellis/spec/macos/` 只保存开发门禁，单次任务的需求和证据保存在 `.trellis/tasks/`。

每个实现任务在规划和 Review 中填写 `Docs Impact: none | update | new`。行为、接口、数据边界、验证状态或开发流程变化时，必须在同一提交中同步相关文档，不能以 README 重复数字代替测试源码或验收记录。

提交文档或行为变更前运行：

```sh
make docs-check
make test-docs
```

`make test` 会先执行这两个 docs gate，再执行 test-privacy、test-ui、test-data、test-shell；当前测试数字和证据以 [`docs/verification/dev-candidate.md`](../verification/dev-candidate.md) 为准，文档测试另计。检查器只读仓库内公开 Markdown，不联网，也不读取认证文件、会话正文或浏览器 Profile。

## 日常检查

```sh
trellis platforms
trellis update --dry-run
git status --short
```

检查结果应显示 Codex active，且工作树只包含本次任务明确允许的文件。不要提交 `.trellis/.developer`、`.trellis/.current-task`、`.trellis/.runtime/` 或平台私有配置；task/workspace 共享记录应纳入审查后的候选。不要把本地认证文件、会话正文或用户路径写入被跟踪内容。

## Runtime 隐私边界

`.trellis/.runtime/sessions/` 只写入由 session/conversation/transcript 派生的 opaque context key 与最小工作流元数据；原始身份值和 transcript 路径不会持久化。runtime 与 session 目录使用 0700，JSON 以 0600 临时文件 fsync 后 atomic replace。JSONL context 引用必须是仓库内相对路径，读取前 canonical containment 检查会拒绝绝对路径、`..` 和逃逸 symlink。update marker 只使用身份 hash，并以 0600 原子写入；runtime/marker symlink 均拒绝。
