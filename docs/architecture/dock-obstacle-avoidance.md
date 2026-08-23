# 底座会话气泡避让架构

> Codex 桌面宠物下方存在会话气泡等浮层时，底座不与气泡重叠；优先下移到最近安全位置，若越出当前屏幕可见区则隐藏底座。障碍消失后自动回到宠物正下方。

避让只改变底座几何展示，不改变宠物识别、跟随目标或数据暂停语义。控制按钮避让属于同一障碍分类链路，产品行为保持现有结论。

## 障碍识别

`PetTracker.obstaclesNear(mascot:candidates:)` 使用与 `selectPet` 同一批 `CGWindowList` 快照，筛选与选中 Mascot 同 owner 的短会话浮层。识别以动态几何为主，另有一条宿主实测标题通道：

- `ownerName == mascot.ownerName`、`isOnscreen && alpha > 0 && layer >= 3`，且不是主窗口；
- 几何气泡通道：高度在 `bubbleHeightMin`（32）到 `bubbleHeightMax`（223）之间，`maxSide <= 600`；
- `minY >= pet.maxY - bubbleMinYSlack`（32），并且水平投影与 pet 重叠；
- 标题气泡通道：标题精确等于 `Codex Pet Composition Surface` 的窗口（宿主实测稳定标识，与 `selectPet` 依赖的 "Mascot" 标题同级）不受高度/边长上限约束——现场取证显示展开气泡卡只渲染在该标题的 768×912 大窗里（7 个同 bounds 重复实例），几何通道会把它排除；纳入条件是同 owner 浮层、水平投影与 pet 重叠且 `bounds.maxY > pet.maxY`（窗口延伸到宠物下方）。
- 除 Mascot 自身、main（layer 0）与几何/标题通道都不匹配的窗口外，voice controls（`height < 32`）及包含整个宠物的 wrapper 仍被排除；高度达到 223 且远低于宠物底部的 512×223 wrapper，以及不在宠物底部附近的 384×95 / 17×6 辅助窗，都不会被当作会话气泡；标题不匹配的同尺寸大窗同样不纳入（精确匹配，不做几何猜测）。
- 输出边界按 `(owner, title, layer, bounds)` 去重（wid 升序保留一个代表）：同一大窗的多个重复实例只产生一个布局障碍和一个 probe 候选，避免对同一大窗重复像素捕获；这也保证布局障碍集与像素探测候选集一致。

辅助窗口不会成为跟随目标：`selectPet` 仍使用 `isReasonablePet` 排除宽扁或过小控件；障碍集合只用于几何避让。

## 避让几何

`Geometry.safeDockFrame(pet:avoiding:dockSize:gap:screen:)` 在 Quartz 全局坐标中计算：

1. `x` 按 pet 中心固定 `dockSize.width`（产品默认 200），不被 pet 或障碍宽度撑大。
2. `y` 从 `pet.maxY + gap` 开始，对水平且垂直相交的障碍迭代 `y = max(y, obstacle.maxY + gap)`，直到不相交。
3. 最终限制在同一 `screen.visibleFrame` 内；任意垂直越界返回 nil，交由面板隐藏。
4. 水平越界使用 `clampDockX` 贴合屏幕左右边缘；可见宽小于 dock 宽时返回 nil。
5. Quartz 与 AppKit 之间只做边界检查和最终 frame 设置所需的转换，统一支持负坐标副屏。

`DockPanel.placeBelow(petQuartzRect:avoiding:visibleScreen:movementChanged:monotonicNow:)` 在 frame 为 nil 时隐藏底座并返回 false；成功则设置 frame 并返回 true。移动状态只对最新目标做最长 32ms 的显式线性插值，不排队历史 frame；首次显示、障碍 / 屏幕变化、无有效 screen、隐藏和其他安全复位路径立即 snap。默认 `avoiding=[] / visibleScreen=nil` 仍是宠物正下方的兼容行为。

主循环的语义是：宠物可见时展示底座并对齐详情，避让失败只隐藏底座；宠物可见性仍由跟随逻辑决定，数据 `pause()` / `resume()` 不与避让隐藏耦合。

## BubbleVisibility 可见性与内容 bbox 避让

窗口的 onscreen、alpha 与 bounds 元数据无法区分展开气泡和收起空背景。`BubbleVisibilityProbe` 在 `CGPreflightScreenCaptureAccess()` 已通过时使用 ScreenCaptureKit 公开 API 捕获候选窗口像素，仅在内存中统计 `alpha > 0.04` 的非透明像素数量与内容底边（窗口内像素 maxY），由纯函数按内容判定：

- 非透明像素数 ≥ 80（内容噪声下限）→ visible，并携带窗口内内容底边 `contentBottom`；
- 非透明像素数 < 80 或完全透明 → hidden，不作为障碍，dock 回宠物下方；
- 成功取得 SCK 窗口清单但找不到此前同 generation 已成功观察过的 WID 时判定为 hidden；首次观察即 targetMissing 仍判 visible。权限、清单、截图、像素统计失败或 macOS 版本不支持时保守判定为 visible 且无内容底边：几何气泡通道（ACT 等小窗）退回整窗 bounds 避让（既有降级语义不变）；标题通道的 Composition Surface 则跳过、不作为障碍（见下文「Composition Surface 无观察数据语义」）。

噪声下限 80 来自 2026-08-24 现场像素级校准：宿主收起后 ACT 容器仅剩 39-57 个非透明像素的不可见小点（6-7px 宽，截屏放大肉眼不可见）；控制按钮出现时实测 189-194px。57 < 80 < 189，双向 ≥40% 余量。该阈值只影响“有无内容”判定；Composition Surface 因宠物像素恒为 visible。因此“是否展开”不再决定避让：可见气泡的障碍矩形高度 = `contentBottom + 1`（像素≈点，dock 紧贴可见内容底 + gap），水平仍使用整窗 bounds（内容水平居中且窗口本身水平定位，保持水平避让语义）。旧的 open/close 比例阈值与滞回假设“收起=无卡”，已被该方案取代。

像素只在内存中统计，不 OCR、不保存图像、不记录颜色、文字或窗口内容。

应用启动时，`ScreenCapturePermissionRequestGate` 保证每个进程最多主动调用一次权限请求。每次 `probe` 都先同步刷新 `knownWids`；preflight 尚未通过时不进入 capturer 或 ScreenCaptureKit，并清除旧 hidden 缓存，使当前候选继续按 visible 保守避让。权限在重启后的进程中生效时，后续 probe 自动恢复捕获，不持久化权限副本。

macOS 14+ 下一次允许启动捕获的受应用控制等待最长 0.1 秒，且始终 strict single-flight；捕获未完成时的新 probe 直接合并，不堆积截图任务。捕获 cadence、绝对 retry deadline 与 follow scheduler 共用 `systemUptime` 单调时钟，墙钟前跳或后跳不会改变探测频率和等待。异步任务只有在 generation 与启动时的候选 identity（bounds、owner、layer 等）仍有效时才能写入缓存；候选集合变化、同 WID 的任一非 bounds 身份字段变化、候选消失或 `reset()` 都会清理该 generation 的成功观察资格，旧任务不能写回缓存或发出通知。完全空闲（无候选、无缓存、无在途）直接早退，不递增 generation。

大面积候选（窗口面积超过 100,000 原始像素，如 Composition Surface 768×912）捕获时按比例降采样：`SCStreamConfiguration` 目标尺寸等比缩到最长边 ≤ 240 并保持纵横比，小窗（ACT 等）不降采样、路径不变。像素探测只需要内容底边，降采样的几像素误差可接受：`contentBottom` 按行高比例换算回原始像素行（`round(maxY × origH/capH)`，随后的避让矩形仍受整窗高度 cap），非透明像素计数按面积比例放大（`count × origArea/capArea`）用于噪声下限比较。

### 拖动期间的粘性可见性

拖动宠物时，气泡窗口的 bounds 会逐帧平移/缩放（如 Activity Stack Backing 200x54↔216x64），但 WID、owner、title、layer、alpha、onscreen 与 sharing state 均不变。这类**纯几何变化**不递增 generation、不清空该 WID 的观察 cache（可见性 + 内容底边）与成功观察资格（粘性）：拖动期间 `visibility(for:)` 沿用拖动前的判定，布局继续使用拖动前的避让状态，底座不会被默认保守 visible 的隐藏气泡窗口推开，从而避免拖动期间宠物与底座之间出现空白。内容底边是窗口内相对坐标，纯平移期间相对位置不变，粘性保留后障碍矩形随窗口平移且高度不变。WID 集合变化或任一身份字段变化（WID 重用/owner/layer 等）仍按上一段清理并回到保守 visible。

写入校验保持严格：捕获完成回调仍要求 generation 与当前 `knownCandidates` 完全一致，拖动中在途的旧捕获结果一律丢弃，不会写入平移后的新几何；拖动结束后 identity 稳定，既有 0.1 秒 cadence 的下一次捕获自然刷新真实状态。代价是拖动过程中用户展开/收起气泡时，粘性判定最迟在拖动结束后的下一次捕获（0.1 秒 cadence 加捕获耗时，通常不超过 0.2 秒）收敛——这是接受的权衡。自动回归见 `make test-ui` 的 T-bv43/T-bv44/T-bv45；真实拖动体感仍需真机 QA 验证。

成功结果写入缓存后，只有当前 `knownWids` 中候选的可见性状态（visible/hidden）实际变化才发出一次 `onVisibilityChange`；结果不变、仅内容底边变化、空候选、reset 与旧 generation 均不通知。内容底边变化（例如展开大卡收成残留横条，可见性保持 visible）由既有 0.1 秒 cadence 的下一次完整 tick 应用，不额外唤醒。运行时由 `FollowTickScheduler` 把后台通知合并为最多一个待执行主线程 tick；若通知在 tick 执行中到达，只保留一次 follow-up。该 tick 的生产 `FollowLayoutPass` 走候选分类、probe/cache 重读、可见障碍筛选（气泡按内容 bbox 高度构造）与 frame sink，再由 sink 执行 `safeDockFrame` 和面板 frame 回写。因此即使宠物 rect 未变化，气泡从 visible 变为 hidden 后，底座也会在该完整 tick 中回到宠物正下方。

moving 状态在 macOS 14+ 且底座可见、实际 `panel.screen` 非空时使用 `NSWindow.displayLink(target:selector:)`，随窗口所在显示器同步；可见窗口暂时没有所属屏幕时使 link 失效并使用 Timer fallback，窗口 screen 变化通过同一 coalesced wake 触发重新选择。macOS 13 使用 `.common` run-loop mode 的 repeating Timer，周期取当前屏幕 `maximumFramesPerSecond` 的倒数并 capped 到 120 Hz，无有效能力值时回退 60 Hz；moving tick 发现能力变化时会重建 Timer。display/timer callback 都只请求 latest-only tick，主线程忙时丢弃过期节拍；不使用已弃用的 `CVDisplayLink`。moving 进入 stable 使用单调 elapsed time 与名义 `4/60s` 静止窗口，并相对固定静止锚点吸收抖动，连续小位移累计越过容差会重置变化时刻。stable 的 0.1 秒 one-shot 由每次完整 tick 的单调起点派生，外部 wake 重置相位；若本次生产布局中的气泡 probe 因 cadence 尚未 due 而跳过，probe 保存绝对 due deadline，scheduler 在 tick 完成时重新计算剩余 delay 并取更早的 one-shot。若本 tick 工作已经跨过 probe deadline，则只立即合并一次 latest-only follow-up；不回放历史节拍。hidden 降为 1 秒 one-shot Timer。

## Composition Surface 无观察数据语义

Composition Surface 是常驻大窗（现场实测 768×912）：像素内容全透明或只在宠物上方时它都不是障碍，只有宠物下方实际渲染的气泡卡内容才是。因此该标题通道候选的障碍性完全取决于观察数据，`obstacleKind` 单独分类为 `.compositionSurface`，布局消费规则为：

- `visibility != visible` → 不作为障碍（内容不可见 / 噪声以下）；
- `visible` 且无 `contentBottom`（macOS 13 恒 unavailable、屏幕录制授权被拒、捕获失败、冷启动首次观察前、代表 wid churn 清 cache 后）→ 跳过，不作为障碍：无观察数据时没有任何依据把整窗 bounds 当障碍——那会把 dock 长距离推离基础位（自动测试实测推到整窗底部）且降级模式下永久如此；
- `visible` 且有 `contentBottom` → 按内容 bbox 避让（高度 = `contentBottom + 1`，受整窗高度 cap），与其他像素通道一致。

由此产生两条已知限制：降级模式（macOS 13 / 无屏幕录制授权 / 捕获失败）下 Composition Surface 气泡不做避让，展开的气泡卡可能与 dock 重叠——这与该通道引入前的行为完全一致；正常模式冷启动首次探测完成前（≤~0.3s），若气泡恰好已展开，同样短暂重叠后由首次探测自动纠正（dock 先停在基础位再下移）。ACT 等几何小窗在降级模式下仍保守整窗避让，既有语义不变。

## 控制按钮与边界

- 障碍几何只影响底座位置；不恢复对辅助窗口的跟随，也不改变宠物隐藏 / 用户隐藏的语义。
- 底座宽度固定 200；副屏负坐标、水平 clamp 和垂直越界分别按上述规则处理。
- 控制按钮出现或消失与消息框上/下位置的组合由 `obstacleKind` 分类；出现时纳入障碍、消失时恢复基础位置，再次出现时重新避让，现有产品结论保持不变。
- z-order 无法由公开 API 完全控制时，以 `.floating` level 加几何不重叠作为降级方案。

## 可重复验证

```sh
make test-ui
```

`test-ui` 不需要屏幕录制权限，使用纯函数与依赖注入覆盖识别、障碍链式下移、固定宽度、水平 clamp、屏幕边界、权限门控、三态捕获结果、可见性变化通知、候选消失复位、elapsed-time stable 语义、调度合并和 32ms bounded interpolation。具体用例以 `tests/main.swift` 为准。真实 TCC、ScreenCaptureKit 像素捕获、macOS 13 Timer、实际 display-link cadence、多屏硬件与 Accessibility 交互仍需单独真机验证，见 [`../verification/dev-candidate.md`](../verification/dev-candidate.md)。
