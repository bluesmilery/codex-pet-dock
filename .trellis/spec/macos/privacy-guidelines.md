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
