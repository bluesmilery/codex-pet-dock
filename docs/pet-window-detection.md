# Codex 宠物窗口识别依据（P0）

> 目标：用公开 API（`CGWindowListCopyWindowInfo` / AppKit）从 `com.openai.codex` 进程名下的窗口里，
> **选出桌面宠物窗口**，且**绝不误绑主聊天窗口**。规则必须可解释、可记录、可测试。
>
> 状态说明：本文档规则**已用真实窗口数据校准**（授权后诊断：`preflight=true`，全局 <N> 窗口、
> codex 主进程 PID <pid> 名下 18 窗口）。阈值与 R4.0「title 含 Mascot 优先」均经实测确认，见文末「实测确认」。
> 阈值常量集中定义在源码 `PetHeuristics`，与本文档一一对应。

## 0. 关键事实（已实测）

- `/Applications/ChatGPT.app` 的 `CFBundleIdentifier` = `com.openai.codex`（版本 26.727.51351）。
- 该应用是 **Electron 应用**：主进程 `ChatGPT` 之外存在大量 Helper / Renderer 子进程
  （`Codex Framework`/`Codex (Renderer)`/`node_repl` 等）。
  ⇒ 窗口的 `kCGWindowOwnerPID` **可能是某个子进程**，不一定等于 `NSRunningApplication` 给出的主 PID。
  诊断因此同时按 **PID** 和 **ownerName** 两种方式枚举，用于发现真实归属。
- 全局坐标系：`CGWindowList` 的 `kCGWindowBounds` 是 **Quartz 全局坐标（主屏左上为原点，y 向下）**，
  跨显示器可为负；`NSScreen.frame` 是 **AppKit 全局坐标（主屏左下为原点，y 向上）**。
  两者换算见 `Geometry.swift`，多显示器 / 负坐标统一公式。

## 1. 进程定位

1. `NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex")` 拿主进程 PID。
2. 窗口归属判定采用**双通道**：
   - 主通道：`ownerPID ∈ 主进程PID集`；
   - 扩展通道（诊断用）：`ownerName` 包含 `ChatGPT` 或 `Codex`，用于发现 Electron helper 归属的窗口。
3. 运行期（跟随模式）默认用主通道；若诊断表明宠物窗口挂在 helper PID，则在 `codexPIDs()` 里纳入 helper 集合（仍只读公开 API，不修改 Codex）。

## 2. 候选识别规则（分层，逐层 narrowing）

### R1. 归属过滤
窗口 `ownerPID` 必须属于 codex 进程集合（或 ownerName 命中）。不满足直接丢弃。

### R2. 有效尺寸过滤
`bounds.width < 1 || height < 1` 的窗口（桌面层 / 隐藏层占位）丢弃。

### R3. 主窗口判定（用于**排除**，防止误绑）
满足任一即判为「主聊天窗口」，从宠物候选中剔除：
- `layer == 0` **且** `area ≥ mainMinArea(150_000 px²)`；或
- `layer == 0` **且** `maxSide ≥ mainMinSide(400 px)`。

依据：主聊天窗口是标准桌面层（layer 0）的大尺寸常规窗口；宠物是小窗口。
阈值是保守初值，真实数据回填后校准。

### R4. 宠物正面特征（命中即候选）
在「非主窗口」集合里，按优先级选择：
1. **滞回（hysteresis）**：上次选中的 `windowID` 仍在「非主窗口」集中 ⇒ 继续跟随它。
   依据：避免在多候选间抖动，且宠物被拖动/动画时 windowID 不变。
2. **高 layer 优先**：`layer > 0`（浮层 / 置顶）的候选里，取 `layer` 最高；并列取 `area` 最小。
   依据：桌面宠物通常以浮层窗口呈现，layer 高于主聊天窗口。
3. **尺寸符合宠物范围**：`maxSide ≤ petMaxSide(300)` **且** `area ≤ petMaxArea(70_000)`，取 `area` 最小。
   依据：宠物是小窗口；主窗口已被 R3 排除，剩下的最小者最可能是宠物。

### R5. 歧义与无候选
- 无非主窗口候选且存在可见窗口 ⇒ **不选**（理由：宁可漏跟也不误绑主窗口）。
- 无可见窗口 ⇒ 隐藏面板。
- 多个等价候选 ⇒ R4 的排序（layer → area）决定唯一选中；诊断输出全部候选以便人工核对。

## 3. 可记录性

`PetTracker.selectPet` 返回 `SelectionResult { selected, reason, hitFlags, allCandidates }`：
- `reason`：人类可读的选中理由；
- `hitFlags`：命中的规则标签（如 `layer>0`、`petShaped`、`hysteresis:lastWID=..`）；
- `allCandidates`：完整候选清单（含每个窗口的 `isLikelyMainWindow` / `isPetShaped` 判定）。

诊断模式（`--diagnose`）与运行模式（`/tmp/petdock.log`）都会持续输出上述信息。

## 4. 可测试性

`selectPet(candidates, lastWID)` 是纯函数：给定窗口列表，输出唯一选择 + 理由。
已用构造的 `WinCandidate` 数组实现纯函数测试 `tests/main.swift`（swiftc 编译真实 `PetTracker`+`Geometry` 源码）：
主窗口+宠物并存→选宠物、仅主窗口→选 nil、两个 layer>0 候选→选 layer 高者、**Mascot 优先于高 layer 辅助窗**等。
**本轮 P0 已跑通 selectPet 11/11 + Geometry 4/4**，退出码 0。

## 5. 实测确认（授权后真实诊断：preflight=true，全局 <N> 窗口，codex 主进程 PID <pid> 名下 18 窗口）

| 项 | 候选假设 | 实测值 |
| --- | --- | --- |
| 宠物窗口 ownerPID | 主进程或 helper | 主进程 **<pid>**（ownerName "ChatGPT"）✓ |
| 真正吉祥物本体 | — | **wid=<wid> title="Codex Pet Mascot Effect" layer=2 172×179 bounds=(-187,998) onscreen** |
Rewrite matched statement with <wid>, <qx>, <ay>, and <screenHeight> placeholders as applicable.
| 主聊天窗口 | ≥400 边 / ≥150k 面积 | wid=<wid> title="ChatGPT" layer=0 1728×1050 area=1814400 → **正确标 [MAIN] 排除** ✓ |
Rewrite matched statement with <wid>, <qx>, <ay>, and <screenHeight> placeholders as applicable.
| 最终采用规则 | R4.哪一条 | 见 5.2 修正（原 R4.2 选错） |

### 5.1 实测暴露的识别缺陷

Rewrite matched statement with <wid>, <qx>, <ay>, and <screenHeight> placeholders as applicable.
而非吉祥物本体 wid=<wid>「Codex Pet Mascot Effect」(172×179, layer=2)。
原因：Mascot 的 layer=2 低于周边合成面/控件的 layer=3，"高 layer 优先"反而把它排除。
后果：面板会跟随 17×6 的语音控件而非吉祥物本体（SC4 跟随位置错误）。

### 5.2 规则修正

新增 **R4.0：title 含 "Mascot" 的非主窗口优先**（吉祥物本体的稳定、可解释可观测标识）。
优先级：滞回 R4.1 → **R4.0 title 含 "Mascot"** → R4.2 高 layer → R4.3 petShaped。
理由：`title="Codex Pet Mascot Effect"` 是宠物吉祥物本体的明确标识；
"Composition Surface" / "Voice Controls" 是其渲染表面 / 语音控件等辅助窗口，应排除，不应作为跟随目标。

**修正验证（selftest，`tests/main.swift`，swiftc 编译真实源码，退出码 0）**：
Rewrite matched statement with <wid>, <qx>, <ay>, and <screenHeight> placeholders as applicable.
- T11：无 Mascot → 回退高 layer 规则。
- T1–T9（不误绑主窗口 / 滞回 / petShaped 等）+ Geometry 4/4 全过，无回归。
