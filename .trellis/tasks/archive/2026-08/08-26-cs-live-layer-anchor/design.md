# Technical Design — CS 活层代表选择

## 现状链路

1. PetTracker.obstaclesNear（Sources/PetDock/PetTracker.swift:266）按 candidates 输入顺序取首个标题命中的 CS 实例为唯一代表（:283）。
2. FollowLayoutPass.placeDock（Sources/PetDock/FollowTickPlan.swift:326 起）把代表交给 BubbleVisibilityProbe 像素探测，用 rep.bounds.minY + contentBottom + 1 覆盖 effectivePetMaxY（:374 起）。
3. 死层（过期残影，bounds 固定、列表序靠前但层级更低）被选为代表后，contentBottom 来自旧位置场景 → dock 被下推 90–170px。

## 设计

### 探测输入扩展

- 主导 `probe(candidates:)` 只吃障碍集（签名去重后的 CS + ACT 等）。CS 的 contentBottom 只从这条通道的 cache 读，禁止再送进参考通道。
- Mascot 只走独立参考通道 `updateReferences([mascot])`，不进入 `knownWids`（回归 A 合同保持）。
- 参考通道节奏必须与主导探测相同：`identityDirty ? 0.1s : stableProbeInterval(1.0s)`。禁止固定 `minInterval` 每 tick 扫描。稳态快速路径在 cadence 未到且身份不变时不得启动捕获。
- 现场多 CS（约 6 个大窗）时，稳定态像素捕获应回到：主导通道 1Hz 扫障碍集 + 参考通道 1Hz 只扫 Mascot；不得出现"主导扫 CS 一遍、参考再扫 CS+Mascot"的双倍捕获。

### 活层判定（一致性窗口 + 最小 contentBottom）

设：

- petFootAbs = mascot.bounds.minY + mascotContentBottom + 1（Quartz 坐标；Mascot 窗底部实测有透明 padding，故必须用像素脚底而非窗口底）。
- 对每个 CS 候选 c：csBottomAbs = c.bounds.minY + c.contentBottom + 1。

规则：

1. 一致性窗口：csBottomAbs ∈ [petFootAbs − ε, petFootAbs + 上限] 的 CS 候选进入活层候选集。ε 取小常数（脚底对齐容差）；上限必须覆盖控制按钮高度 + 展开气泡卡向下延伸（现场证据：展开态内容底在脚底下方约 110px；死层残影约 +170px）。具体取值由 red/green fixture 证据固化。
2. 代表 = 活层候选集中 csBottomAbs 最小者（collapsed 活层紧贴脚底；死层内容底显著更低时被排除）。
3. 无任何候选落在窗口内 → 判定"无可判定活层"：锚定回退 Mascot 窗口底（现状回退语义），CS 不作为障碍（与现有"无 contentBottom → 跳过"一致）。
4. 观察不可用（unavailable/降级/首 tick 无 cache）→ 维持现状保守语义，不整窗避让、不改变锚定回退。

### 为什么"窗口 + 最小值"

- 死层内容 = 旧位置整景（气泡+宠物+按钮残影）。旧位置在当前脚底上方时，其内容底 < petFootAbs，被窗口下界排除；旧位置更靠下或气泡残留展开态时，内容底显著大于活层，被"最小值"排除。
- 两组现场（2026-08-24 ghost 层、2026-08-26 死层）中，最小 csBottomAbs 均落在活层。
- 单 CS 实例（绝大多数现场）：唯一候选即代表，行为与现状一致，T-cs 系列天然不回归。

### 契约保持

obstacleKind 分类、输出去重与排序、保守降级、evidence 计数口径、水平居中按 Mascot 窗口、contentBottom+1 语义——全部不变。本设计只改变"多个标题命中 CS 实例时代表是谁"。

### 体验不回归

`DockPanel` 200ms avoidance / 32ms movement 与 `Follower.stableInterval` 不得改。参考通道不得成为第二条 10Hz ScreenCaptureKit 热路径。

## 测试策略

- 复用 Tests/main.swift T-cs 模式：mkw 构造窗口、BubbleAlphaStats 注入 contentBottom、生产组合走真实 probe 节拍 + 真实 DockPanel.placeBelow → frame。
- 新增 fixture：死层 CS（列表序第一、contentBottom 显著偏离）+ 活层 CS + Mascot 参照窗；断言 DockPanel.frame 锚定活层内容底。
- 边界 fixture：活层恰在上/下界、全部候选出窗（回退路径）。
- 既有 T-cs 全量回归。

## 兼容与回滚

- 无持久化格式、无跨进程契约变化；单 commit 最小修复，revert 即回滚。
- macOS 13 / TCC 拒绝路径不走新逻辑（探测不可用分支在前），行为与现状一致。
