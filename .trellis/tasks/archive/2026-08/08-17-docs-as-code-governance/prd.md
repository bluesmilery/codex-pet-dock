# 建立 docs-as-code 管理门禁

## Goal

让项目文档具备可发现、可追溯、可自动检查的最小治理闭环：Trellis 管理“何时必须更新文档”，Git 保存文档版本，`make docs-check` 离线检查文档结构、链接和隐私，避免再次出现旧路径、重复事实和验证口径漂移。

## Background

- 当前 `docs/` 已按 `architecture/`、`development/`、`verification/` 分类，但没有统一目录页。
- `.trellis/spec/macos/` 还没有专门的 documentation guideline；现有质量规范没有 Docs Impact 门禁。
- `Makefile` 只有 Swift 构建和 UI/data/shell 测试，没有文档检查入口。
- 仓库没有 CI 和 JavaScript/Rust 文档工具链；为保持最小依赖，首版使用 Python 3 标准库，不引入 markdownlint、lychee、Vale、MkDocs 或 Docusaurus。
- 当前 `make test` 的公开口径是 394 项 Swift 断言；文档测试作为额外门禁，不计入这 394 项。

## Requirements

1. 新增 `docs/README.md`，作为人和 AI 都可读取的文档目录：
   - 列出全部 `docs/**/*.md` 文档；
   - 为每份文档标记类型、事实来源和更新触发条件；
   - 说明 `docs/`、`.trellis/spec/`、`.trellis/tasks/` 的职责边界；
   - README 中英文版提供该目录入口。
2. 新增 `.trellis/spec/macos/documentation-guidelines.md` 并加入 `.trellis/spec/macos/index.md`：
   - 规定单一事实源、三类文档、同提交更新、验证状态边界、避免重复易漂移数字、文档可发现性；
   - 规定每个实现任务在规划/Review 时判断 `Docs Impact`；
   - 规定文档变更运行 `make docs-check`，行为变化应同步相关架构/验证文档；
   - 不把产品事实全文复制进 spec，而是链接到 `docs/`。
3. 更新 `.trellis/spec/macos/quality-guidelines.md`，把 Docs Impact、`make docs-check` 和文档测试纳入质量门禁；保持 release build、394 项 Swift 测试和真机 QA 的既有要求。
4. 新增无第三方依赖的 `tools/check_docs.py`：
   - 离线扫描 `README.md`、`README.zh-CN.md`、`docs/**/*.md`、`.trellis/spec/macos/**/*.md`；
   - 校验本地 Markdown 文件/目录链接可解析，忽略网络 URL 与纯 anchor；
   - 校验 `docs/README.md` 能发现其余全部 `docs/**/*.md`；
   - 阻止已删除的旧顶层 docs 路径回流；
   - 检测真实 `/Users/<name>` 路径、数字 wid/坐标、带值 CDHash、Co-Authored-By trailer、构建特定长 hash 等公开文档隐私残留，同时允许明确占位符和规范本身的规则描述；
   - 输出确定性的错误列表和汇总，任一错误退出非零；不得读取认证文件、会话正文或网络。
5. 新增 `tests/test_check_docs.py`，使用临时目录覆盖成功与至少以下失败路径：断链、未入目录、旧路径、真实用户路径/窗口元数据；测试不得修改真实仓库。
6. 更新 `Makefile`：
   - `docs-check` 运行真实仓库检查；
   - `test-docs` 运行文档检查器单元测试；
   - `test` 同时执行 `docs-check`、`test-docs` 和现有三套 Swift 测试；
   - 支持 `PYTHON ?= python3`，不写本机 Python 绝对路径。
7. 同步 README 中英文版、`docs/development/trellis.md`、`docs/verification/dev-candidate.md` 中的开发门禁表述：明确 `make test` 包含额外 docs gate，但 Swift 断言仍为 394 项。
8. 不修改 Swift 业务行为、控制按钮/底座避让规则、现有测试断言、Trellis workflow/scripts/config、main 分支或远端。

## Acceptance Criteria

- [x] `docs/README.md` 完整列出其余全部 docs 文档，README 中英文版均可进入该目录。
- [x] Trellis macOS spec 索引包含 Documentation Guidelines，质量规范明确 Docs Impact 与 docs gate。
- [x] 文档检查器只有 Python 标准库依赖，离线运行且不读取敏感文件。
- [x] 文档测试先证明缺失实现/错误 fixture 会失败，再在实现后全部通过。
- [x] `make docs-check` 退出 0，并输出文档/链接检查统计。
- [x] `make test-docs` 退出 0，覆盖成功、断链、未索引、旧路径和隐私失败场景。
- [x] `make test` 退出 0：文档门禁通过，现有 UI 172 + data 123 + shell 99 = 394 项 Swift 断言仍全绿。
- [x] `swift build -c release` 退出 0 且 0 warning。
- [x] `git diff --check`、新增行隐私扫描和 Markdown 链接复核通过。
- [x] 独立 Review 对目标完整 SHA 得出 P0/P1/P2=0；独立 QA 对同一 SHA 验证 ACCEPTED。

## Out of Scope

- 引入或发布 MkDocs、Docusaurus、markdownlint、lychee、Vale 等第三方工具。
- 新建 GitHub Actions/CI、GitHub Pages 或在线文档站点。
- 检查外部 HTTP 链接可达性、自动判断任意自然语言是否语义过时。
- 修改业务实现、控制按钮避让、TCC/ScreenCaptureKit 行为或真机验收结论。
- 改写 Git 历史、修改 `main`、push、tag 或 release。

## Notes

- Keep `prd.md` focused on requirements, constraints, and acceptance criteria.
- Lightweight tasks can remain PRD-only.
- For complex tasks, add `design.md` for technical design and `implement.md` for execution planning before `task.py start`.
