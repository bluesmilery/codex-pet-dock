# 底座会话气泡避让（Dock Obstacle Avoidance）

> 目标：Codex 桌面宠物下方的「会话气泡」等浮层存在时，底座**不与气泡重叠**；
> 优先**下移**到最近安全位置；若越出当前 screen 的可见区则**隐藏**底座（不判宠物消失、不 pause 数据）。
> 障碍消失后自动回到宠物正下方。

## 规则（可解释，纯函数驱动）

### 1. 障碍识别 `PetTracker.obstaclesNear(mascot:candidates:)`
在「与 `selectPet` 同一批 `CGWindowList` 快照」中，筛选与选中 Mascot **同 owner** 的「短会话浮层」
（会话气泡）。**动态几何窗，不依赖 title**：
- `ownerName == mascot.ownerName`、`isOnscreen && alpha > 0 && layer >= 3`、非主窗（`!isLikelyMainWindow`）
- 高度 ∈ [`bubbleHeightMin`(32), `bubbleHeightMax`(223)）；`maxSide <= 600`
- `minY >= pet.maxY - bubbleMinYSlack`(32)（在 pet 底部附近，允许小负偏差）
- 水平投影与 pet 重叠（会话气泡位于 pet 正下方）
- **排除**：Mascot 自身、main(layer0)、Composition Surface（`maxSide>600`）、voice controls（`height<32`）、
  以及 **512×223 wrapper**（`height>=223` 且 `minY` 远低于 pet 底部 → 它包含整个 pet，非会话气泡）、
  384×95 / 17×6（`minY` 不在 pet 底部附近）。阈值集中在 `PetHeuristics`。

> **不改变 `selectPet` 的合理回退**：障碍仅用于几何避让，绝不作为跟随目标；
> 384x95 / 18x6 等辅助窗仍被 `selectPet` 的 `isReasonablePet` 排除，不会被重新跟随。

### 2. 避让几何 `Geometry.safeDockFrame(pet:avoiding:dockSize:gap:screen:)`
- `x` 始终按 pet 中心固定 `dockSize.width`（200，**不被 pet/障碍宽度撑大**）。
- `y` 从 `pet.maxY + gap` 起；对与当前 dock 矩形**水平重叠且垂直重叠**的障碍，
  迭代 `y = max(y, obstacle.maxY + gap)`，直到不相交（多障碍链式，收敛于有限次）。
- 限定同一 `screen` 的 `visibleFrame`：最终 dock 越界（任意一边）→ **返回 nil（隐藏）**。
- 避让计算在 Quartz 中完成；边界检查与最终 `setFrame` 各做一次纯算术 AppKit 转换（`appKitRectFromQuartz`，多屏/负坐标统一公式），无重复几何重算。

### 3. 接线 `DockPanel.placeBelow(petQuartzRect:avoiding:visibleScreen:) -> Bool`
- 有障碍或 screen 时调 `safeDockFrame`；frame nil → `hideIfNeeded()` + 返回 `false`（隐藏）；有 → `setFrame` + `true`。
- 默认 `avoiding=[] / visibleScreen=nil` = 原 behavior（pet 正下方），向后兼容。
- `main.tick`：`shown=true` 显示底座 + 对齐详情；`shown=false` 隐藏底座 + 关详情 ——
  但**宠物仍判可见、数据探测不 pause**（pause/resume 仅跟随 `petVisible`，与避让隐藏解耦）。

## 边界与约束
1. **不误主窗口为障碍**：`isLikelyMainWindow` 排除（layer0 + 大尺寸）。
2. **不恢复跟随辅助窗**：`selectPet` 的 `isReasonablePet` 不动；`obstaclesNear` 也排除 `isAuxiliaryTitle`。
3. **底座宽固定 200**：按 pet 中心，不被 pet/障碍宽度撑大（384x95 不再致底座变宽）。
4. **水平 clamp（副屏边缘）**：若 dock 按 pet 中心居中后 x 超出当前 screen 的 `visibleFrame`
   左右边界，clamp 到 `[visMinX, visMaxX - dockWidth]` 使 dock 完全留在屏内（像消息条一样贴边展示）。
   Quartz x 与 AppKit x 同轴，负坐标副屏正确。屏可见宽 < dock 宽 → nil 隐藏。
   y/气泡链式避让不受 clamp 影响。
5. **仅几何避让**：避让隐藏与「宠物隐藏 / 用户隐藏」语义分离；障碍消失自动回 pet 下方。
6. **垂直降级**：避让后底座垂直越出 screen visibleFrame → nil 隐藏（不 clamp 垂直）。
7. **负坐标副屏**：避让逻辑（Quartz）与坐标转换（`appKitRectFromQuartz`）统一适用多屏/负坐标。

## 测试覆盖（`tests/main.swift` T-avoid + T-clamp）
- 无障碍 → pet 下方；bubble 重叠 → 下移且不相交；bubble + 512x223 链式避让。
- 384x95 障碍 → dock 宽仍 200；`obstaclesNear` 排除 main/composition/voice/mascot。
- 屏底不足 → 隐藏(nil)；障碍消失 → 恢复；placeBelow 避让 shown=true；负坐标副屏避让。
- T-clamp：无 screen 不 clamp；右边缘 clamp 到 maxX-dw；左边缘 clamp 到 minX；正常居中不 clamp；
  expanded x clamp + y 避让；固定 200 宽；垂直底部 nil 隐藏。

## Bubble 可见性判定（`BubbleVisibility.swift`，ScreenCaptureKit 像素 alpha）

`obstaclesNear` 纳入的候选可能处于「展开（有内容）」或「收起（空背景）」状态——两者 `onscreen`/`alpha`/
`bounds` 元数据完全相同（公开 CGWindowList 无法区分）。`BubbleVisibilityProbe` 用 **ScreenCaptureKit**
公开 API 捕获候选窗口像素，只在内存计算 `alpha>0.04` 的非透明占比与 bbox 占比（**不 OCR、不保存图、
不记录颜色/文字**），经纯函数滞回分类判定 visible/hidden。**macOS 13 / 捕获失败 / SC 窗口缺失 → 保守
visible**（沿用 metadata 避让，不漏避让）。

### 实测校准阈值（`BubbleVisibilityThresholds`，同窗口 345×64 真实 collapsed vs expanded 对照）
| 指标 | collapsed（收起） | expanded（展开） |
| --- | --- | --- |
| nonTransparentRatio | 34/22080 ≈ **0.154%** | 189/22080 ≈ **0.856%** |
| bboxRatio | 48/22080 ≈ **0.217%** | 390/22080 ≈ **1.766%** |

- **判 visible**（open）：`nonTransparentRatio ≥ 0.6%` 或 `bboxRatio ≥ 1.0%`（在 collapsed 与 expanded 之间）。
- **判 hidden**（close）：`nonTransparentRatio ≤ 0.3%` 且 `bboxRatio ≤ 0.5%`。
- **中间滞回**：保持 previous（防抖动）。
- **unknown**（nil stats）：保守 visible。

### 调度
- macOS 14+ ScreenCaptureKit 异步捕获，**max 2Hz**（0.5s 间隔）、**single-flight**（在途不重发）。
- 主线程缓存结果；tick 非阻塞读缓存，异步结果下 tick 生效（≤1s 收起贴回 / 展开避让）。
- 候选/宠物消失 → `reset()` 递增 generation + 清 cached（不设 inFlight=false，由旧 Task 回调清，保证 strict single-flight）。
- `main.tick`：`obstaclesNear` → `bubbleProbe.probe(candidates)` → 仅 `visible` 候选作为 `placeBelow` 障碍。

### 测试（`tests/main.swift` T-bv，11 项）
纯分类（collapsed→hidden / expanded→visible / 中间滞回 / nil→visible）+ 调度（isDue max2Hz /
single-flight / reset / unknown→visible）。依赖注入 fake clock，不依赖真实 TCC。
