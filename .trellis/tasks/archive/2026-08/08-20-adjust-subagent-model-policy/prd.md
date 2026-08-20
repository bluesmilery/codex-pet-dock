# 调整子 Agent 模型选择规则

## Goal

让项目子 Agent 的模型配置支持任务级显式覆盖，同时保留统一默认值：下达任务时指定的模型或推理强度优先；未指定的配置项分别默认使用 `luna` 和 `max`。

## Background

- 当前 `AGENTS.md` 将所有子 Agent 固定为 `luna + max`，并在 L1/L2 检查和派发预检中硬编码该配置。
- `.trellis/workflow.md` 同样在 L1 一致性检查和 L2 正式 Review 流程中硬编码 `luna + max`。
- 已有任务可以在任务规划中明确指定其他模型配置；持久规则需要承认并优先采用这种任务级指定。
- 本任务仅调整治理和流程文档，不改变应用代码、测试逻辑、可执行脚本、运行时配置或隐私安全行为。

## Delivery Path

L1

## Requirements

1. 子 Agent 的模型配置按以下优先级解析：
   - 任务下达或已批准的任务规划中显式指定的模型、推理强度优先。
   - 未显式指定的模型默认使用 `luna`。
   - 未显式指定的推理强度默认使用 `max`。
2. 派发前必须验证解析后的实际模型和推理强度可用；不可用时停止派发并明确报告，不自动降级或替换。
3. `AGENTS.md` 中 L1 一致性检查、L2 正式 Review、通用模型规则及派发预检使用同一套优先级，不再把 `luna + max` 表述为不可覆盖的固定配置。
4. `.trellis/workflow.md` 中 L1/L2 的模型要求与 `AGENTS.md` 保持一致，避免 Trellis 阶段提示覆盖任务级显式指定。
5. 保留既有的全新 Agent、只读 Review、独立 worktree、SHA 绑定、Review/QA 分离和禁止静默降级等约束。

## Acceptance Criteria

- [x] AC1：在任务未指定模型和推理强度时，规则明确要求使用 `luna + max`。
- [x] AC2：任务显式指定模型或推理强度时，规则明确要求采用指定值，并仅对未指定项应用默认值。
- [x] AC3：派发前预检检查解析后的配置；不可用时停止派发且不自动替换或降级。
- [x] AC4：`AGENTS.md` 和 `.trellis/workflow.md` 中所有当前生效的 L1/L2 模型规则语义一致，不残留“所有子 Agent 固定使用 `luna + max`”的冲突表述。
- [x] AC5：改动仅限本任务 PRD、`AGENTS.md` 和 `.trellis/workflow.md`，不修改历史任务规划中的既有模型指定，也不触及可执行文件。
- [x] AC6：目标静态检查通过，并由一个按新规则解析配置的全新只读一致性 Agent 完成复核；本任务未显式覆盖该检查 Agent 的配置，因此使用默认 `luna + max`。

## Out of Scope

- 修改现有活跃或归档任务中已经批准的模型配置。
- 修改子 Agent 调度器、Trellis 脚本、Hook 或运行时配置。
- 调整子 Agent 的 worktree、Review、QA、状态机或质量门禁规则。
- 修改应用代码、测试或构建发布行为。

## Risks and Deferred Items

- 本次只调整文档规则；调度平台能否提供指定模型仍需在每次实际派发前验证。
- 若未来需要自动解析任务文件并选择模型，应另建 L2 任务评估调度器或脚本改动。
