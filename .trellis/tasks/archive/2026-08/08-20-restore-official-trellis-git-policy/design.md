# 设计：恢复 Trellis 官方 Git 管理策略

## 1. 设计目标

以本机已安装 Trellis 0.6.14 的官方模板和行为为基线，恢复项目共享 Trellis 资料的 Git 持久化，同时把隐私治理从“整类目录不入库”改为“入库前清理内容”。变更只涉及治理配置、说明文档和 Trellis 资料，不触碰 PetDock 运行时行为。

## 2. 来源与优先级

1. Trellis 0.6.14 官方 `.trellis/.gitignore` 模板控制 Trellis 自身的持久化边界。
2. Trellis 0.6.14 官方配置默认值控制 `session_auto_commit` 行为。
3. 用户本次要求控制内容级隐私边界，以及删除当前未使用的 `.claude/`。
4. 项目 `AGENTS.md` 控制 L2 worktree、Agent、Review、QA 和发布边界；这些规则保持不变。
5. 项目 privacy/documentation/quality specs 控制脱敏、文档同步和验证门禁。

若官方 Trellis 默认与用户明确隐私要求同时适用，则目录按官方规则入库，内容按用户要求先脱敏。

## 3. 变更边界

### 配置与忽略规则

- `.trellis/.gitignore`：与 Trellis 0.6.14 官方模板对齐，删除项目额外的 `spec/backend/`、`spec/frontend/`、`workspace/` 忽略项。
- `.trellis/config.yaml`：显式设置 `session_auto_commit: true`，使有效行为清晰可审计。
- `.gitignore`：删除对整个 `.claude/` 的忽略规则；不新增替代规则。
- `.gitattributes`：保留现有 `.trellis/workspace/*/journal-*.md merge=union`，无需改动。

### 内容迁移

- 将当前 `.trellis/tasks/**` 和 `.trellis/workspace/**` 全部纳入候选提交。
- 在 `git add` 前扫描未跟踪资料；真实 home 路径、本机用户名和其他本机标识替换为 `<user>`、`<repo>`、`<worktree>` 等语义明确的占位符。
- 保留 task 状态、时间、需求、结论、相对项目路径和引用关系。
- 公开 Git 身份 `bluesmilery` 及其 GitHub noreply 地址允许保留。
- 不打开认证文件，不复制原始会话正文；扫描结果只输出命中文件名和数量。

### 文档同步

- `AGENTS.md`：将 workspace/journal 改为官方 Git 管理边界；只移除 `.claude/` 永不上传子句；保留私有 refs / bundle id 分叉、内容级隐私与平台本机身份不得入库的独立规则。
- `.trellis/spec/macos/privacy-guidelines.md`：从目录排除策略改为内容级治理和官方 runtime 排除策略。
- `docs/development/trellis.md`：说明 task、workspace journal、spec 均由 Git 管理，runtime/identity 保持本机；删除当前 Claude 平台相关常驻说明。
- 其他文档只有在直接矛盾时才做最小同步。
- 对被编辑的复合规则执行删除词项检查：搜索 base 中被删除的独立政策关键词，逐项确认属于明确废止范围或已在候选中保留。
- 对本次新纳入 Git 的历史 task 资料执行时间语义检查：已失效策略只能作为“当时基线”保留，不得继续以现在时充当当前规则。

### `.claude/` 清理

- 清理前再次确认精确目标仍只有项目根目录 `.claude/settings.local.json`。
- 不把该本机文件复制到实现、Review 或 QA worktree，也不读取其正文。
- 候选通过 Review/QA 并集成到当前 `dev` 后，由主管删除该文件和空目录；若删除被安全钩子拦截，则将精确目标移动到系统回收站。
- 不读取文件正文，不修改或移动 Chrome Profile、Codex 配置或其他项目外目录。

## 4. 独立 worktree 数据迁移

当前部分 task/workspace 是未跟踪文件，新 worktree 不会自动包含它们。主管在派发实现前：

1. 记录 `dev` 的完整 base SHA，并创建唯一、干净的实现分支和 worktree。
2. 将本任务范围内的未跟踪 `.trellis/tasks/**`、`.trellis/workspace/**` 作为未提交输入逐项复制到实现 worktree；不得复制本机 `.claude/` 或无关的根目录 `design/`。
3. 比较文件清单和校验值，确认输入完整；不创建包含未脱敏内容的临时 commit。
4. 实现 Agent 只在自己的 worktree 内检查、脱敏、修改和提交。

这样既遵守一个 Agent 一个 worktree，也避免为迁移原始本机路径而制造 Git 历史。

## 5. 实施顺序

1. 只读清点并核对官方模板、当前文件清单、ignore 来源和敏感命中文件。
2. 在实现 worktree 导入未跟踪输入，并复核完整性。
3. 逐文件脱敏命中的 task/workspace 内容，先复扫为零再暂存。
4. 恢复 `.trellis/.gitignore` 和 `session_auto_commit` 官方行为。
5. 从候选配置和文档中移除 `.claude/` 常驻规则，同步根 `.gitignore`、`AGENTS.md`、privacy spec 和 Trellis 文档；用 base/HEAD 关键词对照确认未误删同句中的独立政策。
6. 检查所有新纳入 Git 的历史 task 中与本次策略相关的现在时描述；仅为已失效策略补充时间限定，保留原结论和证据结构。
7. 暂存全部 task/workspace 和直接受影响文件，确认无关 `design/` 未进入 diff。
8. 执行静态、文档、构建和测试门禁；由实现负责人使用 `trellis-check` 做可写自检。
9. 使用项目公开 Git 身份提交候选；冻结完整 SHA 后进入全新只读 Review 和全新 QA。
10. 候选 accepted 后，将源工作区中会与提交冲突的未跟踪 task/workspace 输入先备份到任务专属临时目录，以校验值确认候选内容已完整保留，再集成到 `dev`；随后精确清理当前项目根目录 `.claude/`。

## 6. 失败与回滚

- 任一敏感扫描命中未解释内容：不提交，先在实现 worktree 修复。
- 官方模板或 `trellis update --dry-run` 与设计不一致：停止并报告，不猜测覆盖。
- 发现 task/workspace 文件缺失：停止迁移并用源清单/校验值恢复，不删除现有资料。
- `.claude/` 删除被拦截：移入回收站并报告可恢复位置，不使用强制递归删除绕过。
- 集成前备份与 accepted 候选不一致：停止集成并保留备份，不能用候选覆盖来源不明的新内容。
- 候选提交后的回滚使用普通 `git revert` 或丢弃尚未集成的独立分支；不改写共享历史。

## 7. 非目标

- 不修改应用代码、测试逻辑、TCC、ScreenCaptureKit 或发布产物。
- 不归档或删除其他任务。
- 不重新启用 Claude 平台。
- 不执行 push、PR、`main`、tag 或 Release 操作。
