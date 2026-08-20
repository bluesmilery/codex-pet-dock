# 底座会话气泡避让架构

> Codex 桌面宠物下方存在会话气泡等浮层时，底座不与气泡重叠；优先下移到最近安全位置，若越出当前屏幕可见区则隐藏底座。障碍消失后自动回到宠物正下方。

避让只改变底座几何展示，不改变宠物识别、跟随目标或数据暂停语义。控制按钮避让属于同一障碍分类链路，产品行为保持现有结论。

## 障碍识别

`PetTracker.obstaclesNear(mascot:candidates:)` 使用与 `selectPet` 同一批 `CGWindowList` 快照，筛选与选中 Mascot 同 owner 的短会话浮层。识别依赖动态几何，不依赖 title：

- `ownerName == mascot.ownerName`、`isOnscreen && alpha > 0 && layer >= 3`，且不是主窗口；
- 高度在 `bubbleHeightMin`（32）到 `bubbleHeightMax`（223）之间，`maxSide <= 600`；
- `minY >= pet.maxY - bubbleMinYSlack`（32），并且水平投影与 pet 重叠；
- 排除 Mascot 自身、main（layer 0）、Composition Surface（`maxSide > 600`）、voice controls（`height < 32`）及包含整个宠物的 wrapper；高度达到 223 且远低于宠物底部的 512×223 wrapper，以及不在宠物底部附近的 384×95 / 17×6 辅助窗，都不会被当作会话气泡。

辅助窗口不会成为跟随目标：`selectPet` 仍使用 `isReasonablePet` 排除宽扁或过小控件；障碍集合只用于几何避让。

## 避让几何

`Geometry.safeDockFrame(pet:avoiding:dockSize:gap:screen:)` 在 Quartz 全局坐标中计算：

1. `x` 按 pet 中心固定 `dockSize.width`（产品默认 200），不被 pet 或障碍宽度撑大。
2. `y` 从 `pet.maxY + gap` 开始，对水平且垂直相交的障碍迭代 `y = max(y, obstacle.maxY + gap)`，直到不相交。
3. 最终限制在同一 `screen.visibleFrame` 内；任意垂直越界返回 nil，交由面板隐藏。
4. 水平越界使用 `clampDockX` 贴合屏幕左右边缘；可见宽小于 dock 宽时返回 nil。
5. Quartz 与 AppKit 之间只做边界检查和最终 frame 设置所需的转换，统一支持负坐标副屏。

`DockPanel.placeBelow(petQuartzRect:avoiding:visibleScreen:)` 在 frame 为 nil 时隐藏底座并返回 false；成功则设置 frame 并返回 true。默认 `avoiding=[] / visibleScreen=nil` 仍是宠物正下方的兼容行为。

主循环的语义是：宠物可见时展示底座并对齐详情，避让失败只隐藏底座；宠物可见性仍由跟随逻辑决定，数据 `pause()` / `resume()` 不与避让隐藏耦合。

## BubbleVisibility 可见性

窗口的 onscreen、alpha 与 bounds 元数据无法区分展开气泡和收起空背景。`BubbleVisibilityProbe` 在 `CGPreflightScreenCaptureAccess()` 已通过时使用 ScreenCaptureKit 公开 API 捕获候选窗口像素，仅在内存中计算 `alpha > 0.04` 的非透明占比与 bbox 占比，再由纯函数滞回分类：

- open：`nonTransparentRatio >= 0.6%` 或 `bboxRatio >= 1.0%`；
- close：`nonTransparentRatio <= 0.3%` 且 `bboxRatio <= 0.5%`；
- 中间区间保持上一次状态；捕获失败、macOS 版本不支持或 SC 窗口缺失时保守判定为 visible。

像素只在内存中统计，不 OCR、不保存图像、不记录颜色、文字或窗口内容。

应用启动时，`ScreenCapturePermissionRequestGate` 保证每个进程最多主动调用一次权限请求。每次 `probe` 都先同步刷新 `knownWids`；preflight 尚未通过时不进入 capturer 或 ScreenCaptureKit，并清除旧 hidden 缓存，使当前候选继续按 visible 保守避让。权限在重启后的进程中生效时，后续 probe 自动恢复捕获，不持久化权限副本。

macOS 14+ 下一次允许启动捕获的受应用控制等待最长 0.1 秒，且始终 strict single-flight；捕获未完成时的新 probe 直接合并，不堆积截图任务。捕获 cadence、绝对 retry deadline 与 follow scheduler 共用 `systemUptime` 单调时钟，墙钟前跳或后跳不会改变探测频率和等待。异步任务只有在 generation 仍有效时才能写入缓存；候选消失立即按当前帧失效，`reset()` 或仍有缓存 / 在途任务的空候选会递增 generation，使旧任务不能写回缓存或发出通知。完全空闲（无候选、无缓存、无在途）直接早退，不递增 generation。

成功结果写入缓存后，只有当前 `knownWids` 中候选的可见性实际变化才发出一次 `onVisibilityChange`；结果不变、空候选、reset 与旧 generation 均不通知。运行时由 `FollowTickScheduler` 把后台通知合并为最多一个待执行主线程 tick；若通知在 tick 执行中到达，只保留一次 follow-up。该 tick 的生产 `FollowLayoutPass` 走候选分类、probe/cache 重读、可见障碍筛选与 frame sink，再由 sink 执行 `safeDockFrame` 和面板 frame 回写。因此即使宠物 rect 未变化，气泡从 visible 变为 hidden 后，底座也会在该完整 tick 中回到宠物正下方。

moving 状态在 macOS 14+ 且底座可见、实际 `panel.screen` 非空时使用 `NSWindow.displayLink(target:selector:)`，随窗口所在显示器同步；可见窗口暂时没有所属屏幕时使 link 失效并使用 Timer fallback，窗口 screen 变化通过同一 coalesced wake 触发重新选择。macOS 13 使用 `.common` run-loop mode 的 repeating Timer，周期取当前屏幕 `maximumFramesPerSecond` 的倒数并 capped 到 120 Hz，无有效能力值时回退 60 Hz；moving tick 发现能力变化时会重建 Timer。display/timer callback 都只请求 latest-only tick，主线程忙时丢弃过期节拍；不使用已弃用的 `CVDisplayLink`。moving 进入 stable 使用单调 elapsed time 与名义 `4/60s` 静止窗口，并相对固定静止锚点吸收抖动，连续小位移累计越过容差会重置变化时刻。stable 的 0.1 秒 one-shot 由每次完整 tick 的单调起点派生，外部 wake 重置相位；若本次生产布局中的气泡 probe 因 cadence 尚未 due 而跳过，probe 保存绝对 due deadline，scheduler 在 tick 完成时重新计算剩余 delay 并取更早的 one-shot。若本 tick 工作已经跨过 probe deadline，则只立即合并一次 latest-only follow-up；不回放历史节拍。hidden 降为 1 秒 one-shot Timer。

## 控制按钮与边界

- 障碍几何只影响底座位置；不恢复对辅助窗口的跟随，也不改变宠物隐藏 / 用户隐藏的语义。
- 底座宽度固定 200；副屏负坐标、水平 clamp 和垂直越界分别按上述规则处理。
- 控制按钮出现或消失与消息框上/下位置的组合由 `obstacleKind` 分类；出现时纳入障碍、消失时恢复基础位置，再次出现时重新避让，现有产品结论保持不变。
- z-order 无法由公开 API 完全控制时，以 `.floating` level 加几何不重叠作为降级方案。

## 可重复验证

```sh
make test-ui
```

`test-ui` 不需要屏幕录制权限，使用纯函数与依赖注入覆盖识别、障碍链式下移、固定宽度、水平 clamp、屏幕边界、权限门控、可见性变化通知、候选消失复位、elapsed-time stable 语义和调度合并。当前公开口径为 **BubbleVisibility 84 项**（`test-ui` 套件的一部分）；细分用例以 `tests/main.swift` 为准。真实 TCC、ScreenCaptureKit 像素捕获、macOS 13 Timer、实际 display-link cadence、多屏硬件与 Accessibility 交互仍需单独真机验证，见 [`../verification/dev-candidate.md`](../verification/dev-candidate.md)。
