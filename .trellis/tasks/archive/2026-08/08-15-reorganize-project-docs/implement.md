# Implementation Plan — 项目文档重组

1. 在独立 worktree 从 `dev` 当前完整 SHA 创建实现分支，确认初始 clean。
2. 记录重组前文档清单、README/源码引用和当前 Trellis platform/测试口径证据。
3. 用最小内容迁移创建 `docs/architecture/`、`docs/development/`、`docs/verification/`。
4. 合并 `success-criteria.md` 中未重复的手工验证步骤后删除 6 个旧顶层文档。
5. 更新 README 中英文链接、`PetTracker.swift` 路径注释和全部文档内部相对链接。
6. 验证：
   - `rg` 确认旧路径和错误 `trellis init --claude` 指令无残留；
   - 本地 Markdown 链接解析脚本通过；
   - 测试口径与 README/current tests 一致；
   - 敏感字面量扫描通过；
   - `git diff --check` 通过；
   - `swift build -c release` 0 warning；
   - `make test` 全绿，证明唯一源码注释改动无行为影响。
7. 使用公开 Git 身份创建 Conventional Commit，不带 `Co-Authored-By`。
8. 对完整实现 SHA 启动全新只读 Review；P0/P1/P2 未清零则退回实现者修复，新 SHA 重新 Review。
9. Review 通过后对同一 SHA 启动全新 QA，复核文档树、链接、构建、测试、隐私边界和工作树 clean。
10. 仅将 accepted SHA 集成到 `dev`；不 push、不触碰 `main`、tag 或 release。

## Allowed Files

- `README.md`
- `README.zh-CN.md`
- `docs/**/*.md`
- `Sources/PetDock/PetTracker.swift`（仅第 3 行文档路径注释）

## Stop Conditions

- base SHA 或分支漂移；
- 实现需要修改业务代码、测试或 Trellis 配置；
- 无法以 `gpt-5.6-luna` + `max` 派发实现/Review/QA 子 Agent；
- 发现与用户未跟踪 handoff/design 文件冲突；
- 文档事实无法由仓库或实际命令确认。
