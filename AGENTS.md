# Codex Pet Dock — 项目开发规则

> 本文件仅包含项目特定的持久规则，补充但不重复用户根级 `AGENTS.md` 通用规则（Python 环境、浏览器操作、谨慎编码等）。

## 1. 仓库与分支

- 单仓库（mono-repo），无 submodule。
- `main` 是唯一的 GitHub 稳定/发布分支；`dev` 是本地集成分支；特性分支从 `dev` 创建。
- 严禁向 `main` 直接 push；推送 `main`、创建 tag / release 都需要**用户明确人工确认**。

## 2. 代码纪律

- 文件边界严格：只改分配范围内的文件，不碰无关模块。
- 最小手术：每一行改动可追溯到任务要求。
- 先写测试（纯函数 / fixture），再实现，最后真机验证。
- Git 身份：`author` / `committer` 使用公开身份 `bluesmilery <19263500+bluesmilery@users.noreply.github.com>`；commit body **不带 Co-Authored-By**。

## 3. 质量门禁

- `swift build -c release` **0 warning** 是硬前提。
- `make test` 全绿（test-ui + test-data + test-shell）。
- macOS 窗口 / TCC / ScreenCaptureKit 功能须**真机验证**（CGWindowList / 三态 QA），不依赖纯编译通过。

## 4. 隐私边界

- **不读** `auth.json` / token / 邮箱 / 会话正文；**不改** Codex 应用；**不用** 私有 CGS API。
- BubbleVisibility 只在**内存**计算 alpha 像素统计，**不 OCR、不保存图像、不记录颜色 / 文字**。
- 公开分发前对**全 history** 敏感扫描（`/Users/<user>` 路径 / 真实 wid / 坐标 / CDHash / SHA / 旧 hash / CoAuthored），残留需清理。
- 私有 refs / bundle id 分叉 / `.claude/` 永不上传 GitHub。

## 5. 构建与分发

- `make app`（ad-hoc 签名）只在**最终 QA / 发布阶段**执行，减少 TCC 重授权次数。
- 分发包为 ad-hoc 签名（无 Developer ID、未公证），README 须含 **Preview + Open Anyway** 安装说明。
- 用户首次安装需手动授权 Gatekeeper + 屏幕录制 + （如需）系统音频录制。

## 6. 与根级 AGENTS.md 的关系

- 尊重用户提供的根级 `AGENTS.md` 通用规则（Python 环境、Chrome Profile 只读、谨慎编码、最小改动）。
- 本文件仅补充项目特定内容，不重复或冲突。
