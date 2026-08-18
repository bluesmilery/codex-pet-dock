# Codex Pet Dock — dev 候选验收

> 本文是 `dev` 分支候选的可重复验收清单和边界说明，不代表已经合入 `main`，也不代表已发布或已完成真机 QA。

## 验收口径

验收结论分为三类，不能互相替代：

1. **自动验证**：在当前工作树执行的构建、独立 swiftc 测试和 fixture 检查；结果以命令退出码和测试输出为准。
2. **静态结论**：由源码、公开 API 规则、隐私约束和纯函数测试推导出的行为边界；不等于真实窗口或 TCC 运行结果。
3. **真机验证**：需要屏幕录制、ScreenCaptureKit、Accessibility、登录项或多显示器环境的手工项目；未实际运行时必须标记未验证。

## 自动验证门禁

候选可重复执行：

```sh
swift build -c release
make docs-check
make test-docs
make test
```

通过条件是 release 构建退出码 0 且 0 warning，docs gate 通过，`make test` 的 test-privacy、test-ui、test-data、test-shell 四个独立入口全部通过。Swift 断言细分以各入口测试源码和实际输出为准，避免在 README/spec 复制易漂移计数。文档测试是额外门禁，不计入 Swift 断言。

文档变更还需在任务和 Review 中记录 `Docs Impact: none | update | new`。`make docs-check` 离线检查本地链接、`docs/README.md` 目录完整性、旧顶层 docs 路径和公开隐私模式；它不检查外部 URL 可达性，也不替代真机验证。

release 构建属于上述自动门禁；构建通过不能推导 `.app` 已启动、UI 已渲染或真机交互已通过。

自动测试使用纯函数、依赖注入和脱敏 fixture，不联网、不读取认证文件、不读取会话正文，也不需要屏幕录制权限。数据层只聚合 `last_token_usage` 数值；BubbleVisibility 只在内存计算 alpha 比例。

## 静态结论

- `selectPet` 通过公开 CGWindowList / AppKit 规则过滤主窗口、辅助控件并选择 Mascot；无合理候选时返回 nil，不误绑主聊天窗口。
- `Geometry.safeDockFrame` 固定底座宽度，按障碍链式下移，执行水平 clamp；垂直越界返回 nil。避让隐藏与宠物可见性、数据暂停语义分离。
- `BubbleVisibilityProbe` 使用 ScreenCaptureKit 公开 API、最多 2Hz、single-flight 和 generation 失效保护；捕获失败时保守按 visible 避让。
- 数据层通过 codex app-server stdio JSON-RPC 和本机日志数值聚合提供 WEEK LEFT / WEEK TOKENS，不复制 `auth.json` 或凭证。
- 日志、诊断与 token cache 只写入 Application Support/PetDock 私有目录（0700/0600）；默认诊断脱敏，不落盘标题、owner、WID/PID 或精确坐标。helper 环境为严格白名单，resolver 拒绝不可信可执行文件。
- Trellis context 路径执行 canonical containment，runtime 只保存 opaque context key 和最小元数据；原始 session/conversation/transcript 值不落盘。
- 文档、测试与源码注释中的示例不得包含真实窗口 ID、坐标、构建指纹、提交标识、认证内容或用户路径。

## 基础手工场景（真机未验证）

以下步骤承接窗口识别与跟随的基础验收；本次文档候选不把它们标记为已完成：

1. `make diagnose`：确认 Codex 进程归属、候选窗口清单、规则命中和选中理由可读。
2. `make run`：确认透明底座出现在宠物正下方并保持几何间隙。
3. 拖动宠物到另一位置，含副屏或负坐标区域，确认底座跟随且不越出可见区。
4. 在 Codex 内隐藏宠物，确认底座与详情隐藏；再次显示后确认重新捕获并跟随。
5. 退出并重新打开 Codex，确认底座隐藏、重开后重新发现宠物。
6. 展开和收起会话气泡，确认展开时底座下移、收起时回到宠物下方；控制按钮出现 / 消失不改变避让分类结论。
7. 在真实屏幕录制授权下验证 BubbleVisibility 的展开→收起→展开可逆性，以及捕获失败时的保守避让。
8. 使用状态栏菜单验证主题、显示 / 隐藏底座、退出和登录自启等 Accessibility / SMAppService 交互。
9. 验证底座与详情卡的透明渲染、字段布局和详情卡点击展开 / 收起。
10. 验证三种内置主题切换，以及外部 JSON 主题文件的安全解析和热加载。
11. 在已登录的真实 Codex 环境中验证 WEEK LEFT / WEEK TOKENS 刷新、窗口边界和独立退避；不输出账户或会话内容。
12. 观察 Follower 移动升频、稳定降频、隐藏与重捕的实际性能和体感。

这些项目依赖 TCC、ScreenCaptureKit、Accessibility、真实多显示器和 `.app` 运行环境，不能由 `make test` 代替。`make app` 属于发布 / 真机阶段命令，本页不把其执行状态写成当前候选结论。

## 风险与边界

- ad-hoc 签名没有稳定的开发者身份，重新签名可能要求重新授予屏幕录制权限；发布时应使用稳定签名或 notarized 构建。
- 屏幕录制权限是窗口枚举和像素探测的前提；无授权时只能依赖自动测试与静态结论。
- `codex app-server` 为 experimental 协议，字段可能随 CLI 版本变化；客户端只解析稳定子集并对缺失字段降级。
- 跨应用 z-order 不能由公开 API 完全控制；产品降级是 `.floating` level 加几何不重叠，而不是私有 API。
- 宠物隐藏、Codex 退出、登录自启和多屏硬件结果必须由具备相应权限的真机 QA 单独记录，不能从本页的自动门禁推断。

## 候选交付边界

本页只描述 `dev` 候选的验收条件。只有在独立 Review 与 QA 针对同一完整提交均为 P0/P1/P2 清零、自动门禁通过、真机项目明确标注结果后，才可由维护者决定是否合入 `dev` 或进一步发布；本页不替代人工合入确认，也不授权向 `main` 推送。
