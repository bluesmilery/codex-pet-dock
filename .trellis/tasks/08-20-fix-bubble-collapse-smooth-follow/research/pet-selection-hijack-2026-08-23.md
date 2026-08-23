# Research: 宠物识别被隐藏气泡窗口劫持（2026-08-23 现场证据）

- Query: 用户报告图1（气泡在宠物下方展开）→图2（收起后底座停在旧避让位不恢复）与图4（拖到屏幕下方再展开后短暂空白、过一会恢复）；判定 dock 侧还是宿主侧根因。
- Method: 只读 CGWindowList 采样 + 生产 PetTracker.selectPet 离线回放 + 运行中底座实际 frame 几何核对。全程未写诊断文件、未保存图像、未记录会话内容；窗口标题仅用于结构识别。
- Date: 2026-08-23

## Findings

1. 宿主窗口结构（采样时，同 owner 进程）：
   - 宠物本体：title 含 "Mascot Effect"，layer=2，172x179。
   - 会话气泡窗口：title 仅为应用名 "Codex"（无 Pet 前缀），layer=3，384x95，与宠物水平精确居中（中心差 0px），垂直覆盖宠物下半部；内容隐藏后窗口仍在窗口列表（onscreen=true、alpha=1）。
   - 状态卡："Codex Pet Activity Stack Backing"，layer=3，200x54。
   - 容器/控件："Codex Pet Voice Controls Glass" 512x223、"Codex Pet Voice Controls Backing" 24x6、"Codex Pet Composition Surface" 768x912（多个）。
2. 现场实锤：运行中底座实际 frame 的 y 恰好等于隐藏气泡窗口底部 + 2px（产品 gap），而不是 Mascot 窗口底部 + 2px；水平中心与两者一致（气泡与宠物精确居中）。即底座当时正把隐藏气泡窗口当作宠物本体跟随。
3. 生产代码回放（真实候选清单喂入当前构建的 PetTracker.selectPet）：
   - lastWID=气泡 wid → 滞回直接返回气泡窗口（reason=滞回：沿用上次选中）。
   - lastWID=nil → title 含 'Mascot' 规则正确返回 Mascot 本体。
   - 滞回对任意 visible 非主窗（含 768x912 组合面、24x6 控件、384x95 气泡）均无任何再校验。
4. WID 世代证据：宿主重建宠物窗口栈后（采样时宠物相关窗口为新一世代 WID 段），旧世代的气泡窗口仍存活并被滞回持续锁定。
5. 症状映射：
   - 图2 持续不恢复 = 底座锚定隐藏气泡窗口；宠物不动、宿主不清理旧窗口 → 永久保持错误位置。
   - 图4 过一会恢复 = 展开消息促使宿主清理/复用旧气泡窗口 → 滞回失效 → title 规则找回真宠物 → 底座回位。
   - 用户"空白那块可能还属于消息气泡"的猜测正确：空白即隐藏气泡窗口的占位；但可控缺陷在 dock 侧的选择逻辑，不是宠物侧。

## Root Cause（第一性原理）

selectPet 的 R4.1 滞回规则只检查"上次 wid 仍在 visible 非主窗集合"，不校验该窗口是否仍具备宠物特征（标题/几何/layer）。任何瞬时错误选中（如 Mascot 短暂不可见期间 fallback 规则选中缩小后的气泡窗口，或宿主窗口世代切换间隙）都会经滞回永久锁定到错误窗口。锁定后底座以错误窗口为锚，避让与回位逻辑全部失效。

## Fix Direction（最小手术）

滞回沿用前增加宠物有效性再校验：被沿用窗口仍满足 isReasonablePet 或 title 含 'Mascot' 才可沿用；否则立即落入正常规则链（title 规则会找回真 Mascot）。真宠物窗口（172x179）满足 isReasonablePet，现有行为不变；384x95/768x912/24x6 等宿主辅助窗口不再可能被滞回锁定。

## Evidence Chain

- 触发/扰动：Mascot 短暂不可见或宿主窗口世代重建 → fallback/滞回锁定气泡窗口。
- 实际生产消费者：PetTracker.selectPet → AppDelegate.tick 的 sel.selected。
- 最终状态所有者：DockPanel.frame（锚定错误窗口底部 + gap）。

## Caveats / Not Found

- 未捕获到锁定发生的精确瞬间（需带 --verbose/--runtime-evidence 的候选 + 用户复现操作）；不影响修复方向——滞回再校验对所有锁定路径均鲁棒。
- 气泡像素捕获 unavailable → 保守 visible 的既有行为保持不变；本修复不触及 BubbleVisibility / obstaclesNear / 调度链。
