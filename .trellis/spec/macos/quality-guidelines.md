# Quality Guidelines

> 质量门禁与测试纪律。

---

## 硬门禁

- `swift build -c release` **0 warning**（不是「忽略 warning」，是 0）。
- `make docs-check` 与 `make test-docs` 必须通过；它们离线检查公开 Markdown 的本地链接、目录完整性、旧路径和隐私残留。
- `make test` 全绿 = docs gate + `test-privacy` + test-ui + test-data + test-shell 五个独立入口；测试数字和证据以 [dev 候选验收](../../../docs/verification/dev-candidate.md) 与测试源码为准，文档测试另计。
- `build/PetDock.app` 只作为可覆盖的 staging；开发候选须按 [产物归档规则](../../../docs/verification/dev-candidate.md#开发候选产物归档) 创建全新、提交绑定的 `YYYY-MM-DD-HHmmss-<label>-<shortSHA>` 本地目录，并验证签名与来源。
- 自动验证**不能代替**真机 QA：TCC 屏幕录制 / ScreenCaptureKit 像素捕获 / 多屏负坐标 / Instruments 内存。

## Docs Impact

- 每个实现任务在规划和 Review 中必须填写 `Docs Impact: none | update | new`。
- 行为、接口、数据边界、验证状态或开发门禁变化时，`Docs Impact` 不能填写 `none`；相关 `docs/` 事实和验证说明应与代码在同一提交中更新。
- 规则文档只保留执行约束和链接，不复制产品事实全文；详见 [Documentation Guidelines](./documentation-guidelines.md)。

## TDD 纪律

- 逐项**先写失败测试**（红），再实现（绿）。
- 测试用纯函数 / 依赖注入 / fixture，不依赖屏幕录制权限、不联网、不启动 GUI。
- 不可靠隔离的集成测试（如 rpc 全链路握手、超时/取消分支）**不写**，在交付报告说明，不为覆盖率伪造。
- 每条 AC 的自动证据必须列出 `输入/扰动 → 实际生产消费者 → 可观察结果`；只对应到测试名、通过计数或未被 SUT 读取的 fake 不算覆盖。
- 事件驱动 UI 链路若要求唤醒/合并/frame 写回，集成测试必须经过生产 callback、scheduler/coalescer 和实际 frame owner；手工调用 Geometry/helper 只能作为相邻单元测试。
- 对生产设计明确排除的依赖（例如 cadence 不接受墙钟），使用行为测试加可执行 source/API guard 固化“无该依赖”的契约；不要为了测试注入而向生产增加无业务用途的依赖。

## 改动纪律

- **最小手术**：每一行改动可追溯到任务要求。不「改进」相邻代码、不重构未坏的东西。
- 匹配现有风格（命名、注释密度、中文注释惯例），即使偏好不同。
- 发现无关死代码 → 提及，不擅自删除。

## Git

- 特性分支从 `dev` 创建；不 push `main`、不建 tag/release 除非用户明确确认。
- 公开身份 `bluesmilery <19263500+bluesmilery@users.noreply.github.com>`，commit body **不带 Co-Authored-By**。
- 每个逻辑批次独立提交，conventional commit message。
