# AC Evidence Topology — v5 evidence-only campaign

- 任务：fix-bubble-collapse-smooth-follow（v5，第四次 break-loop 后 evidence-only 复盘）。
- 产品基线：`585b9a4b4e2eef291755d5bc8971294e32feafa9`（完整 SHA，本候选 Sources/ 与其逐字节一致，`git diff 24b9732 -- Sources/` 为空）。
- 测试态：基线之上叠加治理/规划 HEAD `cac75c395d73df85cf71cf4f1d43741ba95fdd29`，再加本候选的 test-only 改动（`tests/main.swift` 与本文件）；产品代码零改动。
- 基线结论：两条新证据路径（T-sch4f source guard、T-bv42 生产组合回归）在未修改 24b9732 产品树上直接通过 → 按“基线合同”判定为 coverage-only gap，不做任何产品行为修改。
- 冻结候选完整 SHA 在交付报告中单独给出；候选 SHA 变化后本表结论一并失效。

## 用户症状与验收标准证据拓扑

| 症状 / AC | 证据类型 | 触发 / 扰动 | 基线来源 / 结果 | 生产消费者 / 路径 | 最终所有者 / 断言 | 命令 / 结果 | 手工缺口 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| S1 消息卡片仍在但 expanded→collapsed 后底座不复位（用户已反馈当前可正常复位；作为原始症状路径/相邻回归保护保留） | behavior（生产组合） | fake capturer 返回 `.stats(expanded)` 后改 `.stats(collapsed)`；probe 单调时钟 11_000→11_001 越过 cadence | 24b9732 基线通过（准入审计修复后 T-bv39 frameSink 写入实际 `DockPanel`） | capturer → `BubbleVisibilityClassifier` → cache 变化 → `onVisibilityChange` → `FollowTickScheduler.visibilityChangeCallback`（coalescer wake）→ 主线程完整 tick → `FollowLayoutPass.placeDock` → **真实 `DockPanel.placeBelow`** | T-bv39b/d：实际 `transitionDock.frame` 从避让 frame 复位到独立计算的基础 frame（`Geometry.appKitRectFromQuartz`，容差 <1.0）；T-bv39c/e：仅一次提前完整 tick、主线程执行、旧 stable timer 失效、hidden 不变不重复 wake；障碍 [1,0] | `make test-ui` PASS（T-bv39a–e） | 真实像素收起、真实 SCK 时延与体感未验证 |
| S2 全部消息/控制隐藏后底座保持旧避让间距 | behavior（生产组合，AC2b 证据 owner） | `.stats(expanded)` 建立成功观察 + 未到期 stable one-shot 后，capturer 改返回权威 `.targetMissing`；probe 时钟 15_000→15_001 | 24b9732 基线通过（本轮新增 T-bv42；v4 的 T-bv39f2 helper 路径降级为分类补充证据） | capturer → classifier（hasSuccessfulObservation=true → hidden）→ cache 变化 → `onVisibilityChange` → scheduler coalescer `requestWake` → 主线程 drain → 完整 `FollowLayoutPass.placeDock` → **真实 `DockPanel.placeBelow`** | T-bv42c/d：仅一次提前 tick（ticks=2）、onMain=true、旧 stable timer invalidated、新 one-shot 唯一、障碍 [1,0]、**实际 `missDock.frame` 回基础 frame**（像素对齐容差 <1.0） | `make test-ui` PASS：T-bv42a–e 全绿（frame 期望值由 `Geometry.appKitRectFromQuartz` 独立计算） | 真实 CG 候选残留窗口与 SCK 清单时序、真机 full-hide 未验证 |
| S3 拖动跟随跳变/不连续 | behavior（纯值 + 真实 panel sink） | 60/120/不规则节拍采样、retarget、障碍/隐藏/无 screen 扰动；注入单调时间 | 24b9732 基线通过（既有回归） | `DockFrameInterpolator.update/frame(at:)` ← `DockPanel.placeBelow(movementChanged:monotonicNow:)` | T-ip1–7（32ms 线性、无过冲、只追最新目标、精确终点）；T-ip8–10 真实 DockPanel frame sink；T-ip11 无 screen 每帧 snap | `make test-ui` PASS（T-ip1–11） | 60Hz/高刷真实拖拽手感、Instruments CPU/内存未验证 |
| AC1 单调时钟 cadence 上限 + 墙钟独立性 | behavior + static/absence（source guard） | 注入单调时钟驱动 phase-aligned/off-grid/工作跨 deadline/missed deadline/in-flight；guard 扫描 cadence owner 源码 + 生产默认时钟 provider | 24b9732 基线通过；无效的局部 wall-jump fixture 已按 break-loop 4 移除 | scheduler tick/probe cadence/retry 全部消费同一注入单调时钟；guard 直接读取 `Sources/PetDock/FollowTickPlan.swift`、`Sources/PetDock/BubbleVisibility.swift`、`Sources/PetDock/Follower.swift`、`Sources/PetDock/DockPanel.swift`、`Sources/PetDock/main.swift`（生产 provider `followMonotonicNow` 所在文件）源文本 | T-sch1/1c–1h、T-sch4a–d（`max(tickStartedAt+0.1, workCompletedAt)`、latest-only、无 backlog）；T-sch4f：出现 `Date`/`NSDate`/`CFAbsoluteTime`/`timeIntervalSince`/`DispatchWallTime`/`gettimeofday` 即 FAIL | `make test-ui` PASS（read=5/5）；guard 可失败性两次真实验证：① 临时注入 `Date()` 到 Follower.swift → FAIL（violations=Sources/PetDock/Follower.swift）；② 首轮 Review P1 修复时把生产 `followMonotonicNow` 临时改为 `Date().timeIntervalSinceReferenceDate` → FAIL（violations=Sources/PetDock/main.swift，read=5/5）；两次 mutation 均已完整撤销，Sources/ diff 复核为空后恢复 PASS | 系统真实 NTP 跳变下的运行表现未验证（契约由 guard + 行为回归固化） |
| AC2 分类变化唤醒执行完整布局（宠物不动也回基础 frame） | behavior（生产组合） | stable 调度已建立、宠物 rect 不变，仅气泡 cache visible→hidden | 24b9732 基线通过 | wake → coalescer → 完整 tick → `FollowLayoutPass` 重读 `bubbleProbe.visibility` 并重算无障碍 frame → `DockPanel.placeBelow` | T-bv39c/d（实际 panel 障碍 [1,0]、frame 回基础位）；T-bv42d（真实 panel frame） | `make test-ui` PASS | 真实 run-loop 排序（事件跟踪/模态）未验证 |
| AC2b 见 S2 | behavior（生产组合） | 见 S2 | 见 S2 | 见 S2 | 见 S2 | 见 S2 | 见 S2 |
| AC3 重复转换/密集 callback 不丢最终状态且 pending ≤1 | behavior | 连续 wake（running 期间到达）、重复 expanded↔missing 循环、hidden 不变重复 probe | 24b9732 基线通过 | `FollowTickCoalescer.requestWake/requestBeat` 状态机消费全部注入事件 | T-bv38d/e/f1–f3（最多一个 pending、一次 follow-up、无过期 tick）；T-bv39f5b（3 轮 full hide/show 收敛）；T-bv42e（hidden 不变 ticks 保持 2） | `make test-ui` PASS | 真实高频 display 回调压力未验证 |
| AC4 display link + macOS13 fallback + screen 存活恢复 | behavior（注入 factory） | display-link factory 返回可控 link；screen 变化触发 wake；60→120→60 能力切换 | 24b9732 基线通过 | `FollowTickScheduler.startMovingSourceIfNeeded` 消费 factory/eligibility；DockPanel screen-change 通知 → 同一 wake | T-sch2a/b（fallback 重读屏幕能力）；T-sch3a–c（active link → 失 screen → fallback → 恢复，macOS14 以下跳过分支） | `make test-ui` PASS | 真实 CADisplayLink 跨屏/VRR 回调、macOS13 真机未验证 |
| AC5 stable 时长语义与采样频率解耦 | behavior（纯函数，注入时间序列） | 60/120/不规则采样时刻 + 0.5px 累计亚阈值位移 | 24b9732 基线通过 | `Follower.decide(pet:stationaryAnchor:lastMaterialChangeAt:now:)` 消费注入 now | F18/F19（同一 elapsed 阈值进 stable）；F21–23（累计位移不误入 stable）；F16（4/60s 语义） | `make test-ui` PASS | 无 |
| AC5b 32ms 插值时间线与安全 snap | behavior（纯值 + panel sink） | 见 S3 | 见 S3 | 见 S3 | 见 S3 | 见 S3 | 真实体感拖尾未验证 |
| AC6 既有保守/卫生回归不破坏 | behavior | TCC false、capture unavailable、never-observed targetMissing、reset/空候选、旧 generation、同 WID 身份变化 | 24b9732 基线通过 | `BubbleVisibilityProbe` lock/generation/knownWids/single-flight 全链消费注入扰动 | T-bv38a–c（TCC false 保守）；T-bv39f3/f4/f5a（保守语义）；T-bv40（旧 generation 不通知）；T-bv41a–c（身份变化失效）；T-sch4e（reset/空/权限无残留 hint） | `make test-ui` PASS | 真实 TCC 中途变化未验证 |
| AC7 硬门禁 | build/docs/static | 候选完整树（test-only 改动 + 本文件） | 基线 24b9732 之上执行 | swiftc/SwiftPM/python gate 消费当前工作树 | release 0 warning；docs 0 finding；全套件全绿；diff 无 whitespace 错误 | `swift build -c release` Build complete!（0 warning）；`make docs-check` 14 files 0 findings；`make test-docs` 10 OK；`make PYTHON=<miniconda-python> test` 全绿（UI 244 passed / 0 failed）；`git diff --check 24b9732..HEAD` 通过 | 无 |
| AC8 模型/推理配置 | process/dispatch record | 父会话派发记录 + task.json meta | 本次实现 owner = zhipu/glm-5.3 + max（父会话解析，未降级） | 派发合同（本 worktree 唯一实现负责人） | 派发记录含任务名/角色/worktree/分支/base/范围/验收；本报告为该 owner 交付 | 见交付报告 | 正式 Review/QA 子 Agent 尚未派发，其模型预检在各自派发前执行 |
| AC9 开发候选产物 | 真机/QA（未启动） | — | — | — | — | 未执行 `make app`（按规则仅 Review 清零后由 QA 执行） | QA 未启动；候选归档、签名、来源验证全部未验证 |
| AC10 真机验收矩阵 | 真机 QA（未启动） | — | — | — | — | 未运行任何 .app | expanded→collapsed、full-hide、60Hz/高刷拖拽、多屏、TCC/ScreenCaptureKit、Instruments 全部未验证 |

## Fake / clock / event 消费合同（逐项证明被 SUT 读取）

| 注入物 | 被测生产对象实际消费点 | 证明 |
| --- | --- | --- |
| 单调时钟闭包（scheduler） | `FollowTickScheduler.monotonicNow()` 在 `performTick`/`scheduleStableTick` 读取 | T-sch1c–1h 的 deadline/latest-only 行为随注入时间变化 |
| 单调时钟闭包（probe） | `BubbleVisibilityProbe.monotonicNow()` 在 `probe`/`takePendingRetryDelay` 读取 | T-sch4a–d 的 capture 时刻/剩余等待随注入时间变化 |
| 生产默认单调时钟 provider（main.swift `followMonotonicNow`） | 单一闭包注入 `FollowTickScheduler`、`BubbleVisibilityProbe`、`Follower.decide`（经 tick）与 `DockPanel.placeBelow`；测试注入时钟不覆盖该默认值，故由 T-sch4f source guard 直接扫描 main.swift 源文本兜底 | 红测 ②：把该闭包临时改为 `Date().timeIntervalSinceReferenceDate` 后 guard FAIL 并精确指向 `Sources/PetDock/main.swift` |
| fake capturer（stats/targetMissing/unavailable） | `BubbleVisibilityProbe.probe` 的 `Task.detached` 逐候选调用并经 generation 校验写 cache | T-bv39/T-bv41/T-bv42 的分类、通知与失效行为依赖其返回值 |
| visibility 事件 | 生产构造点 `onVisibilityChange: scheduler.visibilityChangeCallback`（与 `Sources/PetDock/main.swift` 生产接线同构） | T-bv39c/T-bv42c 的 tick 计数只能由该回调驱动（测试从未手工调用 runTick 路径） |
| fake timer / display-link factory | `FollowTickScheduler.makeTimer/makeDisplayLink` 创建 source 并在其回调请求 beat | T-sch1–4 的 fire/invalidate 计数直接反映 factory 产物生命周期 |
| 障碍几何 fixture | `PetTracker.obstaclesNear` → `FollowLayoutPass` → `DockPanel.placeBelow` 真实消费 | T-bv39b/d 与 T-bv42b/d 的实际 panel frame 均随障碍集变化 |
| 墙钟扰动（已移除） | 无生产消费者 → 按 break-loop 4 判定为无效证据并删除 | 替换为 T-sch4f source guard（可执行、可失败） |

## 边界声明

- 自动证据不覆盖：真实 TCC/ScreenCaptureKit 像素流、真实 CG/SCK 生命周期错位、多屏负坐标、高刷/VRR 真实回调、拖拽体感、Instruments 开销——全部标记未验证，留待真机 QA。
- 本候选不包含产品代码改动；任何后续产品变更都会使本表及全部测试结论失效并需要重新冻结。

---

## v6 runtime-first 诊断候选（Fifth break-loop 控制段）

- 任务：fix-bubble-collapse-smooth-follow（v6，runtime-first bubble full-hide diagnostics）。
- 产品基线 + 治理/规划 HEAD：`773317752d9487a5551df1d53109e7066047ff5a`（worktree 初始 clean；本候选在其上叠加 runtime evidence 实现）。
- 本候选性质：仅增加默认关闭、QA 显式启用的匿名聚合诊断（`--runtime-evidence=<sha>`）及其测试/privacy guard/文档；不修改障碍分类、alpha 阈值、candidate identity、control 几何、capture cadence、scheduler 架构、插值语义或权限请求。

### 逐 AC 证据拓扑（v6 新增部分）

| AC / 症状 | 证据类型 | 触发 / 扰动 | 生产消费者 / 路径 | 最终所有者 / 断言 | 命令 / 结果 | 手工缺口 |
| --- | --- | --- | --- | --- | --- | --- |
| AC2c-1 默认关闭：无 flag 不创建诊断文件、不增加 capture/timer | behavior + static/absence | `RuntimeEvidenceFlag.parseCandidateSHA` 对空参数/非法值/裸 flag 返回 nil；evidence=nil 走完整生产布局链 | `main.swift` 唯一构造点（`init(runtimeEvidenceSHA:)` 内 `if let`）→ probe/placeDock/placeBelow 全部收到 nil；`RuntimeEvidence.swift` 无 Timer/Task/capture/墙钟 API（T-re8 + pytest source guard） | T-re1a–d、T-re7a（evidence=nil 时真实 DockPanel frame 与既有避让一致）；python guard 断言 Sources 中 `RuntimeEvidenceCollector(` 构造点唯一 | `make test-ui` 262/262；`pytest tests/test_runtime_privacy.py` 22 passed | 生产 AppDelegate 完整启动路径未在测试中实例化（避免拉起数据栈）；由唯一构造点 source guard + flag 解析测试覆盖 |
| AC2c-2 白名单序列化 / 禁止字段 | behavior | 对 collector 记录全部计数类别后取 snapshot 并 JSON 序列化 | `RuntimeEvidenceCollector.snapshot()` 固定 key 集合（21 字段：schema/candidateSHA/tick/kind/outcome/visibility/identity/wake/dy bucket 计数） | T-re2a key 集合精确等于白名单（无多余/缺失）；T-re2b 计数正确；T-re2c JSON 文本不含 owner/title/wid/pid/screen/alpha/color/image/bounds/process token | 同上 | 无 |
| AC2c-3 权限 / no-follow fail-closed | behavior | 临时目录 + sentinel 目标文件 + symlink 落盘点；调用 flush | `RuntimeEvidenceCollector.flush()` → `PrivateStorage.atomicWrite`（目录 ensurePrivateDirectory 0700、临时文件 0600、目标 symlink 先移除再原子替换，绝不写入链接目标） | T-re3a 仅 record 不创建文件；T-re3b flush 后目录 0700/文件 0600/内容=快照；T-re4 sentinel 目标内容不变且落点位成为常规证据文件（URL resourceValues 有实例缓存，断言走 attributesOfItem） | 同上 | 无 |
| AC2c-4 聚合输入在生产 owner 处采集 | behavior（生产组合，plumbing-only） | fake capturer `.stats(expanded)`→`.targetMissing`；同 WID bounds 亚像素抖动；control-kind fixture（60×24） | `BubbleVisibilityProbe.probe`（identity-change/outcome/visibility/wake，经 Task 消费）→ `onVisibilityChange` → `FollowTickScheduler.visibilityChangeCallback` → 完整 tick → `FollowLayoutPass.placeDock`（kind/visible 计数）→ 真实 `DockPanel.placeBelow`（实际 frame 相对同 tick 无障碍 base 的 dy bucket） | T-re5a–d：capture/visibility/identity/wake 计数、tick/kind/visible 计数、dy upTo64→base 迁移、真实 frame 避让→复位；T-re6a/b：control 存在即占位 → bubble=1/control=1/visible=2 | 同上 | 真实 image3 的 runtime kind/outcome/identity 分布未采样（本表所有 fake 注入均为 plumbing-only） |
| AC2b（v6 状态重申） | plumbing-only | 既有 T-bv42 fake `.targetMissing` 注入 | 既有生产组合证据不变（v5 表） | 管道能力已证；真实 full-hide 触发等价性未证 | `make test-ui` 262/262（含 T-bv42） | **待真机采样**：用本诊断候选执行真实图1→图2→图3，读 runtime-evidence.json 聚合后才可判定 H1/H2/H3/H4b 分支；在此之前不得宣称 image3 已修复 |

### v6 诊断候选边界声明

- 诊断启用只经 QA 启动参数；`candidateSHA` 由 QA 显式提供并只写入私有 0600 文件，被跟踪文件不包含真实 SHA。
- dy bucket 的 base 判定含 <1.0 像素对齐容差，与既有 frame 断言容差一致；不输出任何坐标数值。
- 诊断聚合在既有 tick 内采集；probe 的 outcome/visibility 计数来自其既有后台捕获 Task，wake 计数来自既有 `onVisibilityChange` 回调，均未新增捕获流、Timer 或 runloop source。
- 真实 TCC/ScreenCaptureKit 像素流、真实 CG/SCK 生命周期、多屏、拖拽体感与 Instruments 开销仍未验证；image3 症状结论等待同一诊断候选的真机脱敏采样。
