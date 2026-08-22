# Quality Guidelines

> 质量门禁与测试纪律。

---

## 硬门禁

- `swift build -c release` **0 warning**（不是「忽略 warning」，是 0）。
- `make docs-check` 与 `make test-docs` 必须通过；它们离线检查公开 Markdown 的本地链接、目录完整性、旧路径和隐私残留。
- `make test` 全绿 = docs gate + `test-privacy` + test-ui + test-data + test-shell 五个独立入口；测试数字和证据以 [dev 候选验收](../../../docs/verification/dev-candidate.md) 与测试源码为准，文档测试另计。
- `build/PetDock.app` 只作为可覆盖的 staging；开发候选须按 [产物归档规则](../../../docs/verification/dev-candidate.md#开发候选产物归档) 归档到主工作树 `build/candidates/` 下全新、提交绑定的 `YYYY-MM-DD-HHmmss-<label>-<worktree>-<shortSHA>` 目录，并验证签名与来源。
- 自动验证**不能代替**真机 QA：TCC 屏幕录制 / ScreenCaptureKit 像素捕获 / 多屏负坐标 / Instruments 内存。

## Docs Impact

- 每个实现任务在规划和 Review 中必须填写 `Docs Impact: none | update | new`。
- 行为、接口、数据边界、验证状态或开发门禁变化时，`Docs Impact` 不能填写 `none`；相关 `docs/` 事实和验证说明应与代码在同一提交中更新。
- 规则文档只保留执行约束和链接，不复制产品事实全文；详见 [Documentation Guidelines](./documentation-guidelines.md)。

## TDD 纪律

- 行为修复先在批准的未修改基线上运行能穿过真实生产链的症状测试：确实失败时再做最小修复变绿；如果基线已通过，则按覆盖缺口补证据，不为制造红测而绕过生产组合或猜测式改代码。
- 测试用纯函数 / 依赖注入 / fixture，不依赖屏幕录制权限、不联网、不启动 GUI。
- 不可靠隔离的集成测试（如 rpc 全链路握手、超时/取消分支）**不写**，在交付报告说明，不为覆盖率伪造。

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
- **所有者合同**：断言必须落到真实最终所有者，例如实际 `DockPanel.frame`、持久化状态或对外 action；只断言目标 frame、helper 返回值或临时 sink 不代表产品状态已更新。
- **基线合同**：先在批准的未修改基线上运行关键症状测试。基线 fail 才支持行为修复；基线 pass 说明是覆盖缺口，应补证据但不得为制造红测而绕过生产组合或继续猜测式改代码。
- **缺失合同**：要证明“不依赖墙上时间”“不调用禁用 API”等不存在性，使用行为测试加可执行 source/API guard；不得注入一个生产代码从未读取的禁用依赖来宣称通过。
- **边界合同**：TCC、ScreenCaptureKit 像素、多屏负坐标、真实拖拽手感等无法可靠隔离的部分明确留给真机 QA，自动证据不得越界宣称。
- **持久化合同**：表格写入当前 task 的 `research/ac-evidence-topology.md` 并包含在冻结候选提交中；主 Agent 将该路径和完整候选 SHA 一并交给全新 Reviewer。Reviewer 必须从候选树读取，不能依赖聊天里的旧副本。

### 准入判定矩阵

| 情况 | 结论 |
| --- | --- |
| 真实触发经过生产 callback/scheduler，并直接断言最终所有者 | 可作为行为 AC 的主证据 |
| helper / 纯函数测试，另有完整生产组合回归 | 可作为补充证据 |
| 手动调用下游 helper，绕过本应验证的 callback/scheduler | 拒绝送审 |
| fake 已变化，但被测对象没有读取该 fake | 拒绝送审 |
| 只断言计算出的目标值，未断言实际窗口/状态所有者 | 拒绝送审 |
| 基线已通过关键症状测试 | 记录为覆盖补强，不做无证据产品改动 |
| 只能真机验证且已明确列为未验证 | 可进入正式 Review，但 QA 前不得宣称完成 |

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

## 改动纪律

- **最小手术**：每一行改动可追溯到任务要求。不「改进」相邻代码、不重构未坏的东西。
- 匹配现有风格（命名、注释密度、中文注释惯例），即使偏好不同。
- 发现无关死代码 → 提及，不擅自删除。

## Git

- 开发会话使用 `codex/...` 工作分支和独立 worktree；新 worktree 建在主工作树旁边的 `<repo>-worktrees/<slug>/`，禁止 `~/.ao/` 或主工作树内部。一个已完成功能停放到一条 `feature/<slug>` 分支。`codex/` 从当时的 `dev` 或该功能已有 `feature/` 创建。不 push `main`、不建 tag/release 除非用户明确确认。
- 公开身份 `bluesmilery <19263500+bluesmilery@users.noreply.github.com>`，commit body **不带 Co-Authored-By**。
- 每个逻辑批次独立提交，conventional commit message。
- 功能 `accepted` 后把 accepted SHA 落到对应 `feature/` 分支，使该 SHA 成为 feature 祖先；`feature/` 彼此不互相 merge 或 rebase。合入本地 `dev` 只在专门合入会话中从 `feature/` 串行 merge，一次一条；不得 rebase / cherry-pick 改写已 accepted 候选，也不得对 `dev` 使用 `reset --hard` 或 force-push 消除冲突。开发会话不得直接 merge 到 `dev`。
- 冲突解决必须保留双方已验收功能和行为合同，禁止覆盖解决：不得 `checkout --ours/--theirs`、`merge -X ours/-X theirs`、整文件或整段逻辑只取一边，也不得删除另一方的测试、文档或验收证据来让合并变绿。仅格式或空白冲突可按当前 `dev` 风格统一。语义不能同时成立时停止并报告，不得丢弃任一方已验收行为。合入产生的 merge SHA 一律是新候选；旧 SHA 的 Review、测试、QA 和证据结论均不得复用。
