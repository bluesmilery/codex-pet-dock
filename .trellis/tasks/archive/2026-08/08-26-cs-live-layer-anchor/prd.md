# Fix dock anchor regression from stale composition surface layers

## Goal

底座锚定不再消费过期 Composition Surface（CS）层的像素内容：当宿主同时存在活层与死层 CS 窗口时，PetDock 必须选出与当前宠物渲染一致的活层作为代表，使 dock 基础位紧贴真实可见内容底（宠物/控制按钮区域），恢复"宠物与底座之间无异常空白"的预期行为。

## Background（confirmed facts）

- 2026-08-26 症状（用户截图）：宠物与底座之间出现大片异常空白；宠物上方与消息气泡之间的空白会自行消失（用户已认定是宠物应用自身行为，不在本任务范围）。
- 本机只读诊断（diag 脚本实测；含屏幕内容的 PNG 已按隐私规则清理）：宿主同时挂 7 个标题为 Codex Pet Composition Surface 的窗口——4 个死层（bounds 长时间不变，内容为宠物旧位置的过期残影，在 CGWindowList 中排在前面）+ 3 个活层（bounds 跟随宠物移动，层级更高）。
- 现行代表选择：PetTracker.obstaclesNear 取 CGWindowList 顺序首个标题命中（Sources/PetDock/PetTracker.swift:283 附近；"最前=活层"假设由 commit 17d049c 引入）。该假设已失效：死层排在活层前面，代表被选成死层。
- 锚定链：FollowLayoutPass.placeDock（Sources/PetDock/FollowTickPlan.swift:374 附近）用代表 CS 的 contentBottom 观察计算 effectivePetMaxY；死层 contentBottom 比真实可见内容底低约 90–170px，dock 被推到幽灵内容下方。
- 次要事实：即使选中活层，CS 在控制按钮以下仍有约 30–60px 淡阴影/白色不透明像素；alpha-only 隐私合同禁止用颜色区分内容与渲染残影，只能用几何/一致性规则。
- 已排除：commit 623442f 的 onScreenWindowsOnly:true 不丢窗口（实测全部 CG onscreen 窗口均在 SCK onscreen 清单中，targetMissing 路径未触发）。

## Requirements

- R1（方案 A，用户已选定）：CS 代表选择改为"活层判定"——主导障碍探测覆盖全部标题命中的 CS 候选（签名去重后）；Mascot 仅走独立参考通道提供实测脚底；用该脚底从主导探测已有的 CS contentBottom 中排除死层/残影。CS 不得在参考通道被二次捕获。
- R2：修复后 dock 基础位锚定活层真实可见内容底（含控制按钮区），宠物与底座恢复正常间距；展开气泡卡时仍避让到气泡内容底（不回归 T-cs 既有语义）。
- R3：保持既有保守降级语义——探测不可用（macOS 13 / TCC 拒绝 / 捕获失败 / 首次观察前）时不整窗避让、锚定回退 Mascot 窗口底；"无任何可判定活层"的回退行为必须显式定义并有测试。
- R4：隐私边界不变——像素统计仅内存 alpha 统计，不新增颜色/文字/图像记录；Mascot 窗纳入探测不得引入新的落盘内容。
- R5（用户 2026-08-27 体验回归）：不得破坏已合入的稳定态 1Hz 气泡心跳与 200ms 静止避让丝滑。参考通道必须与主导探测共用稳定节奏（identityDirty 时 0.1s，稳定后 1.0s），不得固定 0.1s 全量扫描 CS。

## Acceptance Criteria

- AC1（症状回归，红→绿）：在批准基线 ba8b87f 的未修改树上，新增"死层排在活层前 + Mascot 参照窗"的生产组合 fixture，穿过 FollowLayoutPass.placeDock → DockPanel.placeBelow 断言实际 DockPanel.frame：基线失败（锚到死层 contentBottom），最小修复后通过（锚到活层一致内容底）。基线与修复后输出记入 ac-evidence-topology。
- AC2（不回归）：既有 T-cs 系列（多同 bounds 实例去重 1 代表、展开态避让、收起态内容底锚定、保守降级跳过）在新代表选择下保持全绿。
- AC3（一致性边界）：对边界 fixture（活层 contentBottom 恰在参照窗口上/下界附近、死层显著偏离）代表选择稳定；无候选满足一致性时按 R3 显式回退并有测试。
- AC4（门禁）：swift build -c release 0 warning；make test 全绿；ac-evidence-topology 表覆盖全部 AC 并随冻结候选提交。
- AC5（真机 QA，边界合同）：真实宿主环境重建症状（多 CS 层并存），dock 不再被死层下推；真机 outcome 证据（脱敏 telemetry 或等价观察）与 UI 结果绑定同一冻结候选 SHA。自动证据不能替代本条。
- AC6（体验不回归）：稳定身份的多 CS fixture 上，参考通道只捕获 Mascot；CS 只出现在主导探测 capturer 列表；稳定后参考捕获间隔为 1.0s 量级而非 0.1s。DockPanel/Follower 平滑与节拍源码相对 ba8b87f 保持不变。生产链断言仍落到 DockPanel.frame。

## Out of Scope

- 宿主（Codex 桌面端）死层残留 bug 本身的修复或上报文案（用户可另行向宠物应用反馈）。
- 宠物上方气泡间距的自动消失行为（宠物应用自身问题）。
- CS 按钮下方淡阴影像素的颜色级识别（隐私合同禁止；几何压制仅限代表选择逻辑内）。
- dock 锚定平滑/滞回（contentBottom 逐帧微跳的已知权衡维持现状）。
- 不为了降 CPU 改回"CG 顺序首个 CS 即代表"（会再引入死层空白）。

## Delivery Path

Delivery Path: L2（应用代码 + ScreenCaptureKit 行为）。

- 实现基线：dev ba8b87f（用户确认基于当前 dev 创建）。
- worktree：codex-pet-dock-worktrees/cs-live-layer-anchor，分支 codex/cs-live-layer-anchor（已创建，初始状态干净）。
- 子 Agent 模型：任务未显式指定 → 默认 luna + max（派发前预检实际 worker context；不可用即停止并报告，不静默降级）。
- Docs Impact: update——若 docs/ 描述 CS 代表选择或锚定语义，需在同一提交内最小同步（实现者负责检索）。

## Open Questions

（无——方案 A 已由用户选定；worktree 基线已确认。）
