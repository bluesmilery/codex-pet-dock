# Implementation Plan — docs-as-code 管理门禁

1. 在独立 worktree 从 `dev` 完整 base SHA 创建实现分支，确认 branch/HEAD/clean。
2. 记录红证据：当前缺少 docs catalog、documentation spec、`docs-check`/`test-docs` targets；先添加 checker 单元测试并验证失败。
3. 最小实现 `tools/check_docs.py`，使 fixture 测试和真实仓库检查通过。
4. 新增 `docs/README.md`，更新双语 README 文档入口。
5. 新增 Documentation Guidelines，更新 macOS spec index 与 quality gate。
6. 更新 Trellis 开发说明、dev 候选验收说明和 Makefile；`make test` 保持 394 项 Swift 断言口径并额外执行 docs gate。
7. 验证：
   - 项目 Python 环境顺序检查；无项目环境时使用 conda base 执行 Python 命令，但仓库 Makefile 只写 `PYTHON ?= python3`；
   - `make docs-check`；
   - `make test-docs`；
   - `swift build -c release` 0 warning；
   - `make test` 全绿，确认 Swift 172/123/99；
   - `git diff --check`、路径/隐私/Co-Authored 扫描、worktree clean。
8. 用公开 Git 身份创建 Conventional Commit，不带 `Co-Authored-By`。
9. 对完整实现 SHA 派发全新只读 Review；findings 退回同一实现者追加 commit，新 SHA 重新 Review。
10. Review 通过后对同一 SHA 派发全新 QA；accepted 后仅快进集成到 `dev`，不 push/main/tag/release。

## Allowed Files

- `Makefile`
- `README.md`
- `README.zh-CN.md`
- `docs/README.md`
- `docs/development/trellis.md`
- `docs/verification/dev-candidate.md`
- `.trellis/spec/macos/index.md`
- `.trellis/spec/macos/quality-guidelines.md`
- `.trellis/spec/macos/documentation-guidelines.md`
- `tools/check_docs.py`
- `tests/test_check_docs.py`

## Stop Conditions

- 实现需要第三方 Python/Node/Rust 依赖或网络；
- 需要修改 Swift 业务行为、现有 Swift 测试断言、Trellis workflow/scripts/config；
- base SHA/branch 漂移或与用户未跟踪文件冲突；
- 无法使用 `gpt-5.6-luna` + `max` 派发实现、Review、QA；
- checker 只能通过读取认证、会话正文或本机私有数据实现。
