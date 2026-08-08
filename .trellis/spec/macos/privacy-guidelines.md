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

## 公开分发前扫描

- **全 history** 敏感扫描：`/Users/<user>` 路径 / 真实 wid / 真实坐标 / CDHash / SHA / 旧 hash / CoAuthored 残留。
- 文档示例坐标用占位符（`<qx>` / `<ay>` / `<petBottom>`），不写真实数值。

## Trellis / workspace 隐私

- `.trellis/workspace/<developer>/` 是开发者机器身份（journal / session 痕迹），**不入库**，由各克隆者 `trellis init -u <name>` 本地生成。
- `.trellis/.gitignore` 已排除 `.developer` / `.current-task` / `.runtime/` 等本地状态。
- `config.yaml` 设 `session_auto_commit: false`，journal 不自动提交。
