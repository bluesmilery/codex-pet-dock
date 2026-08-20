# 修复五项运行时隐私风险

## Goal

消除 `dev` 当前审计确认的五项运行时隐私风险，使公开候选在 Trellis 上下文读取、诊断与日志、Codex 子进程、Trellis runtime 状态和 token cache 五个边界上遵循最小读取、最小持久化和最小授权原则，同时保留现有可用功能。

## Background

- 目标基线：`dev` commit `3cecbcdf3cd4c67e491159ca3898db59e8b83bf6`。
- 当前树与 15 个可达 commit 未发现已提交的真实凭证、真实用户路径、真实 WID/坐标、CDHash、私有身份或真实会话正文。
- 静态审计确认五项代码层风险：Trellis context 路径越界、固定 `/tmp` 诊断/日志、Codex helper 完整环境继承、Trellis runtime 原始会话元数据、token cache 绝对 session 路径。
- 本任务修改行为与隐私边界，Docs Impact 为 `update`。

## Requirements

### R1 Trellis context 路径约束

- 所有 task/context JSONL 引用和目录引用在读取时必须 canonicalize，并限制在批准的仓库或任务根目录内。
- 拒绝绝对路径、`..` 逃逸和解析后越过根目录的 symlink；被拒绝内容不得进入模型上下文。
- 保留现有文本/二进制识别与单文件、总字节预算行为。

### R2 私有诊断与日志

- `--diagnose` 和 PetLogger 不再使用固定、可预创建的 `/tmp/petdock-*` 路径。
- 持久化目录和文件须显式采用私有权限；日志打开与轮转不得跟随外部 symlink。
- 默认诊断输出不持久化窗口标题、真实 WID/PID、owner 或精确坐标；如保留完整诊断能力，必须由清晰的显式不安全开关启用。
- `make diagnose`、`make clean-logs` 和中英文 README 与新行为一致。

### R3 Codex helper 最小环境

- helper 仅接收 app-server 正常启动所需的环境白名单，不继承无关 token、cookie、代理凭证或其他敏感变量。
- resolver 对候选做 canonical path、symlink 和信任边界校验；不得把未知可写替代品静默当作可信 Codex。
- 保留现有无 shell 的 `Process.executableURL` 启动方式和 JSON-RPC 行为。

### R4 Trellis runtime 元数据最小化

- runtime 不持久化原始 transcript 路径、conversation ID 或 session ID；仅保留会话隔离所需的不透明标识。
- `.trellis/.runtime` 目录和 session JSON 使用显式私有权限。
- 多会话隔离、current task 解析和清理行为保持兼容。

### R5 Token cache 去标识化

- on-disk cache 不包含 home 绝对路径、`.codex/sessions` 路径或 rollout 文件名/UUID。
- cache key 使用不可逆或无法还原原路径的稳定标识，仍支持同一文件的增量命中和删除淘汰。
- 旧格式 cache 可安全失效重建，不要求迁移保留。
- cache 目录和文件使用显式私有权限；缓存值仍只包含时间和 token 数值，不加入会话正文。

## Constraints

- 不读取真实 `auth.json`、凭证、浏览器 Profile 或真实会话正文；测试仅使用临时目录和合成 fixture。
- 不改变 BubbleVisibility 的内存 alpha 统计隐私边界。
- 不引入网络服务，不使用私有 CGS/SPI。
- 最小手术；Trellis 生成文件修改需同步模板 hash，避免后续 update 把修复误判为未知漂移。
- 控制按钮与 dock 底座避让不在本任务范围。
- Codex app-server 使用严格环境白名单：不传递 `OPENAI_API_KEY`、token、cookie、代理凭证或其他认证变量；仅保留启动所需的 `HOME`、受控 `PATH`、临时目录、locale 和明确的非秘密 Codex 路径配置。仅依赖环境变量认证的用户须改用 Codex 自身登录态。

## Acceptance Criteria

- [ ] AC1：绝对路径、`..`、逃逸 symlink 的 context fixture 被拒绝，仓库内合法文件/目录及预算行为测试通过。
- [ ] AC2：默认诊断落盘内容不含合成 title/WID/PID/owner/坐标；诊断路径是私有且非固定 `/tmp`；日志 symlink fixture 无法重定向写入。
- [ ] AC3：child environment 测试证明敏感变量被剔除，所需 HOME/PATH/临时目录/locale 等兼容变量按最终决策保留；不可信 resolver fixture 被拒绝。
- [ ] AC4：runtime JSON fixture 不含原始 session/conversation/transcript 值，权限与多会话隔离测试通过。
- [ ] AC5：序列化 token cache 不含合成 home 路径、`.codex`、rollout UUID，缓存命中/淘汰与私有权限测试通过。
- [ ] AC6：`swift build -c release` 0 warning；`make test` 全绿；新增 Python/Trellis 测试纳入统一门禁。
- [ ] AC7：中英文 README、数据层/验证文档和 macOS privacy spec 与最终行为一致；`make docs-check test-docs` 通过。
- [ ] AC8：独立 Review 对完整目标 SHA 的 P0/P1/P2 清零，独立 QA 绑定同一 SHA；不把未执行的 TCC/ScreenCaptureKit 真机项写成通过。
- [ ] AC9：完整 `dev` 可达历史敏感扫描继续无真实私密值；提交身份使用公开 noreply 地址且无 `Co-Authored-By`。

## Out of Scope

- 重写现有 Git 历史（当前历史未发现需要净化的真实隐私值）。
- 改动 Codex App、认证文件或用户 Chrome Profile。
- 控制按钮避让、dock 布局、主题视觉和其他无关功能。
- Developer ID、公证、发布或推送 `main`。

## Key Decision

- 用户已确认采用严格子进程环境策略，不为环境变量认证保留兼容例外。
