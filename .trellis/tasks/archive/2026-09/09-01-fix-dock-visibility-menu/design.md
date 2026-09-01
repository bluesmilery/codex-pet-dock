# Design: stable pet-source routing across transient menus

## Overview

本轮不重新实现容器捕获。实现基线使用已停放的 `feature/pet-window-adaptation`：它已经能从宿主大型透明容器的内存 alpha bbox 恢复宠物矩形，但尚未合入 `v0.5.0`。本轮只补齐来源优先级，确保通用小窗口回退不能在容器宠物存在时被右键菜单劫持。

## Evidence Gate Before Product Changes

实现者先在干净 feature 基线上重放菜单扰动，并记录脱敏分类：

1. `independent-window`：菜单出现时 `PetTracker.selectPet` 选中通用 `isReasonablePet` 候选，而容器候选及其缓存宠物 rect 仍稳定。进入本设计的最小路由修复。
2. `container-bbox-change`：菜单出现时没有通用小窗口误选，但容器捕获 bbox 本身扩张到菜单。停止实现，返回 Phase 1；该分支需要新的连通域 / 历史锚设计和单独风险审查，当前设计不授权。
3. `unknown`：无法取得真实触发等价性。可以补 plumbing 测试，但不得宣称用户症状已修复，也不得进入正式 QA。

Computer Use 不能操作 Codex 自身，因此真实菜单动作由用户或正式 QA 人员执行；自动证据不得伪装成真机触发证据。

## Source Routing Contract

每个 follow tick 仍只产生一个宠物来源：

1. **Strong primary**：独立 Mascot 身份（title 标识或已验证的 Mascot 滞回）优先，继续走现有 `FollowLayoutPass` 气泡 / 控件 / Composition Surface 链路。
2. **Container**：没有 strong primary 且存在大型透明容器候选时，使用 `ContainerPetProbe` 已接受的宠物 rect。捕获尚在途或暂时无有效 rect 时保持 hidden / 等待 callback，不允许临时菜单接管。
3. **Generic legacy fallback**：只有不存在容器候选时，才允许现有通用 `isReasonablePet` 小窗口回退，保留旧宿主没有 Mascot title 的兼容路径。
4. **None**：以上均无有效来源时隐藏底座，不绑定不确定窗口。

实现不得通过解析 `reason` / `hitFlags` 字符串判断来源。`SelectionResult` 增加最小、类型化的来源可信度（命名由实现者匹配现有风格），或提取一个同等窄范围的纯路由函数；生产 `AppDelegate.tick` 与测试必须消费同一结果。

## Data Flow

```text
CGWindowList snapshot
  -> PetTracker primary classification
  -> ContainerPetSelector candidate
  -> ContainerPetProbe cached/async outcome
  -> single pet-source resolver
  -> Follower.decide
  -> FollowTickPlanner
  -> DockPanel.placeBelow / frame owner
```

菜单出现 / 消失只改变候选快照。只要容器 probe 的真实宠物 rect 不变，resolver 输出保持 container，`stationaryAnchor`、容器 generation、placement origin 与 `DockPanel.frame` 均不因菜单发生迁移或重置。

## Production-Chain Regression

关键回归必须覆盖：

- 无菜单：大型容器候选 + 接受的 pet rect，经 scheduler tick 到真实 `DockPanel.frame`，底座可见并在宠物下方。
- 菜单出现：同一容器与 pet rect 保持，加入一个会被旧 generic fallback 选中的临时候选；生产 resolver 必须继续选择 container，完整 tick 后直接断言同一 `DockPanel.frame` 与可见状态。
- 菜单关闭：移除临时候选；容器身份、probe cache 与最终 frame 不被清空或跳变。
- 主 Mascot 阳性对照：Mascot 存在时仍优先走 primary；无容器时 generic legacy fallback 仍可用。
- 失败保护：容器候选存在但捕获尚未接受时，不得退回菜单候选；允许暂时 hidden，等待既有 observation callback 唤醒。

测试触发必须由 `FollowTickScheduler` 的真实 tick 闭包消费，并落到实际 `DockPanel.frame` / visibility owner。纯函数路由用例只作补充。

## Scope and File Boundaries

预期允许修改：

- `Sources/PetDock/PetTracker.swift`：类型化主通道来源（如需要）。
- `Sources/PetDock/FollowTickPlan.swift`：最小 pet-source resolver / 可测试生产编排（优先放在现有规划层，避免新文件）。
- `Sources/PetDock/main.swift`：把现有 primary/container 顺序改为单一 resolver 输出。
- `tests/main.swift`：红测、生产链、边界和 absence guard。
- `docs/architecture/pet-window-detection.md`：记录来源优先级与菜单排除语义。
- 当前 task 的 `research/ac-evidence-topology.md`：绑定 AC、基线和冻结候选证据。

除非 evidence gate 进入 `container-bbox-change` 并重新获批，否则不修改 `ContainerPetChannel.swift`、捕获 cadence、alpha 阈值、`DockPanel.swift`、`Follower.swift` 或数据/UI 内容。

## Compatibility, Privacy, and Performance

- 旧 Mascot 主通道和无容器的 generic fallback 保留。
- 不增加 CGWindowList / ScreenCaptureKit 调用次数，不改变 1 秒稳定捕获、0.1 秒移动捕获及区域捕获参数。
- 不新增 WID/PID/title/坐标落盘；诊断只记录来源枚举与聚合计数。若现有 telemetry 无法区分真实分支，新增字段也必须落在隐私白名单内并先更新合同。
- 无 schema、配置或用户数据迁移。

## Rollback

产品改动集中在来源路由和测试。若候选 QA 失败，回退本任务提交即可恢复 feature 基线；不得回退或改写既有 accepted feature 历史。若真实触发属于容器 bbox 扩张，停止并重新规划，不用扩大 generic-window 黑名单掩盖根因。
