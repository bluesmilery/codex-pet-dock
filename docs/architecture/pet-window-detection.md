# Codex 宠物窗口识别架构

> 目标：使用公开 API（`CGWindowListCopyWindowInfo` / AppKit）从 `com.openai.codex` 进程及其 helper 窗口中选出桌面宠物，绝不误绑主聊天窗口。规则必须可解释、可记录、可测试。

阈值集中定义在 `Sources/PetDock/PetTracker.swift` 的 `PetHeuristics`，与本文规则一一对应。真实窗口诊断仅用于校准规则；窗口数量、进程标识和位置随机器及运行时变化，不写入公开文档。

## 关键事实

- Codex 桌面应用的 bundle identifier 为 `com.openai.codex`；安装版本可能不同。
- 应用基于 Electron。主进程 `ChatGPT` 之外还有 Framework、Renderer、node_repl 等 helper，窗口的 `kCGWindowOwnerPID` 不一定等于 `NSRunningApplication` 返回的主 PID。
- 诊断和运行期都按 PID 与 ownerName 两个通道枚举以发现真实归属；运行期 `unionCandidates()` 每 tick 基于同一份窗口快照合并 PID 通道与 ownerName 关键词通道（`Chat`、`GPT`、`Codex`、`OpenAI`），ownerName 是 helper / renderer 窗口的运行兜底，不只是诊断扩展。
- `codexPIDs()` 只通过 bundle id 查询并缓存 Codex 主进程 PID；helper PID 不写入该缓存，统一由每 tick 的 ownerName 通道补足。
- `CGWindowList` 的 `kCGWindowBounds` 使用 Quartz 全局坐标（主屏左上原点、y 向下），`NSScreen.frame` 使用 AppKit 全局坐标（主屏左下原点、y 向上）；统一换算见 `Geometry.swift`，支持多显示器和负坐标。

所有枚举均为只读公开 API，不修改 Codex，不使用私有 CGS / SPI。

## 进程与候选过滤

### R1–R3：归属、尺寸与主窗口排除

1. `ownerPID` 必须属于 codex 进程集合，或 ownerName 命中诊断扩展通道。
2. `bounds.width < 1 || height < 1` 的占位窗口丢弃。
3. `layer == 0` 且 `area >= mainMinArea`（150_000）或 `maxSide >= mainMinSide`（400）的窗口判为主聊天窗口并排除。

主窗口阈值是保守几何规则，避免把标准桌面层的大窗当作宠物。

### R4：宠物选择优先级

在非主窗口集合中按以下顺序选择：

1. **滞回**：上次选中的 windowID 仍存在且仍具备宠物特征（`isReasonablePet` 或 title 含 `Mascot`）才继续跟随，避免动画或多候选造成抖动。宿主收起会话 UI 后隐藏的气泡/合成面/控件窗口可能仍存活（在屏、与宠物居中），不满足宠物特征的旧选中不再被沿用，立即回落到后续规则重新选择，防止瞬时误选或窗口世代切换被滞回永久锁定。
2. **Mascot 标识**：title 含 `Mascot` 的合理候选优先于周边合成面或语音控件。
3. **高 layer**：`layer > 0` 且 `isReasonablePet` 的候选按 layer 降序、面积升序选择。
4. **尺寸回退**：其余 `isReasonablePet` 候选按面积升序选择。

`isReasonablePet` 要求 `maxSide <= 300`、`area <= 70_000`、最小边至少 50，并排除 Voice Controls、Composition Surface、Backing、Glass 等辅助控件 title。无合理候选时宁可隐藏，也不误绑宽扁或过小辅助窗。底座宽度固定为 200，不由宠物窗口宽度撑大。

### R5：歧义与无候选

- 没有非主窗口候选但存在可见窗口时不选，避免误跟主窗口。
- 没有可见窗口时返回 nil，面板隐藏。
- 多个等价候选由 layer → area 的排序确定唯一选择；诊断输出候选判定和选中理由供人工核对。

## 可记录性与隐私

`PetTracker.selectPet` 返回 `SelectionResult { selected, reason, hitFlags, allCandidates }`：

- `reason` 是人类可读的选择理由；
- `hitFlags` 记录规则标签，例如 `layer>0`、`petShaped`、hysteresis 命中；
- `allCandidates` 仅包含窗口元数据和规则判定，不保存截图、颜色、文字内容或凭证。

诊断模式与运行日志可记录规则命中，但公开示例不得包含真实窗口 ID、坐标或用户路径。

## 可重复验证

`selectPet(candidates:lastWID:)` 是纯函数，`tests/main.swift` 用构造的 `WinCandidate` 数组编译真实 `PetTracker` 与 `Geometry` 源码验证：主窗口与宠物并存时选宠物、仅主窗口时返回 nil、Mascot 优先于高 layer 辅助窗、合理尺寸回退、滞回（含沿用前宠物特征再校验）与辅助控件排除。测试不需要屏幕录制权限；测试项总数随套件演进，以源码为准。

真实多显示器、TCC 屏幕录制授权、宠物隐藏 / 重现和 Accessibility 交互属于候选验收中的真机项目，见 [`../verification/dev-candidate.md`](../verification/dev-candidate.md)。

## 校准依据

曾观察到 Mascot 本体与 Composition Surface、Voice Controls 等周边窗口同时存在，且周边 layer 可能更高、尺寸跨度更大。仅按 layer 会选中辅助窗，因此当前规则把 title 含 `Mascot` 的合理候选置于高 layer 回退之前，并用最小边与标题黑名单排除辅助控件。该顺序由纯函数回归用例持续锁定。

`Mascot` title 是当前可观测的稳定标识，但 Codex 未来可能改名或移除该 title。届时识别会降级到 layer + `isReasonablePet` 几何回退；需要同步更新规则、fixture 与本说明，不能把 title 命中视为永久协议。
