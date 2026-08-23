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
- 本候选性质：仅增加默认关闭、QA 显式启用的匿名聚合诊断（`--runtime-evidence=<sha>`）及其测试/privacy guard/文档；不修改障碍分类、alpha 阈值、candidate identity、control 几何、capture cadence、scheduler 架构、插值语义或权限请求。pre-Review admission 修复批次（identity 计数时机、stale 结果过滤、flush 写盘抑制）与 Review r1 修复批次（T-re10 竞态、flush 0.5s 单调节流）同样只改诊断 instrumentation 语义与测试确定性，不改产品分类/布局/调度行为。
- 基线口径：approved base 为 `773317752d9487a5551df1d53109e7066047ff5a`（产品 Sources 与 v5 冻结基线一致）。正常路径既有 UI 244 项在 v5 冻结候选记录为通过（见上半部分 v5 表），且全部在本候选当前套件中保持通过；AC2c 各项为**新增默认关闭诊断能力**，不存在也不需要既有行为红测——基线列按 N/A（新增能力）/coverage 补强分别注明，不编造任何红测。

### 逐 AC 证据拓扑（v6 新增部分）

| AC / 症状 | 证据类型 | 触发 / 扰动 | 基线来源 / 结果 | 生产消费者 / 路径 | 最终所有者 / 断言 | 命令 / 结果 | 手工缺口 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| AC2c-1 默认关闭：无 flag 不创建诊断文件、不增加 capture/timer | behavior + static/absence | `RuntimeEvidenceFlag.parseCandidateSHA` 对空参数/非法值/裸 flag 返回 nil；evidence=nil 走完整生产布局链 | approved base `bdfd10d`：正常路径无既有"诊断关闭"行为可回归（新增能力，基线 N/A）；正常布局行为由既有 244 项 UI 回归在基线通过并在本候选保持通过佐证 → coverage，非红测 | `main.swift` 唯一构造点（`init(runtimeEvidenceSHA:)` 内 `if let`）→ probe/placeDock/placeBelow 全部收到 nil；`RuntimeEvidence.swift` 无 Timer/Task/capture/墙钟 API（T-re8 + pytest source guard） | T-re1a–d、T-re7a（evidence=nil 时真实 DockPanel frame 与既有避让一致）；python guard 断言 Sources 中 `RuntimeEvidenceCollector(` 构造点唯一 | `make test-ui` 279/279；`pytest tests/test_runtime_privacy.py` 22 passed | 生产 AppDelegate 完整启动路径未在测试中实例化（避免拉起数据栈）；由唯一构造点 source guard + flag 解析测试覆盖 |
| AC2c-2 白名单序列化 / 禁止字段 | behavior | 对 collector 记录全部计数类别后取 snapshot 并 JSON 序列化 | 基线 N/A：新增序列化契约，产品正常路径无既有对应行为；coverage-only | `RuntimeEvidenceCollector.snapshot()` 固定 key 集合（21 字段：schema/candidateSHA/tick/kind/outcome/visibility/identity/wake/dy bucket 计数） | T-re2a key 集合精确等于白名单（无多余/缺失）；T-re2b 计数正确；T-re2c JSON 文本不含 owner/title/wid/pid/screen/alpha/color/image/bounds/process token | 同上 | 无 |
| AC2c-3 权限 / no-follow fail-closed | behavior | 临时目录 + sentinel 目标文件 + symlink 落盘点；调用 flush | 基线 = PrivateStorage 既有契约：DataTests `T-storage-privacy` 与 PetLogger `L10`（symlink 不重定向）在基线通过；本候选复用同一 `PrivateStorage.atomicWrite`，T-re3/T-re4 为 coverage 补强，无红测 | `RuntimeEvidenceCollector.flush()` → `PrivateStorage.atomicWrite`（目录 ensurePrivateDirectory 0700、临时文件 0600、目标 symlink 先移除再原子替换，绝不写入链接目标） | T-re3a 仅 record 不创建文件；T-re3b flush 后目录 0700/文件 0600/内容=快照；T-re4 sentinel 目标内容不变且落点位成为常规证据文件（URL resourceValues 有实例缓存，断言走 attributesOfItem） | 同上 | 无 |
| AC2c-4 聚合输入在生产 owner 处采集 | behavior（生产组合，plumbing-only） | fake capturer `.stats(expanded)`→`.targetMissing`；同 WID bounds 亚像素抖动（due / not-due / in-flight 三态）；control-kind fixture（60×24）；in-flight 用 semaphore gate（entry 确认 calls==1 → 注入 jitter 断言 inFlight → 手工释放 → 收尾），无固定 sleep/竞态 | 基线 = v5 表 T-bv39/T-bv42 于 `24b9732` 通过（plumbing，正常路径无行为变化）；admission 批次新增 T-re9（not-due jitter 不漏计）/T-re10（in-flight replacement 计数 + stale 结果拒绝）；Review r1 批次把 T-re10 改为 deterministic gate——Reviewer 在同 SHA 连跑 7 次仅 2 pass 的非确定性已消除，均为 instrumentation coverage 补强，非红测、不改产品行为 | `BubbleVisibilityProbe.probe`（identity-change 在 capture gate 前同步计数；outcome/visibility 仅在 completion 通过 generation+capturedCandidates 接受并写 cache 后计入）→ `onVisibilityChange` → `FollowTickScheduler.visibilityChangeCallback` → 完整 tick → `FollowLayoutPass.placeDock`（kind/visible 计数）→ 真实 `DockPanel.placeBelow`（实际 frame 相对同 tick 无障碍 base 的 dy bucket） | T-re5a–d：capture/visibility/identity/wake 计数、tick/kind/visible 计数、dy upTo64→base 迁移、真实 frame 避让→复位；T-re6a/b：control 存在即占位；T-re9a/b：not-due jitter → identity+1 且 capture 调用数不变；T-re10（gate 版）：capturer 已进入 calls==1 且 inFlight 确定 → in-flight jitter identity+1、single-flight 不加捕获、stale 完成 0 计数、接受后的新捕获 1 计数 | 同上；T-re10 确定性另由 test-ui 连续 10 次全绿复核 | 真实 image3 的 runtime kind/outcome/identity 分布未采样（本表所有 fake 注入均为 plumbing-only） |
| AC2c-5 flush 写盘抑制 + 最小 0.5s 单调节流（不干扰 moving 高频 tick） | behavior（可观察 flush 结果 + 实际文件内容） | 注入单调时钟：首个 layout 证据 → 100 个完全相同状态 tick → 40 次窗口内 identity 抖动 → 到期 → dy bucket 同值/新值 → layout 状态变化 → accepted capture/identity/wake → 落盘失败（父路径为文件）→ 窗口内路径恢复 → 到期重试 | 基线 N/A：新增机制；修复前的"每 tick 写盘"与"持续 jitter 每 tick 写"均为诊断自身开销缺陷（instrumentation 修复），非产品行为回归 | collector dirty 状态机 + `lastFlushAt` 节流（`minimumFlushInterval=0.5s`，时钟由 main 注入的 follow 单调时钟提供；`RuntimeEvidence.swift` 不读取任何系统时间源，T-re8/pytest guard 复核）；被节流的 dirty 向后携带，到期由既有 tick 写出；失败同样推进 `lastFlushAt` 且恢复 dirty，重试受同一节流；无 Timer/Task/capture/queue 新增 | T-re11a 首证据立即写一次；T-re11b 100 无变化 tick 0 写且文件 tickCount 停更；T-re11g 窗口内 40 次抖动 0 额外写；T-re11h 到期只写一次且 identity 计数=40；T-re11i-1/2/3 失败 false → 窗口内路径恢复仍不重试 → 到期重试成功且计数完整；T-re11j–m dy/layout/accepted evidence 各写一次且同值不写 | 同上 | 无 |
| AC2b（v6 状态重申） | plumbing-only | 既有 T-bv42 fake `.targetMissing` 注入 | 基线 = T-bv42 于 `24b9732` 基线通过（v5 表，plumbing）；触发等价性至今未证 | 既有生产组合证据不变（v5 表） | 管道能力已证；真实 full-hide 触发等价性未证 | `make test-ui` 279/279（含 T-bv42） | **待真机采样**：用本诊断候选执行真实图1→图2→图3，读 runtime-evidence.json 聚合后才可判定 H1/H2/H3/H4b 分支；在此之前不得宣称 image3 已修复 |

### v6 诊断候选边界声明

- 诊断启用只经 QA 启动参数；`candidateSHA` 由 QA 显式提供并只写入私有 0600 文件，被跟踪文件不包含真实 SHA。
- dy bucket 的 base 判定含 <1.0 像素对齐容差，与既有 frame 断言容差一致；不输出任何坐标数值。
- 诊断聚合在既有 tick 内采集；probe 的 outcome/visibility 计数来自其既有后台捕获 Task，wake 计数来自既有 `onVisibilityChange` 回调，均未新增捕获流、Timer 或 runloop source。
- identity-change 在 `probe()` 的 capture gate 之前同步计数（not-due/in-flight 均不漏计）；capture outcome/visibility 仅在 completion 通过当前 generation+capturedCandidates 校验、实际写入 cache 后计入；stale 丢弃结果不进入统计。
- flush 采用 dirty 抑制：仅 accepted capture / identity / wake / layout 状态变化 / dy bucket 变化才产生待写证据；无变化的高频 display tick 零写 IO；写盘失败恢复 dirty 等待节流窗口到期后重试。
- flush 节流由注入的单调时钟驱动（生产为既有 `followMonotonicNow`）：首个证据立即写，其后最小间隔 0.5s；持续 identity 抖动在窗口内合并、到期由下一次既有 tick 写一次；失败重试受同一节流。`RuntimeEvidence.swift` 自身不读取 Date/ProcessInfo 等任何系统时间源（T-re8 + pytest source guard 固化）。
- 真实 TCC/ScreenCaptureKit 像素流、真实 CG/SCK 生命周期、多屏、拖拽体感与 Instruments 开销仍未验证；image3 症状结论等待同一诊断候选的真机脱敏采样。

---

## v7 证据加固候选（Sixth break-loop 控制段）

- 任务：fix-bubble-collapse-smooth-follow（v7，second Review 四项 P2 的证据加固）。
- 实现基线：`<v7-planning-base>`（v7 planning baseline；worktree 初始 clean、HEAD 精确等于该提交）。
- 本候选性质：只加固诊断证据链与门禁可信度（owner read-back、async-safe test gate、test compile warnings gate、递归 privacy guard + production sink 断言、exact 40-hex provenance、本表）。不修改障碍分类、alpha 阈值、candidate identity、capture/generation、scheduler、插值、权限或 UI 行为；不构建/归档 .app（属 Review 后 QA）。
- 冻结候选完整 SHA 在交付报告中给出；SHA 变化后本表结论一并失效。

### 逐项证据拓扑（v7）

| 修复项 | 证据类型 | 触发 / 扰动 | 基线来源 / 结果 | 生产消费者 / 路径 | 最终所有者 / 断言 | 命令 / 结果 | 手工缺口 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| P2-1 dy telemetry 消费 setFrame 后 owner frame（AC2c owner 回读合同） | behavior（生产组合）+ static/absence（source guard）+ mutation | fractional bucket-boundary 避让 fixture（32/64 边界 × 8 个 δ，运行时用同构探针 panel 实测对齐后自适应选择）；经 scheduler wake → FollowLayoutPass.placeDock → DockPanel.placeBelow → collector | 基线 `<v7-planning-base>` 的 v6 代码把请求 frame 传给 dyBucket（等价于 M1 mutation 态）。本显示环境 setFrame 为整数点量化（owner dy ≡ ceil(requested dy)），与整数 bucket 边界（1/32/64）数学上不可区分 → T-re12a 诚实标注 coverage-gap，不伪造区分证据；可失败性由 T-re12b guard + M1 mutation 承担 | DockPanel.placeBelow 在 panel.setFrame(frame, display: true) 之后回读 panel.frame 为 ownerFrame，仅以该值调 dyBucket(actualAppKitFrame:) → RuntimeEvidenceCollector.recordDockDyBucket；插值状态继续用请求值，布局行为不变 | T-re12a：collector lastDockDyBucket == 按真实 reODock.frame（owner 回读）独立计算的 bucket；可区分环境中同时断言 ≠ 按请求 frame 计算的 bucket。T-re12b：DockPanel.swift 空白归一化后必须存在 panel.setFrame(frame,display:true) → letownerFrame=panel.frame → dyBucket(actualAppKitFrame:ownerFrame 且顺序正确 | make test-ui 281/281（T-re12a PASS 带 [coverage-gap: requested==owner in this display environment]）。M1 mutation（dyBucket 改回请求 frame、删除回读）→ make test-ui EXIT=2，唯一 FAIL=T-re12b（readBack=false consume=false）；撤销后 281/281 | 其他显示对齐策略（如半点量化）下行为区分未在本机验证；由探针自适应逻辑覆盖，真机表现留待 QA 环境观察 |
| P2-2 async fixture 不阻塞 cooperative executor + test compile warnings gate（AC7） | behavior（gate 确定性）+ build gate + mutation | T-re10 in-flight identity replacement：capturer 进入后挂起 continuation（不占线程），主线程 pump RunLoop 确定 entered/calls/inFlight 后注入 identity replacement，release 恰好 resume 一次；stale 完成拒绝 + 第二轮 accepted capture | 基线 `<v7-planning-base>`：make test-ui 279/279 PASS 但编译含 warning（tests/main.swift:2222:20 DispatchSemaphore.wait unavailable from asynchronous contexts）；对同一未修改树执行精确 test-ui swiftc 命令 + -warnings-as-errors → 编译 FAIL EXIT=1（红基线） | BubbleVisibilityProbe.probe 的 Task.detached 捕获链消费 AsyncCaptureEntryGate.waitAfterEntry()（test-only，lock 保护 CheckedContinuation<Void, Never> + entered/pendingReleases，早到 release 由下一进入者消费，恰好 resume 一次）；生产代码零改动 | T-re10 前置/a/b/c：entered/calls==1/inFlight 确定 → in-flight jitter identity+1 且不加第二捕获 → stale 完成 outcome/visibility/wake 均 0 → 接受的新捕获 stats/visible 各+1 且 calls==2。Makefile test-ui swiftc 加 -warnings-as-errors 后 0 warning 编译 | make test-ui（新 gate）281/281，0 warning；连续 3 次全绿（continuation gate 确定性）。M2 mutation（capturer 内临时恢复 DispatchSemaphore.wait()）→ 编译阶段 FAIL EXIT=2（error: wait unavailable from asynchronous contexts, tests/main.swift:2274）；撤销后 PASS | 无 |
| P2-3 递归 constructor guard + production sink 断言（AC2c privacy；formal Review r1 后强化） | static/absence（pytest source guard）+ mutation | tests/test_runtime_privacy.py 对 Sources/PetDock 递归枚举（仅排除根级相对路径 RuntimeEvidence.swift，嵌套同名文件仍扫描），空白归一化后同时计数 RuntimeEvidenceCollector( 与 RuntimeEvidenceCollector.init( 两种 direct 形态，总数==1 且位于 main.swift；同时拒绝 typealias 同行引用、RuntimeEvidenceCollector.self metatype 与 typed 注解 + 非 super .init( 旁路；对 main.swift 去空白后在唯一构造点参数区内断言精确 sink 表达式 PrivateStorage.diagnosticsURL.appendingPathComponent(RuntimeEvidenceCollector.outputFileName) | 基线 `<v7-planning-base>`：guard 用 glob("*.swift") 只扫顶层且无 sink 断言（P2 原样）；make PYTHON=<conda-base-python> test-privacy 基线 22 passed（既有用例） | pytest 直接读取 production source tree；main.swift 唯一构造点经 PrivateStorage.diagnosticsURL + 固定文件名落盘（0700/0600/no-follow 由 PrivateStorage 既有合同保证） | 构造点唯一 + sink 精确匹配；嵌套 source 出现第二构造点、显式 .init 形态、alias/typed-init 旁路或 sink 改为非 Diagnostics URL 时 guard FAIL | make PYTHON=<conda-base-python> test-privacy 22 passed（系统 Python 无 pytest，按项目 Python 政策用 conda base）。M3 mutation（嵌套第二构造点）→ FAIL，撤销后 22 passed；M4 mutation（sink 临时改非 Diagnostics URL）→ sink 断言 FAIL，撤销后 22 passed；r1 新增 M7a–M7d 见 formal Review r1 修复批次 | 无 |
| P2-4 exact 40-hex provenance（AC2c/QA 准入合同） | behavior（边界反例）+ mutation + docs | RuntimeEvidenceFlag.isCandidateSHA 收紧为恰好 40 个 ASCII 小写十六进制字符（0-9/a-f）；T-re1c/d/e 显式拒绝 7/39/41/64 位、40 位大写、40 位非 hex、全角 Unicode hex、裸 flag | 基线 `<v7-planning-base>`：v6 parser 接受 7–64 位（T-re1c 曾断言 7 位缩写 enabled）；基线红证据等价于 M5 mutation 态 | main.swift 启动参数 → RuntimeEvidenceFlag.parseCandidateSHA → 唯一构造点 candidateSHA（40 位 ASCII hex 才启用诊断，其余保持关闭零开销） | T-re1b 40 位小写 hex → enabled；T-re1c 7/39/41/64 → disabled；T-re1d 大写/非 hex/裸 flag → disabled；T-re1e 全角 Unicode hex → disabled；dev-candidate.md 同一提交同步 ASCII 40-hex 合同 | make test-ui 282/282。M5 mutation（临时回退 (7...64).contains）→ T-re1c FAIL，撤销后 PASS；M6 mutation（临时回退 Character.isHexDigit 判定）→ T-re1e FAIL，撤销后 PASS；docs 门禁见交付报告 | 无 |

### v7 admission repair 批次（正式 Review 前主会话准入修复）

- 背景：首个 v7 实现提交在正式 Review 前被主会话 admission 拒绝；三项 finding 在同一实现 worktree 内集中为一个修复批次。本节及上文 v7 表格中的 provenance / 机器路径一律使用稳定占位符（`<v7-planning-base>`、`<conda-base-python>`），精确 assignment SHA 只保留在未跟踪的父会话派发记录。
- Finding A（ASCII 合同缺口）：`Character.isHexDigit` 接受全角 Unicode hex（全角 0 / 全角 a 均 isHexDigit=true 且非大写），首个 v7 提交的“40 位 Character”检查无法拒绝 40 个全角字符。红基线：在未修改的首个 v7 parser 上新增 T-re1e（40 个全角 0、40 个全角 a）→ make test-ui FAIL（281 passed / 1 failed，parse 返回非 nil）。修复：改为精确 Git SHA-1 语法 —— value.utf8.count == 40 且每个字节 ∈ 0x30–0x39 / 0x61–0x66；T-re1e PASS。M6 mutation：临时回退为 Character.isHexDigit 判定 → T-re1e FAIL；恢复 ASCII 字节判定 → PASS。既有 7/39/41/64/大写/非 hex 边界全部保持。
- Finding B（tracked 证据脱敏）：上文 v7 节的精确 planning full/short SHA → `<v7-planning-base>`；conda Python 绝对路径 → `<conda-base-python>`；测试中新增的第二个 hash 形态字面量（reOSHA）删除并复用既有 reSHA fixture，7 位边界反例同步改为非字面构造。新增行隐私扫描（本机绝对路径、邮箱地址、完整/短提交指纹、签名指纹或窗口 ID 形态）：按文件名+计数报告，修复后 0 残留，不回显任何敏感值。
- Finding C（sink guard 锚定缺口）：privacy guard 从“sink 表达式存在于 main.swift 任意位置”收紧为“唯一 RuntimeEvidenceCollector( 构造点参数区内（括号配对提取，无新 parser/依赖）outputURL 精确等于 PrivateStorage.diagnosticsURL.appendingPathComponent(RuntimeEvidenceCollector.outputFileName)”。M4 复检：sink 临时改非 Diagnostics URL → test-privacy FAIL；恢复 → 22 passed。M3 递归构造点 mutation 语义不受影响。
- 门禁复跑（脱敏命令形式）：git diff --check、swift build -c release（0 warning）、make PYTHON=<conda-base-python> test、task.py validate、targeted test-ui 重复运行、test-privacy mutation 复检；实际结果见交付报告。未执行 make app / 候选归档。

### v7 formal Review r1 修复批次（sole-constructor guard 强化）

- Review finding（对 `<v7-admission-repair-base>`，P0=0/P1=0/P2=1）：sole-constructor guard 只按文件名排除 RuntimeEvidence.swift，且只计字面 RuntimeEvidenceCollector( —— Reviewer 独立证明嵌套 production RuntimeEvidenceCollector.init(...) 仍 22 passed，嵌套同名 RuntimeEvidence.swift 亦逃逸，破坏 sole-constructor/private-sink absence 合同。该提交及其全部先前 Review 结论失效。
- 本地红基线（修复前同树复现两个逃逸洞，均未修改 guard）：嵌套显式 RuntimeEvidenceCollector.init(...) → make PYTHON=<conda-base-python> test-privacy 22 passed（洞 A）；嵌套 Data/RuntimeEvidence.swift 内直接 RuntimeEvidenceCollector( → 22 passed（洞 B）。
- 修复合同（tests/test_runtime_privacy.py，无新 parser/依赖）：① 断言根级 RuntimeEvidence.swift 定义文件存在，仅按精确相对路径排除该文件，嵌套同名文件仍扫描；② 其余全部 production Swift 空白归一化后计数 direct RuntimeEvidenceCollector(，总数==1 且唯一许可点为 main.swift；③ 保守拒绝旁路：typealias 绑定、RuntimeEvidenceCollector.init constructor reference（含显式 .init(...) 与无括号 first-class factory 形态）、RuntimeEvidenceCollector.self metatype、typed 注解（: RuntimeEvidenceCollector）+ 非 super .init(（super.init( 显式豁免，避免既有 NSPanel 子类误伤）——文本 guard 不假装解析跨文件 alias；④ sink 断言仍锚定唯一 direct 构造点参数区（括号配对提取）。
- Second-review admission 追加修补（同一 r1 批次内）：首轮修补后仍有两个残留洞——typealias 检测按行 split，typealias 名 = 换行接 RuntimeEvidenceCollector 的合法多行绑定可绕过；RuntimeEvidenceCollector.init 无紧跟括号的 first-class constructor reference（let make = ... 后 make(...)）绕过 direct 形态与 metatype/typed-init 检查。本地红基线（修补前同树）：多行 typealias → 22 passed；无括号 factory reference → 22 passed。修补：typealias 改为空白归一化源上的绑定正则（typealias 名 = 起，惰性跨越至 RuntimeEvidenceCollector，途中不得出现 static/func/class/struct/enum/protocol/extension/let/var/import 关键字或 ;/{，防止无关 alias 与远处注解跨声明误连）；factory 检查改为在全部扫描文件（含 main.swift）禁止任何 RuntimeEvidenceCollector.init 引用，唯一许可生产构造语法保持 main.swift 的直接 RuntimeEvidenceCollector(...)。
- Mutation 证据（均 FAIL → 撤销 → PASS）：M7a 嵌套显式 RuntimeEvidenceCollector.init( → FAIL（constructor-factory-reference）；M7b 嵌套 Data/RuntimeEvidence.swift 直接构造 → FAIL（direct-construction，该文件被扫描不再按文件名逃逸）；M7c 单行 typealias ... = RuntimeEvidenceCollector + 别名调用 → FAIL（typealias-alias）；M7d typed 注解 + .init( → FAIL（typed-inferred-init）；M8a 多行 typealias（= 换行接 RuntimeEvidenceCollector）→ FAIL（typealias-alias）；M8b 无括号 first-class factory reference → FAIL（constructor-factory-reference）；M3 复检嵌套直接构造 → FAIL；M4 复检 sink 改非 Diagnostics URL → FAIL。清洁树 22 passed。
- 冻结计数：make test-ui 282/282；make PYTHON=<conda-base-python> test-privacy 22 passed；其余门禁见交付报告。未执行 make app / 候选归档。

### v7 边界声明

- 本候选不改变任何正常用户路径行为：障碍分类、alpha 阈值、candidate identity、control 几何、capture cadence/generation、scheduler、插值语义、权限请求与 UI 均与基线一致；唯一生产代码改动是 DockPanel.placeBelow 在 setFrame 后回读 panel.frame 并仅用于 dy telemetry 输入（插值/setFrame 请求值不变），以及 parser 长度收紧。
- 原始 image3 症状（全部消息/控制隐藏后底座保持旧避让间距）仍未修复也未宣称修复：v7 全部 fake 注入（含 T-re12）仍是 plumbing-only；真实 runtime kind/outcome/identity 分支未采样，等待同一候选的真机脱敏 runtime-evidence。
- 本机显示环境（整数点量化）无法行为性区分 requested 与 owner dy bucket，T-re12a 如实标注 coverage-gap；该缺口由 T-re12b source guard 的 M1 mutation FAIL/PASS 证据承担可失败性，不伪造红证据。
- 真机 TCC/ScreenCaptureKit、多屏、拖拽体感、Instruments、.app 构建/归档全部未验证、未执行（make app 属 Review 清零后的 QA 阶段）。

---

## v8 编译器优先 runtime evidence sink 候选（Seventh break-loop 控制段）

- 任务：fix-bubble-collapse-smooth-follow（v8，v7 第二轮 Review 两项 P2 构造守卫逃逸后的结构性重做）。
- 实现基线：`<v8-planning-base>`（worktree 初始 clean、HEAD 精确等于该提交、branch/worktree 唯一）。
- 本候选性质：仅重做 runtime evidence 构造/布线边界——designated initializer 改 `private`、同文件无地址参数 `production(candidateSHA:flushNow:)` 工厂（sink 固定 PrivateStorage.diagnosticsURL + 证据文件名）、`#if PETDOCK_TESTING` 包裹的同文件 `forTesting` 工厂、Makefile test-ui swiftc 单点 `-DPETDOCK_TESTING`（Package.swift 无 flag）、W0–W6 单一 token/shape/布线 canary 替换 v7 构造 regex 家族，及同步文档与本表。record/flush/snapshot/字段/节流语义与全部产品分类/布局/调度/插值/权限行为零改动。
- 防线分层声明：访问控制主证据是 release 编译失败（编译器拒绝），不是文本 canary；W0/W6 仅 accidental-drift，W1–W5 仅单一 token/declaration/布线计数。主 admission 必须检查编译器证据与布线 canary，不得只看测试计数。

### 红基线（未修改 v7 树，先于任何 v8 改动，临时改动均完全还原）

| 编号 | 临时改动 | 旧树预期 | 实际结果 |
| --- | --- | --- | --- |
| RB-A | RuntimeEvidence.swift 内加未 flag `static func`（接收任意落盘地址参数）并由 main.swift 调用（保留原唯一构造点） | `make test-privacy` 仍全绿（定义文件豁免洞） | 22 passed, exit 0 —— 任意生产 sink 在旧守卫下可表达 |
| RB-B | 嵌套生产文件加 `RuntimeEvidenceCollector /*rb*/ (` 注释分隔构造 | 同上（注释 trivia 洞） | 22 passed, exit 0 —— 空白归一化对注释分隔形态失效 |

### MA 编译层 mutation（v8 树，`swift build -c release` 必须 FAIL）

| 编号 | 临时改动 | 实际失败 |
| --- | --- | --- |
| MA1 | 嵌套生产文件直接 `RuntimeEvidenceCollector(...)` | error: 'RuntimeEvidenceCollector' initializer is inaccessible due to 'private' protection level, exit 1 |
| MA2 | 嵌套生产文件显式 `.init(...)` | 同上（同文件工厂专属语义对语法变体一次封死）, exit 1 |
| MA3 | 嵌套生产文件注释分隔 `RuntimeEvidenceCollector /*ma*/ (` | 同上（r2 洞 B 形态不再相关）, exit 1 |
| MA4 | main.swift `production(...)` 临时加 `outputURL:` 实参 | error: extra argument 'outputURL' in call, exit 1 —— 任意 sink 在生产调用点不可表达 |
| MA5 | 嵌套生产文件调用 `forTesting(...)` | release: error: type 'RuntimeEvidenceCollector' has no member 'forTesting', exit 1；同时 W1 privacy FAIL（1 failed, 27 passed）|

### MA 布线/shape mutation（`make test-privacy` 必须 FAIL）

| 编号 | 临时改动 | 命中 |
| --- | --- | --- |
| MA6 | Package.swift 加 `.define("PETDOCK_TESTING")` | W4 FAIL（1 failed, 27 passed）|
| MA7-A | Makefile flag 复制到 test-data swiftc 行（两处 flag） | W5 FAIL（flag 计数 != 1）|
| MA7-B | Makefile flag 从 test-ui 移到 test-data（单处但错位） | W5 FAIL（行不含 tests/main.swift 且不在 test-ui recipe 内）|
| MA8 | RuntimeEvidence.swift 区域外加落盘地址型参数工厂（洞 A 的 v8 复刻） | W3 identifier-boundary URL allowlist FAIL |
| MA9 | 删除 `#if PETDOCK_TESTING`/`#endif` 包裹（forTesting 裸露） | W2 + W3 双 FAIL |
| MA10 | 三态对照（保留 MA1 外部直接构造 probe） | A 正确 private 树：release 编译 FAIL；B 临时去掉 `private`：同一 probe 变为可编译（breach 实证访问控制是主防线）且 W0 FAIL；C 恢复：probe 再次编译 FAIL 且 W0 PASS（28 passed）|

### v8 formal Review r1 修复批次（W7 declaration inventory canary）

- Review finding（对 `<v8-r1-review-base>`，P0=0/P1=0/P2=1）：W3 只盘点 `URL|NSURL|CFURL` 类型 token；Reviewer 证明定义文件内未 flag 的同文件生产 API 可接收 `String` 并经 `URLComponents` 或 `FileManager.default.temporaryDirectory` 派生任意 sink——release 编译通过且当时 28 项 privacy 全绿。该 SHA 及其全部 Review 结论失效。
- 修复合同（`tests/test_runtime_privacy.py` 新增 W7，编译层访问控制证据保持主证据、W3 原样保留）：① test flag 区域外完全禁止 `extension` token（含注释/字符串，fail-closed）；② 以行首 declaration shape（可选 attribute + 修饰词组合 + class/struct/enum/protocol/typealias/func/init/deinit/let/var）钉死区域外完整 declaration 清单（53 行，含嵌套局部 declaration——区分作用域即自制 parser，故整文件 fail-closed；任何新增行必须更新清单并走隐私复审）。仅防 accidental drift，不作为语言层证明。
- Mutation 证据（均 FAIL → 完全撤销 → PASS）：

| 编号 | 临时改动 | release 编译 | privacy 结果 |
| --- | --- | --- | --- |
| MA11-A | 文件末尾未 flag `extension` + `static func` 工厂接收 `path: String`，经 `URLComponents(string:)` 派生 sink | Build complete（exit 0）——Reviewer 场景真实可编译，W3 对其完全无感 | 仅 W7 FAIL（1 failed, 28 passed；W3 保持绿）|
| MA11-B | class 内 `static func` 工厂经 `FileManager.default.temporaryDirectory.appendingPathComponent(path)` 派生 sink，无地址类型注解 | Build complete（exit 0）——真实 drift | 仅 W7 FAIL（1 failed, 28 passed；W3 保持绿）。附带证据：临时注释含英文单词 "URL" 时 W3 亦 FAIL（fail-closed 注释误报方向成立），改写注释后聚焦为 W7-only FAIL |

- 撤销后清洁树 privacy：29 passed（v7 22 → v8 28 → r1 修复后 29）。W0–W6 与既有 MA1–MA10 语义零改动。

### 行为/回归与门禁证据

- T-re1–T-re12 断言、fixture 与时序零改动；tests/main.swift 仅 9 处构造改为 `forTesting(...)`。test-ui 282/282，连续 3 次全绿（run1/2/3 均 282 passed, 0 failed；r1 修复批次复跑同样三连绿）。
- privacy gate：v7 22 passed → v8 28 passed（删 1 个构造 regex 测试，新增 W0–W6 共 7 个；aggregate-only 与既有合同测试原样保留）→ r1 修复后 29 passed（新增 W7 declaration inventory；W0–W6 原样）。
- 门禁：`git diff --check` 通过；`swift build -c release` 0 warning；`make PYTHON=<project-python> test`（docs-check + test-docs + test-privacy + test-ui + test-data + test-shell）全绿；`task.py validate` 全绿；added-line 隐私扫描按文件名+计数报告，0 残留；无生成产物 staged。
- 生产工厂真实落盘不在 test-ui 内行为化（不写真实私有目录）：由编译层（无地址参数）+ W6/源审 + QA 真机（`--runtime-evidence=<candidate-full-sha>` 后检查私有 Diagnostics 文件出现且权限正确）分层验证。

### v8 边界声明

- 本候选不改变任何正常用户路径行为：障碍分类、alpha 阈值、candidate identity、capture cadence/generation、scheduler、插值语义、telemetry 字段/flush 行为、权限与 UI 均与基线一致；DockPanel/BubbleVisibility/FollowTickPlan/Follower/obstacle/capture/scheduler/interpolation 零改动。
- 原始 image3 症状仍未解决也不宣称解决：全部 fake 注入仍是 plumbing-only；等待同一候选真机脱敏 runtime-evidence 采样后再判定分支。
- 真机 TCC/ScreenCaptureKit、多屏、拖拽体感、Instruments、make app/候选归档全部未验证、未执行（属 Review 清零后的 QA 阶段）。

---

## v9 私有实现边界候选（Eighth break-loop 控制段）

- 任务：fix-bubble-collapse-smooth-follow（v9，v8 第二轮 Review P1/P2 后的 runtime evidence 私有实现边界重做）。
- 实现基线：`<v9-planning-base>`（worktree 初始 clean、HEAD 精确等于该提交、branch/worktree 唯一；完整 SHA 只保留在未跟踪的父会话派发记录，不写入被跟踪文件）。
- 本候选性质：仅重做 runtime evidence 访问控制与布线守卫——`RuntimeEvidenceCollector` 改为 `private final` 并实现 internal `RuntimeEvidenceRecording` 协议（仅既有 record/snapshot/flush 能力，无 URL/path/sink）；生产文件（main.swift、BubbleVisibility.swift、FollowTickPlan.swift 的 FollowLayoutPass、DockPanel.swift）只保存 `any RuntimeEvidenceRecording` existential，经无地址参数的同文件 `makeRuntimeEvidenceRecorder(candidateSHA:flushNow:)` 取得；`makeRuntimeEvidenceRecorderForTesting(candidateSHA:outputURL:flushNow:)` 仅在 `#if PETDOCK_TESTING` 下存在；filename-only 常量 `runtimeEvidenceOutputFileName` 不暴露地址能力。record/flush/snapshot/字段/节流语义与全部产品分类/布局/调度/插值/权限行为零改动。
- 防线分层声明：跨文件访问控制主证据是真实编译失败（Swift 编译器拒绝命名 file-private 类型），pytest 编译 probe 在每次隐私门禁自动执行；W1/W2/W4/W5 仅单一 token/布线 canary。Swift declaration/constructor inventory 已删除且不得以新形态回归。

### 红基线（未修改 v8 树，隔离副本执行后完全恢复并丢弃）

| 编号 | 临时改动 | 旧树预期 | 实际结果 |
| --- | --- | --- | --- |
| RB-C | 定义文件内加未 flag `convenience init`（String 派生任意 sink）并由外部生产文件调用 | release 编译通过且 privacy 全绿 | `swift build -c release` exit 0；旧 privacy 29 passed（任意生产 sink 在旧守卫下可表达） |
| RB-D | 定义文件内加未 flag `static subscript`（选择任意 sink）并由外部生产文件调用 | 同上 | release exit 0；旧 privacy 29 passed |
| RB-E | 第二个 swiftc recipe（test-data）加分离式 `-D PETDOCK_TESTING` | 旧 W5 只计连写形态，privacy 全绿 | 旧 privacy 29 passed（分离式 flag 布线逃逸） |

### MC 编译层 mutation（v9 树，隔离副本，`swift build -c release` 必须 FAIL）

| 编号 | 临时改动 | 实际失败 |
| --- | --- | --- |
| MC1 | 嵌套生产文件直接 `RuntimeEvidenceCollector(...)` | error: 'RuntimeEvidenceCollector' is inaccessible due to 'private' protection level, exit 1 |
| MC2 | private collector 加 `convenience init`（String sink 形态）后重复 MC1 外部构造 | 同上错误, exit 1 —— v8 P1 洞在 v9 结构下被封死 |
| MC3 | private collector 加 static property + static subscript + static method（均可选任意 sink）后外部逐一引用 | 同上错误（3 处引用全部拒绝）, exit 1 —— 任意成员形态不扩大跨文件 API |
| MC4 | main.swift 生产 facade 调用临时加 `outputURL:` 实参 | error: extra argument 'outputURL' in call, exit 1 |
| MC5 | main.swift 临时调用 `makeRuntimeEvidenceRecorderForTesting(...)` | error: cannot find 'makeRuntimeEvidenceRecorderForTesting' in scope, exit 1 |

### MW 布线 mutation（v9 树，`make test-privacy` 必须 FAIL）

| 编号 | 临时改动 | 命中 |
| --- | --- | --- |
| MW1 | Package.swift 加 `.define("PETDOCK_TESTING")` | W4 FAIL（1 failed, 27 passed） |
| MW2 | test-data recipe 加连写 `-DPETDOCK_TESTING` | W5 FAIL（flag 计数 != 1 且 recipe 非 test-ui） |
| MW3 | test-data recipe 加分离 `-D PETDOCK_TESTING` | W5 FAIL（token 解析捕获分离形态） |
| MW4 | test-data recipe 行尾 dangling `-D` | W5 FAIL（dangling -D 拒绝） |

- 每项 mutation 后完全恢复；恢复树与实现树逐字节一致后 clean gate 复跑 `make test-privacy` 28 passed。全部 RB/MC/MW 在隔离 /tmp 副本执行，结束后移入废纸篓，未污染 worktree。

### v9 逐 AC 证据拓扑

| AC / 边界 | 证据类型 | 触发 / 扰动 | 基线来源 / 结果 | 生产消费者 / 路径 | 最终所有者 / 断言 | 命令 / 结果 | 手工缺口 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| v9-1 具体 collector 文件私有 + 协议 existential | static/absence（编译层）+ wiring | 外部生产文件命名/构造具体类型；具体类型加 convenience init / static subscript / property / method 后重复；生产 facade 传 `outputURL`；release 引用测试 facade | RB-C/RB-D 证明旧树可逃逸（release exit 0 + privacy 29 passed）；MC1–MC3 在 v9 树全部编译 FAIL；MC4/MC5 编译 FAIL | Swift 编译器（file-private 类型边界）+ `makeRuntimeEvidenceRecorder` 唯一生产入口（无地址参数） | 编译失败本身即所有者断言；main/BubbleVisibility/FollowLayoutPass/DockPanel 均只持有 `any RuntimeEvidenceRecording` | MC1–MC5 见上表；pytest 三个编译 probe 每次 `make test-privacy` 自动执行（28 passed） | 无 |
| v9-2 测试 facade 仅存在于 flag 区域 | wiring（单一 token + 区域） | 定义文件外出现 `makeRuntimeEvidenceRecorderForTesting` token；token 移出 `#if PETDOCK_TESTING` 区域 | W1/W2 单一 token 与区域 canary；MC5 编译失败为 release 主证据 | `#if PETDOCK_TESTING` 词法区域（Package.swift 不定义该 flag） | token 只在定义文件且只在 flag 区域内出现 | `make test-privacy` W1/W2 PASS | 无 |
| v9-3 flag 布线 token 感知（含 admission 修复） | wiring（全局 identifier 计数 + shell token 解析，不解析 Make 语法） | Package.swift 加 define；第二 recipe 加连写/分离 flag；recipe 加 dangling `-D`；变量定义+其他 recipe 引用；唯一 token 移入变量由 test-ui 间接引用 | RB-E 证明旧 W5 只计连写（29 passed 逃逸）；MW1–MW4 全部 FAIL；admission 实测证明变量展开绕过（旧 W5 28 passed）后 admission-MW5/MW6 修复 FAIL | 第一层：`PETDOCK_TESTING` 是不可分割稳定 identifier，整个 Makefile 按 identifier 边界全局计数恰 1（变量/注释/间接引用 fail-closed）；第二层：`shlex.split` 解析 swiftc recipe token 流（`-DNAME`/`-D NAME`，拒绝 dangling `-D`），证明唯一出现是 test-ui 的合法 direct flag | `PETDOCK_TESTING` 整个 Makefile 恰一次、为 test-ui swiftc direct `-D` 布线；Package.swift 无该 flag | `make test-privacy` W4/W5 PASS（28 passed）；MW1–MW4 + admission-MW5/MW6 六项 mutation 全 FAIL→恢复后 PASS | 无 |
| v9-4 生产消费者迁移不改行为 | behavior（既有回归） | 四个生产文件 evidence 参数/属性类型改为协议 existential；tests/main.swift 机械替换 factory/filename 引用 | 基线 `<v9-planning-base>` 既有 T-re1–T-re12 全部保持 | capturer → probe → scheduler → FollowLayoutPass → 真实 DockPanel.placeBelow（与基线同构，仅类型收窄为协议 existential） | T-re 断言/fixture/timing 零改动；test-ui 282 passed / 0 failed | `make test-ui` PASS（282/282） | 无 |
| v9-5 门禁 | build/docs/static | 候选完整树 | 基线之上执行 | swiftc/SwiftPM/python gate 消费当前工作树 | 见交付报告（release 0 warning、全套件、privacy、docs、diff-check） | 见交付报告 | 无 |
| image3（原始 full-hide 症状） | plumbing-only（未采样） | — | — | — | — | 无任何 fix 宣称 | **仍 unresolved**：等待 Review 清零 + QA 归档精确候选后，由视觉 QA 执行真实图 1→图 2→图 3 并采集脱敏聚合 |

### v9 边界声明

- 本候选不改变任何正常用户路径行为：障碍分类、alpha 阈值、candidate identity、capture cadence/generation、scheduler、插值语义、telemetry 字段/flush 行为、权限与 UI 均与基线一致。
- 原始 image3 症状仍未解决也不宣称解决：全部 fake 注入仍是 plumbing-only；等待同一候选真机脱敏 runtime-evidence 采样后再判定分支。
- 真机 TCC/ScreenCaptureKit、多屏、拖拽体感、Instruments、make app/候选归档全部未验证、未执行（属 Review 清零后的 QA 阶段）。
- 旧 W0/W3/W6/W7（private-init shape、URL token allowlist、production-factory shape、declaration inventory）已删除，不以新 regex/inventory 形态重钉；本文件 v8 段落中的 W6 引用仅是历史记录。

### v9 pre-Review admission 修复批次（W5 make-variable indirection）

- 背景：主管 pre-Review admission 在隔离 HEAD 副本实测发现 W5 只解析 swiftc recipe 行的字面 token——`TEST_DATA_EXTRA_FLAGS := -D PETDOCK_TESTING` 加 test-data `$(TEST_DATA_EXTRA_FLAGS)` 引用时，`make` 展开后第二个 flag 实际生效，但旧 W5 仍 28 passed（变量展开绕过）。本批次为 formal Review 前修复，不计 Review round；首个 v9 候选 `<v9-first-candidate>` 及其全部先前结论失效，完整 SHA 只保留在未跟踪的父会话派发记录。
- 修复合同（`tests/test_runtime_privacy.py` W5，不引入 Make 语法 parser）：利用 `PETDOCK_TESTING` 是不可分割稳定 identifier，对整个 Makefile 做 identifier 边界全局计数（joined `-DPETDOCK_TESTING` 与 separated `-D PETDOCK_TESTING` 两种固定宽度 lookbehind 分别计数求和），必须恰好 1——变量定义、注释、其他 recipe 任何出现都 fail-closed；随后既有 shlex token guard 继续证明这唯一出现是 test-ui swiftc 的合法 `-DNAME`/`-D NAME` 并拒绝 dangling `-D`。

| 编号 | 临时改动（隔离副本） | `make -n` 展开确认 | privacy 结果 |
| --- | --- | --- | --- |
| admission-MW5 | `TEST_DATA_EXTRA_FLAGS := -D PETDOCK_TESTING` + test-data `$(TEST_DATA_EXTRA_FLAGS)` 引用（主管实测形态） | test-data 展开后含 1 处 flag（实际生效） | W5 FAIL（全局计数=2，1 failed/27 passed） |
| admission-MW6 | 唯一 token 移入 `TEST_UI_EXTRA_FLAGS := -DPETDOCK_TESTING`，test-ui 改 `$(TEST_UI_EXTRA_FLAGS)` 直写删除 | test-ui 展开后含 1 处 flag（实际生效） | W5 FAIL（全局=1 但 direct token 扫描为空，1 failed/27 passed） |
| MW2 复验 | test-data 直写连写 `-DPETDOCK_TESTING` | — | W5 FAIL（保持既有覆盖） |
| MW3 复验 | test-data 直写分离 `-D PETDOCK_TESTING` | — | W5 FAIL（保持既有覆盖） |
| MW4 复验 | test-data 行尾 dangling `-D` | — | W5 FAIL（保持既有覆盖） |

- 全部 mutation 后完全恢复；恢复树与实现树逐字节一致后 clean gate `make test-privacy` 28 passed。mutation 均在隔离 /tmp 副本执行，结束后移入废纸篓，未污染 worktree。

---

## 宠物识别被隐藏气泡窗口劫持修复（impl-selection 轮，2026-08-23）

- 任务：fix-bubble-collapse-smooth-follow（用户症状修复轮：宠物识别被隐藏气泡窗口劫持）。
- 批准产品基线：`7828e4ed1798f9d5d47fb190be660c9bc1f10787`（本 worktree 创建时 HEAD，实现前 Sources 未修改）。
- 根因证据：`research/pet-selection-hijack-2026-08-23.md`（现场只读 CGWindowList 采样 + 生产 `selectPet` 离线回放 + 运行中底座实际 frame 核对：底座 y=隐藏气泡窗口底部+2px 而非 Mascot 底部+2px）。
- 最小修复：`PetTracker.selectPet` R4.1 滞回沿用前增加宠物有效性再校验（`isReasonablePet` 或 title 含 `Mascot` 才可沿用；否则落入既有规则链）。不改其他选择规则、障碍分类、布局与调度。

| 症状 / AC | 证据类型 | 触发 / 扰动 | 基线来源 / 结果 | 生产消费者 / 路径 | 最终所有者 / 断言 | 命令 / 结果 | 手工缺口 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| S-hj 图2/图3：会话 UI 隐藏后底座仍跟随宠物移动但保持旧避让间距（锚定隐藏气泡窗口） | behavior（生产组合） | 候选集含真 Mascot（title 含 Mascot、172x179、layer=2）与隐藏气泡窗口（title 仅应用名、384x95、layer=3、与宠物水平精确居中、垂直覆盖下半部且底部低于宠物 45px、onscreen/alpha=1）；`selectPet(lastWID=气泡wid)` 处于劫持锁定态；另含 768x912 组合面与 24x6 控件两种劫持形态 | 基线 `7828e4ed1798f9d5d47fb190be660c9bc1f10787`（git show 提取基线版 PetTracker.swift 编译进驱动）：T-hj1/2/3/6a/6b 全 FAIL——底座实际 frame y=326=气泡底部(324)+2，精确复现现场症状；T-hj4/5（不变性保护）PASS | CGWindowList 候选快照 → `PetTracker.selectPet(lastWID:)` 滞回分支（生产 `AppDelegate.tick` 同一入口）→ `FollowLayoutPass.placeDock` → `PetTracker.obstaclesNear/obstacleKind` → 真实 `DockPanel.placeBelow` | T-hj6b：实际 `DockPanel.frame`（setFrame 后 owner 状态）回到真 Mascot 正下方基础位（y=281，由 `Geometry.appKitRectFromQuartz` 独立换算，容差<1.0）、obstacles=[0]；修复后 T-hj 全块 7/7 PASS | 独立驱动以与 `make test-ui` 完全相同的源文件清单编译真实源码：基线 2 passed / 5 failed（红）→ 修复树 7 passed / 0 failed（绿） | 真机复现图1→图2→图3 由视觉 QA 在精确候选上执行；本表为自动行为证据 |
| 滞回不变性 | behavior | lastWID=Mascot wid；lastWID=120x120 合理回退窗口（title 无 Mascot） | 基线与修复树均 PASS（T-hj4/5） | 同上（滞回分支） | 选择结果与 `hysteresis:lastWID` hitFlag 保持 | 见上；既有 T4（100x100 滞回）在修复树 15/15 PASS 中保持 | 无 |
| 既有 selectPet 回归 | behavior | T1–T14 既有全部用例（主窗口排除、Mascot 优先、高 layer/尺寸回退、辅助控件排除） | 修复树 15/15 PASS（独立驱动） | `selectPet` 全规则链 | 既有断言全部保持 | 见上 | 无 |
| 硬门禁 | build/docs/static | 候选完整树 | 基线之上执行 | swiftc/SwiftPM/python gate 消费当前工作树 | release 0 warning；docs 0 finding；privacy 28 passed；test-data/test-shell 通过 | `swift build -c release` Build complete!（0 warning）；`make docs-check` 14 files 0 findings；`make test-docs` 10 OK；`make test-privacy` 28 passed；`make test-data` 全部通过；`make test-shell` exit 0 | `make test-ui` 运行时受实现沙箱限制（见下） |

### 实现环境限制（如实记录，供 Review/QA 复核）

- 本 implement 沙箱（seatbelt）无 WindowServer 访问（`NSScreen.screens.count==0`）：`make test-ui` 编译阶段 0 warning 通过（`-warnings-as-errors`），但运行时在**既有** `tests/main.swift:180` `guard let main = NSScreen.screens.first else { fatalError("无屏幕") }` 崩溃，先于本候选全部新增测试；该崩溃与本候选改动无关。
- 替代证据：新增 T-hj 全块（含 `DockPanel.frame` sink）与既有 T1–T14 selectPet 块已用与 `make test-ui` 相同的源文件清单抽成独立 main.swift 驱动，分别在基线（`git show 7828e4e:Sources/PetDock/PetTracker.swift`）与修复树上真实运行并记录（红→绿）。
- 遗留：完整 test-ui 套件运行需在 GUI 会话环境对冻结 SHA 复跑（历史参考：上一冻结候选记录 282 passed，结论不跨 SHA 复用）；本候选产品改动仅 selectPet 滞回分支，已由上述驱动覆盖其全部非 nil lastWID 用例。
- 构建命令差异：外层 seatbelt 禁止 SwiftPM 内层 sandbox-exec 嵌套与 `~/Library` 缓存写入，故 `swift build` 使用 `--disable-sandbox --cache-path/--config-path/--security-path /tmp/...`，swiftc 类目标设置 `CLANG_MODULE_CACHE_PATH=/tmp/petdock-mcache`，`test-privacy` 使用 conda base python（系统 python3 无 pytest）。编译产物与门禁语义不变。

---

## 拖动期间空白症状修复（impl-sticky 轮，2026-08-23）

- 任务：fix-bubble-collapse-smooth-follow（用户症状修复轮：拖动宠物期间 dock 与宠物之间出现空白）。
- 批准产品基线：`ccb35f22b9d6ec995249cc7e8dff0ccac6bc97c5`（本 worktree 创建时 HEAD，实现前 Sources 未修改）。
- 根因证据（主 Agent 现场采样，见派发记录）：拖动时气泡窗口（Activity Stack Backing 200x54/216x64）bounds 逐帧跟随宠物 → `BubbleCandidateIdentity`（含 bounds）逐 tick 变化 → `candidatesChanged` → generation 递增 + `cached`/`successfullyObservedWids` 清空 → `visibility(for:)` 对仍在 knownWids 的 WID 返回默认 `.visible`（保守避让）且在途捕获完成回调全部因 generation/knownCandidates 失配被丢弃 → 整个拖动期间 dock 持续避让隐藏气泡 → 空白；拖动停止后 identity 稳定，下一次捕获（≤0.1s cadence + 捕获耗时）恢复，与用户观察的 ~0.3s 吻合。运行时证据：拖动测试 identityChangeCount 从稳定态个/两位数涨至 418。
- 最小修复（`Sources/PetDock/BubbleVisibility.swift`）：区分纯几何变化（WID 集合与 owner/title/layer/alpha/isOnscreen/sharingState 全部不变，仅 bounds 变）与真身份变化；纯几何 → 保留 cache 与成功观察集合（粘性）、不递增 generation；真身份 → 维持现行 generation 递增 + 清空 + 保守 visible。捕获写入校验保持现行严格语义（generation + knownCandidates 精确相等）：bounds 平移期间启动的旧捕获结果一律丢弃，不写入新几何；粘性只影响 cache 保留（理由：可见性分类基于窗口内容 alpha 统计而非几何，风险仅限于拖动期间状态变化延迟到拖动后 ≤0.2s 收敛，已在代码注释与架构文档写明）。

| 症状 / AC | 证据类型 | 触发 / 扰动 | 基线来源 / 结果 | 生产消费者 / 路径 | 最终所有者 / 断言 | 命令 / 结果 | 手工缺口 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| S-drag 拖动宠物期间 dock 与宠物之间出现空白（dy 跳到避让值 54-67，拖动停止 ~0.3s 后恢复） | behavior（生产组合，T-bv44） | 气泡先捕获为 hidden；拖动序列 8 tick，宠物与同 WID 气泡候选 bounds 每步平移 (7,5)（生产 `FollowLayoutPass.placeDock` 内真实 `probe(candidates:)` 消费），时间步 0.016s；拖动结束后 capturer 改 `.stats(expanded)` 注入真实状态变化 | 基线 `ccb35f22b9d6ec995249cc7e8dff0ccac6bc97c5`（Sources 未修改，仅叠加 test-only tests/main.swift）：T-bv44b FAIL——拖动期间 obstacles=[0,1,1,1,1,1,1,1,…]、实际 `DockPanel.frame` y=376（避让位）而非 321（基础位），空白症状精确复现 | `FollowLayoutPass.placeDock` → `BubbleVisibilityProbe.probe/visibility(for:)` → 可见障碍筛选 → frameSink → **真实 `DockPanel.placeBelow`**（与生产 `AppDelegate.tick` 同构；tick 经 `onVisibilityChange: scheduler.visibilityChangeCallback` + coalescer 驱动） | T-bv44b：拖动期间每 tick 实际 `DockPanel.frame` 保持当步无障碍基础位（obstacles=[0]×9，容差 <1.0）；T-bv44c：拖动结束后 hidden→visible 经 wake→coalescer→完整 tick 写回实际避让 frame（y=376） | headless 驱动（同 test-ui 源清单+flags）基线 313 passed / 5 failed（红）→ 修复树 318 passed / 0 failed（绿）；真实输出已存档 | 真机拖动体感（高刷/60Hz、展开收起叠加拖动）留视觉 QA |
| 拖动期间粘性可见性语义（probe 级，T-bv43） | behavior | 同 WID 候选 bounds 逐 tick 平移+中途 200x54→216x64 尺寸变化（10 tick）；visible/hidden 两组前置；拖动后 `.targetMissing`/`.stats(expanded)` 刷新；拖动中在途捕获经 continuation gate 释放；owner/layer/WID 集合三种真身份变化 | 同上基线：T-bv43b/d/f/g FAIL（visibility=visible、cached=nil、无 wake——根因精确复现）；T-bv43a/c/h1-h3 基线即 PASS（保守/不变性用例） | `BubbleVisibilityProbe.probe` 消费每个候选快照；`BubbleVisibilityClassifier`、lock 内 generation/knownCandidates/knownWids/successfullyObservedWids 状态机 | T-bv43b/c：拖动期间 hidden 保持 hidden、visible 保持 visible（cached 保留）；T-bv43d：纯几何拖动保留成功观察资格→拖动后首次 `.targetMissing` 权威 hidden；T-bv43f：拖动结束后 hidden→visible 刷新并恰好唤醒一次；T-bv43g：拖动中在途旧结果拒绝写入且不启动第二捕获（single-flight 保持）；T-bv43h1-3：owner/layer/WID 变化仍清空回保守 visible 且观察资格同步清空 | 同上（红→绿） | 无 |
| 既有回归不破坏 | behavior | 既有全部 test-ui 用例（T-bv33-42 回归A/保守避让/generation/identity、T-re5d/9/10 bounds 抖动 telemetry 与 in-flight 拒绝、T-bv39f 系列） | 修复树全部保持 PASS（identityChangeCount 语义不变：bounds 抖动仍计数） | 同 test-ui 全套生产/纯函数链 | 318/0 | 同上 | 无 |
| 硬门禁 | build/docs/static | 候选完整树 | 基线之上执行 | swiftc/SwiftPM/python gate 消费当前工作树 | 见交付报告 | `swift build -c release` 0 warning；docs/test-docs/privacy/data/shell 全绿；test-ui 经 headless 驱动（见环境限制） | 完整 `make test`（含真实 test-ui）需 GUI 会话对冻结 SHA 复跑 |

### 实现环境限制（本轮，如实记录）

- 本 implement 沙箱与上一轮相同无 WindowServer（`NSScreen.screens.count==0`）：`make test-ui` 的既有 `tests/main.swift:180` guard 会 fatalError。test-ui 改用 headless 驱动副本运行：复制 `tests/main.swift` 到 /tmp，仅替换该 NSScreen guard 为固定负 origin 合成屏 frame（primary fixture 走既有合成负坐标分支），并把 3 处 `#filePath` 推导的仓库根固定为本 worktree 绝对路径（T-sch4f/T-re8/T-re12b source guard 需要），其余测试与源文件清单、`-warnings-as-errors -DPETDOCK_TESTING` flags 与 `make test-ui` 完全一致。
- 该差异只影响 Geometry 屏幕 fixture 与 source guard 的路径解析；本候选新增测试（T-bv43/T-bv44）与被测生产链不依赖 NSScreen。完整 `make test` 需在 GUI 会话对冻结 SHA 复跑。
- `swift build` 使用 `--disable-sandbox` 与 /tmp 缓存路径（外层 seatbelt 禁止 SwiftPM 内层 sandbox 与 `~/Library` 写入）；python 门禁使用任务指定 `/Users/Gai/workspace/codex-pet-dock/.venv/bin/python`。
