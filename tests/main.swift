import Cocoa

// 无需屏幕录制权限的纯函数测试：验证 selectPet 识别逻辑与 Geometry 坐标转换。
// 用 swiftc 与真实源码一起编译：PetTracker.swift + Geometry.swift + selftest.swift

func mk(_ wid: UInt32, layer: Int, w: CGFloat, h: CGFloat,
        onscreen: Bool = true, pid: Int32 = 11111, owner: String = "ChatGPT", title: String = "") -> WinCandidate {
    WinCandidate(wid: CGWindowID(wid), ownerPID: pid, ownerName: owner, title: title,
                 layer: layer, alpha: 1.0, isOnscreen: onscreen, sharingState: 1,
                 bounds: CGRect(x: 100, y: 100, width: w, height: h))
}
/// 自定义 bounds 的 WinCandidate（避让几何测试用）。
func mkw(_ wid: UInt32, layer: Int, _ bounds: CGRect, owner: String = "ChatGPT",
         title: String = "", alpha: Double = 1.0) -> WinCandidate {
    WinCandidate(wid: CGWindowID(wid), ownerPID: 11111, ownerName: owner, title: title,
                 layer: layer, alpha: alpha, isOnscreen: true, sharingState: 1, bounds: bounds)
}

var pass = 0, fail = 0
func check(_ desc: String, _ cond: Bool, _ extra: String = "") {
    print((cond ? "PASS" : "FAIL") + ": " + desc + (extra.isEmpty ? "" : "  | " + extra))
    if cond { pass += 1 } else { fail += 1 }
}

// ---- selectPet 识别规则 ----
let r1 = PetTracker.selectPet(candidates: [mk(1, layer: 0, w: 800, h: 600), mk(2, layer: 3, w: 120, h: 120)], lastWID: nil)
check("T1 主窗口+高layer宠物→选宠物 wid2", r1.selected?.wid == 2, r1.selected?.detailed() ?? "nil")

let r2 = PetTracker.selectPet(candidates: [mk(1, layer: 0, w: 800, h: 600)], lastWID: nil)
check("T2 仅主窗口→nil(不误绑)", r2.selected == nil, r2.reason)

let r3 = PetTracker.selectPet(candidates: [mk(1, layer: 2, w: 100, h: 100), mk(2, layer: 5, w: 100, h: 100)], lastWID: nil)
check("T3 两高layer→选layer高者 wid2", r3.selected?.wid == 2, r3.selected?.detailed() ?? "nil")

let r4 = PetTracker.selectPet(candidates: [mk(1, layer: 5, w: 100, h: 100), mk(2, layer: 2, w: 100, h: 100)], lastWID: 2)
check("T4 滞回→沿用lastWID=2(即使layer低)", r4.selected?.wid == 2, r4.reason)

let r5 = PetTracker.selectPet(candidates: [mk(1, layer: 0, w: 100, h: 100, onscreen: false)], lastWID: nil)
check("T5 无可见窗口→nil", r5.selected == nil, r5.reason)

let r6 = PetTracker.selectPet(candidates: [mk(1, layer: 0, w: 800, h: 600), mk(2, layer: 0, w: 200, h: 200), mk(3, layer: 0, w: 100, h: 100)], lastWID: nil)
check("T6 petShaped(无高layer)→选面积最小 wid3", r6.selected?.wid == 3, r6.selected?.detailed() ?? "nil")

let r7 = PetTracker.selectPet(candidates: [mk(1, layer: 0, w: 500, h: 500)], lastWID: nil)
check("T7 500x500 layer0→nil(不误绑主窗口)", r7.selected == nil, r7.reason)

let r8 = PetTracker.selectPet(candidates: [mk(1, layer: 0, w: 10, h: 500)], lastWID: nil)
check("T8 细长10x500 layer0→nil(maxSide>=400判为主窗口)", r8.selected == nil, r8.reason)

let r9 = PetTracker.selectPet(candidates: [mk(1, layer: 0, w: 800, h: 600), mk(2, layer: 0, w: 600, h: 500)], lastWID: nil)
check("T9 两个大窗口均判主→nil", r9.selected == nil, r9.reason)

// T10 真实场景复现：主窗口 + Mascot(layer2) + 高layer小窗口(layer3) → 必须选 Mascot
let r10 = PetTracker.selectPet(candidates: [
    mk(1, layer: 0, w: 1728, h: 1050, title: "ChatGPT"),
    mk(2, layer: 2, w: 172, h: 179, title: "Codex Pet Mascot Effect"),
    mk(3, layer: 3, w: 17, h: 6, title: "Codex Pet Voice Controls Backing"),
    mk(4, layer: 3, w: 768, h: 912, title: "Codex Pet Composition Surface")
], lastWID: nil)
check("T10 Mascot优先于高layer子窗口→选wid2", r10.selected?.wid == 2, r10.selected?.detailed() ?? "nil")

// T11 无 Mascot 时回退高 layer（须合理候选：非辅助控件、几何正常）
let r11a = PetTracker.selectPet(candidates: [
    mk(1, layer: 0, w: 800, h: 600),
    mk(2, layer: 3, w: 120, h: 120, title: "Codex Pet Something")   // 合理宠物（非辅助 title）
], lastWID: nil)
check("T11a 无Mascot→回退高layer选合理 wid2", r11a.selected?.wid == 2, r11a.selected?.detailed() ?? "nil")

let r11b = PetTracker.selectPet(candidates: [
    mk(1, layer: 0, w: 800, h: 600),
    mk(2, layer: 3, w: 120, h: 120, title: "Codex Pet Voice Controls Glass")   // 辅助 title
], lastWID: nil)
check("T11b 无Mascot+仅辅助控件→nil", r11b.selected == nil, r11b.reason)

// T12 无 Mascot + 384x95/18x6 layer3 → nil（Mascot 消失不误选辅助 / 极端几何）
let r12 = PetTracker.selectPet(candidates: [
    mk(1, layer: 0, w: 1728, h: 1050, title: "ChatGPT"),
    mk(2, layer: 3, w: 384, h: 95),    // 宽扁辅助（maxSide>300）
    mk(3, layer: 3, w: 18, h: 6)       // 细长辅助（minSide<50）
], lastWID: nil)
check("T12 无Mascot+384x95/18x6 layer3→nil", r12.selected == nil, r12.selected?.detailed() ?? r12.reason)

// T13 有 Mascot + 384x95 layer3 → 仍优先 Mascot
let r13 = PetTracker.selectPet(candidates: [
    mk(1, layer: 0, w: 1728, h: 1050, title: "ChatGPT"),
    mk(2, layer: 2, w: 172, h: 179, title: "Codex Pet Mascot Effect"),
    mk(3, layer: 3, w: 384, h: 95)
], lastWID: nil)
check("T13 有Mascot→优先Mascot wid2(不受辅助干扰)", r13.selected?.wid == 2, r13.selected?.detailed() ?? "nil")

// T14 仅已知辅助控件 → nil
let r14 = PetTracker.selectPet(candidates: [
    mk(1, layer: 0, w: 1728, h: 1050, title: "ChatGPT"),
    mk(2, layer: 3, w: 17, h: 6, title: "Codex Pet Voice Controls Backing"),
    mk(3, layer: 3, w: 768, h: 912, title: "Codex Pet Composition Surface")
], lastWID: nil)
check("T14 仅辅助(Voice Controls/Composition)→nil", r14.selected == nil, r14.selected?.detailed() ?? r14.reason)

print("\n[selectPet] \(pass) passed, \(fail) failed")

// ---- Geometry 坐标转换（多屏/负坐标）----
let gBase = fail, gPass = pass
guard let main = NSScreen.screens.first else { fatalError("无屏幕") }
let mh = main.frame.height
for s in NSScreen.screens {
    let f = s.frame
    let q = CGRect(x: f.origin.x, y: mh - (f.origin.y + f.height), width: f.width, height: f.height)
    let back = Geometry.appKitRectFromQuartz(q)
    let ok = abs(back.origin.x - f.origin.x) < 0.01 && abs(back.origin.y - f.origin.y) < 0.01
        && abs(back.width - f.width) < 0.01 && abs(back.height - f.height) < 0.01
    check("坐标往返一致 screen=\"\(s.localizedName)\" frame=\(f)", ok, "quartz=\(q) back=\(back)")
    let scr = Geometry.screenContaining(quartzCenterX: q.midX, q.midY)
    check("屏中心落回本屏 screen=\"\(s.localizedName)\"", scr?.localizedName == s.localizedName, "")
}
print("\n[Geometry] \(pass - gPass) passed, \(fail - gBase) failed")

// ---- Follower 自适应跟随状态机（纯函数 decide）----
let fBase = fail, fPass = pass
let petA = CGRect(x: 100, y: 100, width: 172, height: 179)
let petB = CGRect(x: 200, y: 100, width: 172, height: 179)  // 移动后位置

let d1 = Follower.decide(pet: nil, lastPet: petA, state: .stable, stableCount: 10)
check("F1 无宠物→hidden/show=false/setFrame=false", d1.state == .hidden && d1.showDock == false && d1.shouldSetFrame == false)

let d2 = Follower.decide(pet: petA, lastPet: nil, state: .hidden, stableCount: 0)
check("F2 首次捕获→moving/setFrame=true/count=0", d2.state == .moving && d2.shouldSetFrame == true && d2.stableCount == 0)

let d3 = Follower.decide(pet: petA, lastPet: petA, state: .moving, stableCount: 0)
check("F3 位置不变(过渡)→moving/setFrame=false/count=1", d3.state == .moving && d3.shouldSetFrame == false && d3.stableCount == 1)

let d4 = Follower.decide(pet: petA, lastPet: petA, state: .moving, stableCount: Follower.stableThreshold)
check("F4 达阈值→stable/setFrame=false", d4.state == .stable && d4.shouldSetFrame == false)

let d5 = Follower.decide(pet: petB, lastPet: petA, state: .stable, stableCount: 100)
check("F5 stable后移动→moving/setFrame=true/count=0", d5.state == .moving && d5.shouldSetFrame == true && d5.stableCount == 0)

let d6 = Follower.decide(pet: petA, lastPet: nil, state: .hidden, stableCount: 0)
check("F6 隐藏后重现→moving/setFrame=true(重捕)", d6.state == .moving && d6.shouldSetFrame == true)

check("F7 频率阶 moving<stable<hidden",
      Follower.movingInterval < Follower.stableInterval && Follower.stableInterval < Follower.hiddenInterval)
check("F8 hidden间隔=hiddenInterval", d1.nextInterval == Follower.hiddenInterval)
check("F9 moving间隔=movingInterval", d2.nextInterval == Follower.movingInterval)
check("F10 stable间隔=stableInterval", d4.nextInterval == Follower.stableInterval)
// 隐藏决策应同步隐藏底座（详情由调用方跟随 showDock 关闭）
check("F11 隐藏时showDock=false(底座+详情隐藏)", d1.showDock == false)

// F12-F14: 亚像素抖动容差（pet 来自 CGWindowList double 精度 bounds，
// Electron 渲染微抖动 0.x px 会使精确 != 永真 → Follower 永不进 stable）。
// 容差：origin 位移 ≤ positionTolerance 视为位置不变（尺寸变化仍判为变化）。
let petJitter = CGRect(x: 100.4, y: 100.3, width: 172, height: 179)   // 位移 0.5px < 阈值
let d12 = Follower.decide(pet: petJitter, lastPet: petA, state: .moving, stableCount: 0)
check("F12 亚像素抖动0.5px→判不变(过渡moving/setFrame=false/count=1)",
      d12.state == .moving && d12.shouldSetFrame == false && d12.stableCount == 1, "state=\(d12.state) setFrame=\(d12.shouldSetFrame) count=\(d12.stableCount)")

let petMove = CGRect(x: 102, y: 100, width: 172, height: 179)   // 位移 2px > 阈值
let d13 = Follower.decide(pet: petMove, lastPet: petA, state: .stable, stableCount: 100)
check("F13 位移2px→判变化(moving/setFrame=true/count=0)",
      d13.state == .moving && d13.shouldSetFrame == true && d13.stableCount == 0, "")

// 边界：位移恰等于阈值 → 视为不变（≤ 而非 <）
let petEdge = CGRect(x: 100 + PetHeuristics.positionTolerance, y: 100, width: 172, height: 179)
let d14 = Follower.decide(pet: petEdge, lastPet: petA, state: .moving, stableCount: 0)
check("F14 位移恰=阈值→判不变(边界≤)",
      d14.state == .moving && d14.shouldSetFrame == false && d14.stableCount == 1, "")

// 尺寸变化（即使 origin 不变）仍判为变化——宠物形变需重定位
let petResize = CGRect(x: 100, y: 100, width: 173, height: 179)   // width +1
let d15 = Follower.decide(pet: petResize, lastPet: petA, state: .stable, stableCount: 100)
check("F15 尺寸变化→判变化(setFrame=true)",
      d15.state == .moving && d15.shouldSetFrame == true, "state=\(d15.state) setFrame=\(d15.shouldSetFrame)")

print("\n[Follower] \(pass - fPass) passed, \(fail - fBase) failed")

// ---- Dock 几何 / reset 显示 / placeBelow 宽度（需 NSApplication 初始化 NSPanel/NSView）----
let _ = NSApplication.shared
let dkBase = fail, dkPass = pass

// T15 placeBelow：pet 宽 384 → 底座宽仍 200（不被撑大）
let dp = DockPanel()
dp.placeBelow(petQuartzRect: CGRect(x: 100, y: 100, width: 384, height: 179))
check("T15 placeBelow pet384→dock宽200(不撑大)", dp.frame.width == 200, "width=\(dp.frame.width)")

// T16 DockView reset 显示：有 resetAt → 显示；nil → 占位不崩
let dv = DockView()
let snapReset = DockSnapshot(weekLeft: "50%", weekTokens: "1.2M", plan: "pro",
    resetAt: "01-02 03:04", cacheRatio: nil, inputTokens: nil, outputTokens: nil,
    sessionCount: nil, updatedAt: nil, localEstimateNote: "n")
dv.render(snapReset)
check("T16 DockView render resetAt→显示", dv.resetTextForTesting == "01-02 03:04", dv.resetTextForTesting)
let snapNil = DockSnapshot(weekLeft: "50%", weekTokens: "1.2M", plan: "pro",
    resetAt: nil, cacheRatio: nil, inputTokens: nil, outputTokens: nil,
    sessionCount: nil, updatedAt: nil, localEstimateNote: "n")
dv.render(snapNil)
check("T16b DockView resetAt nil→占位—", dv.resetTextForTesting == DockSnapshot.placeholder, dv.resetTextForTesting)

// T17 几何回归：DockView frame 200x48 + DockPanel dockHeight/Width（加 reset 不改外框）
check("T17a DockView frame 200x48", dv.frame.width == 200 && dv.frame.height == 48, "\(dv.frame.size)")
check("T17b DockPanel dockWidth=200", DockPanel().dockWidth == 200, "")
check("T17c DockPanel dockHeight=48", DockPanel().dockHeight == 48, "")
print("\n[Dock 几何/reset/placeBelow] \(pass - dkPass) passed, \(fail - dkBase) failed")

// ---- T-avoid: 会话气泡避让（obstaclesNear + safeDockFrame + placeBelow）----
let avBase = fail, avPass = pass
let petRect = CGRect(x: 100, y: 100, width: 172, height: 179)   // Mascot 几何（示例）
let mascotW = mkw(1, layer: 2, petRect, title: "Codex Pet Mascot Effect")
let dockSize = CGSize(width: 200, height: 48)
let gap: CGFloat = 2

// T-a1 无障碍 → pet 下方（pet.maxY+gap），宽 200 中心对齐
let ra1 = Geometry.safeDockFrame(pet: petRect, avoiding: [], dockSize: dockSize, gap: gap, screen: nil)
check("T-a1 无障碍→pet下方 y=petMaxY+gap 宽200",
      ra1.frame?.origin.y == petRect.maxY + gap && ra1.frame?.width == 200, "y=\(ra1.frame?.origin.y ?? -1)")

// T-a2 bubble(345x54) 在 pet 下方与 dock 重叠 → 下移到 bubble.maxY+gap
let bubble = CGRect(x: 80, y: 280, width: 345, height: 54)   // 280..334，与 dock 281..329 重叠
let ra2 = Geometry.safeDockFrame(pet: petRect, avoiding: [bubble], dockSize: dockSize, gap: gap, screen: nil)
check("T-a2 bubble 避让→y=bubbleMaxY+gap=336", ra2.frame?.origin.y == bubble.maxY + gap, "y=\(ra2.frame?.origin.y ?? -1)")
if let f = ra2.frame {
    let noOverlap = !(f.origin.y < bubble.maxY && f.origin.y + dockSize.height > bubble.minY)
    check("T-a2b 避让后与 bubble 不相交", noOverlap, "")
} else { check("T-a2b", false) }

// T-a3 链式：bubble + 512x223 叠叠
let bigObs = CGRect(x: 80, y: 336, width: 512, height: 223)   // dock 下移到 336 后又与 bigObs 重叠
let ra3 = Geometry.safeDockFrame(pet: petRect, avoiding: [bubble, bigObs], dockSize: dockSize, gap: gap, screen: nil)
check("T-a3 链式避让→y=bigMaxY+gap=561", ra3.frame?.origin.y == bigObs.maxY + gap, "y=\(ra3.frame?.origin.y ?? -1)")

// T-a4 384x95 障碍 → 底座宽仍 200（不被撑大）
let wideObs = CGRect(x: 50, y: 280, width: 384, height: 95)
let ra4 = Geometry.safeDockFrame(pet: petRect, avoiding: [wideObs], dockSize: dockSize, gap: gap, screen: nil)
check("T-a4 384x95 避让→dock 宽仍 200", ra4.frame?.width == 200, "w=\(ra4.frame?.width ?? -1)")

// T-a5 obstaclesNear 纯几何排除 main(layer0)/Composition(maxSide>600)/voice(height<32)/mascot（不依赖 title）
let mainW = mkw(2, layer: 0, CGRect(x: 0, y: 0, width: 1728, height: 1084))
let compW = mkw(3, layer: 3, CGRect(x: 0, y: 0, width: 768, height: 912))
let bubbleW = mkw(4, layer: 3, CGRect(x: 80, y: 280, width: 345, height: 54))
let voiceW = mkw(5, layer: 3, CGRect(x: 0, y: 0, width: 17, height: 6))
let obs = PetTracker.obstaclesNear(mascot: mascotW, candidates: [mainW, compW, bubbleW, voiceW, mascotW])
check("T-a5 obstaclesNear 纯几何排除 main/composition/voice/mascot→仅 bubble",
      obs.count == 1 && obs[0].wid == 4, "count=\(obs.count)")

// T-a6 屏底不足 → 隐藏（nil）：真实屏 + 巨大障碍推 dock 越界
if let screen = NSScreen.screens.first {
    let huge = CGRect(x: 80, y: 280, width: 345, height: 100000)
    let ra6 = Geometry.safeDockFrame(pet: petRect, avoiding: [huge], dockSize: dockSize, gap: gap, screen: screen)
    check("T-a6 屏底不足→隐藏(nil)", ra6.frame == nil, ra6.reason)
} else {
    check("T-a6 屏底不足→隐藏（无屏跳过）", true, "无屏")
}

// T-a7 障碍消失 → 恢复 pet 下方
let ra7 = Geometry.safeDockFrame(pet: petRect, avoiding: [], dockSize: dockSize, gap: gap, screen: nil)
check("T-a7 障碍消失→恢复 pet 下方", ra7.frame?.origin.y == petRect.maxY + gap, "")

// T-a8 placeBelow avoiding → 避让 + shown=true + 宽 200
let dpA = DockPanel()
let shownA = dpA.placeBelow(petQuartzRect: petRect, avoiding: [bubble], visibleScreen: nil)
check("T-a8 placeBelow 避让→shown=true", shownA, "")
check("T-a8b placeBelow dock 宽 200", dpA.frame.width == 200, "w=\(dpA.frame.width)")

// T-a9 负坐标副屏：避让逻辑一致（screen=nil 不判 visible）+ screenContaining 不崩
let negPet = CGRect(x: -380, y: 372, width: 172, height: 179)         // maxY=551
let negBubble = CGRect(x: -466, y: 551, width: 345, height: 54)      // 与 dock 553..601 重叠
let ra9 = Geometry.safeDockFrame(pet: negPet, avoiding: [negBubble], dockSize: dockSize, gap: gap, screen: nil)
check("T-a9 负坐标副屏避让→y=negBubbleMaxY+gap=607", ra9.frame?.origin.y == negBubble.maxY + gap, "y=\(ra9.frame?.origin.y ?? -1)")
_ = Geometry.screenContaining(quartzCenterX: negPet.midX, negPet.midY)   // 不崩即可（值依赖硬件）

// T-a10..a13 真实两状态（动态收紧：排除 512 wrapper / 384x95 / 17x6，只识别 bubble）
let petR = CGRect(x: -269, y: 398, width: 172, height: 179)              // maxY=577
let mascotR = mkw(10, layer: 2, petR, title: "Codex Pet Mascot Effect")
let wrapper = mkw(11, layer: 3, CGRect(x: -512, y: 380, width: 512, height: 223))   // 含整个 pet
let obs384 = mkw(12, layer: 3, CGRect(x: -350, y: 444, width: 384, height: 95))
let obs17 = mkw(13, layer: 3, CGRect(x: -200, y: 531, width: 17, height: 6))
let bubbleR = mkw(14, layer: 3, CGRect(x: -466, y: 549, width: 345, height: 54))   // 549..603

// A 无 bubble，wrapper+384+17 → obstacles empty，dock 回 pet.maxY+gap=579
let oA = PetTracker.obstaclesNear(mascot: mascotR, candidates: [wrapper, obs384, obs17])
check("T-a10A 无bubble+wrapper/384/17→obstacles empty", oA.isEmpty, "count=\(oA.count)")
check("T-a10A2 dock回579",
      Geometry.safeDockFrame(pet: petR, avoiding: oA.map { $0.bounds }, dockSize: dockSize, gap: gap, screen: nil).frame?.origin.y == 579, "")

// B + bubble → 只选 bubble，dock 605
let oB = PetTracker.obstaclesNear(mascot: mascotR, candidates: [wrapper, obs384, obs17, bubbleR])
check("T-a11B +bubble→只选bubble", oB.count == 1 && oB[0].wid == 14, "count=\(oB.count)")
check("T-a11B2 dock=605",
      Geometry.safeDockFrame(pet: petR, avoiding: oB.map { $0.bounds }, dockSize: dockSize, gap: gap, screen: nil).frame?.origin.y == 605, "")

// C bubble 消失（下 tick）→ 恢复 579
let oC = PetTracker.obstaclesNear(mascot: mascotR, candidates: [wrapper, obs384, obs17])
check("T-a12C bubble消失→恢复579",
      Geometry.safeDockFrame(pet: petR, avoiding: oC.map { $0.bounds }, dockSize: dockSize, gap: gap, screen: nil).frame?.origin.y == 579, "")

// D 多行 bubble（height 80）仍识别
let bubbleMulti = mkw(15, layer: 3, CGRect(x: -466, y: 549, width: 345, height: 80))
let oD = PetTracker.obstaclesNear(mascot: mascotR, candidates: [wrapper, obs384, obs17, bubbleMulti])
check("T-a13D 多行bubble(height80)→识别", oD.count == 1 && oD[0].wid == 15, "count=\(oD.count)")

print("\n[会话气泡避让] \(pass - avPass) passed, \(fail - avBase) failed")

// ---- T-bv: BubbleVisibility 分类（纯函数滞回）+ 调度（max2Hz/single-flight/reset）+ 异步集成（generation/strict single-flight）----
let bvBase = fail, bvPass = pass
// 实测基线（同窗口 345×64 真实对照）
let collapsedS = BubbleAlphaStats(nonTransparentRatio: 34.0/22080, bboxRatio: 48.0/22080)
let expandedS = BubbleAlphaStats(nonTransparentRatio: 189.0/22080, bboxRatio: 390.0/22080)
let midS = BubbleAlphaStats(nonTransparentRatio: 0.004, bboxRatio: 0.007)
check("T-bv1 collapsed→hidden", BubbleVisibilityClassifier.classify(stats: collapsedS, previous: .visible) == .hidden, "")
check("T-bv2 expanded→visible", BubbleVisibilityClassifier.classify(stats: expandedS, previous: .hidden) == .visible, "")
check("T-bv3 中间滞回→保持visible", BubbleVisibilityClassifier.classify(stats: midS, previous: .visible) == .visible, "")
check("T-bv4 中间滞回→保持hidden", BubbleVisibilityClassifier.classify(stats: midS, previous: .hidden) == .hidden, "")
check("T-bv5 nil stats→保守visible", BubbleVisibilityClassifier.classify(stats: nil, previous: .hidden) == .visible, "")

// 调度（isDue + single-flight + reset）—— 经 lock 访问
let probe = BubbleVisibilityProbe(now: { Date(timeIntervalSince1970: 1000) })
check("T-bv6 初始isDue=true", probe.isDue(Date(timeIntervalSince1970: 1000)), "")
probe.lock.withLock { $0.lastCapture = Date(timeIntervalSince1970: 1000); $0.inFlight = false }
check("T-bv7 <0.5s→false", !probe.isDue(Date(timeIntervalSince1970: 1000.3)), "")
check("T-bv8 >=0.5s→true", probe.isDue(Date(timeIntervalSince1970: 1000.5)), "")
probe.lock.withLock { $0.inFlight = true }
check("T-bv9 single-flight→false", !probe.isDue(Date(timeIntervalSince1970: 1001)), "")
probe.reset()
check("T-bv10 reset不清inFlight(旧Task负责)", probe.lock.withLock { $0.inFlight }, "")
probe.lock.withLock { $0.inFlight = false; $0.cached = [CGWindowID(1): .visible] }
probe.reset()
check("T-bv11 reset→cached空(inFlight不变)", probe.lock.withLock { $0.cached.isEmpty && !$0.inFlight }, "")
probe.lock.withLock { $0.inFlight = false }
check("T-bv12 unknown wid→保守visible", probe.visibility(for: CGWindowID(99)) == .visible, "")

// 异步集成（fake capturer + RunLoop pump）：pending capture 完成 → cached 更新
var fakeTime = Date(timeIntervalSince1970: 2000)
let fakeCollapsed: @Sendable (WinCandidate) async -> BubbleAlphaStats? = { _ in
    BubbleAlphaStats(nonTransparentRatio: 34.0/22080, bboxRatio: 48.0/22080)
}
let asyncProbe = BubbleVisibilityProbe(now: { fakeTime }, capturer: fakeCollapsed)
let c1 = mkw(100, layer: 3, CGRect(x: 0, y: 580, width: 345, height: 64))
asyncProbe.probe(candidates: [c1])
check("T-bv13 probe后inFlight=true", asyncProbe.lock.withLock { $0.inFlight }, "")
let pumpDeadline0 = Date().addingTimeInterval(5)
while asyncProbe.lock.withLock({ $0.inFlight }) && Date() < pumpDeadline0 {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
}
check("T-bv14 pending完成→cached(hidden)+inFlight=false",
      asyncProbe.visibility(for: CGWindowID(100)) == .hidden && !asyncProbe.lock.withLock { $0.inFlight }, "")

// strict single-flight：reset 期间新 probe 不启动（inFlight 由旧 Task 清）
let slowCap: @Sendable (WinCandidate) async -> BubbleAlphaStats? = { _ in
    try? await Task.sleep(nanoseconds: 300_000_000)  // 300ms（async-safe，无 semaphore）
    return BubbleAlphaStats(nonTransparentRatio: 0.001, bboxRatio: 0.001)
}
fakeTime = Date(timeIntervalSince1970: 3000)
let concProbe = BubbleVisibilityProbe(now: { fakeTime }, capturer: slowCap)
concProbe.probe(candidates: [c1])
check("T-bv15 首次probe→inFlight=true", concProbe.lock.withLock { $0.inFlight }, "")
concProbe.probe(candidates: [c1])
check("T-bv16 重复probe被拒(single-flight)", concProbe.lock.withLock { $0.inFlight }, "")
// reset 期间 inFlight 保持 true（旧 Task 在途）
concProbe.reset()
check("T-bv17 reset不清inFlight(旧Task负责)", concProbe.lock.withLock { $0.inFlight }, "")
check("T-bv18 reset后新probe被拒(inFlight仍true)", !concProbe.isDue(fakeTime), "")
// 旧 Task 完成 → 清 inFlight（generation 过期 → 不写 cached）
let pumpDeadline1 = Date().addingTimeInterval(5)
while concProbe.lock.withLock({ $0.inFlight }) && Date() < pumpDeadline1 {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
}
check("T-bv19 旧Task完成→inFlight=false", !concProbe.lock.withLock { $0.inFlight }, "")
check("T-bv20 旧Task回调generation过期→cached仍空", concProbe.lock.withLock { $0.cached.isEmpty }, "")

// 新 probe 启动（旧完成后）→ 新结果生效
fakeTime = Date(timeIntervalSince1970: 3001)
let c2 = mkw(200, layer: 3, CGRect(x: 0, y: 580, width: 345, height: 64))
concProbe.probe(candidates: [c2])
check("T-bv21 旧完成后新probe启动→inFlight=true", concProbe.lock.withLock { $0.inFlight }, "")
let pumpDeadline2 = Date().addingTimeInterval(5)
while concProbe.lock.withLock({ $0.inFlight }) && Date() < pumpDeadline2 {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
}
check("T-bv22 新probe完成→cached更新(hidden)", concProbe.visibility(for: CGWindowID(200)) == .hidden, "")
check("T-bv23 新wid不污染旧wid", concProbe.visibility(for: CGWindowID(100)) == .visible, "")

// strict single-flight：在途 Task 中 probe(empty) → 候选重新出现 probe 仍被拒（inFlight 不清）
fakeTime = Date(timeIntervalSince1970: 4000)
let concProbe2 = BubbleVisibilityProbe(now: { fakeTime }, capturer: slowCap)  // 300ms capturer
concProbe2.probe(candidates: [c1])
check("T-bv24 首次probe→inFlight=true", concProbe2.lock.withLock { $0.inFlight }, "")
// 在途时 probe(empty) → 与 reset 一致：不清 inFlight
concProbe2.probe(candidates: [])
check("T-bv25 probe(empty)不清inFlight(旧Task持有token)", concProbe2.lock.withLock { $0.inFlight }, "")
// 候选重新出现 → 被 inFlight 拒（strict single-flight）
concProbe2.probe(candidates: [c1])
check("T-bv26 候选重现probe被拒(inFlight仍true)", concProbe2.lock.withLock { $0.inFlight }, "")
// 旧 Task 完成 → 清 inFlight（generation 过期 → 不写 cached）
let pumpDeadline3 = Date().addingTimeInterval(5)
while concProbe2.lock.withLock({ $0.inFlight }) && Date() < pumpDeadline3 {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
}
check("T-bv27 旧Task完成→inFlight=false", !concProbe2.lock.withLock { $0.inFlight }, "")
check("T-bv28 旧结果不写cached(generation过期)", concProbe2.lock.withLock { $0.cached.isEmpty }, "")
// 新 probe 可启动 → 结果生效
fakeTime = Date(timeIntervalSince1970: 4001)
concProbe2.probe(candidates: [c2])
check("T-bv29 旧完成后新probe启动→inFlight=true", concProbe2.lock.withLock { $0.inFlight }, "")
let pumpDeadline4 = Date().addingTimeInterval(5)
while concProbe2.lock.withLock({ $0.inFlight }) && Date() < pumpDeadline4 {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
}
check("T-bv30 新probe完成→cached(hidden)", concProbe2.visibility(for: CGWindowID(200)) == .hidden, "")

print("\n[BubbleVisibility] \(pass - bvPass) passed, \(fail - bvBase) failed")

// ---- T-clamp: clampDockX 纯函数 + safeDockFrame 水平 clamp ----
let clBase = fail, clPass = pass
// 纯数值测试（副屏模拟 visMinX=-1728 visMaxX=0 dockWidth=200）
// 正常居中不超界 → 原值
check("T-clamp1 正常居中不clamp",
      Geometry.clampDockX(centeredX: -914, dockWidth: 200, visibleMinX: -1728, visibleMaxX: 0) == -914, "")
// 右超界 centeredX=-165 → clamp 到 maxX-dw = 0-200 = -200
check("T-clamp2 右边缘clamp",
      Geometry.clampDockX(centeredX: -165, dockWidth: 200, visibleMinX: -1728, visibleMaxX: 0) == -200, "")
// 左超界 centeredX=-1800 → clamp 到 minX = -1728
check("T-clamp3 左边缘clamp",
      Geometry.clampDockX(centeredX: -1800, dockWidth: 200, visibleMinX: -1728, visibleMaxX: 0) == -1728, "")
// 屏宽 < dock 宽 → nil
check("T-clamp4 屏窄nil",
      Geometry.clampDockX(centeredX: 0, dockWidth: 200, visibleMinX: -50, visibleMaxX: 50) == nil, "")
// safeDockFrame 无 screen → 不 clamp（x 居中不变）
let noScreenPet = CGRect(x: -151, y: 346, width: 172, height: 179)
let rNoScreen = Geometry.safeDockFrame(pet: noScreenPet, avoiding: [], dockSize: CGSize(width: 200, height: 48), gap: 2, screen: nil)
check("T-clamp5 safeDockFrame无screen不clamp", rNoScreen.frame?.origin.x == -151 + (172-200)/2, "")
// safeDockFrame integration（可选：用本机副屏，但核心覆盖在纯函数 1-4）
if let scr = NSScreen.screens.first(where: { $0.frame.origin.x < 0 }) {
    let vMax = scr.visibleFrame.maxX
    let rInt = Geometry.safeDockFrame(pet: noScreenPet, avoiding: [], dockSize: CGSize(width: 200, height: 48), gap: 2, screen: scr)
    check("T-clamp6 integration右clamp", rInt.frame?.origin.x == vMax - 200, "x=\(rInt.frame?.origin.x ?? -999)")
} else {
    check("T-clamp6 integration（无副屏跳过）", true, "")
}
print("\n[水平clamp] \(pass - clPass) passed, \(fail - clBase) failed")

// ---- T-detail: DetailPanel 水平 clamp + fullScreenAuxiliary ----
let dtBase = fail, dtPass = pass

// D1: DetailPanel.collectionBehavior 与 DockPanel 一致含 .fullScreenAuxiliary
let dtPanel = DetailPanel()
let dtCB = dtPanel.collectionBehaviorForTesting
check("D1 DetailPanel collectionBehavior 含 .fullScreenAuxiliary",
      dtCB.contains(.fullScreenAuxiliary), "cb=\(dtCB.rawValue)")

// D2: dock clamp 到屏幕右边缘 → detail frame maxX <= visibleMaxX（不越出屏幕）
if let screen = NSScreen.screens.first {
    let v = screen.visibleFrame
    let dockAtRightEdge = NSRect(x: v.maxX - 200, y: v.minY + 100, width: 200, height: 48)  // dock 贴右
    dtPanel.placeBelow(dockFrame: dockAtRightEdge, visibleScreen: screen)
    let df = dtPanel.frameForTesting
    check("D2 dock贴右→detail maxX<=visibleMaxX", df.maxX <= v.maxX,
          "detailMaxX=\(df.maxX) visibleMaxX=\(v.maxX)")

    // D3: dock 在屏幕左边缘 → detail 不越出左边（minX >= visibleMinX）
    let dockAtLeftEdge = NSRect(x: v.minX, y: v.minY + 100, width: 200, height: 48)
    dtPanel.placeBelow(dockFrame: dockAtLeftEdge, visibleScreen: screen)
    let df3 = dtPanel.frameForTesting
    check("D3 dock贴左→detail minX>=visibleMinX", df3.minX >= v.minX,
          "detailMinX=\(df3.minX) visibleMinX=\(v.minX)")

    // D4: dock 居中不超界 → detail 与 dock 左对齐（clamp 不改变原对齐；NSPanel 可能像素对齐，容差 1px）
    let dockCenter = NSRect(x: v.midX - 100, y: v.minY + 100, width: 200, height: 48)
    dtPanel.placeBelow(dockFrame: dockCenter, visibleScreen: screen)
    let df4 = dtPanel.frameForTesting
    check("D4 dock居中→detail与dock左对齐(clamp不改变)", abs(df4.origin.x - dockCenter.origin.x) < 1.0,
          "detailX=\(df4.origin.x) dockX=\(dockCenter.origin.x)")
} else {
    check("D2/D3/D4（无屏跳过）", true, "")
}

// D5: 无 screen → 不 clamp（与原 behavior 一致，x 与 dock 对齐）
let noScrDock = NSRect(x: 5000, y: 5000, width: 200, height: 48)  // 远超常规屏
dtPanel.placeBelow(dockFrame: noScrDock, visibleScreen: nil)
let df5 = dtPanel.frameForTesting
check("D5 无screen→不clamp(x与dock对齐)", abs(df5.origin.x - noScrDock.origin.x) < 0.01,
      "detailX=\(df5.origin.x) dockX=\(noScrDock.origin.x)")

print("\n[DetailPanel clamp] \(pass - dtPass) passed, \(fail - dtBase) failed")

// ---- T-log: PetLogger release 门控 + 后台异步 IO ----
let lgBase = fail, lgPass = pass
let logTmp = FileManager.default.temporaryDirectory
    .appendingPathComponent("petdock-log-test-\(ProcessInfo.processInfo.processIdentifier).log")
try? FileManager.default.removeItem(at: logTmp)

// L1: enabled=false → no-op，不创建/写文件
let offLogger = PetLogger(enabled: false, logURL: logTmp)
offLogger.log("should-not-write")
// 等待足够时间确认后台队列也无写入
let l1Deadline = Date().addingTimeInterval(0.5)
while Date() < l1Deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
check("L1 enabled=false→文件不创建(no-op)", !FileManager.default.fileExists(atPath: logTmp.path), "")

// L2: enabled=true → 后台异步写入文件（主线程不阻塞）
let onLogger = PetLogger(enabled: true, logURL: logTmp)
onLogger.log("hello-petdock")
let l2Deadline = Date().addingTimeInterval(2)
while Date() < l2Deadline && !FileManager.default.fileExists(atPath: logTmp.path) {
    RunLoop.current.run(until: Date().addingTimeInterval(0.02))
}
let l2Content = (try? String(contentsOf: logTmp, encoding: .utf8)) ?? ""
check("L2 enabled=true→后台异步写入文件", l2Content.contains("hello-petdock"), "content=\(l2Content)")

// L3: enabled=true → log() 异步派发（调用返回时尚未同步写盘，证明主线程无同步文件 IO）
let asyncTmp = FileManager.default.temporaryDirectory
    .appendingPathComponent("petdock-log-async-\(ProcessInfo.processInfo.processIdentifier).log")
try? FileManager.default.removeItem(at: asyncTmp)
let asyncLogger = PetLogger(enabled: true, logURL: asyncTmp)
asyncLogger.log("async-write")
// 调用立即返回：全新文件首次写入需 create，异步派发下此刻尚未落盘
check("L3 log()异步派发(调用返回时未同步写盘)", !FileManager.default.fileExists(atPath: asyncTmp.path), "")
let l3Deadline = Date().addingTimeInterval(2)
while Date() < l3Deadline && !FileManager.default.fileExists(atPath: asyncTmp.path) {
    RunLoop.current.run(until: Date().addingTimeInterval(0.02))
}
check("L3b 异步派发后最终落盘", FileManager.default.fileExists(atPath: asyncTmp.path), "")
try? FileManager.default.removeItem(at: asyncTmp)

try? FileManager.default.removeItem(at: logTmp)
print("\n[PetLogger] \(pass - lgPass) passed, \(fail - lgBase) failed")

print("\n=== 总计 \(pass) passed, \(fail) failed ===")
exit(fail == 0 ? 0 : 1)
