# Documentation Guidelines

> 文档是代码的一部分：可发现、可追溯、可离线检查，但不替代源码、测试或真机证据。

## 单一事实源与职责

- `docs/` 保存项目事实（what / why / current evidence），入口是 [`docs/README.md`](../../../docs/README.md)。架构事实放 `architecture/`，开发流程放 `development/`，构建与验收证据放 `verification/`。
- `.trellis/spec/` 保存执行规则（how to change / required gates）。规则可以摘要说明，但产品字段、阈值、测试矩阵和真机结论只保存在 `docs/` 或测试源码中，不在 spec 中全文复制。
- `.trellis/tasks/` 保存一次任务的 requirements、plan 和 Review/QA 证据；它不是公开文档目录。
- Git 提供文档版本和审计记录。文档与行为变更应在同一个提交中更新，避免短暂的事实分叉。

## 内容与验证边界

- architecture 文档解释当前实现、数据边界和设计依据；development 文档解释如何初始化、修改和检查项目；verification 文档区分自动验证、静态结论和真机验证。
- 未实际运行的 TCC、ScreenCaptureKit、Accessibility、多屏和 `.app` 场景必须标记“未验证”，不能用编译或纯函数测试替代。
- README 和 spec 只提供摘要与链接；不要复制容易漂移的测试数量、字段表或完整真机矩阵。测试源码、`make` 输出和候选验收记录是这些事实的来源。
- 文档示例使用 `<user>`、`<qx>`、`<ay>` 等明确占位符，不公开用户路径、窗口 ID、运行时坐标、构建指纹、认证内容或会话正文。

## 可发现性与质量门禁

- 新增或移动 `docs/**/*.md` 时，必须更新 [`docs/README.md`](../../../docs/README.md) 的目录表和本地链接；链接目标必须留在仓库内。
- 文档改动提交前运行 `make docs-check` 与 `make test-docs`。检查器离线验证输入清单、Markdown 本地链接、目录完整性、旧顶层 docs 路径和公开隐私模式。
- 每个实现任务在规划阶段填写 `Docs Impact: none | update | new`，在 Review 中复核：行为、接口、数据边界、验证状态或开发门禁变化时，不能填写 `none`。
- `make test` 包含 docs gate 和三套 Swift 入口；docs 测试是额外门禁，不计入公开的 394 项 Swift 断言。
