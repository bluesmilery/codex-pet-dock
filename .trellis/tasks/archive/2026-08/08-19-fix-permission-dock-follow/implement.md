# Implementation Plan

1. 权限红测：覆盖 request-once 决策与 preflight=false 时 probe 不调用 capturer、仍保守 visible。
2. 最小权限修复：加入进程内 request gate，并在 `BubbleVisibilityProbe` 调度前门控 ScreenCaptureKit。
3. 回位红测：覆盖 expanded→collapsed 结果变化通知、无变化不重复通知、旧 generation 不通知。
4. 最小回位修复：Probe 成功提交新状态后通知主线程立即重排 follow tick；复用现有唯一布局路径。
5. 丝滑跟随红测/绿测：把 moving 更新提升到约 60 Hz、stable 探测压到 0.1 秒以内，保留 stable 降频状态机。
6. 文档同步：更新中英文 README 的权限行为、拖动跟随说明和实际测试计数（仅以本轮运行结果为准）。
7. 实现自验：`swift build -c release`、`make test`、`git diff --check`、限定范围/隐私检查，使用公开 Git 身份提交。
8. 全新 Review Agent 针对完整 SHA 做只读审查；有问题退回实现 Agent，新 SHA 后重审。
9. 全新 QA Agent 针对最终 SHA 重跑 release/test/diff-check，并在最终阶段执行 `make app` 与 codesign 检查；不启动、不安装、不覆盖 `/Applications`。
10. 主管仅在 Review/QA 均通过后把精确候选快进到本地 `dev`，不 push、不发版；随后只读预检并清理干净临时 worktree/branch。

## Validation commands

```bash
swift build -c release
make test
git diff --check <base>..<candidate>
make app
codesign --verify --deep --strict build/PetDock.app
```

`make app` 仅由最终 QA 执行。真机 TCC、实际 ScreenCaptureKit 像素分类、拖动手感、多屏与 Instruments 若未实际运行，必须列为未验证。
