# 实施计划

## 0. 启动前门禁

- [ ] 用户批准最终规划摘要。
- [ ] `task.py start` 后状态为 `in_progress`。
- [ ] 实现 Agent 预检 `gpt-5.6-luna` + `max`、独立分支/worktree、base `3cecbcdf3cd4c67e491159ca3898db59e8b83bf6`、初始 clean。
- [ ] 实现 Agent 仅修改本计划列出的代码、测试、文档和模板 hash；不触碰用户未跟踪 handoff/design 或控制按钮范围。

## 1. 红测：Trellis 路径与 runtime

- [ ] 新增 Python 隐私测试，先证明绝对路径、`..`、逃逸 symlink 会被读取，raw session/conversation/transcript 会被持久化，权限未显式收紧。
- [ ] 将测试接入 `make test-privacy` / `make test`，记录修复前失败证据。

## 2. 绿测：Trellis 路径与 runtime

- [ ] 在 `task_context.py` 和 hook 读取端加入 canonical containment；目录子项二次校验。
- [ ] `active_task.py` 只保存最小元数据，runtime 使用 `0700/0600` + atomic replace。
- [ ] 同步 `.template-hashes.json` 三个受影响模板 hash。
- [ ] Python 隐私测试转绿；现有 task current/context 命令 smoke 通过。

## 3. 红测：私有文件、诊断与日志

- [ ] 为私有目录/文件权限、symlink 写重定向、诊断脱敏和日志 WID 去除增加失败测试。
- [ ] 保留现有 PetLogger 异步、flush、轮转与 release gate 测试。

## 4. 绿测：私有文件、诊断与日志

- [ ] 新增 `PrivateStorage` 最小共享工具。
- [ ] PetLogger 迁移到私有 Logs，安全 open/rotate，去除真实 WID。
- [ ] `--diagnose` 与 `tools/diagnose.swift` 改为脱敏输出和私有 Diagnostics 文件。
- [ ] 更新 Makefile 的 run/diagnose/clean-logs 路径和测试编译源清单。

## 5. 红测与绿测：helper 环境和 resolver

- [ ] 先添加敏感环境变量仍被继承、父 PATH 污染、可写/不可信候选仍被接受的失败测试。
- [ ] `childEnvironment` 改为严格白名单和受控 PATH；不传认证/token/cookie/proxy/未知变量。
- [ ] resolver 校验 canonical target、owner、普通可执行文件和 group/world writable 状态，同时保留安全 nvm/npm symlink 兼容。
- [ ] fake app-server JSON-RPC、超时/取消及 resolver 既有测试继续通过。

## 6. 红测与绿测：token cache

- [ ] 添加序列化 cache 含 home、`.codex`、rollout UUID，以及旧格式加载的失败测试。
- [ ] key 改为版本化 SHA-256；统一命中/淘汰；旧格式丢弃。
- [ ] cache 使用私有存储权限；数值字段、增量命中和 sessionFileCount 行为不回归。

## 7. 文档与 spec

- [ ] 更新 README.md / README.zh-CN.md 的诊断、日志和认证说明。
- [ ] 更新 data-layer、Trellis、dev-candidate 文档与 privacy/quality spec；明确真机未验证。
- [ ] 更新测试事实源，不在 README/spec 复制易漂移计数。
- [ ] `make docs-check test-docs` 通过。

## 8. 实现候选验证与提交

- [ ] `PYTHONDONTWRITEBYTECODE=1 make PYTHON=<worktree>/miniconda3/bin/python test-privacy`。
- [ ] `swift build -c release`，0 warning。
- [ ] `PYTHONDONTWRITEBYTECODE=1 make PYTHON=<worktree>/miniconda3/bin/python test`，全绿。
- [ ] `trellis update --dry-run`，仅允许已解释结果；无 `.claude/`、workspace/runtime/task 被 tracked。
- [ ] `git diff --check`、新增行与 base..HEAD 隐私扫描通过。
- [ ] 使用公开 Git 身份提交，无 `Co-Authored-By`，回报完整 SHA 和未验证项。

## 9. 独立 Review

- [ ] 全新 luna+max Review Agent、独立分支/worktree，只读审查完整实现 SHA。
- [ ] 核对五条 source-to-sink 是否真正关闭、测试是否可失败、Trellis template hash/更新兼容、文档/权限/回滚准确。
- [ ] P0/P1/P2 任一 finding 退回原实现 Agent；修复追加新 commit 后对新 SHA 重新 Review。

## 10. 独立 QA 与集成

- [ ] 全新 luna+max QA Agent、独立分支/worktree，绑定 Review 通过的完整 SHA。
- [ ] 重跑 privacy/docs/release/full tests、权限与 symlink fixture、完整历史敏感扫描；不读取真实认证/会话数据。
- [ ] QA ACCEPTED 后由主管将候选集成到 `dev`，确认 refs、主 worktree tracked clean。
- [ ] 归档 Trellis task，清理实现/Review/QA worktree 和临时分支；不 push `main`、不建 tag/release。

## 风险文件与回滚点

- `.codex/hooks/inject-subagent-context.py`、`.trellis/scripts/common/{task_context,active_task}.py`：错误会影响 Trellis 会话；必须先通过隔离 Python fixture 再 smoke 当前任务解析。
- `PetLogger.swift` / 私有文件 open/rotate：错误可能丢日志或误写；必须覆盖 symlink、权限、双次轮转。
- `CodexExecutableResolver.swift` / `RateLimitClient.swift`：过严会找不到 Codex；必须覆盖 override/PATH/nvm/volta/system 和 fake app-server。
- `TokenUsageLogReader.swift`：新 key 会导致旧 cache miss；设计接受安全重建，禁止尝试保留旧绝对路径。
