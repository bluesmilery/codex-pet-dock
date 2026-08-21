# 修复气泡收起并提升跟随平滑度

Delivery Path: L2

## Goal

修复真实候选中会话气泡收起后底座仍未及时回到宠物下方的问题，并让拖动跟随在普通与高刷新率屏幕上更连续、低延迟，同时保持静止态低开销和现有隐私边界。

## Background

- v5 冻结候选通过自动测试与独立 Review，但主 Agent 按用户图 1→图 2→图 3 的真实操作复验后，图 3 仍保留旧避让间距，因此该候选未 accepted。其生产组合测试注入了 `.targetMissing`，只能证明管道能够处理该 outcome，不能证明真实 full-hide 会产生同一种 trigger。
- 精确候选 `91a8fe6ba915f84e35f232943fd1c1c3a558063d` 已实现 0.1 秒气泡探测、统一单调时钟、latest-only 调度、macOS 14+ display link、macOS 13 Timer fallback 和基于时长的 stable 判定，并通过当时的自动 Review/QA。
- 用户真机验证区分出两条状态链：消息卡片仍存在时 expanded→collapsed 能正确复位；控制按钮和全部消息窗口一起隐藏后，底座仍跟随宠物移动，却保持旧避让间距。该候选因此未 accepted、未合入 `dev`，其 Review/QA 结论不可复用。
- 当前捕获边界用 `BubbleAlphaStats?` 同时表示窗口不在一次成功取得的 ScreenCaptureKit 清单中、清单获取失败和截图失败；所有 `nil` 都保守 `.visible`。这能解释“CGWindowList 几何短暂残留、SCK 已无目标”时旧障碍被持续保活，但仍须先由批准基线上的生产链症状证据与几何误识别假设区分。
- 当前移动路径在每次显示节拍完成布局后直接调用 `NSPanel.setFrame`；高刷新率减少了跳变间隔，但没有位置插值。用户已批准最大 32ms 的显式线性插值拖尾。

## Requirements

### R1 气泡收起端到端回位

- 对仍存在但像素内容由 expanded 变为 collapsed 的气泡，调度器额外引入的下一次探测等待不超过 0.1 秒；该上限不包含当前串行主线程 tick 的工作时间或 single-flight capture 的在途时间。ScreenCaptureKit 返回成功分类后，布局唤醒不得再等待 stable/moving 周期。
- scheduler、probe cadence 和 pending retry deadline 必须使用同一可注入单调时钟；系统墙上时间前跳或后跳不得提高捕获频率或延长探测等待。
- 唤醒必须真正执行完整生产布局链，而不只证明回调收到 `interval == 0`；宠物 rect 不变时也必须重新读取气泡可见性并应用无障碍 frame。
- 连续 expanded→collapsed→expanded→collapsed 转换不得因重复回调、已有定时器或主线程繁忙而丢失最终布局；同一时刻最多保留一个待执行 follow tick，不积压过期帧。
- 完全隐藏会话 UI 时，即使 CGWindowList 暂时仍返回旧几何候选，只要该 WID 先前已有成功像素观察，且随后一次成功取得的 ScreenCaptureKit 窗口清单明确不再包含该 WID，就必须把该候选从障碍集中失效并唤醒完整布局；不得继续保持旧避让间距。
- 捕获结果必须区分“成功统计”“已成功取得清单但目标不存在”和“权限、清单获取、截图或像素统计失败”。目标从未成功观察过时，单次目标缺失不得把未知窗口判 hidden；其余失败继续保守 `.visible`。保留 generation/strict single-flight、当前候选身份校验和 TCC preflight gate 语义。
- TCC 未授权、macOS 13 无像素捕获或 ScreenCaptureKit observation unavailable 时，不得误报已验证收起；继续保守避让并单列运行时限制。

### R2 显示节拍友好的平滑跟随

- macOS 14+ moving 状态跟随当前底座所在显示器的原生显示节拍；高刷屏可高于 60 Hz，普通屏不进行无意义的固定 120 Hz 轮询。
- macOS 13 使用公开、无弃用 warning 的回退调度；频率按屏幕能力确定并消除“每次工作完成后再延迟一周期”的累积漂移。
- display/timer 回调只在主线程请求一次 coalesced tick；主线程忙时丢弃过期节拍，不排队追赶。
- moving→stable 的判定以实际静止时长为准，不因 60/120 Hz 或可变刷新率改变语义；停止移动后仍回到低频 stable 探测，宠物消失后仍使用 hidden 低频探测。
- 在 moving 状态对底座当前位置到最新目标 frame 使用最大 32ms 的显式线性插值，按单调时间计算进度并在显示节拍上渲染；新目标到达时只追最新目标，不排队重放历史位置，不允许过冲。停止移动后精确落到最终目标。
- 隐藏/重新显示、无有效屏幕、目标越界或需要立即避让/复位的安全状态不得被动画延迟；不加入位置预测、弹簧动画、新权限、Accessibility、Input Monitoring、全局鼠标监听或私有 CGS/SPI。

### R3 测试、文档与隐私

- 在再次修改分类、候选 identity、control 障碍或 alpha 阈值前，先用同一诊断候选和用户原始操作采集脱敏聚合：bubble/control 障碍数量、capture outcome / visibility 数量、identity-change / wake callback 计数、visible obstacle 数量与相对无障碍基础 frame 的匿名 dy bucket。诊断默认关闭，不记录窗口/进程标识、标题、owner、绝对坐标、颜色、文字、图像、逐像素值或可关联到单个窗口的事件序列。
- 只有真实 runtime kind/outcome/identity 分支与回归 trigger 建立等价关系后，才允许实施该分支内的最小产品修复；否则候选仅用于诊断，不得宣称症状已修复。
- 先在批准产品基线上运行穿过真实生产组合的调度/状态机症状测试；基线失败才实施最小行为修复，基线通过则只补覆盖证据，不制造红测或继续猜测式修改产品代码。
- `Docs Impact: update`：同步中英文 README 和相关架构/验证文档中 2 Hz、60 Hz、零延迟等已经改变或容易误导的说明。
- 只在内存处理匿名 alpha 比例；不保存图像、不 OCR、不记录颜色、文字、真实 WID/PID/坐标或会话内容。
- 所有 UI frame 操作留在主线程；release build 保持 0 warning。

## Acceptance Criteria

- [ ] AC1：统一可控单调时钟下，visible 气泡下一次可调度探测的启动时间不晚于 `max(tickStartedAt + 0.1s, workCompletedAt)`；覆盖 phase-aligned、off-grid wake、工作跨 deadline 和 missed deadline。跨期时工作完成后立即保留一个 latest-only tick，不把当前 tick 工作或 single-flight capture 在途时间计作调度等待，且空候选、无权限、in-flight 和 unavailable 捕获仍保持既有边界。墙钟独立性必须形成真实可失败证据：若 cadence 生产接口本身不接受墙钟，则用单调行为回归加可执行 source/API guard 禁止 cadence 文件引入 `Date` / `CFAbsoluteTime` 等墙钟输入；仅修改被测链不读取的局部 wall fake 不算覆盖，也不得为测试向生产链添加无业务用途的第二时钟。
- [ ] AC2：集成调度 harness 证明已有 stable/moving 调度被分类变化唤醒后会执行一次完整 tick；宠物不动也从避让 frame 回到基础 frame。
- [ ] AC2b：先以同一冻结诊断候选在真实图 3 操作中确认 `runtime trigger source → observed obstacle kind/capture outcome/visibility/identity behavior`。随后集成 harness 注入等价 trigger，穿过真实 `BubbleVisibilityProbe → visibility callback → scheduler coalescer → FollowLayoutPass → DockPanel.placeBelow`，并直接断言实际 `DockPanel.frame` 回到基础 frame；无法确认等价时该测试只能标为 plumbing-only。相邻 unavailable/从未成功观察等保守用例不得被放宽。
- [ ] AC2c：诊断模式默认关闭，关闭时不创建诊断文件、不增加 capture 或 timer；显式启用时只产生隐私白名单内的时间窗聚合，输出目录/文件权限分别为 0700/0600，文件以 no-follow 语义打开，且 `make test-privacy` 拒绝禁止字段、symlink 跟随和非私有落盘。诊断候选本身不改变正常用户路径的障碍分类或布局行为。
- [ ] AC3：重复可见性转换和密集 display callbacks 最终状态不丢失，且任意时刻待执行主线程 tick 数不超过 1。
- [ ] AC4：macOS 14+ moving 使用与窗口所在屏幕同步的公开 display link；窗口失去 screen 时由 screen-change 事件恢复到 fallback，screen 恢复后可重新启用 display link；macOS 13 回退按 `NSScreen` 能力选择周期且不使用已弃用 `CVDisplayLink`。
- [ ] AC5：同一静止时间序列在 60 Hz、120 Hz 和不规则节拍下进入 stable 的时间语义一致；检测到实质位移立即回到 moving。
- [ ] AC5b：线性插值在 60 Hz、120 Hz 和不规则节拍下使用同一 32ms 时间线，单调趋近最新目标、无过冲、无历史位置队列；`now >= start + 0.032s` 时求值必须精确为目标 frame，实际面板在下一个可用显示节拍写入最终 frame。障碍变化、隐藏、无 screen 和越界路径可立即 snap。
- [ ] AC6：停止移动、宠物隐藏、用户隐藏底座、气泡候选消失、TCC false、capture unavailable、旧 generation/in-flight 等既有回归测试继续通过。
- [ ] AC7：`swift build -c release` 0 warning；`make test`、`make docs-check`、`make test-docs` 和候选 diff-check 全绿。
- [ ] AC8：按用户最新任务级指令，本任务后续所有实现、正式 Review、修复复核和 QA 子 Agent 使用全新 `zhipu/glm-5.3 + max`；任何一次模型/推理不可用都停止派发，不静默降级。Reviewer 对冻结完整 SHA 报告 P0/P1/P2=0 后，QA 才可对同一 SHA 重跑门禁。
- [ ] AC9：最终 QA 按规范生成提交绑定的开发候选并验证架构/签名/来源；不覆盖 `/Applications/PetDock.app`。
- [ ] AC10：在精确开发候选上把真实气泡收起、拖拽手感、TCC/ScreenCaptureKit、多屏和 Instruments 分别记录为已验证或未验证，不用自动测试替代真机结论。

## Out of Scope

- 不修改 Codex/ChatGPT app、TCC 数据库、Chrome Profile 或系统设置。
- 不改变气泡 alpha 阈值，除非实施阶段以脱敏、可复现证据证明分类本身错误并回到规划重新批准。
- 不修改窗口候选几何规则、控制按钮避让、数据层、主题或详情卡产品行为。
- 不引入持续截图流、位置预测、弹簧动画或新的用户可见设置。
- 不 push `main`、不创建 tag/release、不覆盖当前安装版本。
