# Privacy Guidelines

> 隐私边界是本项目的硬约束，违规即阻断发布。

---

## 不读 / 不改 / 不用

- **不读** `auth.json` / token / 邮箱 / 会话正文；鉴权完全由 codex 子进程在其可信环境完成。
- **不改** Codex 应用本身（ChatGPT.app = `com.openai.codex`）。
- **不用** 私有 CGS / 私有 SPI API。

## BubbleVisibility 像素隐私

- 只在**内存**计算 alpha 像素统计（非透明占比 / bbox 占比）。
- **不 OCR、不保存图像、不记录颜色 / 文字 / 内容**。`computeAlphaStats` 仅返回两个 Double 比例。

### Runtime telemetry 白名单

- 仅在显式诊断/QA 模式下启用，默认关闭；输出绑定候选 SHA，但公开或被跟踪文件不得写真实 SHA/CDHash。
- 允许：聚合后的 obstacle kind 数量、capture outcome / visibility enum 数量、identity-change / wake callback 计数、visible obstacle 数量，以及 dock 相对本 tick 无障碍基础 frame 的匿名 bucket（`base`、`(0,32]`、`(32,64]`、`>64`）。
- 禁止：WID/PID、title、owner、绝对/精确坐标、screen 名称、颜色、文字、图像、逐像素值、会话内容或可关联到单个真实窗口的事件序列。
- 若需落盘，只能写入 PetDock 私有 0700/0600 目录，并优先输出时间窗聚合；截图、OCR 或 alpha 原始内容不得落盘。诊断产物进入 task/spec 前必须转成稳定占位符与枚举摘要。
- runtime evidence 的任意生产 sink 必须在语言层不可表达：持有地址状态的具体 collector 类型整体使用文件私有访问级别；其他生产文件只依赖不含 URL/sink 能力的 recorder 协议 existential，并经同文件无地址参数工厂取得实例，固定写入 `PrivateStorage.diagnosticsURL` 加 evidence 文件名。测试自定义 sink 只能位于专用编译 flag 包裹的同文件 test factory；release 构建不得定义该 flag。具体类型新增 initializer/subscript/property/method 不得扩大跨文件 API。
- 不得用 Swift declaration/constructor regex 或源码行 inventory 证明上述访问控制。编译 mutation 负责证明具体类型不可从外部文件命名/构造；编译 flag guard 必须按 shell token 同时识别 `-DNAME` 与 `-D NAME`，并断言测试 flag 只进入批准的 test-ui recipe。
- 禁止用 constructor 拼写枚举、空白/注释归一化或自制 Swift parser 证明“唯一构造点”。文本 guard 只承担不可被 trivia 分割的单一 token absence、presence shape 与编译 flag 布线计数；外部 direct / `.init` / alias / comment-split 构造和 production factory 注入 URL 必须以 release 编译失败作为主证据。
- 上述合同至少记录一条编译层 mutation 与一条布线层 mutation 的 FAIL → 撤销后 PASS；定义文件内新增 URL 型生产 API、测试 flag 进入 `Package.swift`、测试工厂脱离 flag 或 flag 出现在其他 recipe 都必须被可执行 canary 拒绝。

## 数据读取边界

- `TokenUsageLogReader` 只解析 `last_token_usage` 的**数值**字段，不读会话正文。
- `RateLimitClient` 经 stdio JSON-RPC 只取状态 / 比例 / 重置时间，不复制 auth.json。
- `RateLimitClient` 子进程环境从 HOME/TMPDIR/locale、非秘密 CODEX_HOME 与受控 PATH 白名单构建；不得继承 API key、token、cookie、代理凭证或未知变量。resolver 只接受 canonical 普通可执行文件，owner 为当前用户或 root 且无 group/world writable。

## 私有运行时存储

- 日志、诊断和 token cache 只能写入 `~/Library/Application Support/PetDock/` 私有目录；目录显式 0700，文件显式 0600，日志 no-follow 打开并拒绝外部 symlink。
- 默认诊断只落盘脱敏结构统计；不得写入标题、owner、真实 WID/PID、精确 bounds、screen 名称或 frame。
- Token cache key 使用版本化 SHA-256（sessionsRoot 相对路径输入）；序列化内容不得包含 home、`.codex`、rollout UUID，旧格式直接失效重建。

## 公开分发前扫描

- **全 history** 敏感扫描：`/Users/<user>` 路径 / 真实 wid / 真实坐标 / CDHash / SHA / 旧 hash / CoAuthored 残留。
- 文档示例坐标用占位符（`<qx>` / `<ay>` / `<petBottom>`），不写真实数值。

## Trellis / Git 内容隐私

- `.trellis/spec/`、`.trellis/tasks/`、`.trellis/workspace/`、`workflow.md`、`config.yaml` 和脚本是项目共享资料，由 Git 管理。提交前必须扫描内容，并将真实本机 home 路径、本机用户名及其他本机标识替换为 `<user>`、`<repo>`、`<worktree>` 等稳定占位符；不得为了规避隐私而整体忽略这些目录。
- `.trellis/.gitignore` 只排除 `.developer` / `.current-task` / `.runtime/`、临时文件、备份和 Python cache 等本机 runtime/临时状态。Trellis 0.6.14 的官方边界是目录规则基线，内容级扫描是本项目的发布前门禁。
- `config.yaml` 设 `session_auto_commit: true`，让 task archive 与 workspace journal 的共享变更由 Trellis 自动记录；自动提交不放宽内容隐私要求。
- 纳入 Git 的 task、spec 和 workspace 文件不得包含 `auth.json`、密钥、token、认证数据、邮箱、原始 session/conversation/transcript 或会话正文；扫描只报告文件名和计数，不回显疑似秘密原值。公开 Git 身份和明确的占位符/政策术语可以保留。
- `.trellis/.runtime/sessions/` 只保存 opaque context key 与最小工作流元数据；原始 session/conversation/transcript 值不得持久化。写入使用 0600 临时文件 + atomic replace，读取拒绝 symlink。
- `.trellis/.runtime/` 的 update marker 只使用身份 hash；runtime 与 marker 分别固定 0700/0600，canonical containment 和 no-follow 检查拒绝 symlink 外写。
