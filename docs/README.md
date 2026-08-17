# Codex Pet Dock 文档目录

这是项目公开文档的唯一目录入口。文档按事实类型分为 architecture（架构事实）、development（开发流程）和 verification（验证证据）；规则本身位于 [`.trellis/spec/macos/`](../.trellis/spec/macos/index.md)，单次任务资料位于 `.trellis/tasks/`，Git 提供版本和审计记录。

目录表中的“事实来源”指出应修改的单一事实源；“更新触发”描述何时必须在同一提交中同步文档。文档变更提交前运行 `make docs-check`，并在任务或 Review 中填写 Docs Impact。

## 文档清单

| 文档 | 类型 | 事实来源 | 更新触发 |
| --- | --- | --- | --- |
| [宠物窗口识别](architecture/pet-window-detection.md) | architecture | `PetTracker.swift`、`Geometry.swift` 与纯函数测试 | 窗口归属、候选过滤、阈值或隐私边界变化 |
| [数据层架构](architecture/data-layer.md) | architecture | `Sources/PetDock/Data/`、数据层 fixture | 数据字段、读取边界、并发、退避或数据验证变化 |
| [底座气泡避让](architecture/dock-obstacle-avoidance.md) | architecture | `Geometry.swift`、`PetTracker.swift`、`BubbleVisibility.swift` 与 UI 测试 | 障碍分类、避让几何、捕获调度或真机边界变化 |
| [Trellis 开发接入](development/trellis.md) | development | Trellis 配置、项目 `AGENTS.md` 与工作流 | 初始化方式、目录职责、文档门禁或开发流程变化 |
| [dev 候选验收](verification/dev-candidate.md) | verification | 构建、测试、Review/QA 记录与真机 QA 证据 | 验收门禁、测试口径、验证状态或发布边界变化 |

## 目录职责

- `docs/` 保存面向人和 AI 的项目事实、设计依据与验证边界；每份文档必须从本页可发现。
- `.trellis/spec/` 保存如何开发和验收的执行规则；规则只链接到 `docs/` 的事实，不复制完整字段表或测试矩阵。
- `.trellis/tasks/` 保存单次任务的需求、计划和过程证据；它不是公开事实目录，也不由 docs-check 扫描。
- Git 提供文档的版本、同提交更新和审计历史；不要以 README 中的重复数字代替测试源码或验收记录。
