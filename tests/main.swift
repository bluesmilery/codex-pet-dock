import Cocoa
import os

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

func waitPumpingMain(_ predicate: () -> Bool, timeout: TimeInterval = 5) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !predicate() && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.005))
    }
    return predicate()
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

// ---- T-enum: unionCandidates 单次枚举 + codexPIDs 缓存 ----
let enBase = fail, enPass = pass

// 构造 mock infos：主进程 PID=11111 的窗口 + helper PID=22222 但 ownerName 含 Codex 的窗口
func infoDict(_ wid: UInt32, _ pid: Int32, _ owner: String, _ title: String,
              _ layer: Int, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> [String: Any] {
    return [
        (kCGWindowNumber as String): NSNumber(value: wid),
        (kCGWindowOwnerPID as String): NSNumber(value: pid),
        (kCGWindowOwnerName as String): owner,
        (kCGWindowName as String): title,
        (kCGWindowLayer as String): NSNumber(value: layer),
        (kCGWindowAlpha as String): NSNumber(value: 1.0),
        (kCGWindowIsOnscreen as String): true,
        (kCGWindowBounds as String): ["X": x, "Y": y, "Width": w, "Height": h] as [String: Any],
    ]
}
let mockInfos: [[String: Any]] = [
    infoDict(10, 11111, "ChatGPT", "ChatGPT", 0, 0, 0, 1728, 1050),
    infoDict(20, 11111, "ChatGPT", "Codex Pet Mascot Effect", 2, 100, 100, 172, 179),
    infoDict(30, 22222, "Codex (Renderer)", "Codex Pet Mascot Effect", 2, 100, 100, 172, 179),  // helper PID
]

// T-enum1: unionCandidates 单次 infosProvider 调用（PID 通道 + ownerName 通道共享一次枚举）
var infosCallCount = 0
let savedInfosProvider = PetTracker.infosProvider
PetTracker.infosProvider = { infosCallCount += 1; return mockInfos }
let union1 = PetTracker.unionCandidates()
check("T-enum1 unionCandidates 单次枚举(infosProvider 调用 1 次)", infosCallCount == 1, "count=\(infosCallCount)")
// 主进程 PID 通道 + ownerName 通道(helper PID 22222 owner 含 Codex)按 wid 去重合并
check("T-enum1b union 合并 PID+ownerName 通道(wid 10/20/30)", Set(union1.map { $0.wid }) == [10, 20, 30], "wids=\(union1.map { $0.wid })")

// T-enum2: enumerate(pids:) 与 enumerateByOwnerName 各自经 infosProvider（仍单次/各自）
infosCallCount = 0
_ = PetTracker.enumerate(pids: [11111])
_ = PetTracker.enumerateByOwnerName(["Codex"])
// wrapper 各调一次 infosProvider（诊断模式路径，运行模式用 unionCandidates 共享）
check("T-enum2 wrapper 各调 infosProvider(共 2 次)", infosCallCount == 2, "count=\(infosCallCount)")
PetTracker.infosProvider = savedInfosProvider

// T-enum3: codexPIDs 1s TTL 缓存（连续调用命中缓存，不重复查 NSRunningApplication）
var appsCallCount = 0
let savedAppsProvider = PetTracker.runningAppsProvider
let savedNowProvider = PetTracker.nowProvider
var fakeNow = Date(timeIntervalSince1970: 5000)
PetTracker.runningAppsProvider = { appsCallCount += 1; return [11111, 22222] }
PetTracker.nowProvider = { fakeNow }
PetTracker.resetPIDCacheForTesting()
let pids1 = PetTracker.codexPIDs()
let pids2 = PetTracker.codexPIDs()
let pids3 = PetTracker.codexPIDs()
check("T-enum3 codexPIDs 缓存命中(1s TTL 内 provider 仅调 1 次)", appsCallCount == 1, "count=\(appsCallCount)")
check("T-enum3b 缓存返回一致", pids1 == [11111, 22222] && pids2 == pids1 && pids3 == pids1, "")

// T-enum4: 缓存过期 → 重新查询
fakeNow = fakeNow.addingTimeInterval(PetTracker.pidCacheTTL + 0.1)   // 超过 TTL
let pids4 = PetTracker.codexPIDs()
check("T-enum4 TTL 过期→重新查询(provider 调 2 次)", appsCallCount == 2, "count=\(appsCallCount)")
check("T-enum4b 过期后返回正确", pids4 == [11111, 22222], "")

PetTracker.runningAppsProvider = savedAppsProvider
PetTracker.nowProvider = savedNowProvider
PetTracker.resetPIDCacheForTesting()

print("\n[unionCandidates/PID缓存] \(pass - enPass) passed, \(fail - enBase) failed")

// ---- Geometry 坐标转换（多屏/负坐标）----
// 固定两个 fixture：真实主屏 + 合成负坐标副屏。
// 这样保留真实主屏几何，同时不要求物理多屏，也不让测试项数随 NSScreen.screens 变化。
let gBase = fail, gPass = pass
guard let main = NSScreen.screens.first else { fatalError("无屏幕") }
let mh = main.frame.height
let syntheticSecondary = CGRect(x: main.frame.minX - main.frame.width, y: main.frame.minY,
                                width: main.frame.width, height: main.frame.height)
var screenFixtures: [(label: String, frame: CGRect, expected: NSScreen?)] = [
    ("primary", main.frame, main)
]
screenFixtures.append(("synthetic-negative", syntheticSecondary, nil))
for fixture in screenFixtures {
    let f = fixture.frame
    let q = CGRect(x: f.origin.x, y: mh - (f.origin.y + f.height), width: f.width, height: f.height)
    let back = Geometry.appKitRectFromQuartz(q)
    let ok = abs(back.origin.x - f.origin.x) < 0.01 && abs(back.origin.y - f.origin.y) < 0.01
        && abs(back.width - f.width) < 0.01 && abs(back.height - f.height) < 0.01
    check("坐标往返一致 fixture=\(fixture.label) frame=\(f)", ok, "quartz=\(q) back=\(back)")
    if let expected = fixture.expected {
        let scr = Geometry.screenContaining(quartzCenterX: q.midX, q.midY)
        check("屏中心落回 fixture=\(fixture.label)", scr?.frame == expected.frame,
              "actual=\(String(describing: scr?.frame))")
    } else {
        // NSScreen 是系统只读集合，不能注入合成屏供 screenContaining 查询；
        // 合成 fixture 只验证负 x 边界和 Quartz↔AppKit 转换，不虚称命中系统屏。
        let negativeBoundary = f.minX < 0 && q.minX == f.minX && back.minX == f.minX
        check("合成负坐标 fixture 边界", negativeBoundary, "quartz=\(q) back=\(back)")
    }
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

check("F16 moving约60Hz", abs(Follower.movingInterval - 1.0 / 60.0) < 0.001,
      "interval=\(Follower.movingInterval)")
check("F17 stable探测延迟不超过0.1s", Follower.stableInterval <= 0.1,
      "interval=\(Follower.stableInterval)")

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

// T18 两列标题同顶线；WEEK TOKENS 数值在标题下方剩余区域居中（允许 AppKit 像素舍入 1pt）
dv.layoutForTesting()
let available = dv.availableContentFrameForTesting
func descendantTextField(in view: NSView, text: String) -> NSTextField? {
    if let field = view as? NSTextField, field.stringValue == text { return field }
    for child in view.subviews {
        if let field = descendantTextField(in: child, text: text) { return field }
    }
    return nil
}
func titleRectInDock(_ field: NSTextField?, dock: DockView) -> NSRect {
    guard let field else { return .zero }
    let titleBounds = field.cell?.titleRect(forBounds: field.bounds) ?? field.bounds
    return field.convert(titleBounds, to: dock)
}
let leftCapF = titleRectInDock(descendantTextField(in: dv, text: "WEEK LEFT"), dock: dv)
let tokensCapF = dv.tokensCaptionTitleRectForTesting
let tokensValF = dv.tokensValueTitleRectForTesting
let tokensCapIntrinsicH = dv.tokensCaptionIntrinsicSizeForTesting.height
let tokensValIntrinsicH = dv.tokensValueIntrinsicSizeForTesting.height
let remainingBelowCaption = NSRect(
    x: available.minX,
    y: available.minY,
    width: available.width,
    height: max(0, tokensCapF.minY - available.minY)
)
check("T18a WEEK LEFT 与 WEEK TOKENS 标题顶线一致",
      !leftCapF.isEmpty && abs(leftCapF.maxY - tokensCapF.maxY) < 1.0,
      "left=\(leftCapF) tokens=\(tokensCapF)")
check("T18b WEEK TOKENS 标题和值保持 intrinsic 高度",
      abs(tokensCapF.height - tokensCapIntrinsicH) < 1.0
        && abs(tokensValF.height - tokensValIntrinsicH) < 1.0,
      "cap=\(tokensCapF) val=\(tokensValF) capH=\(tokensCapIntrinsicH) valH=\(tokensValIntrinsicH)")
check("T18c WEEK TOKENS 数值在标题下方剩余区域居中",
      !remainingBelowCaption.isEmpty && abs(tokensValF.midY - remainingBelowCaption.midY) < 1.0,
      "valueMidY=\(tokensValF.midY) remainingMidY=\(remainingBelowCaption.midY) remaining=\(remainingBelowCaption)")
check("T18d 对齐后底座仍为 200x48",
      dv.frame.width == 200 && dv.frame.height == 48, "\(dv.frame.size)")
var themedDockGeometryOK = true
var themedDockGeometryExtra = ""
for spec in Theme.builtins {
    let themedDock = DockView()
    themedDock.applyTheme(spec.metrics)
    themedDock.layoutForTesting()
    let themedAvailable = themedDock.availableContentFrameForTesting
    let leftCaptionRect = titleRectInDock(
        descendantTextField(in: themedDock, text: "WEEK LEFT"), dock: themedDock)
    let tokenCaptionRect = themedDock.tokensCaptionTitleRectForTesting
    let tokenValueRect = themedDock.tokensValueTitleRectForTesting
    let remaining = NSRect(
        x: themedAvailable.minX,
        y: themedAvailable.minY,
        width: themedAvailable.width,
        height: max(0, tokenCaptionRect.minY - themedAvailable.minY)
    )
    if leftCaptionRect.isEmpty
        || abs(leftCaptionRect.maxY - tokenCaptionRect.maxY) >= 1.0
        || remaining.isEmpty
        || abs(tokenValueRect.midY - remaining.midY) >= 1.0 {
        themedDockGeometryOK = false
        themedDockGeometryExtra += "\(spec.id): left=\(leftCaptionRect) cap=\(tokenCaptionRect) value=\(tokenValueRect) remaining=\(remaining) "
    }
}
check("T18e 三主题下标题同顶线且 token value 在剩余区居中",
      themedDockGeometryOK, themedDockGeometryExtra)
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

// ---- T-ctrl: 控制按钮避让（消息框在上方时，宠物下方出现两个小控制按钮）----
// 回归 B：控制按钮是独立动态占用区域，高度 < bubbleHeightMin(32)，原 obstaclesNear 排除 → 底座重叠。
// 修复：obstaclesNear 用相对宠物位置/尺寸/owner/PID 等非内容元数据形成最小安全候选规则，
// 纳入 pet 正下方紧邻的紧凑控制按钮，同时排除 17x6 细长 voice control 与 pet 内部噪声窗。
let ctBase = fail, ctPass = pass

// 场景 B 拓扑：消息框在 pet 上方，pet 下方出现两个小控制按钮（移动/交互时）。
let petCtrl = CGRect(x: 200, y: 400, width: 172, height: 179)   // maxY=579
let mascotCtrl = mkw(20, layer: 2, petCtrl, title: "Codex Pet Mascot Effect")
// 两个控制按钮：pet 正下方紧邻、紧凑（高度<32）、水平分列 pet 两侧下方
let ctrlBtn1 = mkw(21, layer: 3, CGRect(x: 210, y: 585, width: 60, height: 28))   // 585..613，在 pet 下方
let ctrlBtn2 = mkw(22, layer: 3, CGRect(x: 300, y: 585, width: 60, height: 28))   // 585..613，在 pet 下方
// 噪声窗：必须排除
let voiceCtrl = mkw(23, layer: 3, CGRect(x: 250, y: 450, width: 17, height: 6))   // 细长 + 在 pet 内部
let innerNoise = mkw(24, layer: 3, CGRect(x: 250, y: 500, width: 40, height: 10)) // 在 pet 内部
let mainCtrl = mkw(25, layer: 0, CGRect(x: 0, y: 0, width: 1728, height: 1084))   // 主窗

// B1 控制按钮出现 → obstaclesNear 必须纳入两个按钮（当前排除 height<32 → 缺陷）
let oc1 = PetTracker.obstaclesNear(mascot: mascotCtrl, candidates: [ctrlBtn1, ctrlBtn2, voiceCtrl, innerNoise, mainCtrl])
check("T-ctrl1 控制按钮出现→纳入两按钮(非排除)",
      oc1.count == 2 && Set(oc1.map { $0.wid }) == [21, 22], "count=\(oc1.count) wids=\(oc1.map { $0.wid }.sorted())")

// B2 控制按钮避让 → dock 下移到按钮底部下方（maxY=613 → dock y=615），不重叠
let oc1Dock = Geometry.safeDockFrame(pet: petCtrl, avoiding: oc1.map { $0.bounds },
                                     dockSize: dockSize, gap: gap, screen: nil).frame
check("T-ctrl2 控制按钮→dock避让到按钮底部下方(615)",
      oc1Dock?.origin.y == 615, "y=\(oc1Dock?.origin.y ?? -1)")
if let f = oc1Dock {
    let noOverlap1 = !(f.origin.y < ctrlBtn1.bounds.maxY && f.origin.y + dockSize.height > ctrlBtn1.bounds.minY)
    let noOverlap2 = !(f.origin.y < ctrlBtn2.bounds.maxY && f.origin.y + dockSize.height > ctrlBtn2.bounds.minY)
    check("T-ctrl2b 避让后与两按钮均不相交", noOverlap1 && noOverlap2, "")
} else { check("T-ctrl2b", false) }

// B3 噪声窗排除：17x6 voice control（细长）、pet 内部小窗、主窗 均不纳入
check("T-ctrl3 噪声窗排除(voice/inner/main)",
      !oc1.contains { $0.wid == 23 } && !oc1.contains { $0.wid == 24 } && !oc1.contains { $0.wid == 25 }, "")

// B4 控制按钮消失（下 tick）→ obstacles empty → dock 回基础位置 581
let oc2 = PetTracker.obstaclesNear(mascot: mascotCtrl, candidates: [voiceCtrl, innerNoise, mainCtrl])
check("T-ctrl4 按钮消失→obstacles empty(复位)", oc2.isEmpty, "count=\(oc2.count)")
check("T-ctrl4b 按钮消失→dock回基础位置581",
      Geometry.safeDockFrame(pet: petCtrl, avoiding: oc2.map { $0.bounds }, dockSize: dockSize, gap: gap, screen: nil).frame?.origin.y == 581, "")

// B5 消息框上方 × 按钮出现：消息框不在下方（不构成障碍），按钮单独构成障碍
// 消息框在 pet 上方（minY < pet.minY）→ 不在 pet 下方，不纳入；按钮在下方 → 纳入
let bubbleAbove = mkw(26, layer: 3, CGRect(x: 200, y: 200, width: 345, height: 54))  // 200..254，pet 上方
let oc3 = PetTracker.obstaclesNear(mascot: mascotCtrl, candidates: [ctrlBtn1, ctrlBtn2, bubbleAbove])
check("T-ctrl5 消息框上方不纳入+按钮纳入",
      oc3.count == 2 && !oc3.contains { $0.wid == 26 } && Set(oc3.map { $0.wid }) == [21, 22],
      "count=\(oc3.count) wids=\(oc3.map { $0.wid }.sorted())")

// B6 消息框下方 × 按钮出现：两者并存 → 合并避让（消息框在上则按钮决定，消息框在下则取更低者）
let bubbleBelow = mkw(27, layer: 3, CGRect(x: 180, y: 620, width: 345, height: 54))  // 620..674，按钮(613)下方
let oc4 = PetTracker.obstaclesNear(mascot: mascotCtrl, candidates: [ctrlBtn1, ctrlBtn2, bubbleBelow])
check("T-ctrl6 消息框下方+按钮→合并3障碍",
      oc4.count == 3 && Set(oc4.map { $0.wid }) == [21, 22, 27], "count=\(oc4.count)")
// bubbleBelow.maxY=674 > 按钮 maxY=613 → dock 避让到 676（链式取最低）
check("T-ctrl6b 合并避让→dock到最低障碍下方(676)",
      Geometry.safeDockFrame(pet: petCtrl, avoiding: oc4.map { $0.bounds }, dockSize: dockSize, gap: gap, screen: nil).frame?.origin.y == 676, "")

// B7 出现→消失转换：按钮出现(下移) → 消失(复位)，每帧基于当前几何重算
let appearObs = PetTracker.obstaclesNear(mascot: mascotCtrl, candidates: [ctrlBtn1, ctrlBtn2])
let appearY = Geometry.safeDockFrame(pet: petCtrl, avoiding: appearObs.map { $0.bounds }, dockSize: dockSize, gap: gap, screen: nil).frame?.origin.y
let vanishObs = PetTracker.obstaclesNear(mascot: mascotCtrl, candidates: [])
let vanishY = Geometry.safeDockFrame(pet: petCtrl, avoiding: vanishObs.map { $0.bounds }, dockSize: dockSize, gap: gap, screen: nil).frame?.origin.y
check("T-ctrl7 出现→消失: 出现避让615/消失复位581(禁用上帧偏移)",
      appearY == 615 && vanishY == 581, "appear=\(appearY ?? -1) vanish=\(vanishY ?? -1)")

// B8 消失→出现转换
check("T-ctrl8 消失→出现: 复位581/避让615", vanishY == 581 && appearY == 615, "")

// B9 回归 a10A：原 17x6 voice control 仍被排除（不因纳入控制按钮而误纳入细长噪声）
let oA_recheck = PetTracker.obstaclesNear(mascot: mascotR, candidates: [wrapper, obs384, obs17])
check("T-ctrl9 回归: 17x6 voice control仍排除", oA_recheck.isEmpty, "count=\(oA_recheck.count)")

// B10 obstacleKind 分类契约：气泡→.bubble（经像素可见性），控制按钮→.control（不经像素探测）
let kindPetMaxY = petCtrl.maxY   // 579
check("T-ctrl10a 气泡分类.bubble",
      PetTracker.obstacleKind(bubbleBelow, petMaxY: kindPetMaxY) == .bubble, "")
check("T-ctrl10b 控制按钮分类.control",
      PetTracker.obstacleKind(ctrlBtn1, petMaxY: kindPetMaxY) == .control, "")
check("T-ctrl10c 控制按钮分类.control(btn2)",
      PetTracker.obstacleKind(ctrlBtn2, petMaxY: kindPetMaxY) == .control, "")

print("\n[控制按钮避让] \(pass - ctPass) passed, \(fail - ctBase) failed")
print("\n[会话气泡避让] \(pass - avPass) passed, \(fail - avBase) failed")

// ---- T-bv: BubbleVisibility 分类（纯函数滞回）+ 调度（max2Hz/single-flight/reset）+ 异步集成（generation/strict single-flight）----
let bvBase = fail, bvPass = pass
// 进程内权限请求 gate：preflight=false 只请求一次；preflight=true 不请求。
var requestGate = ScreenCapturePermissionRequestGate()
check("T-bv0a preflight=false首次请求", requestGate.shouldRequest(preflightGranted: false), "")
check("T-bv0b preflight=false重复检查不再请求", !requestGate.shouldRequest(preflightGranted: false), "")
var grantedGate = ScreenCapturePermissionRequestGate()
check("T-bv0c preflight=true不请求", !grantedGate.shouldRequest(preflightGranted: true), "")
check("T-bv0d preflight后续false仍可首次请求", grantedGate.shouldRequest(preflightGranted: false), "")
// 实测基线（同窗口 345×64 真实对照）
let collapsedS = BubbleAlphaStats(nonTransparentRatio: 34.0/22080, bboxRatio: 48.0/22080)
let expandedS = BubbleAlphaStats(nonTransparentRatio: 189.0/22080, bboxRatio: 390.0/22080)
let midS = BubbleAlphaStats(nonTransparentRatio: 0.004, bboxRatio: 0.007)
check("T-bv1 collapsed→hidden", BubbleVisibilityClassifier.classify(stats: collapsedS, previous: .visible) == .hidden, "")
check("T-bv2 expanded→visible", BubbleVisibilityClassifier.classify(stats: expandedS, previous: .hidden) == .visible, "")
check("T-bv3 中间滞回→保持visible", BubbleVisibilityClassifier.classify(stats: midS, previous: .visible) == .visible, "")
check("T-bv4 中间滞回→保持hidden", BubbleVisibilityClassifier.classify(stats: midS, previous: .hidden) == .hidden, "")
check("T-bv5 nil stats→visible(capture失败/SC缺失保守避让)",
      BubbleVisibilityClassifier.classify(stats: nil, previous: .visible) == .visible, "")
// P1 nil 保守语义（README: capture failure conservatively avoids）：
// 当前仍存在的气泡，SC 捕获失败（macOS13/TCC 抖动/窗口刚注册未进 SC content）
// 必须保守判 visible（当障碍避让），不能因 capture nil 当成收起导致底座重叠气泡。
check("T-bv5b nil stats(previous hidden)→visible(保守避让,不沿用previous)",
      BubbleVisibilityClassifier.classify(stats: nil, previous: .hidden) == .visible, "")
check("T-bv5c nil stats(previous visible)→visible(保守避让)",
      BubbleVisibilityClassifier.classify(stats: nil, previous: .visible) == .visible, "")

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
check("T-bv12 wid不在当前候选集→hidden(当前帧失效)", probe.visibility(for: CGWindowID(99)) == .hidden, "")

// 异步集成（fake capturer + RunLoop pump）：pending capture 完成 → cached 更新
var fakeTime = Date(timeIntervalSince1970: 2000)
let fakeCollapsed: @Sendable (WinCandidate) async -> BubbleAlphaStats? = { _ in
    BubbleAlphaStats(nonTransparentRatio: 34.0/22080, bboxRatio: 48.0/22080)
}
let asyncProbe = BubbleVisibilityProbe(now: { fakeTime }, canCapture: { true }, capturer: fakeCollapsed)
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
let concProbe = BubbleVisibilityProbe(now: { fakeTime }, canCapture: { true }, capturer: slowCap)
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
check("T-bv23 旧wid从候选消失→hidden(当前帧失效,非污染)", concProbe.visibility(for: CGWindowID(100)) == .hidden, "")

// strict single-flight：在途 Task 中 probe(empty) → 候选重新出现 probe 仍被拒（inFlight 不清）
fakeTime = Date(timeIntervalSince1970: 4000)
let concProbe2 = BubbleVisibilityProbe(now: { fakeTime }, canCapture: { true }, capturer: slowCap)  // 300ms capturer
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

// T-bv31: 完全空闲态（candidates 空 + cached 空 + !inFlight）probe 不递增 generation（避免无意义锁写）
let idleProbe = BubbleVisibilityProbe(now: { Date(timeIntervalSince1970: 5000) })
let genBefore = idleProbe.lock.withLock { $0.generation }
idleProbe.probe(candidates: [])
idleProbe.probe(candidates: [])
idleProbe.probe(candidates: [])
let genAfter = idleProbe.lock.withLock { $0.generation }
check("T-bv31 空闲态空probe不递增generation", genAfter == genBefore, "before=\(genBefore) after=\(genAfter)")

// T-bv32: cached 有值时 probe([]) → 仍清 cached + 递增 generation（旧结果失效）
let cacheProbe = BubbleVisibilityProbe(now: { Date(timeIntervalSince1970: 6000) })
cacheProbe.lock.withLock { $0.cached = [CGWindowID(7): .visible]; $0.inFlight = false }
let genCB = cacheProbe.lock.withLock { $0.generation }
cacheProbe.probe(candidates: [])
let genCA = cacheProbe.lock.withLock { $0.generation }
check("T-bv32 cached非空时probe([])→递增generation+清cached",
      genCA == genCB + 1 && cacheProbe.lock.withLock { $0.cached.isEmpty }, "before=\(genCB) after=\(genCA)")

// T-bv33 (回归A·收起不复位)：候选 wid 上一帧 visible，本帧从 probe 列表移除 →
// 该 wid 的 cached visibility 必须立即失效（不再返回 visible）。
// 真机语义：消息框收起后窗口可能从 obstaclesNear 消失，底座必须复位到宠物下方，
// 而非沿用上一帧偏移。当前帧候选消失 = 状态立即失效，禁止残留 visible 缓存。
let vanishCap: @Sendable (WinCandidate) async -> BubbleAlphaStats? = { _ in
    BubbleAlphaStats(nonTransparentRatio: 189.0/22080, bboxRatio: 390.0/22080)   // expanded → visible
}
let vanishProbe = BubbleVisibilityProbe(
    now: { Date(timeIntervalSince1970: 7000) }, canCapture: { true }, capturer: vanishCap
)
vanishProbe.probe(candidates: [mkw(300, layer: 3, CGRect(x: 0, y: 580, width: 345, height: 64))])
let vanishPump0 = Date().addingTimeInterval(5)
while vanishProbe.lock.withLock({ $0.inFlight }) && Date() < vanishPump0 {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
}
check("T-bv33a 前置: expanded 候选→cached visible",
      vanishProbe.visibility(for: CGWindowID(300)) == .visible, "")
// 本帧候选集变化（wid 300 消失，换成 wid 301）→ wid 300 状态必须立即失效
vanishProbe.probe(candidates: [mkw(301, layer: 3, CGRect(x: 0, y: 580, width: 345, height: 64))])
check("T-bv33b 候选消失→旧wid状态立即失效(非visible)",
      vanishProbe.visibility(for: CGWindowID(300)) != .visible, "实际=\(vanishProbe.visibility(for: CGWindowID(300)))")

// T-bv34 (P1·保守避让)：同一 wid 仍在当前候选集（knownWids），SC 捕获失败(nil) →
// 必须保守判 visible（当障碍避让），不可因 capture nil 当成收起。
// 这是 README "capture failure conservatively avoids" 契约：当前仍存在的气泡，
// capture 失败时底座必须继续避让，不能重叠气泡。
// 收起态的正确复位由 wid 从候选集消失驱动（见 T-bv33），不由 capture nil 驱动。
var vanishTime = Date(timeIntervalSince1970: 8000)
var vanishStats: BubbleAlphaStats? = BubbleAlphaStats(nonTransparentRatio: 189.0/22080, bboxRatio: 390.0/22080)
let nilCap: @Sendable (WinCandidate) async -> BubbleAlphaStats? = { _ in vanishStats }
let nilProbe = BubbleVisibilityProbe(now: { vanishTime }, canCapture: { true }, capturer: nilCap)
let nilCand = mkw(310, layer: 3, CGRect(x: 0, y: 580, width: 345, height: 64))
nilProbe.probe(candidates: [nilCand])
let nilPump0 = Date().addingTimeInterval(5)
while nilProbe.lock.withLock({ $0.inFlight }) && Date() < nilPump0 {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
}
check("T-bv34a 前置: expanded→visible", nilProbe.visibility(for: CGWindowID(310)) == .visible, "")
// SC 捕获该窗口失败（stats nil）——但 wid 仍在当前候选集 → 保守 visible（不当收起）
vanishStats = nil
vanishTime = Date(timeIntervalSince1970: 8001)
nilProbe.probe(candidates: [nilCand])
let nilPump1 = Date().addingTimeInterval(5)
while nilProbe.lock.withLock({ $0.inFlight }) && Date() < nilPump1 {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
}
check("T-bv34b 候选仍存在+capture nil→保守visible(不误判收起,README保守避让)",
      nilProbe.visibility(for: CGWindowID(310)) == .visible,
      "实际=\(nilProbe.visibility(for: CGWindowID(310)))")

// T-bv34c (P1 场景3·nil 后无 hidden-visible 错误转换)：收起(候选消失→hidden)
// 后若再出现(候选重现)，capture 仍 nil 时必须回到 visible，不能因缓存/异步滞留 hidden。
vanishTime = Date(timeIntervalSince1970: 8002)
nilProbe.probe(candidates: [])   // 候选全部消失 → wid 310 失效为 hidden
check("T-bv34c1 候选消失→旧wid立即hidden",
      nilProbe.visibility(for: CGWindowID(310)) == .hidden, "")
// 候选重新出现 + capture nil → 保守 visible（不能滞留 hidden）
vanishTime = Date(timeIntervalSince1970: 8003)
nilProbe.probe(candidates: [nilCand])
let nilPump2 = Date().addingTimeInterval(5)
while nilProbe.lock.withLock({ $0.inFlight }) && Date() < nilPump2 {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
}
check("T-bv34c2 候选重现+capture nil→恢复visible(无hidden→visible滞留错误)",
      nilProbe.visibility(for: CGWindowID(310)) == .visible,
      "实际=\(nilProbe.visibility(for: CGWindowID(310)))")

// T-bv35 (回归A·收起后复位)：tick 序列模拟——expanded 探测 visible→下移；
// 收起后 wid 从候选集消失 → visibility 失效（hidden）→ visibleObstacles 为空
// → safeDockFrame 回 pet 下方（不复用上帧偏移）。回归A复位由候选消失驱动，不由 capture nil 驱动。
let petForCollapse = CGRect(x: 100, y: 100, width: 172, height: 179)   // maxY=279
let bubbleForCollapse = CGRect(x: 80, y: 280, width: 345, height: 54)  // 280..334，与 dock 281..329 重叠
let dockSizeBV = CGSize(width: 200, height: 48)
let gapBV: CGFloat = 2
let baseY = petForCollapse.maxY + gapBV   // 281（无障碍基础位置）
let avoidY = bubbleForCollapse.maxY + gapBV  // 336（避让位置）
// 帧1 expanded：visibleObstacles=[bubble] → dock 下移到 336
let dockY_expanded = Geometry.safeDockFrame(pet: petForCollapse, avoiding: [bubbleForCollapse],
                                            dockSize: dockSizeBV, gap: gapBV, screen: nil).frame?.origin.y
check("T-bv35a expanded→dock避让到336", dockY_expanded == avoidY, "y=\(dockY_expanded ?? -1)")
// 帧2 收起（wid 从候选集消失）→ visibility 失效（hidden）→ visibleObstacles 为空 → dock 必须回到基础位置 281
let dockY_collapsed = Geometry.safeDockFrame(pet: petForCollapse, avoiding: [],
                                             dockSize: dockSizeBV, gap: gapBV, screen: nil).frame?.origin.y
check("T-bv35b 收起→visibleObstacles空→dock复位到281(禁用上帧偏移)",
      dockY_collapsed == baseY, "y=\(dockY_collapsed ?? -1)")

// T-bv36 (P1 场景2·候选消失时旧 cache/in-flight 不能继续成为障碍)：
// 帧1 候选 A 被 capture 为 visible 并写入 cached[A]=visible；
// 帧2 候选 A 从集合消失（knownWids 不含 A）→ visibility(A) 必须立即 hidden，
// 即使 cached[A] 仍残留 visible，也不能继续作为障碍（回归A复位由候选消失驱动）。
let p1capTime = Date(timeIntervalSince1970: 9000)
let p1Expanded: @Sendable (WinCandidate) async -> BubbleAlphaStats? = { _ in
    BubbleAlphaStats(nonTransparentRatio: 189.0/22080, bboxRatio: 390.0/22080)   // expanded → visible
}
let p1Probe = BubbleVisibilityProbe(now: { p1capTime }, canCapture: { true }, capturer: p1Expanded)
let p1Cand = mkw(400, layer: 3, CGRect(x: 0, y: 580, width: 345, height: 64))
p1Probe.probe(candidates: [p1Cand])
let p1Pump0 = Date().addingTimeInterval(5)
while p1Probe.lock.withLock({ $0.inFlight }) && Date() < p1Pump0 {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
}
check("T-bv36a 前置: 候选A expanded→cached visible",
      p1Probe.visibility(for: CGWindowID(400)) == .visible, "")
// 确认 cached 残留 visible（这是要被 knownWids 失效机制屏蔽的旧结果）
let p1CachedResidue = p1Probe.lock.withLock { $0.cached[CGWindowID(400)] }
check("T-bv36b cached[A]残留visible(旧结果存在,待失效屏蔽)",
      p1CachedResidue == .visible, "cached[A]=\(String(describing: p1CachedResidue))")
// 帧2 候选 A 从集合消失 → knownWids 更新 → visibility(A) 必须 hidden（不被残留 cache 继续当障碍）
p1Probe.probe(candidates: [])
check("T-bv36c 候选A消失→visibility立即hidden(旧cache不继续成为障碍)",
      p1Probe.visibility(for: CGWindowID(400)) == .hidden, "")

// T-bv37 (P1 场景2·在途 in-flight 写入不能复活已消失候选的障碍)：
// 帧1 候选 A probe（in-flight 未完成）；帧2 候选 A 消失（knownWids 不含 A），
// 此时 in-flight Task 完成（generation 仍匹配）写入 cached[A]=visible；
// visibility(A) 仍必须 hidden —— knownWids 失效优先于 cached 写入。
let p1Time2 = Date(timeIntervalSince1970: 9100)
let p1SlowCap: @Sendable (WinCandidate) async -> BubbleAlphaStats? = { _ in
    try? await Task.sleep(nanoseconds: 200_000_000)
    return BubbleAlphaStats(nonTransparentRatio: 189.0/22080, bboxRatio: 390.0/22080)   // visible
}
let p1Probe2 = BubbleVisibilityProbe(now: { p1Time2 }, canCapture: { true }, capturer: p1SlowCap)
let p1Cand2 = mkw(401, layer: 3, CGRect(x: 0, y: 580, width: 345, height: 64))
p1Probe2.probe(candidates: [p1Cand2])   // 启动 in-flight
check("T-bv37a in-flight启动", p1Probe2.lock.withLock { $0.inFlight }, "")
// 帧2 候选 A 消失（in-flight 仍在途）→ knownWids 更新
p1Probe2.probe(candidates: [])
check("T-bv37b 候选消失(in-flight在途)→visibility立即hidden",
      p1Probe2.visibility(for: CGWindowID(401)) == .hidden, "")
// in-flight 完成：候选消失时 probe([]) 已递增 generation，在途 Task 持有的旧 generation 失配
// → 其结果被丢弃，绝不写 cached[401]（generation 校验是防止旧 in-flight 结果复活已消失候选
// 障碍的第一道防线；第二道 knownWids 失效由 T-bv37d 覆盖）。
let p1Pump1 = Date().addingTimeInterval(5)
while p1Probe2.lock.withLock({ $0.inFlight }) && Date() < p1Pump1 {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
}
let p1Cached401 = p1Probe2.lock.withLock { $0.cached[CGWindowID(401)] }
check("T-bv37c in-flight完成→generation失配→cached不写入(旧结果被丢弃)",
      p1Cached401 == nil, "cached[401]=\(String(describing: p1Cached401))")
// 关键断言：无论 in-flight 是否写 cached，visibility(401) 必须 hidden（knownWids 失效优先）
check("T-bv37d 已消失候选→visibility保持hidden(in-flight写入不能复活障碍)",
      p1Probe2.visibility(for: CGWindowID(401)) == .hidden,
      "实际=\(p1Probe2.visibility(for: CGWindowID(401)))")

// T-bv38: preflight=false 时重复 probe 不进入 capturer，当前候选继续保守 visible。
let blockedCaptureCalls = OSAllocatedUnfairLock(initialState: 0)
let blockedCap: BubbleCapturer = { _ in
    blockedCaptureCalls.withLock { $0 += 1 }
    return collapsedS
}
let blockedProbe = BubbleVisibilityProbe(
    now: { Date(timeIntervalSince1970: 10_000) },
    canCapture: { false },
    capturer: blockedCap
)
let blockedCandidate = mkw(500, layer: 3, CGRect(x: 0, y: 580, width: 345, height: 64))
blockedProbe.probe(candidates: [blockedCandidate])
blockedProbe.probe(candidates: [blockedCandidate])
check("T-bv38a preflight=false不启动capture", blockedCaptureCalls.withLock { $0 } == 0, "")
check("T-bv38b preflight=false无inFlight", !blockedProbe.lock.withLock { $0.inFlight }, "")
check("T-bv38c preflight=false候选保守visible",
      blockedProbe.visibility(for: CGWindowID(500)) == .visible, "")

// T-bv38d: production wake bridge 可从后台调用，但 scheduler 必须在主线程以零延迟执行。
let bridgeCount = OSAllocatedUnfairLock(initialState: 0)
let bridgeDelay = OSAllocatedUnfairLock<TimeInterval?>(initialState: nil)
let bridgeOnMain = OSAllocatedUnfairLock(initialState: false)
let bridgeCalledOffMain = OSAllocatedUnfairLock(initialState: false)
let bridgeCallback = FollowTickWake.visibilityChangeCallback { delay in
    bridgeCount.withLock { $0 += 1 }
    bridgeDelay.withLock { $0 = delay }
    bridgeOnMain.withLock { $0 = Thread.isMainThread }
}
DispatchQueue.global().async {
    bridgeCalledOffMain.withLock { $0 = !Thread.isMainThread }
    bridgeCallback()
}
let bridgeCompleted = waitPumpingMain { bridgeCount.withLock { $0 } == 1 }
check("T-bv38d wake bridge后台→主线程zero-delay scheduler一次",
      bridgeCompleted
        && bridgeCalledOffMain.withLock { $0 }
        && bridgeCount.withLock { $0 } == 1
        && bridgeDelay.withLock { $0 } == 0
        && bridgeOnMain.withLock { $0 }, "")

// T-bv39: 同一候选 expanded→collapsed 的成功结果只通知一次；通知后即使 pet rect 不变，
// 复用现有 safeDockFrame 布局路径也会从避让 frame 回到基础 frame。
var transitionTime = Date(timeIntervalSince1970: 11_000)
let transitionStats = OSAllocatedUnfairLock<BubbleAlphaStats?>(initialState: expandedS)
let transitionSchedules = OSAllocatedUnfairLock(initialState: 0)
let transitionDelay = OSAllocatedUnfairLock<TimeInterval?>(initialState: nil)
let transitionOnMain = OSAllocatedUnfairLock(initialState: false)
let transitionCap: BubbleCapturer = { _ in transitionStats.withLock { $0 } }
let transitionWake = FollowTickWake.visibilityChangeCallback { delay in
    transitionSchedules.withLock { $0 += 1 }
    transitionDelay.withLock { $0 = delay }
    transitionOnMain.withLock { $0 = Thread.isMainThread }
}
let transitionProbe = BubbleVisibilityProbe(
    now: { transitionTime },
    canCapture: { true },
    capturer: transitionCap,
    onVisibilityChange: transitionWake
)
let transitionCandidate = mkw(501, layer: 3, bubbleForCollapse)
transitionProbe.probe(candidates: [transitionCandidate])
let transitionPump0 = Date().addingTimeInterval(5)
while transitionProbe.lock.withLock({ $0.inFlight }) && Date() < transitionPump0 {
    RunLoop.current.run(until: Date().addingTimeInterval(0.01))
}
check("T-bv39a 初始visible结果不调度", transitionSchedules.withLock { $0 } == 0, "")
let transitionVisibleObstacles = transitionProbe.visibility(for: CGWindowID(501)) == .visible
    ? [bubbleForCollapse] : []
let transitionExpandedY = Geometry.safeDockFrame(
    pet: petForCollapse, avoiding: transitionVisibleObstacles,
    dockSize: dockSizeBV, gap: gapBV, screen: nil
).frame?.origin.y
check("T-bv39b 初始visible仍避让", transitionExpandedY == avoidY, "y=\(transitionExpandedY ?? -1)")

transitionStats.withLock { $0 = collapsedS }
transitionTime = Date(timeIntervalSince1970: 11_001)
transitionProbe.probe(candidates: [transitionCandidate])
let transitionPump1 = Date().addingTimeInterval(5)
while (transitionProbe.lock.withLock({ $0.inFlight })
       || transitionSchedules.withLock({ $0 }) < 1) && Date() < transitionPump1 {
    RunLoop.current.run(until: Date().addingTimeInterval(0.01))
}
check("T-bv39c visible→hidden经production bridge主线程zero-delay调度一次",
      transitionSchedules.withLock { $0 } == 1
        && transitionDelay.withLock { $0 } == 0
        && transitionOnMain.withLock { $0 }, "")
let transitionHiddenObstacles = transitionProbe.visibility(for: CGWindowID(501)) == .visible
    ? [bubbleForCollapse] : []
let transitionCollapsedY = Geometry.safeDockFrame(
    pet: petForCollapse, avoiding: transitionHiddenObstacles,
    dockSize: dockSizeBV, gap: gapBV, screen: nil
).frame?.origin.y
check("T-bv39d pet不变+通知后重排→回基础位置", transitionCollapsedY == baseY,
      "y=\(transitionCollapsedY ?? -1)")

transitionTime = Date(timeIntervalSince1970: 11_002)
transitionProbe.probe(candidates: [transitionCandidate])
let transitionPump2 = Date().addingTimeInterval(5)
while transitionProbe.lock.withLock({ $0.inFlight }) && Date() < transitionPump2 {
    RunLoop.current.run(until: Date().addingTimeInterval(0.01))
}
check("T-bv39e hidden不变不重复调度", transitionSchedules.withLock { $0 } == 1, "")

// T-bv40: reset 后旧 generation 的成功结果不得通知布局。
let staleNotifications = OSAllocatedUnfairLock(initialState: 0)
let staleCap: BubbleCapturer = { _ in
    try? await Task.sleep(nanoseconds: 100_000_000)
    return collapsedS
}
let staleProbe = BubbleVisibilityProbe(
    now: { Date(timeIntervalSince1970: 12_000) },
    canCapture: { true },
    capturer: staleCap,
    onVisibilityChange: { staleNotifications.withLock { $0 += 1 } }
)
staleProbe.probe(candidates: [mkw(502, layer: 3, bubbleForCollapse)])
staleProbe.reset()
let stalePump = Date().addingTimeInterval(5)
while staleProbe.lock.withLock({ $0.inFlight }) && Date() < stalePump {
    RunLoop.current.run(until: Date().addingTimeInterval(0.01))
}
check("T-bv40 旧generation结果不通知", staleNotifications.withLock { $0 } == 0, "")

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

    // D4: dock 居中不超界 → detail 相对 dock 水平居中（NSPanel 可能像素对齐，容差 1px）
    let dockCenter = NSRect(x: v.midX - 100, y: v.minY + 100, width: 200, height: 48)
    dtPanel.placeBelow(dockFrame: dockCenter, visibleScreen: screen)
    let df4 = dtPanel.frameForTesting
    check("D4 常规空间→detail相对dock水平居中", abs(df4.midX - dockCenter.midX) < 1.0,
          "detailMidX=\(df4.midX) dockMidX=\(dockCenter.midX)")

    // D5/D6: 直接穿过生产 open/toggle（不注入 screen），边缘首次打开也必须 clamp。
    let productionPanel = DetailPanel()
    productionPanel.open(relativeTo: dockAtLeftEdge)
    let openLeftFrame = productionPanel.frameForTesting
    check("D5 生产open左边缘→自动解析screen并clamp",
          openLeftFrame.minX >= v.minX,
          "detailMinX=\(openLeftFrame.minX) visibleMinX=\(v.minX)")
    productionPanel.close()
    productionPanel.toggle(relativeTo: dockAtRightEdge)
    let toggleRightFrame = productionPanel.frameForTesting
    check("D6 生产toggle右边缘→自动解析screen并clamp",
          toggleRightFrame.maxX <= v.maxX,
          "detailMaxX=\(toggleRightFrame.maxX) visibleMaxX=\(v.maxX)")
    productionPanel.close()
} else {
    check("D2-D6（无屏跳过）", true, "")
}

// D7: 无 screen → 不 clamp，但仍相对 dock 水平居中
let noScrDock = NSRect(x: 5000, y: 5000, width: 200, height: 48)  // 远超常规屏
dtPanel.placeBelow(dockFrame: noScrDock, visibleScreen: nil)
let df5 = dtPanel.frameForTesting
check("D7 无screen→不clamp但仍水平居中", abs(df5.midX - noScrDock.midX) < 0.01,
      "detailMidX=\(df5.midX) dockMidX=\(noScrDock.midX)")
let unresolvedScreenPanel = DetailPanel()
unresolvedScreenPanel.open(relativeTo: noScrDock)
let unresolvedFrame = unresolvedScreenPanel.frameForTesting
check("D8 生产open无法解析screen→合理降级为水平居中",
      abs(unresolvedFrame.midX - noScrDock.midX) < 0.01,
      "detailMidX=\(unresolvedFrame.midX) dockMidX=\(noScrDock.midX)")
unresolvedScreenPanel.close()

print("\n[DetailPanel clamp] \(pass - dtPass) passed, \(fail - dtBase) failed")

// ---- T-detail-ui: B 方案双列表格 + ThemeMetrics 同步 ----
let duBase = fail, duPass = pass
let detailUI = DetailPanel()
let snapFilled = DockSnapshot(
    weekLeft: "73%", weekTokens: "1.2M", plan: "Plus",
    resetAt: "08-21 09:00", cacheRatio: "12%", inputTokens: "800k",
    outputTokens: "400k", sessionCount: 3, updatedAt: "08-20 10:00",
    localEstimateNote: "本机估算 · 仅供参考")
detailUI.render(snapFilled)
detailUI.layoutForTesting()
check("DU1 七行标签保留",
      detailUI.captionsForTesting == ["套餐", "重置时间", "缓存比例", "输入", "输出", "会话数", "更新时间"],
      "caps=\(detailUI.captionsForTesting)")
check("DU2 既有字段渲染",
      detailUI.valuesForTesting == ["Plus", "08-21 09:00", "12%", "800k", "400k", "3", "08-20 10:00"],
      "vals=\(detailUI.valuesForTesting)")
check("DU3 本机估算提示渲染",
      detailUI.noteForTesting == "本机估算 · 仅供参考",
      "note=\(detailUI.noteForTesting)")

let snapPlace = DockSnapshot(
    weekLeft: nil, weekTokens: nil, plan: nil, resetAt: nil, cacheRatio: nil,
    inputTokens: nil, outputTokens: nil, sessionCount: nil, updatedAt: nil,
    localEstimateNote: "本机估算 · 暂无数据")
detailUI.render(snapPlace)
check("DU4 空字段占位不回归",
      detailUI.valuesForTesting.allSatisfy { $0 == DockSnapshot.placeholder },
      "vals=\(detailUI.valuesForTesting)")
check("DU5 空提示仍渲染",
      detailUI.noteForTesting == "本机估算 · 暂无数据",
      "note=\(detailUI.noteForTesting)")

detailUI.render(snapFilled)
func nearlyEqual(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat = 1.0) -> Bool { abs(a - b) < t }
func allNearlyEqual(_ xs: [CGFloat], _ t: CGFloat = 1.0) -> Bool {
    guard let first = xs.first else { return false }
    return xs.allSatisfy { nearlyEqual($0, first, t) }
}
func sameCGColor(_ a: CGColor?, _ b: CGColor?) -> Bool {
    guard let a, let b else { return false }
    return a == b
}
func sameNSColor(_ a: NSColor?, _ b: NSColor?) -> Bool {
    guard let a, let b else { return false }
    let ac = a.usingColorSpace(.sRGB) ?? a
    let bc = b.usingColorSpace(.sRGB) ?? b
    return abs(ac.redComponent - bc.redComponent) < 0.02
        && abs(ac.greenComponent - bc.greenComponent) < 0.02
        && abs(ac.blueComponent - bc.blueComponent) < 0.02
        && abs(ac.alphaComponent - bc.alphaComponent) < 0.02
}
func isClearWindowBackground(_ c: NSColor) -> Bool {
    let sc = c.usingColorSpace(.sRGB) ?? c
    return sc.alphaComponent < 0.01
}
func fontPointSize(_ f: NSFont?) -> CGFloat { f?.pointSize ?? -1 }
func fontIsMedium(_ f: NSFont?) -> Bool {
    guard let f else { return false }
    let traits = f.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
    let weight = (traits?[.weight] as? NSNumber)?.doubleValue ?? 0
    return abs(weight - Double(NSFont.Weight.medium.rawValue)) < 0.08
}
func detailSnapshot(note: String) -> DockSnapshot {
    DockSnapshot(
        weekLeft: "73%", weekTokens: "1.2M", plan: "Plus",
        resetAt: "08-21 09:00", cacheRatio: "12%", inputTokens: "800k",
        outputTokens: "400k", sessionCount: 3, updatedAt: "08-20 10:00",
        localEstimateNote: note)
}
func wrappedTextHeight(_ text: String, font: NSFont, width: CGFloat) -> CGFloat {
    ceil((text as NSString).boundingRect(
        with: NSSize(width: width, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        attributes: [.font: font]
    ).height)
}
func detailContentFits(_ detail: DetailPanel) -> (Bool, String) {
    detail.layoutForTesting()
    let bounds = detail.contentBoundsForTesting
    let rows = detail.rowFramesForTesting
    let note = detail.noteFrameForTesting
    let topInset = bounds.maxY - (rows.first?.maxY ?? bounds.maxY)
    let bottomInset = note.minY - bounds.minY
    let inside = rows.allSatisfy { bounds.contains($0) } && bounds.contains(note)
    let noOverlap = rows.allSatisfy { !$0.intersects(note) }
    let ok = inside && noOverlap
        && abs(topInset - 8) <= 1.0
        && abs(bottomInset - 8) <= 1.0
    return (ok, "frame=\(detail.frameForTesting.size) note=\(note) top=\(topInset) bottom=\(bottomInset)")
}

// DU-dynamic: render 三态与 applyTheme 后都必须按当前实际文字重新贴合。
let dynamicDetail = DetailPanel()
dynamicDetail.applyTheme(Theme.holographic.metrics)
let emptyNote = ""
let shortNote = "本机估算 · 仅供参考"
let wideNote = "本机估算 · LEFT 为官方额度，TOKENS 来自本机日志"
var dynamicLayoutOK = true
var dynamicLayoutExtra = ""
var stateHeights: [CGFloat] = []
for (name, note) in [("empty", emptyNote), ("short", shortNote), ("wide", wideNote)] {
    dynamicDetail.render(detailSnapshot(note: note))
    let fit = detailContentFits(dynamicDetail)
    stateHeights.append(dynamicDetail.frameForTesting.height)
    if !fit.0 {
        dynamicLayoutOK = false
        dynamicLayoutExtra += "\(name):\(fit.1) "
    }
    if !note.isEmpty, let font = dynamicDetail.noteFontForTesting {
        let noteFrame = dynamicDetail.noteFrameForTesting
        let expectedHeight = wrappedTextHeight(note, font: font, width: noteFrame.width)
        let twoLineLimit = ceil(font.boundingRectForFont.height) * 2
        if abs(noteFrame.height - expectedHeight) > 1 || expectedHeight > twoLineLimit + 1 {
            dynamicLayoutOK = false
            dynamicLayoutExtra += "\(name):actualH=\(noteFrame.height) expectedH=\(expectedHeight) twoLineLimit=\(twoLineLimit) "
        }
    }
}
let wideUnwrapped = (wideNote as NSString).size(
    withAttributes: [.font: dynamicDetail.noteFontForTesting ?? NSFont.systemFont(ofSize: 9)]).width
check("DU6 render三态后内容贴合且超宽note完整换行",
      dynamicLayoutOK
        && stateHeights.count == 3
        && stateHeights[2] > stateHeights[1]
        && wideUnwrapped > dynamicDetail.noteFrameForTesting.width,
      "heights=\(stateHeights) unwrapped=\(wideUnwrapped) \(dynamicLayoutExtra)")

var dynamicThemeLayoutOK = true
var dynamicThemeLayoutExtra = ""
for spec in Theme.builtins {
    dynamicDetail.applyTheme(spec.metrics)
    let fit = detailContentFits(dynamicDetail)
    let noteFrame = dynamicDetail.noteFrameForTesting
    let expectedHeight = wrappedTextHeight(
        wideNote,
        font: dynamicDetail.noteFontForTesting ?? NSFont.systemFont(ofSize: 9),
        width: noteFrame.width)
    if !fit.0 || abs(noteFrame.height - expectedHeight) > 1 {
        dynamicThemeLayoutOK = false
        dynamicThemeLayoutExtra += "\(spec.id):\(fit.1) actualH=\(noteFrame.height) expectedH=\(expectedHeight) "
    }
}
check("DU7 applyTheme后三主题按当前note重算且不截断",
      dynamicThemeLayoutOK, dynamicThemeLayoutExtra)

var themeOk = true
var themeExtra = ""
var geoOk = true
let dockTheme = DockView()
for spec in Theme.builtins {
    let m = spec.metrics
    dockTheme.applyTheme(m)
    detailUI.applyTheme(m)
    dockTheme.layoutForTesting()
    detailUI.layoutForTesting()
    let expectedCaption = m.label.nsColor.withAlphaComponent(0.6)
    let expectedValue = m.label.nsColor
    let expectedCaptionFont = DockView.font(m.font, caption: true)
    let expectedBodyFont = DockView.font(m.font, size: 11, weight: .medium)
    let checks: [(String, Bool)] = [
        ("windowClear", isClearWindowBackground(detailUI.windowBackgroundColorForTesting)),
        ("layerBg", sameCGColor(detailUI.contentLayerBackgroundColorForTesting, m.background.nsColor.cgColor)),
        ("layerBgAlpha", abs((detailUI.contentLayerBackgroundColorForTesting?.alpha ?? -1) - CGFloat(m.background.a)) < 0.02),
        ("border", sameCGColor(detailUI.borderColorForTesting, m.accent.nsColor.cgColor)),
        ("radius", abs(detailUI.cornerRadiusForTesting - CGFloat(m.cornerRadius)) < 0.01),
        ("borderW", abs(detailUI.borderWidthForTesting - CGFloat(m.borderWidth)) < 0.01),
        ("capColor", sameNSColor(detailUI.captionColorForTesting, expectedCaption)),
        ("valColor", sameNSColor(detailUI.valueColorForTesting, expectedValue)),
        ("dockBg", sameCGColor(dockTheme.backgroundColorForTesting, m.background.nsColor.cgColor)),
        ("dockBorder", sameCGColor(dockTheme.borderColorForTesting, m.accent.nsColor.cgColor)),
        ("dockCapFont", dockTheme.captionFontForTesting == DockView.font(m.font, caption: true)),
        ("dockValFont", dockTheme.valueFontForTesting == DockView.font(m.font, caption: false)),
        ("detailCapFont", detailUI.captionFontForTesting == expectedBodyFont
            && abs(fontPointSize(detailUI.captionFontForTesting) - 11) < 0.01
            && fontIsMedium(detailUI.captionFontForTesting)),
        ("detailNoteFont", detailUI.noteFontForTesting == expectedCaptionFont
            && abs(fontPointSize(detailUI.noteFontForTesting) - 9) < 0.01),
        ("detailBodyFont", detailUI.valueFontsForTesting.allSatisfy { abs(fontPointSize($0) - 11) < 0.01 && fontIsMedium($0) }
            && detailUI.valueFontsForTesting.allSatisfy { $0 == expectedBodyFont }
            && abs(fontPointSize(detailUI.valueFontForTesting) - 11) < 0.01
            && fontIsMedium(detailUI.valueFontForTesting)
            && abs(fontPointSize(detailUI.valueFontForTesting) - 15) > 0.5),
    ]
    let failed = checks.filter { !$0.1 }.map { $0.0 }
    if !failed.isEmpty {
        themeOk = false
        themeExtra += "\(spec.id):\(failed) "
    }

    let capWs = detailUI.captionWidthsForTesting
    let valWs = detailUI.valueWidthsForTesting
    let capXs = detailUI.captionMinXForTesting
    let valMaxXs = detailUI.valueMaxXForTesting
    let rowFs = detailUI.rowFramesForTesting
    let noteF = detailUI.noteFrameForTesting
    let seps = detailUI.separatorFramesForTesting
    let bounds = detailUI.contentBoundsForTesting
    let rowsInside = rowFs.allSatisfy { bounds.contains($0) }
    let noteInside = bounds.contains(noteF)
    let sepsInside = seps.allSatisfy { bounds.insetBy(dx: -1, dy: -1).intersects($0) }
    var overlap = false
    for i in 0..<rowFs.count {
        for j in (i+1)..<rowFs.count where rowFs[i].intersects(rowFs[j]) { overlap = true }
        if rowFs[i].intersects(noteF) { overlap = true }
    }
    let lowestRowMinY = rowFs.map { $0.minY }.min() ?? 0
    let noteBelowRows = lowestRowMinY >= noteF.maxY - 1.0
    let noteLeftAligned = nearlyEqual(noteF.minX, 12, 1.0)
    let rowSeparatorSpacing = zip(0..<max(0, rowFs.count - 1), seps).allSatisfy { pair in
        let (i, sep) = pair
        return rowFs[i].minY - sep.maxY >= 2.0
            && sep.minY - rowFs[i + 1].maxY >= 2.0
    }
    let topInset = bounds.maxY - (rowFs.first?.maxY ?? bounds.maxY)
    let bottomInset = noteF.minY - bounds.minY
    let contentFitted = nearlyEqual(topInset, 8, 1.1)
        && nearlyEqual(bottomInset, 8, 1.1)
        && detailUI.frameForTesting.height < 190
    let geo: [(String, Bool)] = [
        ("size", abs(detailUI.frameForTesting.width - 230) < 0.01 && contentFitted),
        ("capAlign", detailUI.captionAlignmentForTesting == .left && allNearlyEqual(capWs) && allNearlyEqual(capXs) && capXs.allSatisfy { nearlyEqual($0, 12, 1.0) }),
        ("valAlign", detailUI.valueAlignmentForTesting == .right && allNearlyEqual(valWs) && allNearlyEqual(valMaxXs) && valMaxXs.allSatisfy { nearlyEqual($0, 218, 1.0) }),
        ("seps", detailUI.separatorCountForTesting >= 6 && rowSeparatorSpacing),
        ("inside", rowsInside && noteInside && sepsInside && !overlap && noteBelowRows && !noteF.isEmpty && noteLeftAligned),
    ]
    let geoFailed = geo.filter { !$0.1 }.map { $0.0 }
    if !geoFailed.isEmpty {
        geoOk = false
        themeExtra += "\(spec.id)-geo:\(geoFailed) frame=\(detailUI.frameForTesting.size) top=\(topInset) bottom=\(bottomInset) "
    }
}
check("DU8 标签列左对齐且共享稳定宽度（换肤后）", geoOk, themeExtra)
check("DU9 数值列右对齐且共享稳定宽度（换肤后）", geoOk, themeExtra)
check("DU10 七行之间有克制分隔线（换肤后）", geoOk, themeExtra)
check("DU11 内容不截断/重叠且底部提示分层（换肤后）", geoOk, themeExtra)
check("DU12 三主题详情卡与底座共用 ThemeMetrics 并同步换肤", themeOk, themeExtra)
check("DU13 详情左右文字字号一致", nearlyEqual(fontPointSize(detailUI.captionFontForTesting), fontPointSize(detailUI.valueFontForTesting), 0.01),
      "caption=\(fontPointSize(detailUI.captionFontForTesting)) value=\(fontPointSize(detailUI.valueFontForTesting))")

print("\n[DetailPanel UI] \(pass - duPass) passed, \(fail - duBase) failed")

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
onLogger.log("follow wid=123 pid=456")
let l2Deadline = Date().addingTimeInterval(2)
var l2Content = ""
while Date() < l2Deadline && !l2Content.contains("hello-petdock") {
    l2Content = (try? String(contentsOf: logTmp, encoding: .utf8)) ?? ""
    RunLoop.current.run(until: Date().addingTimeInterval(0.02))
}
// 以期望日志内容作为完成条件，不能只等文件出现（文件可能已创建但异步写入尚未完成）。
check("L2 enabled=true→后台异步写入文件", l2Content.contains("hello-petdock"), "content=\(l2Content)")
check("L2b 日志不含真实 WID/PID", !l2Content.contains("wid=123") && !l2Content.contains("pid=456"), "content=\(l2Content)")

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

// L4: 默认构造（不显式传 enabled）的 logger 必须实时跟随 DebugLog.enabled ——
// 模拟 release 启动顺序：logger 在 applyOverrides 之前创建（此时 enabled=false），
// 随后 applyOverrides 设 DebugLog.enabled=true，默认构造的 logger 仍须落盘。
// 回归保护：见 review §4.1（--verbose 在 release 下静默失效）。
let savedDebugLogEnabled = DebugLog.enabled
let defaultTmp = FileManager.default.temporaryDirectory
    .appendingPathComponent("petdock-log-default-\(ProcessInfo.processInfo.processIdentifier).log")
func resetDefaultTmp() { try? FileManager.default.removeItem(at: defaultTmp) }

// L4a: logger 默认构造于 enabled=false 之后翻转为 true → 须落盘（修复点）
DebugLog.enabled = false
resetDefaultTmp()
let defaultLogger = PetLogger(logURL: defaultTmp)   // 默认构造，不传 enabled
DebugLog.enabled = true                              // 模拟 applyOverrides(--verbose)
defaultLogger.log("follow-state-after-verbose")
let l4Deadline = Date().addingTimeInterval(2)
while Date() < l4Deadline && !FileManager.default.fileExists(atPath: defaultTmp.path) {
    RunLoop.current.run(until: Date().addingTimeInterval(0.02))
}
let l4Content = (try? String(contentsOf: defaultTmp, encoding: .utf8)) ?? ""
check("L4a 默认构造logger在enabled翻转后落盘(--verbose修复)", l4Content.contains("follow-state-after-verbose"),
      "content=\(l4Content)")

// L4b: 默认构造 + DebugLog.enabled=false → 不写（保证 release 默认 no-op 不回归）
DebugLog.enabled = false
resetDefaultTmp()
let defaultOffLogger = PetLogger(logURL: defaultTmp)
defaultOffLogger.log("should-not-write-default")
let l4bDeadline = Date().addingTimeInterval(0.5)
while Date() < l4bDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
check("L4b 默认构造logger enabled=false→不写(no-op不回归)",
      !FileManager.default.fileExists(atPath: defaultTmp.path), "")

resetDefaultTmp()
DebugLog.enabled = savedDebugLogEnabled   // 恢复，避免污染后续测试

// L5-L9: 句柄复用 + 大小上限轮转（accepted-deferred）。
// 每个 logger 用独立文件 + 独立队列隔离；flush() 同步落盘，测试无需 RunLoop pump。
func uniqueLogURL(_ tag: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("petdock-log-\(tag)-\(ProcessInfo.processInfo.processIdentifier).log")
}
/// 提取 "line-N" 中的行号集合（轮转无重叠断言用）。
func lineNums(in content: String) -> Set<Int> {
    var nums = Set<Int>()
    for line in content.split(separator: "\n") {
        if let r = line.range(of: "line-") {
            if let n = Int(line[r.upperBound...]) { nums.insert(n) }
        }
    }
    return nums
}
func disjointLineNums(_ a: String, _ b: String) -> Bool {
    lineNums(in: a).isDisjoint(with: lineNums(in: b))
}
let rotTmp = uniqueLogURL("rot")
let rotOld = rotTmp.deletingPathExtension().appendingPathExtension("log.1")   // 轮转副本
try? FileManager.default.removeItem(at: rotTmp)
try? FileManager.default.removeItem(at: rotOld)

// L5: 句柄复用——连续多次 log() 后 flush() 同步落盘，内容完整且只有一份（句柄常驻，不再每次 open/close）。
let rotLogger = PetLogger(enabled: true, logURL: rotTmp, maxBytes: 512)
for i in 0..<8 { rotLogger.log("line-\(i)") }
rotLogger.flush()
let l5Content = (try? String(contentsOf: rotTmp, encoding: .utf8)) ?? ""
check("L5 句柄复用→多次写入内容完整(0..7均在)",
      (0..<8).allSatisfy { l5Content.contains("line-\($0)") }, "content=\(l5Content)")

// L6: 大小上限轮转——累计写入超过 maxBytes(512) 后，旧内容滚动到 .1，主文件仅含末尾写入。
// 每行 "[line-N]\n" 约 9 字节，写 200 行远超 512 → 必触发轮转（可触发多次）。
for i in 100..<300 { rotLogger.log("line-\(i)") }
rotLogger.flush()
let l6Main = (try? String(contentsOf: rotTmp, encoding: .utf8)) ?? ""
let l6Roll = FileManager.default.fileExists(atPath: rotOld.path)
    ? ((try? String(contentsOf: rotOld, encoding: .utf8)) ?? "") : ""
check("L6 超上限→生成.1轮转文件", FileManager.default.fileExists(atPath: rotOld.path), "")
check("L6b 主文件仅含末尾内容(不含早期 line-100)", !l6Main.contains("line-100"),
      "mainHas100=\(l6Main.contains("line-100"))")
// 单份覆盖式轮转不变量：主文件与 .1 是时间上的两段，同一行号不会同时出现（无重叠）。
check("L6c 主文件与.1无内容重叠(任一行号不同时出现)",
      l6Roll.contains("line-") && disjointLineNums(l6Main, l6Roll),
      "rollTail=\(l6Roll.suffix(40))")

// L7: flush() 同步——调用返回后内容已在盘上（无需 RunLoop pump，证明串行队列 sync 落盘）。
let syncTmp = uniqueLogURL("sync")
try? FileManager.default.removeItem(at: syncTmp)
let syncLogger = PetLogger(enabled: true, logURL: syncTmp, maxBytes: 1_000_000)
syncLogger.log("sync-line")
syncLogger.flush()
let l7Content = (try? String(contentsOf: syncTmp, encoding: .utf8)) ?? ""
check("L7 flush同步落盘(无需RunLoop pump)", l7Content.contains("sync-line"), "content=\(l7Content)")

// L8: enabled=false 时 flush() 也不创建文件（no-op 不回归；句柄常驻不破坏 release 默认行为）。
let noopTmp = uniqueLogURL("noop")
try? FileManager.default.removeItem(at: noopTmp)
let noopLogger = PetLogger(enabled: false, logURL: noopTmp, maxBytes: 512)
noopLogger.log("ignored"); noopLogger.flush()
check("L8 enabled=false→flush也不创建文件(no-op不回归)",
      !FileManager.default.fileExists(atPath: noopTmp.path), "")

// L9: 二次轮转——再次超过上限时 .1 被替换为主文件当时的旧内容（旧 .1 不残留累积）。
for i in 500..<900 { rotLogger.log("line-\(i)") }
rotLogger.flush()
let l9Main = (try? String(contentsOf: rotTmp, encoding: .utf8)) ?? ""
let l9Roll = FileManager.default.fileExists(atPath: rotOld.path)
    ? ((try? String(contentsOf: rotOld, encoding: .utf8)) ?? "") : ""
check("L9 二次轮转→.1被替换为前一段(含line-100..299之一,不含line-500+)",
      l9Roll.contains("line-") && !l9Roll.contains("line-500") && !l9Main.contains("line-100"),
      "rollTail=\(l9Roll.suffix(30))")

// L10: 外部 symlink 不得把日志重定向到目标文件。
let symlinkLog = uniqueLogURL("symlink")
let symlinkTarget = uniqueLogURL("symlink-target")
try? FileManager.default.removeItem(at: symlinkLog)
try? FileManager.default.removeItem(at: symlinkTarget)
FileManager.default.createFile(atPath: symlinkTarget.path, contents: Data("UNCHANGED\n".utf8))
try? FileManager.default.createSymbolicLink(at: symlinkLog, withDestinationURL: symlinkTarget)
let symlinkLogger = PetLogger(enabled: true, logURL: symlinkLog)
symlinkLogger.log("should-not-follow")
symlinkLogger.flush()
let symlinkContent = (try? String(contentsOf: symlinkTarget, encoding: .utf8)) ?? ""
check("L10 日志 symlink 不重定向写入", symlinkContent == "UNCHANGED\n", "content=\(symlinkContent)")

try? FileManager.default.removeItem(at: rotTmp)
try? FileManager.default.removeItem(at: rotOld)
try? FileManager.default.removeItem(at: syncTmp)
try? FileManager.default.removeItem(at: noopTmp)
try? FileManager.default.removeItem(at: symlinkLog)
try? FileManager.default.removeItem(at: symlinkTarget)

print("\n[PetLogger] \(pass - lgPass) passed, \(fail - lgBase) failed")

// ---- T-plan: FollowTickPlan 纯决策层（数据 pause/resume 边沿 + UI show/hide + dockVisible + 候选为空）----
let plBase = fail, plPass = pass

// P1: 宠物首次可见（false→true 边沿）→ resumeData，UI 取决于 dockVisible
let p1 = FollowTickPlanner.decide(input: FollowTickInput(petVisible: true, wasPetVisible: false, dockVisible: true))
check("P1 宠物首次可见→resumeData边沿", p1.resumeData && !p1.pauseData, "")
check("P1b dockVisible→showUI", p1.showUI && !p1.hideUI, "")
check("P1c 宠物可见→petDisappeared=false", !p1.petDisappeared, "")

// P2: 宠物持续可见（true→true，无边沿）→ 不 resume 也不 pause
let p2 = FollowTickPlanner.decide(input: FollowTickInput(petVisible: true, wasPetVisible: true, dockVisible: true))
check("P2 持续可见→无resume无pause", !p2.resumeData && !p2.pauseData, "")
check("P2b 持续可见+dockVisible→showUI", p2.showUI, "")

// P3: 宠物消失（true→false 边沿）→ pauseData + hideUI + petDisappeared
let p3 = FollowTickPlanner.decide(input: FollowTickInput(petVisible: false, wasPetVisible: true, dockVisible: true))
check("P3 宠物消失→pauseData边沿", p3.pauseData && !p3.resumeData, "")
check("P3b 宠物消失→hideUI", p3.hideUI && !p3.showUI, "")
check("P3c 宠物消失→petDisappeared=true", p3.petDisappeared, "")

// P4: 持续隐藏（false→false）→ 无边沿，不 resume/pause
let p4 = FollowTickPlanner.decide(input: FollowTickInput(petVisible: false, wasPetVisible: false, dockVisible: true))
check("P4 持续隐藏→无resume无pause", !p4.resumeData && !p4.pauseData, "")
check("P4b 持续隐藏→hideUI+petDisappeared", p4.hideUI && p4.petDisappeared, "")

// P5: dockVisible=false（用户隐藏）—— 宠物仍可见但 UI 隐藏；数据探测不受影响（仍跟随宠物）
let p5 = FollowTickPlanner.decide(input: FollowTickInput(petVisible: true, wasPetVisible: false, dockVisible: false))
check("P5 用户隐藏→hideUI(宠物可见但UI关)", p5.hideUI && !p5.showUI, "")
check("P5b 用户隐藏不影响数据→resumeData仍触发", p5.resumeData, "")
check("P5c 用户隐藏→petDisappeared=false(仍跟踪宠物)", !p5.petDisappeared, "")

// P6: dockVisible 在持续可见时切换 → 仅 UI 变化，数据无边沿
let p6 = FollowTickPlanner.decide(input: FollowTickInput(petVisible: true, wasPetVisible: true, dockVisible: false))
check("P6 持续可见+用户隐藏→hideUI且无数据边沿", p6.hideUI && !p6.resumeData && !p6.pauseData, "")

// P7: showUI 与 hideUI 严格互斥（覆盖所有 8 种输入组合）
var mutexOk = true
for pv in [false, true] {
    for wpv in [false, true] {
        for dv in [false, true] {
            let pl = FollowTickPlanner.decide(input: FollowTickInput(petVisible: pv, wasPetVisible: wpv, dockVisible: dv))
            if pl.showUI == pl.hideUI { mutexOk = false }
        }
    }
}
check("P7 showUI/hideUI 严格互斥(全8组合)", mutexOk, "")

// P8: resumeData/pauseData 仅在 petVisible 边沿触发（互斥，且持续态均为 false）
var edgeOk = true
for pv in [false, true] {
    for wpv in [false, true] {
        let pl = FollowTickPlanner.decide(input: FollowTickInput(petVisible: pv, wasPetVisible: wpv, dockVisible: true))
        if pl.resumeData && pl.pauseData { edgeOk = false }                          // 不可同时触发
        if pv == wpv && (pl.resumeData || pl.pauseData) { edgeOk = false }           // 持续态无边沿
    }
}
check("P8 resume/pause 仅边沿触发且互斥", edgeOk, "")

// P9: showUI = petVisible && dockVisible（真值表精确）
check("P9a pv=T dv=T → showUI", FollowTickPlanner.decide(input: FollowTickInput(petVisible: true, wasPetVisible: false, dockVisible: true)).showUI)
check("P9b pv=T dv=F → hideUI", FollowTickPlanner.decide(input: FollowTickInput(petVisible: true, wasPetVisible: false, dockVisible: false)).hideUI)
check("P9c pv=F dv=T → hideUI", FollowTickPlanner.decide(input: FollowTickInput(petVisible: false, wasPetVisible: true, dockVisible: true)).hideUI)
check("P9d pv=F dv=F → hideUI", FollowTickPlanner.decide(input: FollowTickInput(petVisible: false, wasPetVisible: true, dockVisible: false)).hideUI)

print("\n[FollowTickPlan] \(pass - plPass) passed, \(fail - plBase) failed")

print("\n=== 总计 \(pass) passed, \(fail) failed ===")
exit(fail == 0 ? 0 : 1)
