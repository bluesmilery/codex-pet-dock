# 恢复 Trellis 官方 Git 管理策略

Delivery Path: L2

## Goal

恢复 Trellis 0.6.14 官方默认的 Git 持久化边界：项目共享的 task、spec、workspace journal、workflow、配置和脚本均由 Git 管理；仅本机身份、会话 runtime、临时文件和缓存保持忽略。同时将隐私治理明确为内容级约束，禁止被跟踪内容包含真实本机路径、本机用户名、密钥、token、认证数据或会话正文。

## Background

- 用户已于 2026-08-20 明确批准创建本 L2 task。
- 当前项目将 `.trellis/workspace/` 整体忽略，并设置 `session_auto_commit: false`，偏离 Trellis 0.6.14 官方默认。
- 任务创建并开始规划时，`.trellis/tasks/` 的基线清点为 61 个文件，其中 17 个已被 Git 跟踪；规划过程新增的本任务设计文件同样属于待跟踪资料。
- 基线清点时 `.trellis/workspace/` 有 2 个本地文件，均未被 Git 跟踪。
- 只报文件名、不回显匹配原值的初筛发现：6 个未跟踪 task 文件含真实本机路径或本机用户名模式；workspace 文件未命中路径、邮箱或凭据模式。
- 项目公开 Git 身份 `bluesmilery` 及其 GitHub noreply 邮箱属于项目公开身份，不视为本机隐私；本机账户名和由其构成的绝对路径必须使用占位符。
- 第二轮正式 Review 对 `87d78212761da2d6baac16fadac39d43cf906f78` 报告 P1=1、P2=1：移除 `.claude/` 规则时误删同一复合句中的私有 refs / bundle id 分叉边界；新纳入 Git 的历史研究仍用现在时描述已失效的 `.claude/` 忽略策略。按项目规则已执行 `trellis-break-loop` 并重新规划。

## Requirements

1. `.trellis/.gitignore` 恢复 Trellis 0.6.14 官方模板边界，不再整体忽略 `workspace/`、`tasks/` 或 spec 子目录。
2. `.trellis/config.yaml` 恢复官方默认的 journal/task archive Git 行为，即 `session_auto_commit: true`。
3. `.trellis/tasks/**` 的活动任务、归档任务、PRD、设计、实施计划、上下文清单和研究资料应全部纳入 Git 管理。
4. `.trellis/workspace/**` 的共享索引、开发者索引和 journal 应纳入 Git 管理；`.trellis/.developer`、`.trellis/.runtime/` 和其他官方 runtime/临时路径继续忽略。
5. 纳入 Git 前，对现有未跟踪 task/workspace 内容执行内容级隐私扫描；将真实本机路径和本机用户名替换为明确占位符，同时保持任务语义和证据结构。
6. 不读取或提交 `auth.json`、密钥、token、认证内容或会话正文；扫描只能报告文件和计数，不回显疑似秘密原值。
7. 更新 `AGENTS.md`、`.trellis/spec/macos/privacy-guidelines.md`、`docs/development/trellis.md` 及其他直接受影响说明，使其统一表达官方 Git 边界和内容级隐私治理。
8. 保留项目既有 L0/L1/L2、worktree、Review、QA、候选交付和发布授权规则；本任务不修改应用业务行为。
9. 所有已有 task 状态和内容必须保留；不得为了得到干净状态而删除或归档不属于本任务的活动 task。
10. 删除当前未使用的项目根目录 `.claude/`，并移除根 `.gitignore` 对整个 `.claude/` 的忽略规则以及文档中的“`.claude/` 永不上传”表述；未来只有实际启用 Claude 平台时才重新生成对应平台文件。
11. 编辑包含多个独立约束的复合规则时，只移除本任务明确废止的子句；私有 refs 和 bundle id 分叉不得上传 GitHub 的既有边界必须保留。
12. 历史 task 内容继续保留原结论；若新纳入 Git 的资料以现在时描述已失效的仓库策略，只添加“当时基线”等时间限定，不把历史描述伪装成当前规则。

Docs Impact: update

## Acceptance Criteria

- [ ] `git check-ignore` 证明 `.trellis/tasks/**` 与 `.trellis/workspace/**` 不再被忽略。
- [ ] `git check-ignore` 证明 `.trellis/.developer`、`.trellis/.runtime/**`、临时文件、备份和 Python cache 仍按官方模板忽略。
- [ ] `.trellis/config.yaml` 的有效配置为 `session_auto_commit: true`。
- [ ] 当前全部 task/workspace 文件均被纳入候选 Git diff，没有遗留 `?? .trellis/tasks/...`。
- [ ] 隐私扫描对被跟踪候选不报告真实本机路径、本机用户名、私钥、凭据、token 或会话正文；公开 Git 身份和明确占位符允许保留。
- [ ] task 文件中的路径脱敏不改变 task 状态、需求、验收标准、研究结论或引用关系。
- [ ] `AGENTS.md`、privacy spec、Trellis 开发文档和实际 ignore/config 行为一致。
- [ ] 项目根目录 `.claude/` 不再存在，根 `.gitignore` 不再整体忽略 `.claude/`，文档不再将该目录描述为本项目的常驻本机资产。
- [ ] `AGENTS.md` 仍明确禁止将私有 refs 和 bundle id 分叉上传 GitHub；删除 `.claude/` 子句没有删除其他独立隐私/发布边界。
- [ ] 新纳入 Git 的历史 task 资料中，不存在把已失效 `.claude/` 忽略策略写成当前事实的现在时表述；修订仅增加时间限定并保留历史结论。
- [ ] `trellis update --dry-run` 不会静默覆盖项目本地 workflow 定制，并且官方 `.trellis/.gitignore` 边界核对通过。
- [ ] `make docs-check`、`make test-docs`、`swift build -c release` 和 `make test` 全部通过且 release build 0 warning。
- [ ] 完整候选 SHA 经独立只读 Review 达到 P0/P1/P2=0，并由全新 QA Agent 对同一 SHA 验证。

## Out of Scope

- 修改 PetDock 应用功能、UI、TCC 或 ScreenCaptureKit 行为。
- 删除、合并或擅自归档当前其他活动 task。
- push、创建 PR、修改 `main`、创建 tag 或发布 Release。
- 将原始 Codex/Claude 会话 transcript 或认证文件复制进 Trellis workspace。
- 为当前未使用的 Claude 平台重新初始化配置、命令或 skill。
