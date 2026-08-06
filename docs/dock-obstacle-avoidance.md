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
4. **仅几何避让**：避让隐藏与「宠物隐藏 / 用户隐藏」语义分离；障碍消失自动回 pet 下方。
5. **负坐标副屏**：避让逻辑（Quartz）与坐标转换（`appKitRectFromQuartz`）统一适用多屏/负坐标。

## 测试覆盖（`tests/main.swift` T-avoid）
- 无障碍 → pet 下方；bubble 重叠 → 下移且不相交；bubble + 512x223 链式避让。
- 384x95 障碍 → dock 宽仍 200；`obstaclesNear` 排除 main/composition/voice/mascot。
- 屏底不足 → 隐藏(nil)；障碍消失 → 恢复；placeBelow 避让 shown=true；负坐标副屏避让。
