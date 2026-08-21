# Quality Guidelines

> 质量门禁与测试纪律。

---

## 硬门禁

- `swift build -c release` **0 warning**（不是「忽略 warning」，是 0）。
- 独立 `swiftc` 编译的测试入口同样必须 0 warning，并在命令层启用 warnings-as-errors；`make test` 通过但编译输出含 warning 不得送审。
- `make docs-check` 与 `make test-docs` 必须通过；它们离线检查公开 Markdown 的本地链接、目录完整性、旧路径和隐私残留。
- `make test` 全绿 = docs gate + `test-privacy` + test-ui + test-data + test-shell 五个独立入口；测试数字和证据以 [dev 候选验收](../../../docs/verification/dev-candidate.md) 与测试源码为准，文档测试另计。
- `build/PetDock.app` 只作为可覆盖的 staging；开发候选须按 [产物归档规则](../../../docs/verification/dev-candidate.md#开发候选产物归档) 创建全新、提交绑定的 `YYYY-MM-DD-HHmmss-<label>-<shortSHA>` 本地目录，并验证签名与来源。
- 自动验证**不能代替**真机 QA：TCC 屏幕录制 / ScreenCaptureKit 像素捕获 / 多屏负坐标 / Instruments 内存。

## Docs Impact

- 每个实现任务在规划和 Review 中必须填写 `Docs Impact: none | update | new`。
- 行为、接口、数据边界、验证状态或开发门禁变化时，`Docs Impact` 不能填写 `none`；相关 `docs/` 事实和验证说明应与代码在同一提交中更新。
- 规则文档只保留执行约束和链接，不复制产品事实全文；详见 [Documentation Guidelines](./documentation-guidelines.md)。

## TDD 纪律

- 行为修复先在批准的未修改基线上运行能穿过真实生产链的症状测试：确实失败时再做最小修复变绿；如果基线已通过，则按覆盖缺口补证据，不为制造红测而绕过生产组合或猜测式改代码。
- 测试用纯函数 / 依赖注入 / fixture，不依赖屏幕录制权限、不联网、不启动 GUI。
- 不可靠隔离的集成测试（如 rpc 全链路握手、超时/取消分支）**不写**，在交付报告说明，不为覆盖率伪造。
- 每条 AC 的自动证据必须列出 `输入/扰动 → 实际生产消费者 → 可观察结果`；只对应到测试名、通过计数或未被 SUT 读取的 fake 不算覆盖。
- fake outcome 即使被完整生产组合消费，也只有在同一症状的真实 runtime 证据确认其 kind / outcome 语义等价时，才能作为症状 AC 的主证据；否则只能标为 plumbing-only。
- 事件驱动 UI 链路若要求唤醒/合并/frame 写回，集成测试必须经过生产 callback、scheduler/coalescer 和实际 frame owner；手工调用 Geometry/helper 只能作为相邻单元测试。
- 对生产设计明确排除的依赖（例如 cadence 不接受墙钟），使用行为测试加可执行 source/API guard 固化“无该依赖”的契约；不要为了测试注入而向生产增加无业务用途的依赖。
- async 测试 fixture 必须用 continuation、actor 或其他 async-safe gate 挂起任务；禁止在 async closure 中用 semaphore wait、sleep 窗口或阻塞 cooperative executor 来制造确定性。

## 验收证据拓扑合同

### 适用范围与触发条件

- 所有 L2 候选都必须为每条验收标准建立证据拓扑；用户直接反馈的症状、跨 callback/scheduler 的事件链、最终写入窗口或持久状态的路径属于关键链路。
- 纯函数、helper 和 fixture 适合证明局部算法，但不能单独证明“用户触发后真实对象最终发生变化”。关键症状至少需要一条穿过生产组合并断言最终状态所有者的回归测试。

### 必交付格式

实现者在冻结候选前提交 AC Evidence Topology Table，每行包含：

| 字段 | 必须回答的问题 |
| --- | --- |
| 症状 / AC | 正在证明哪条用户现象或验收标准？ |
| 证据类型 | behavior、build、docs、static/absence 还是真机 QA？ |
| 触发 / 扰动 | 测试实际注入了什么事件、clock、失败或状态变化？ |
| 基线来源 / 结果 | 批准产品基线的完整 SHA 是什么？基线 checkout 干净，还是只叠加了可辨识的 test-only patch/commit；改了哪些路径；结果是 fail 还是 pass？ |
| 生产消费者 / 路径 | 哪个真实生产对象读取了该扰动，经过哪些 callback/scheduler？ |
| 最终所有者 / 断言 | 最终由谁持有用户可观察状态，测试直接断言什么？ |
| 命令 / 结果 | 执行了什么，实际结果是什么？ |
| 手工缺口 | 哪部分只能由真机或人工 QA 验证？ |

### 强制合同

- **消费合同**：fake、clock、event、failure 和 callback 必须注入被测生产对象并被实际读取。只修改测试局部变量、但生产对象继续读取默认依赖，视为无效证据。
- **组合合同**：测试不得手动调用本应由上游 callback 或 scheduler 触发的下游 helper 来冒充整条链路。
- **触发等价合同**：测试注入的 kind、outcome、failure provenance 或状态分布必须有同一真实症状的脱敏 runtime 证据支持。生产组合完整但 trigger 语义未经确认时，只能证明 plumbing 能力，不得宣称症状 AC 已通过。
- **所有者合同**：断言必须落到真实最终所有者，例如实际 `DockPanel.frame`、持久化状态或对外 action；只断言目标 frame、helper 返回值或临时 sink 不代表产品状态已更新。
- **所有者回读合同**：telemetry 若声称记录最终 owner，必须在副作用完成后从 owner 回读状态；不得把传给 `setFrame` / write / action 的请求值、target 或 helper 结果重命名为 actual。测试须能区分 requested value 与 owner read-back。
- **基线合同**：先在批准的未修改基线上运行关键症状测试。基线 fail 才支持行为修复；基线 pass 说明是覆盖缺口，应补证据但不得为制造红测而绕过生产组合或继续猜测式改代码。
- **缺失合同**：要证明“不依赖墙上时间”“不调用禁用 API”等不存在性，使用行为测试加可执行 source/API guard；不得注入一个生产代码从未读取的禁用依赖来宣称通过。
- **Guard 范围合同**：source/API guard 的枚举范围必须覆盖其声称保护的完整 production tree（有子目录时递归），并精确断言关键 wiring/sink，而不只计数同名符号。每个关键 guard 至少记录一次临时 mutation FAIL → 撤销后 PASS；没有可失败性证据只能算人工静态检查。
- **边界合同**：TCC、ScreenCaptureKit 像素、多屏负坐标、真实拖拽手感等无法可靠隔离的部分明确留给真机 QA，自动证据不得越界宣称。
- **真机 outcome 合同**：外部窗口、TCC 或 ScreenCaptureKit 决定行为的症状，真机 QA 除 UI 结果外还必须绑定同一候选的脱敏生产 outcome 证据；只有 UI 截图或只注入 fake outcome 均不足以证明修复触发了真实分支。
- **持久化合同**：表格写入当前 task 的 `research/ac-evidence-topology.md` 并包含在冻结候选提交中；主 Agent 将该路径和完整候选 SHA 一并交给全新 Reviewer。Reviewer 必须从候选树读取，不能依赖聊天里的旧副本。

### 准入判定矩阵

| 情况 | 结论 |
| --- | --- |
| 真实触发经过生产 callback/scheduler，并直接断言最终所有者 | 可作为行为 AC 的主证据 |
| helper / 纯函数测试，另有完整生产组合回归 | 可作为补充证据 |
| 手动调用下游 helper，绕过本应验证的 callback/scheduler | 拒绝送审 |
| fake 已变化，但被测对象没有读取该 fake | 拒绝送审 |
| 生产组合完整，但 fake kind/outcome 未被真实 runtime 证据确认等价 | plumbing-only；不得作为症状 AC 主证据 |
| 只断言计算出的目标值，未断言实际窗口/状态所有者 | 拒绝送审 |
| telemetry 在副作用后仍消费请求值，未从最终 owner 回读 | 拒绝送审 |
| source guard 未覆盖完整递归范围、关键 sink 或没有 mutation 失败证据 | 不得作为 absence/privacy 主证据 |
| 基线已通过关键症状测试 | 记录为覆盖补强，不做无证据产品改动 |
| 只能真机验证且已明确列为未验证 | 可进入正式 Review，但 QA 前不得宣称完成 |
| 真机 UI 通过，但外部观察驱动的生产 outcome 未记录 | QA 不准入；补同一候选的脱敏 outcome 证据 |

### 最小测试组合

- 局部算法变化：纯函数或状态机单测，覆盖边界与错误分支。
- 用户原始症状：至少一条生产组合回归，路径为 `真实入口 → callback/scheduler/coalescer → 完整 tick/action → 最终状态所有者`。
- 其余每条 AC：逐条给出与类型匹配的直接证据；build/docs 使用真实命令，static/absence 使用可执行 guard，不能因不属于 UI 行为就省略。
- 时间或不存在性约束：可注入单调时间的行为测试，加 source/API guard。
- 系统能力边界：自动回归保守语义，真机 QA 验证权限、像素、多屏和手感。

### 本项目正反例

- **错误**：测试改变一个本地 wall-clock fake，但 scheduler/probe 从未接收它，然后据此宣称墙上时间跳变不影响 cadence。
- **正确**：cadence 只接收可注入单调时钟，测试在同一单调时间序列下改变外部墙上时间仍得到相同调度结果，并用 source/API guard 禁止 cadence owner 引用墙上时间 API。
- **错误**：测试收到 `targetMissing` 后手动调用几何 helper，并断言 helper 算出的 frame；这跳过了 visibility callback、coalescer、完整 tick 和真实 panel 写入。
- **正确**：向真实生产组合发送 `targetMissing`，让 callback 请求一次 coalesced tick，执行完整布局，再直接断言实际 `DockPanel.frame` 回到底座基础位置。

## Scenario: 外部观察驱动 UI 的 Trigger Equivalence

### 1. Scope / Trigger

- 触发：产品行为由 CGWindowList、ScreenCaptureKit、TCC、Accessibility 或其他外部观察结果驱动，而自动测试需要注入 kind / outcome / failure。
- 目标：同时证明“生产管道会消费该 outcome”和“真实用户动作确实产生同一种 outcome”；两者缺一不可。

### 2. Signatures

诊断实现使用聚合、脱敏的逻辑结构；字段名可按实现语言调整，但语义不得扩张：

```swift
struct RuntimeEvidenceSample {
    let bubbleObstacleCount: Int
    let controlObstacleCount: Int
    let captureOutcomeCounts: [CaptureOutcome: Int]
    let visibilityCounts: [BubbleVisibility: Int]
    let identityChangeCount: Int
    let wakeCallbackCount: Int
    let dockDyBucket: DockDyBucket
}

enum DockDyBucket { case base, upTo32, upTo64, above64 }
```

### 3. Contracts

- 诊断默认关闭，仅在显式 QA/诊断模式下启用，并绑定完整候选 SHA 与真实操作步骤。
- 当前仓库 runtime evidence 的完整候选 SHA 合同是恰好 40 个小写十六进制字符；文档、parser 与边界测试必须同一提交保持一致，缩写或任意长度区间不得用于 exact-candidate provenance。
- 只聚合 count、enum 与相对基础 frame 的 bucket；禁止记录窗口标识、进程标识、标题、owner、绝对坐标、颜色、文字或图像。
- 每个症状 AC 必须注明 `runtime trigger source → observed kind/outcome → injected regression trigger` 的对应关系；未取得对应关系时回归测试标为 plumbing-only。
- `unavailable` 等保守失败语义不得因 UI 期望而重解释为 authoritative absence。

### 4. Validation & Error Matrix

| 条件 | 判定 |
| --- | --- |
| runtime kind/outcome 与测试注入一致，生产组合与最终 owner 断言完整 | 可作为症状 AC 主证据 |
| runtime 未采样或样本来自其他 SHA | trigger provenance 缺失，拒绝 QA 准入 |
| UI 已复位，但 outcome/visibility 计数缺失 | 仅症状观察，不能证明根因分支 |
| outcome 为 unavailable，但测试注入 targetMissing | 触发不等价，禁止据此改 hidden 策略 |
| telemetry 含任何禁止字段 | 隐私门禁失败，候选不得交付 |
| 文档要求 full SHA，但 parser/test 接受缩写或其他长度 | provenance 合同不一致，拒绝 QA 准入 |

### 5. Good / Base / Bad Cases

- Good：真实 full-hide 采样显示 `stats → hidden`，回归注入同类 stats 并穿过 callback/scheduler 到实际 `DockPanel.frame`。
- Base：fake `targetMissing` 穿过完整生产组合并回位，但 runtime outcome 未知；只记录 plumbing coverage。
- Bad：看到 UI 未复位后直接下调 alpha 阈值，或把 `unavailable` 改成 hidden，却没有真实 kind/outcome 分布。

### 6. Tests Required

- 自动：每个确认的 runtime 分支使用生产消费者、callback/scheduler 和最终 owner 断言；另保留相邻 classifier/helper 边界测试。
- 可失败性：改变测试 trigger 为与 runtime 不同的 outcome 时，症状主证据必须失败或被明确降级为 plumbing-only。
- 真机：同一 SHA 执行用户原始操作，记录 UI 结果与白名单 telemetry 聚合；二者均符合验收矩阵才可 accepted。
- 隐私：`make test-privacy` 或等价 guard 拒绝禁止字段与非私有落盘路径。

### 7. Wrong vs Correct

#### Wrong

```swift
fakeCapturer.result = .targetMissing
// 管道和 frame 都通过，因此宣称真实 full-hide 已修复。
```

#### Correct

```swift
// 先用同一候选的脱敏 runtime evidence 确认真实 full-hide outcome。
precondition(runtimeEvidence.dominantOutcome == .stats)
fakeCapturer.result = .stats(runtimeEquivalentStats)
// 再穿过生产 callback/scheduler 并断言实际 frame owner。
```

## 改动纪律

- **最小手术**：每一行改动可追溯到任务要求。不「改进」相邻代码、不重构未坏的东西。
- 匹配现有风格（命名、注释密度、中文注释惯例），即使偏好不同。
- 发现无关死代码 → 提及，不擅自删除。

## Git

- 特性分支从 `dev` 创建；不 push `main`、不建 tag/release 除非用户明确确认。
- 公开身份 `bluesmilery <19263500+bluesmilery@users.noreply.github.com>`，commit body **不带 Co-Authored-By**。
- 每个逻辑批次独立提交，conventional commit message。
