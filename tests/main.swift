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

print("\n=== 总计 \(pass) passed, \(fail) failed ===")
exit(fail == 0 ? 0 : 1)
