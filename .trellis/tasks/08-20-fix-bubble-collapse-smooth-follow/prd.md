# 修复气泡收起并提升跟随平滑度

Delivery Path: L2

## Goal

修复真实候选中会话气泡收起后底座仍未及时回到宠物下方的问题，并让拖动跟随在普通与高刷新率屏幕上更连续、低延迟，同时保持静止态低开销和现有隐私边界。

## Background

- 用户在精确运行 `build/candidates/2026-08-19-dev-c5c41b2/PetDock.app` 对应二进制时仍可观察到问题；不是旧安装包误判。
- 当前气泡探测最多 2 Hz（`Sources/PetDock/BubbleVisibility.swift:70-73`）。分类成功变化后虽会请求主线程零延迟调度（`Sources/PetDock/FollowTickPlan.swift:3-10`），但这不覆盖分类前最多约 0.5 秒的轮询等待和截图耗时。
- 当前 moving 采用每个 tick 完成后再创建一次 1/60 秒 Timer（`Sources/PetDock/main.swift:179-185,294`；`Sources/PetDock/Follower.swift:26`），实际周期包含窗口枚举和布局处理时间，会漂移且低于名义 60 Hz。
- 本机匿名只读基准显示单次窗口枚举存在明显长尾；高频调度必须避免在主线程忙时积压过期帧。
- 项目最低支持 macOS 13；AppKit `displayLink(target:selector:)` 从 macOS 14 提供，旧 `CVDisplayLink` 在当前 SDK 已弃用并会威胁 release 0-warning 门禁。

## Requirements

### R1 气泡收起端到端回位

- 对仍存在但像素内容由 expanded 变为 collapsed 的气泡，调度器额外引入的下一次探测等待不超过 0.1 秒；该上限不包含当前串行主线程 tick 的工作时间或 single-flight capture 的在途时间。ScreenCaptureKit 返回成功分类后，布局唤醒不得再等待 stable/moving 周期。
- scheduler、probe cadence 和 pending retry deadline 必须使用同一可注入单调时钟；系统墙上时间前跳或后跳不得提高捕获频率或延长探测等待。
- 唤醒必须真正执行完整生产布局链，而不只证明回调收到 `interval == 0`；宠物 rect 不变时也必须重新读取气泡可见性并应用无障碍 frame。
- 连续 expanded→collapsed→expanded→collapsed 转换不得因重复回调、已有定时器或主线程繁忙而丢失最终布局；同一时刻最多保留一个待执行 follow tick，不积压过期帧。
- 保留 `knownWids` 候选消失立即失效、capture nil 保守 `.visible`、generation/strict single-flight 和 TCC preflight gate 语义。
- TCC 未授权、macOS 13 无像素捕获或 ScreenCaptureKit 返回 nil 时，不得误报已验证收起；继续保守避让并单列运行时限制。

### R2 显示节拍友好的平滑跟随

- macOS 14+ moving 状态跟随当前底座所在显示器的原生显示节拍；高刷屏可高于 60 Hz，普通屏不进行无意义的固定 120 Hz 轮询。
- macOS 13 使用公开、无弃用 warning 的回退调度；频率按屏幕能力确定并消除“每次工作完成后再延迟一周期”的累积漂移。
- display/timer 回调只在主线程请求一次 coalesced tick；主线程忙时丢弃过期节拍，不排队追赶。
- moving→stable 的判定以实际静止时长为准，不因 60/120 Hz 或可变刷新率改变语义；停止移动后仍回到低频 stable 探测，宠物消失后仍使用 hidden 低频探测。
- 不加入位置插值或隐式动画造成尾随，不新增 Accessibility、Input Monitoring、全局鼠标监听或私有 CGS/SPI。

### R3 测试、文档与隐私

- 先增加会在当前实现失败的调度/状态机测试，再实施最小修复。
- `Docs Impact: update`：同步中英文 README 和相关架构/验证文档中 2 Hz、60 Hz、零延迟等已经改变或容易误导的说明。
- 只在内存处理匿名 alpha 比例；不保存图像、不 OCR、不记录颜色、文字、真实 WID/PID/坐标或会话内容。
- 所有 UI frame 操作留在主线程；release build 保持 0 warning。

## Acceptance Criteria

- [ ] AC1：统一可控单调时钟下，visible 气泡下一次可调度探测的启动时间不晚于 `max(tickStartedAt + 0.1s, workCompletedAt)`；覆盖 phase-aligned、off-grid wake、工作跨 deadline、missed deadline，以及独立墙上时间前跳/后跳不影响 cadence。跨期时工作完成后立即保留一个 latest-only tick，不把当前 tick 工作或 single-flight capture 在途时间计作调度等待，且空候选、无权限、in-flight 和 nil 捕获仍保持既有边界。
- [ ] AC2：集成调度 harness 证明已有 stable/moving 调度被分类变化唤醒后会执行一次完整 tick；宠物不动也从避让 frame 回到基础 frame。
- [ ] AC3：重复可见性转换和密集 display callbacks 最终状态不丢失，且任意时刻待执行主线程 tick 数不超过 1。
- [ ] AC4：macOS 14+ moving 使用与窗口所在屏幕同步的公开 display link；窗口失去 screen 时由 screen-change 事件恢复到 fallback，screen 恢复后可重新启用 display link；macOS 13 回退按 `NSScreen` 能力选择周期且不使用已弃用 `CVDisplayLink`。
- [ ] AC5：同一静止时间序列在 60 Hz、120 Hz 和不规则节拍下进入 stable 的时间语义一致；检测到实质位移立即回到 moving。
- [ ] AC6：停止移动、宠物隐藏、用户隐藏底座、气泡候选消失、TCC false、capture nil、旧 generation/in-flight 等既有回归测试继续通过。
- [ ] AC7：`swift build -c release` 0 warning；`make test`、`make docs-check`、`make test-docs` 和候选 diff-check 全绿。
- [ ] AC8：本任务临时使用全新 `gpt-5.6-sol + high` Reviewer 对冻结完整 SHA 报告 P0/P1/P2=0；全新 `gpt-5.6-sol + high` QA 对同一 SHA 重跑门禁。
- [ ] AC9：最终 QA 按规范生成提交绑定的开发候选并验证架构/签名/来源；不覆盖 `/Applications/PetDock.app`。
- [ ] AC10：在精确开发候选上把真实气泡收起、拖拽手感、TCC/ScreenCaptureKit、多屏和 Instruments 分别记录为已验证或未验证，不用自动测试替代真机结论。

## Out of Scope

- 不修改 Codex/ChatGPT app、TCC 数据库、Chrome Profile 或系统设置。
- 不改变气泡 alpha 阈值，除非实施阶段以脱敏、可复现证据证明分类本身错误并回到规划重新批准。
- 不修改窗口候选几何规则、控制按钮避让、数据层、主题或详情卡产品行为。
- 不引入持续截图流、位置预测、弹簧动画或新的用户可见设置；若最小调度修复仍不足，作为后续独立方案评估。
- 不 push `main`、不创建 tag/release、不覆盖当前安装版本。
