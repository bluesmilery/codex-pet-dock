<!-- TRELLIS:START -->
# Trellis Instructions

These instructions are for AI assistants working in this project.

This project is managed by Trellis. The working knowledge you need lives under `.trellis/`:

- `.trellis/workflow.md` — development phases, when to create tasks, skill routing
- `.trellis/spec/` — package- and layer-scoped coding guidelines (read before writing code in a given layer)
- `.trellis/workspace/` — per-developer journals and session traces
- `.trellis/tasks/` — active and archived tasks (PRDs, research, jsonl context)

If a Trellis command is available on your platform (e.g. `/trellis:finish-work`, `/trellis:continue`), prefer it over manual steps. Not every platform exposes every command.

Managed by Trellis. Edits outside this block are preserved; edits inside may be overwritten by a future `trellis update`.

<!-- TRELLIS:END -->

# Codex Pet Dock — 项目开发规则

> 本文件仅包含项目特定的持久规则，补充但不重复用户根级 `AGENTS.md` 通用规则（Python 环境、浏览器操作、谨慎编码等）。

## 0. 分级交付路径

- 每个请求先按 `.trellis/workflow.md` 分类为 L0 / L1 / L2；跨级或影响不明确时按最高风险级别处理。
- **L0（对话 / 只读）**：解释、讨论、状态查询和只读检查直接处理，不创建开发分支、worktree 或 Review/QA loop；活动任务中的 L0 请求不得推进任务状态。
- **L1（治理 / 文档）**：仅修改流程规则、说明文档、task/spec、AI agent 提示或非可执行配置，且不改变应用代码、测试逻辑、可执行脚本/Hook、构建发布、运行时或隐私安全行为。主 Agent 可直接实施，执行目标静态检查和一次按第 2 节模型选择规则创建的全新只读一致性检查 Agent；不创建实现、修复或 QA worktree，不进入反复 Review loop。若发现触及 L2 边界，停止并按 L2 重新规划。
- **L2（开发 / 高风险）**：应用代码、测试逻辑、可执行脚本/Hook、构建签名发布、运行时配置及隐私/TCC/ScreenCaptureKit 行为变化，必须执行本文件后续章节规定的完整闭环。
- L2 的原实现负责人在自己的 worktree 内使用 `trellis-check` **skill/checklist** 做可写自检和机械修复；不得把可写 `trellis-check` Agent 当作正式 Review。候选冻结完整 SHA 后，由按第 2 节模型选择规则创建的全新只读 Agent 完整 Review 并集中报告全部 P0/P1/P2；首轮有 findings 时由原实现负责人批量修复，第二轮仍有任何实质 finding 则执行 `trellis-break-loop` 并重新规划。正式 QA 只在 Review 清零后对同一冻结 SHA 执行。
- 本节是项目持久边界；详细阶段、状态提示和 Trellis 升级合并步骤以 `.trellis/workflow.md` 为准。以下第 1–7 节中涉及实现、Review 和 QA 的完整流程要求均适用于 L2，L1 按本节例外执行。

## 1. 仓库与分支

- 单仓库（mono-repo），无 submodule。
- `main` 是唯一的 GitHub 稳定/发布分支；`dev` 是本地集成分支；特性分支从 `dev` 创建。
- L2 的每个实现、修复、Review、QA 子 Agent 必须使用独立分支和独立 worktree；一个子 Agent 对应一个分支、一个 worktree。
- 子 Agent 只能在分配给自己的 worktree 内工作，禁止进入或修改其他 Agent 的 worktree。
- worktree 只隔离文件写入；主管仍须按文件或模块划分任务，并在集成时逐项处理潜在冲突。
- 严禁向 `main` 直接 push；推送 `main`、创建 tag / release 都需要**用户明确人工确认**。

## 2. Agent 编排与生命周期

- 对于 L2，主 Agent 只负责任务拆解、范围划分、派发、验收和集成，不直接修改业务代码；所有实现、测试和 Review 均委派给子 Agent。L1 按第 0 节由主 Agent 直接实施。
- 子 Agent 优先使用任务下达或已批准任务规划中显式指定的模型和推理强度；未显式指定的模型默认使用 `luna`，未显式指定的推理强度默认使用 `max`。若当前运行时无法满足解析后的配置，则停止派发并明确报告，不自动降级或替换模型。
- 每项任务同一时间只能有一个实现负责人；派发记录必须包含任务名、角色、worktree、分支、base commit、允许修改的文件范围、验收标准和目标 commit。
- 派发前必须预检：按上述优先级解析后的模型和推理强度实际可用、base commit 正确、分支与 worktree 唯一、worktree 初始状态干净，并且不存在负责同一任务的活跃子 Agent；任一项不满足则不启动。
- 子 Agent 状态统一为 `planning → working → waiting_input / blocked → review → qa → accepted → cleanup`；状态必须由实际活动和交付证据驱动，`idle` 仅表示当前无活动，绝不表示完成。
- 并发数量不得超过当前运行时上限，主 Agent 占用一个并发槽位；只有任务边界和依赖均独立时才可并行。
- L2 开发按审查、实现、独立 Review、QA 分阶段进行；实现子 Agent 先写失败测试，再做最小修复。
- 实现者不得 Review 自己的提交；独立 Review 和 QA 必须使用全新子 Agent，并针对明确的完整 commit SHA 验证。
- Review 子 Agent 只读审查，不直接修复；发现问题后退回该任务的实现子 Agent，修复产生新 commit 后原 Review 结论立即失效，必须对新 SHA 重新 Review。
- 子 Agent 的 `idle` 状态或口头结论不代表完成；交付必须包含修改文件、关键 diff、执行命令、实际结果、失败项、未验证项和 commit。
- 子 Agent 被替换、阻塞或会话需要重启时，必须提供结构化 handoff：base commit、当前 HEAD、已改文件、已执行命令及结果、失败项、未验证项和下一步。
- 自动测试、静态推断和真机 QA 分开验收；未实际执行的项目必须明确标记为“未验证”。
- 每个新版本使用全新的实现、Review 和 QA 子 Agent，禁止跨版本复用；版本结束后先记录或备份未合并 commit，再清理 worktree 和临时分支。

## 3. 代码纪律

- 文件边界严格：只改分配范围内的文件，不碰无关模块。
- 最小手术：每一行改动可追溯到任务要求。
- 先写测试（纯函数 / fixture），再实现，最后真机验证。
- Git 身份：`author` / `committer` 使用公开身份 `bluesmilery <19263500+bluesmilery@users.noreply.github.com>`；commit body **不带 Co-Authored-By**。

## 4. 质量门禁

以下门禁适用于所有 L2 候选，不因分级流程而降低：

- `swift build -c release` **0 warning** 是硬前提。
- `make test` 全绿（test-ui + test-data + test-shell）。
- 独立 Review 按可操作 P0 / P1 / P2 分类清零。
- 所有验收结论必须绑定完整 commit SHA；目标 commit 发生变化后，之前的 Review、测试和 QA 结论不得复用。
- 只有完成独立 Review 和 QA、满足全部门禁并进入 `accepted` 状态的 commit，才可作为集成到 `dev` 的候选。
- macOS 窗口 / TCC / ScreenCaptureKit 功能须**真机验证**（CGWindowList / 三态 QA），不依赖纯编译通过。

## 5. 隐私边界

- **不读** `auth.json` / token / 邮箱 / 会话正文；**不改** Codex 应用；**不用** 私有 CGS API。
- BubbleVisibility 只在**内存**计算 alpha 像素统计，**不 OCR、不保存图像、不记录颜色 / 文字**。
- 公开分发前对**全 history** 敏感扫描（真实本机路径 / 用户名 / wid / 坐标 / CDHash / SHA / 旧 hash / CoAuthored），残留需清理；task、spec、workspace 内容在纳入 Git 前先用稳定占位符脱敏。
- 私有 refs / bundle id 分叉永不上传 GitHub。
- `.trellis/spec/`、`.trellis/tasks/`、`.trellis/workspace/`、workflow、配置和脚本是项目共享资料，由 Git 管理；`.trellis/.developer`、`.trellis/.current-task`、`.trellis/.runtime/` 及临时/缓存路径仍按官方模板忽略。不得将本机 auth/token/邮箱/认证数据或会话正文写入被跟踪内容；公开 Git 身份例外，扫描只报告文件名和计数。

## 6. 构建与分发

- `make app`（ad-hoc 签名）只在**最终 QA / 发布阶段**执行，减少 TCC 重授权次数。
- `build/PetDock.app` 只是可覆盖的 staging；开发候选交付必须按 [dev 候选验收](docs/verification/dev-candidate.md#开发候选产物归档) 归档到全新、不可复用且绑定提交的 `YYYY-MM-DD-HHmmss-<label>-<shortSHA>` 本地目录。
- 分发包为 ad-hoc 签名（无 Developer ID、未公证），README 须含 **Preview + Open Anyway** 安装说明。
- 用户首次安装需手动授权 Gatekeeper + 屏幕录制 + （如需）系统音频录制。

## 7. 版本收尾

- 版本结束后终止旧子 Agent，清理不需要的 worktree 和分支。
- 清理前先做只读预检并列出目标：确认相关 commit 已记录、已集成或已备份，检查 worktree 是否存在修改或未跟踪产物；脏 worktree 一律保留并报告，不强制清理。
- 删除或清理被安全钩子拦截时，将目标移动到回收站，不使用 `rm -rf` 绕过。
- 清理前先备份未合并 refs（创建 `backup-*` tag 或记录完整 commit hash）。
- 保留 `main`、`dev`、发布 tag 和 release。

## 8. 与根级 AGENTS.md 的关系

- 尊重用户提供的根级 `AGENTS.md` 通用规则（Python 环境、Chrome Profile 只读、谨慎编码、最小改动）。
- 本文件仅补充项目特定内容，不重复或冲突。
