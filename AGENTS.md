# Codex Pet Dock — 项目开发规则

> 本文件仅包含项目特定的持久规则，补充但不重复用户根级 `AGENTS.md` 通用规则（Python 环境、浏览器操作、谨慎编码等）。

## 1. 仓库与分支

- 单仓库（mono-repo），无 submodule。
- `main` 是唯一的 GitHub 稳定/发布分支；`dev` 是本地集成分支；`feature/*` 从 `dev` 创建新分支 + 独立 worktree。
- `feature/*` 分支命名在 AO session namespace 下以便 Orchestrator 追踪。

## 2. 合并与推送

- `dev` → `main`、push `main`、创建 tag / GitHub release 都需要**用户明确人工确认**。
- 只显式 `git push origin main`；**禁止** `push --all` / `--mirror` / push `dev` / `feature/*` / AO 分支。
- 本地 `dev` 同步用 `update-ref`（dev 未 checkout 时）或 `merge --ff-only`，不用 `reset --hard`。

## 3. Worker 生命周期

- 每个新版本创建**全新 Orchestrator** 和**全新任务 Worker / 独立 Review Worker**，禁止跨版本复用旧 Worker。
- Orchestrator **只协调不编码**；所有实现、测试、Review 委派 Worker。
- Worker 聚焦分配任务，不做无关重构。

## 4. 代码纪律

- 文件边界严格：只改分配范围内的文件，不碰无关模块。
- 最小手术：每一行改动可追溯到任务要求。
- 先写测试（纯函数 / fixture），再实现，最后真机验证。
- Git 身份：`author` / `committer` 使用公开身份 `bluesmilery <19263500+bluesmilery@users.noreply.github.com>`；commit body **不带 Co-Authored-By**。

## 5. 质量门禁

- `swift build -c release` **0 warning** 是硬前提。
- `make test` 全绿（test-ui + test-data + test-shell）。
- 独立 Review Worker 按可操作 P0 / P1 / P2 分类清零。
- macOS 窗口 / TCC / ScreenCaptureKit 功能须**真机验证**（CGWindowList / 三态 QA），不依赖纯编译通过。

## 6. 进度轮询

- 默认 **5 分钟**间隔轮询 Worker 进度。
- 仅 TCC 授权、短暂 UI 状态等**交互场景**可立即检查（≤30s）。

## 7. 隐私边界

- **不读** `auth.json` / token / 邮箱 / 会话正文；**不改** Codex 应用；**不用** 私有 CGS API。
- BubbleVisibility 只在**内存**计算 alpha 像素统计，**不 OCR、不保存图像、不记录颜色 / 文字**。
- 公开分发前对**全 history** 敏感扫描（`/Users/<user>` 路径 / 真实 wid / 坐标 / CDHash / SHA / 旧 hash / CoAuthored），残留需清理。
- 私有 AO refs / bundle id 分叉 / `.claude/` 永不上传 GitHub。

## 8. 构建与分发

- `make app`（ad-hoc 签名）只在**最终 QA / 发布阶段**执行，减少 TCC 重授权次数。
- 分发包为 ad-hoc 签名（无 Developer ID、未公证），README 须含 **Preview + Open Anyway** 安装说明。
- 用户首次安装需手动授权 Gatekeeper + 屏幕录制 + （如需）系统音频录制。

## 9. 版本收尾

- 版本结束后**终止旧 Workers**、cleanup worktrees、清理不需要的分支。
- 删除 / 清理被安全钩子拦截时，**移到回收站**（不 `rm -rf`）。
- 先备份未合并 refs（`git tag backup-*` 或记录 hash），再清理。
- 保留 `main` / `dev` / tag / release。

## 10. 与根级 AGENTS.md 的关系

- 尊重用户提供的根级 `AGENTS.md` 通用规则（Python 环境、Chrome Profile 只读、谨慎编码、最小改动）。
- 本文件仅补充项目特定内容，不重复或冲突。
