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

let d1 = Follower.decide(pet: nil, stationaryAnchor: petA,
                         lastMaterialChangeAt: 1, now: 10)
check("F1 无宠物→hidden/show=false/setFrame=false", d1.state == .hidden && d1.showDock == false && d1.shouldSetFrame == false)

let d2 = Follower.decide(pet: petA, stationaryAnchor: nil,
                         lastMaterialChangeAt: nil, now: 0)
check("F2 首次捕获→moving/setFrame=true/记录变化时刻",
      d2.state == .moving && d2.shouldSetFrame == true && d2.lastMaterialChangeAt == 0)

let d3 = Follower.decide(pet: petA, stationaryAnchor: petA,
                         lastMaterialChangeAt: 0, now: 1.0 / 60.0)
check("F3 静止时长未达阈值→moving/setFrame=false",
      d3.state == .moving && d3.shouldSetFrame == false && d3.lastMaterialChangeAt == 0)

let d4 = Follower.decide(pet: petA, stationaryAnchor: petA,
                         lastMaterialChangeAt: 0, now: Follower.stationaryDuration)
check("F4 达阈值→stable/setFrame=false", d4.state == .stable && d4.shouldSetFrame == false)

let d5 = Follower.decide(pet: petB, stationaryAnchor: petA,
                         lastMaterialChangeAt: 0, now: 1)
check("F5 stable后移动→moving/setFrame=true/重置变化时刻",
      d5.state == .moving && d5.shouldSetFrame == true && d5.lastMaterialChangeAt == 1)

let d6 = Follower.decide(pet: petA, stationaryAnchor: nil,
                         lastMaterialChangeAt: nil, now: 2)
check("F6 隐藏后重现→moving/setFrame=true(重捕)", d6.state == .moving && d6.shouldSetFrame == true)

check("F7 stable探测间隔<hidden探测间隔", Follower.stableInterval < Follower.hiddenInterval)
check("F8 hidden清空变化时刻", d1.lastMaterialChangeAt == nil)
check("F9 moving保留最近变化时刻", d3.lastMaterialChangeAt == 0)
check("F10 stable保留最近变化时刻", d4.lastMaterialChangeAt == 0)
// 隐藏决策应同步隐藏底座（详情由调用方跟随 showDock 关闭）
check("F11 隐藏时showDock=false(底座+详情隐藏)", d1.showDock == false)

// F12-F14: 亚像素抖动容差（pet 来自 CGWindowList double 精度 bounds，
// Electron 渲染微抖动 0.x px 会使精确 != 永真 → Follower 永不进 stable）。
// 容差：origin 位移 ≤ positionTolerance 视为位置不变（尺寸变化仍判为变化）。
let petJitter = CGRect(x: 100.4, y: 100.3, width: 172, height: 179)   // 位移 0.5px < 阈值
let d12 = Follower.decide(pet: petJitter, stationaryAnchor: petA,
                          lastMaterialChangeAt: 0, now: 1.0 / 60.0)
check("F12 亚像素抖动0.5px→判不变(过渡moving/setFrame=false)",
      d12.state == .moving && d12.shouldSetFrame == false && d12.lastMaterialChangeAt == 0,
      "state=\(d12.state) setFrame=\(d12.shouldSetFrame)")

let petMove = CGRect(x: 102, y: 100, width: 172, height: 179)   // 位移 2px > 阈值
let d13 = Follower.decide(pet: petMove, stationaryAnchor: petA,
                          lastMaterialChangeAt: 0, now: 3)
check("F13 位移2px→判变化(moving/setFrame=true)",
      d13.state == .moving && d13.shouldSetFrame == true && d13.lastMaterialChangeAt == 3, "")

// 边界：位移恰等于阈值 → 视为不变（≤ 而非 <）
let petEdge = CGRect(x: 100 + PetHeuristics.positionTolerance, y: 100, width: 172, height: 179)
let d14 = Follower.decide(pet: petEdge, stationaryAnchor: petA,
                          lastMaterialChangeAt: 0, now: 1.0 / 60.0)
check("F14 位移恰=阈值→判不变(边界≤)",
      d14.state == .moving && d14.shouldSetFrame == false && d14.lastMaterialChangeAt == 0, "")

// 尺寸变化（即使 origin 不变）仍判为变化——宠物形变需重定位
let petResize = CGRect(x: 100, y: 100, width: 173, height: 179)   // width +1
let d15 = Follower.decide(pet: petResize, stationaryAnchor: petA,
                          lastMaterialChangeAt: 0, now: 4)
check("F15 尺寸变化→判变化(setFrame=true)",
      d15.state == .moving && d15.shouldSetFrame == true && d15.lastMaterialChangeAt == 4,
      "state=\(d15.state) setFrame=\(d15.shouldSetFrame)")

check("F16 stable时长保留名义4/60s", abs(Follower.stationaryDuration - 4.0 / 60.0) < 0.000_001,
      "duration=\(Follower.stationaryDuration)")
check("F17 stable探测延迟不超过0.1s", Follower.stableInterval <= 0.1,
      "interval=\(Follower.stableInterval)")

// F18: stable 语义必须由单调 elapsed time 决定，不能由 callback 次数决定。
// 当前 stableCount 实现在 120Hz 下会比 60Hz 提前一半进入 stable，此断言在修复前必须失败。
func elapsedUntilStable(step: TimeInterval) -> TimeInterval {
    var elapsed: TimeInterval = 0
    var currentState: FollowState = .moving
    var changedAt: TimeInterval? = 0
    while currentState != .stable && elapsed < 1 {
        elapsed += step
        let d = Follower.decide(pet: petA, stationaryAnchor: petA,
                                lastMaterialChangeAt: changedAt, now: elapsed)
        currentState = d.state
        changedAt = d.lastMaterialChangeAt
    }
    return elapsed
}
let stableAt60 = elapsedUntilStable(step: 1.0 / 60.0)
let stableAt120 = elapsedUntilStable(step: 1.0 / 120.0)
check("F18 60/120Hz进入stable的elapsed语义一致",
      abs(stableAt60 - stableAt120) < 0.001,
      "60Hz=\(stableAt60) 120Hz=\(stableAt120)")
let irregularTimes: [TimeInterval] = [0.011, 0.029, 0.051, 4.0 / 60.0]
var irregularState: FollowState = .moving
var irregularChangedAt: TimeInterval? = 0
for time in irregularTimes {
    let d = Follower.decide(pet: petA, stationaryAnchor: petA,
                            lastMaterialChangeAt: irregularChangedAt, now: time)
    irregularState = d.state
    irregularChangedAt = d.lastMaterialChangeAt
}
check("F19 不规则cadence在同一elapsed阈值进入stable", irregularState == .stable, "state=\(irregularState)")
check("F20 macOS13 fallback按屏幕能力且上限120Hz",
      FollowTickScheduler.fallbackFramesPerSecond(screenMaximum: 60) == 60
        && FollowTickScheduler.fallbackFramesPerSecond(screenMaximum: 120) == 120
        && FollowTickScheduler.fallbackFramesPerSecond(screenMaximum: 144) == 120
        && FollowTickScheduler.fallbackFramesPerSecond(screenMaximum: 0) == 60)

// F21-F23: 每帧位移都低于容差，但相对静止起点持续累积时仍属于移动。
// 若只与上一帧比较，changedAt 永不更新，约 4/60s 后会错误进入 stable。
func staysMovingDuringCumulativeSubthresholdMotion(times: [TimeInterval]) -> Bool {
    var previous = petA
    var anchor: CGRect? = petA
    var changedAt: TimeInterval? = 0
    var materialChanges = 0
    for time in times {
        let current = previous.offsetBy(dx: 0.5, dy: 0)
        let decision = Follower.decide(
            pet: current,
            stationaryAnchor: anchor,
            lastMaterialChangeAt: changedAt,
            now: time
        )
        if decision.state == .stable { return false }
        if decision.shouldSetFrame { materialChanges += 1 }
        previous = current
        anchor = decision.stationaryAnchor
        changedAt = decision.lastMaterialChangeAt
    }
    return materialChanges > 0
}
let cumulative60Times = (1...12).map { Double($0) / 60.0 }
let cumulative120Times = (1...24).map { Double($0) / 120.0 }
let cumulativeIrregularTimes: [TimeInterval] = [0.009, 0.022, 0.041, 0.068, 0.079, 0.113, 0.151]
check("F21 60Hz连续0.5px移动不误入stable",
      staysMovingDuringCumulativeSubthresholdMotion(times: cumulative60Times))
check("F22 120Hz连续0.5px移动不误入stable",
      staysMovingDuringCumulativeSubthresholdMotion(times: cumulative120Times))
check("F23 不规则cadence连续0.5px移动不误入stable",
      staysMovingDuringCumulativeSubthresholdMotion(times: cumulativeIrregularTimes))

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

// ---- T-interp: latest-only 32ms 线性底座跟随（纯值状态，不依赖真实 display link）----
let ipBase = fail, ipPass = pass
let interpA = NSRect(x: 0, y: 10, width: 200, height: 48)
let interpB = NSRect(x: 100, y: 70, width: 200, height: 48)
let interpC = NSRect(x: 240, y: 30, width: 200, height: 48)
func rectNear(_ lhs: NSRect?, _ rhs: NSRect, tolerance: CGFloat = 0.000_001) -> Bool {
    guard let lhs else { return false }
    return abs(lhs.origin.x - rhs.origin.x) < tolerance
        && abs(lhs.origin.y - rhs.origin.y) < tolerance
        && abs(lhs.width - rhs.width) < tolerance
        && abs(lhs.height - rhs.height) < tolerance
}
func between(_ value: CGFloat, _ a: CGFloat, _ b: CGFloat) -> Bool {
    value >= min(a, b) - 0.000_001 && value <= max(a, b) + 0.000_001
}

var baseInterpolator = DockFrameInterpolator()
_ = baseInterpolator.update(to: interpA, at: 0, movementChanged: false)
let interpStart = baseInterpolator.update(to: interpB, at: 0, movementChanged: true)
let interp16 = baseInterpolator.frame(at: 0.016)
let interp32 = baseInterpolator.frame(at: DockFrameInterpolator.maximumDuration)
check("T-ip1 0ms从起点开始且16ms在线段中点", rectNear(interpStart, interpA) && rectNear(interp16, NSRect(x: 50, y: 40, width: 200, height: 48)),
      "start=\(String(describing: interpStart)) mid=\(String(describing: interp16))")
check("T-ip2 32ms精确到终点且segment结束", rectNear(interp32, interpB) && baseInterpolator.segmentStartedAt == nil,
      "frame=\(String(describing: interp32)) started=\(String(describing: baseInterpolator.segmentStartedAt))")

func interpolationSamples(at times: [TimeInterval]) -> [NSRect] {
    var interpolator = DockFrameInterpolator()
    _ = interpolator.update(to: interpA, at: 0, movementChanged: false)
    _ = interpolator.update(to: interpB, at: 0, movementChanged: true)
    return times.compactMap { interpolator.frame(at: $0) }
}
let samples60 = interpolationSamples(at: [0, 1.0 / 60.0, 2.0 / 60.0])
let samples120 = interpolationSamples(at: [0, 1.0 / 120.0, 2.0 / 120.0, 3.0 / 120.0, 4.0 / 120.0])
let samplesIrregular = interpolationSamples(at: [0, 0.007, 0.021, 0.032])
let allSamplesBounded = (samples60 + samples120 + samplesIrregular).allSatisfy {
    between($0.origin.x, interpA.origin.x, interpB.origin.x)
        && between($0.origin.y, interpA.origin.y, interpB.origin.y)
}
check("T-ip3 60/120Hz与不规则节拍均单调且无过冲", allSamplesBounded
        && rectNear(samples60.last, interpB)
        && rectNear(samples120.last, interpB)
        && rectNear(samplesIrregular.last, interpB),
      "60=\(samples60) 120=\(samples120) irregular=\(samplesIrregular)")

var retargetInterpolator = DockFrameInterpolator()
_ = retargetInterpolator.update(to: interpA, at: 0, movementChanged: false)
_ = retargetInterpolator.update(to: interpB, at: 0, movementChanged: true)
let retargetSource = retargetInterpolator.frame(at: 0.016)
let retargetStart = retargetInterpolator.update(to: interpC, at: 0.016, movementChanged: true)
let retargetMid = retargetInterpolator.frame(at: 0.032)
let retargetEnd = retargetInterpolator.frame(at: 0.048)
let expectedRetargetMid = NSRect(x: ((retargetSource?.origin.x ?? interpA.origin.x) + interpC.origin.x) / 2,
                                 y: ((retargetSource?.origin.y ?? interpA.origin.y) + interpC.origin.y) / 2,
                                 width: 200, height: 48)
check("T-ip4 retarget从当前采样值开始且只追最新目标",
      rectNear(retargetStart, retargetSource ?? interpA)
        && rectNear(retargetMid, expectedRetargetMid)
        && rectNear(retargetEnd, interpC),
      "source=\(String(describing: retargetSource)) mid=\(String(describing: retargetMid)) end=\(String(describing: retargetEnd))")

var safetyInterpolator = DockFrameInterpolator()
_ = safetyInterpolator.update(to: interpA, at: 0, movementChanged: false)
_ = safetyInterpolator.update(to: interpB, at: 0, movementChanged: true)
let safetySnap = safetyInterpolator.update(to: interpC, at: 0.008, movementChanged: false)
check("T-ip5 障碍/安全目标变化立即snap且不留segment",
      rectNear(safetySnap, interpC) && safetyInterpolator.segmentStartedAt == nil,
      "snap=\(safetySnap) started=\(String(describing: safetyInterpolator.segmentStartedAt))")
safetyInterpolator.reset()
check("T-ip6 reset用于隐藏/无screen/首次显示路径", safetyInterpolator.renderedFrame == nil
        && safetyInterpolator.targetFrame == nil && safetyInterpolator.segmentStartedAt == nil, "")

var stableInterpolator = DockFrameInterpolator()
_ = stableInterpolator.update(to: interpA, at: 0, movementChanged: false)
_ = stableInterpolator.update(to: interpB, at: 0, movementChanged: true)
let stableFinal = stableInterpolator.frame(at: Follower.stationaryDuration)
check("T-ip7 stable阈值前最终插值段已精确到位", rectNear(stableFinal, interpB),
      "stableDuration=\(Follower.stationaryDuration) final=\(String(describing: stableFinal))")

let panelPetA = CGRect(x: 100, y: 100, width: 172, height: 179)
let panelPetB = panelPetA.offsetBy(dx: 100, dy: 0)
if let interpolationScreen = NSScreen.screens.first {
    let panelInterpolator = DockPanel()
    _ = panelInterpolator.placeBelow(
        petQuartzRect: panelPetA,
        visibleScreen: interpolationScreen,
        movementChanged: false,
        monotonicNow: 0
    )
    let panelStart = panelInterpolator.frame
    _ = panelInterpolator.placeBelow(
        petQuartzRect: panelPetB,
        visibleScreen: interpolationScreen,
        movementChanged: true,
        monotonicNow: 0
    )
    let panelMovingStart = panelInterpolator.frame
    _ = panelInterpolator.placeBelow(
        petQuartzRect: panelPetB,
        visibleScreen: interpolationScreen,
        movementChanged: false,
        monotonicNow: 0.016
    )
    let panelMovingMid = panelInterpolator.frame
    let panelTargetB = Geometry.appKitRectFromQuartz(
        Geometry.safeDockFrame(
            pet: panelPetB,
            avoiding: [],
            dockSize: CGSize(width: panelInterpolator.dockWidth, height: panelInterpolator.dockHeight),
            gap: panelInterpolator.gap,
            screen: interpolationScreen
        ).frame!
    )
    check("T-ip8 DockPanel frame sink沿用32ms插值", abs(panelMovingStart.origin.x - panelStart.origin.x) < 1.0
            && panelMovingMid.origin.x > min(panelStart.origin.x, panelTargetB.origin.x)
            && panelMovingMid.origin.x < max(panelStart.origin.x, panelTargetB.origin.x),
          "start=\(panelStart) mid=\(panelMovingMid) target=\(panelTargetB)")
    let panelObstacle = CGRect(x: panelPetB.minX, y: panelPetB.maxY, width: panelPetB.width, height: 54)
    _ = panelInterpolator.placeBelow(
        petQuartzRect: panelPetB,
        avoiding: [panelObstacle],
        visibleScreen: interpolationScreen,
        movementChanged: true,
        monotonicNow: 0.016
    )
    let panelSafetyTarget = Geometry.appKitRectFromQuartz(
        Geometry.safeDockFrame(
            pet: panelPetB,
            avoiding: [panelObstacle],
            dockSize: CGSize(width: panelInterpolator.dockWidth, height: panelInterpolator.dockHeight),
            gap: panelInterpolator.gap,
            screen: interpolationScreen
        ).frame!
    )
    check("T-ip9 DockPanel障碍变化立即snap", abs(panelInterpolator.frame.origin.y - panelSafetyTarget.origin.y) < 1.0,
          "actual=\(panelInterpolator.frame) target=\(panelSafetyTarget)")
    panelInterpolator.hideIfNeeded()
    _ = panelInterpolator.placeBelow(
        petQuartzRect: panelPetB,
        visibleScreen: interpolationScreen,
        movementChanged: true,
        monotonicNow: 0.016
    )
    check("T-ip10 DockPanel隐藏后重现首帧snap", abs(panelInterpolator.frame.origin.x - panelTargetB.origin.x) < 1.0, "frame=\(panelInterpolator.frame)")
} else {
    check("T-ip8 DockPanel frame sink沿用32ms插值（无screen跳过）", true, "无有效screen")
    check("T-ip9 DockPanel障碍变化立即snap（无screen跳过）", true, "无有效screen")
    check("T-ip10 DockPanel隐藏后重现首帧snap（无screen跳过）", true, "无有效screen")
}

// P2 red regression: 持续无有效 screen 时，移动也必须每帧 snap/reset，不能进入 32ms segment。
let noScreenInterpolator = DockPanel()
_ = noScreenInterpolator.placeBelow(petQuartzRect: panelPetA, visibleScreen: nil, movementChanged: false, monotonicNow: 0)
let noScreenTargetB = Geometry.appKitRectFromQuartz(CGRect(
    x: panelPetB.origin.x + (panelPetB.width - noScreenInterpolator.dockWidth) / 2,
    y: panelPetB.origin.y + panelPetB.height + noScreenInterpolator.gap,
    width: noScreenInterpolator.dockWidth,
    height: noScreenInterpolator.dockHeight
))
_ = noScreenInterpolator.placeBelow(petQuartzRect: panelPetB, visibleScreen: nil, movementChanged: true, monotonicNow: 0.016)
let noScreenMovedFrame = noScreenInterpolator.frame
_ = noScreenInterpolator.placeBelow(petQuartzRect: panelPetB, visibleScreen: nil, movementChanged: false, monotonicNow: 0.024)
let noScreenStableFrame = noScreenInterpolator.frame
check("T-ip11 RED 持续无screen移动每帧snap且不延续segment",
      abs(noScreenMovedFrame.origin.x - noScreenTargetB.origin.x) < 1.0
        && abs(noScreenStableFrame.origin.x - noScreenTargetB.origin.x) < 1.0,
      "moved=\(noScreenMovedFrame) stable=\(noScreenStableFrame) target=\(noScreenTargetB)")
print("\n[DockFrameInterpolator] \(pass - ipPass) passed, \(fail - ipBase) failed")

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

// ---- T-bv: BubbleVisibility 分类（纯函数滞回）+ 调度（0.1s/single-flight/reset）+ 异步集成（generation/strict single-flight）----
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
let probe = BubbleVisibilityProbe(monotonicNow: { 1000 })
let cadenceStateTypes: (lastCaptureAt: TimeInterval, pendingRetryAt: TimeInterval?) = probe.lock.withLock {
    ($0.lastCaptureAt, $0.pendingRetryAt)
}
check("T-bv6a cadence state/deadline为monotonic TimeInterval",
      cadenceStateTypes.lastCaptureAt == -TimeInterval.greatestFiniteMagnitude
        && cadenceStateTypes.pendingRetryAt == nil,
      "last=\(cadenceStateTypes.lastCaptureAt) retry=\(String(describing: cadenceStateTypes.pendingRetryAt))")
check("T-bv6 初始isDue=true", probe.isDue(1000), "")
probe.lock.withLock { $0.lastCaptureAt = 1000; $0.inFlight = false }
check("T-bv7 <0.1s→false", !probe.isDue(1000.09), "")
check("T-bv8 >=0.1s→true", probe.isDue(1000.1), "")
probe.lock.withLock { $0.inFlight = true }
check("T-bv9 single-flight→false", !probe.isDue(1001), "")
probe.reset()
check("T-bv10 reset不清inFlight(旧Task负责)", probe.lock.withLock { $0.inFlight }, "")
probe.lock.withLock { $0.inFlight = false; $0.cached = [CGWindowID(1): .visible] }
probe.reset()
check("T-bv11 reset→cached空(inFlight不变)", probe.lock.withLock { $0.cached.isEmpty && !$0.inFlight }, "")
probe.lock.withLock { $0.inFlight = false }
check("T-bv12 wid不在当前候选集→hidden(当前帧失效)", probe.visibility(for: CGWindowID(99)) == .hidden, "")

// 异步集成（fake capturer + RunLoop pump）：pending capture 完成 → cached 更新
var fakeTime: TimeInterval = 2000
let fakeCollapsed: BubbleCapturer = { _ in
    .stats(BubbleAlphaStats(nonTransparentRatio: 34.0/22080, bboxRatio: 48.0/22080))
}
let asyncProbe = BubbleVisibilityProbe(monotonicNow: { fakeTime }, canCapture: { true }, capturer: fakeCollapsed)
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
let slowCap: BubbleCapturer = { _ in
    try? await Task.sleep(nanoseconds: 300_000_000)  // 300ms（async-safe，无 semaphore）
    return .stats(BubbleAlphaStats(nonTransparentRatio: 0.001, bboxRatio: 0.001))
}
fakeTime = 3000
let concProbe = BubbleVisibilityProbe(monotonicNow: { fakeTime }, canCapture: { true }, capturer: slowCap)
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
fakeTime = 3001
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
fakeTime = 4000
let concProbe2 = BubbleVisibilityProbe(monotonicNow: { fakeTime }, canCapture: { true }, capturer: slowCap)  // 300ms capturer
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
fakeTime = 4001
concProbe2.probe(candidates: [c2])
check("T-bv29 旧完成后新probe启动→inFlight=true", concProbe2.lock.withLock { $0.inFlight }, "")
let pumpDeadline4 = Date().addingTimeInterval(5)
while concProbe2.lock.withLock({ $0.inFlight }) && Date() < pumpDeadline4 {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
}
check("T-bv30 新probe完成→cached(hidden)", concProbe2.visibility(for: CGWindowID(200)) == .hidden, "")

// T-bv31: 完全空闲态（candidates 空 + cached 空 + !inFlight）probe 不递增 generation（避免无意义锁写）
let idleProbe = BubbleVisibilityProbe(monotonicNow: { 5000 })
let genBefore = idleProbe.lock.withLock { $0.generation }
idleProbe.probe(candidates: [])
idleProbe.probe(candidates: [])
idleProbe.probe(candidates: [])
let genAfter = idleProbe.lock.withLock { $0.generation }
check("T-bv31 空闲态空probe不递增generation", genAfter == genBefore, "before=\(genBefore) after=\(genAfter)")

// T-bv32: cached 有值时 probe([]) → 仍清 cached + 递增 generation（旧结果失效）
let cacheProbe = BubbleVisibilityProbe(monotonicNow: { 6000 })
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
let vanishCap: BubbleCapturer = { _ in
    .stats(BubbleAlphaStats(nonTransparentRatio: 189.0/22080, bboxRatio: 390.0/22080))   // expanded → visible
}
let vanishProbe = BubbleVisibilityProbe(
    monotonicNow: { 7000 }, canCapture: { true }, capturer: vanishCap
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
var vanishTime: TimeInterval = 8000
let vanishStats = OSAllocatedUnfairLock<BubbleCaptureOutcome>(initialState: .stats(
    BubbleAlphaStats(nonTransparentRatio: 189.0/22080, bboxRatio: 390.0/22080)
))
let nilCap: BubbleCapturer = { _ in vanishStats.withLock { $0 } }
let nilProbe = BubbleVisibilityProbe(monotonicNow: { vanishTime }, canCapture: { true }, capturer: nilCap)
let nilCand = mkw(310, layer: 3, CGRect(x: 0, y: 580, width: 345, height: 64))
nilProbe.probe(candidates: [nilCand])
let nilPump0 = Date().addingTimeInterval(5)
while nilProbe.lock.withLock({ $0.inFlight }) && Date() < nilPump0 {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
}
check("T-bv34a 前置: expanded→visible", nilProbe.visibility(for: CGWindowID(310)) == .visible, "")
// SC 捕获该窗口失败（stats nil）——但 wid 仍在当前候选集 → 保守 visible（不当收起）
vanishStats.withLock { $0 = .unavailable }
vanishTime = 8001
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
vanishTime = 8002
nilProbe.probe(candidates: [])   // 候选全部消失 → wid 310 失效为 hidden
check("T-bv34c1 候选消失→旧wid立即hidden",
      nilProbe.visibility(for: CGWindowID(310)) == .hidden, "")
// 候选重新出现 + capture nil → 保守 visible（不能滞留 hidden）
vanishTime = 8003
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
let p1capTime: TimeInterval = 9000
let p1Expanded: BubbleCapturer = { _ in
    .stats(BubbleAlphaStats(nonTransparentRatio: 189.0/22080, bboxRatio: 390.0/22080))   // expanded → visible
}
let p1Probe = BubbleVisibilityProbe(monotonicNow: { p1capTime }, canCapture: { true }, capturer: p1Expanded)
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
let p1Time2: TimeInterval = 9100
let p1SlowCap: BubbleCapturer = { _ in
    try? await Task.sleep(nanoseconds: 200_000_000)
    return .stats(BubbleAlphaStats(nonTransparentRatio: 189.0/22080, bboxRatio: 390.0/22080))   // visible
}
let p1Probe2 = BubbleVisibilityProbe(monotonicNow: { p1Time2 }, canCapture: { true }, capturer: p1SlowCap)
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
    return .stats(collapsedS)
}
let blockedProbe = BubbleVisibilityProbe(
    monotonicNow: { 10_000 },
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

// T-bv38d: production wake bridge 可从后台调用，coalescer 必须在主线程执行 tick。
let bridgeCount = OSAllocatedUnfairLock(initialState: 0)
let bridgeOnMain = OSAllocatedUnfairLock(initialState: false)
let bridgeCalledOffMain = OSAllocatedUnfairLock(initialState: false)
let bridgeGate = FollowTickCoalescer {
    bridgeCount.withLock { $0 += 1 }
    bridgeOnMain.withLock { $0 = Thread.isMainThread }
}
let bridgeCallback: @Sendable () -> Void = { bridgeGate.requestWake() }
DispatchQueue.global().async {
    bridgeCalledOffMain.withLock { $0 = !Thread.isMainThread }
    bridgeCallback()
}
let bridgeCompleted = waitPumpingMain { bridgeCount.withLock { $0 } == 1 }
check("T-bv38d wake bridge后台→主线程coalesced tick一次",
      bridgeCompleted
        && bridgeCalledOffMain.withLock { $0 }
        && bridgeCount.withLock { $0 } == 1
        && bridgeOnMain.withLock { $0 }, "")

// T-bv38e: 同一主线程忙周期内的密集 wake 应合并为最多一个 pending tick，
// 不能为每次可见性通知各排队一次过期布局。
let denseWakeCount = OSAllocatedUnfairLock(initialState: 0)
let denseWakeGate = FollowTickCoalescer {
    denseWakeCount.withLock { $0 += 1 }
}
let denseWake: @Sendable () -> Void = { denseWakeGate.requestWake() }
let denseWakeSubmitted = DispatchSemaphore(value: 0)
DispatchQueue.global().async {
    for _ in 0..<20 { denseWake() }
    denseWakeSubmitted.signal()
}
_ = denseWakeSubmitted.wait(timeout: .now() + 2)
let denseWakeCompleted = waitPumpingMain { denseWakeCount.withLock { $0 } > 0 }
RunLoop.current.run(until: Date().addingTimeInterval(0.05))
check("T-bv38e 密集wake最多一个pending tick",
      denseWakeCompleted
        && denseWakeCount.withLock { $0 } == 1,
      "ticks=\(denseWakeCount.withLock { $0 })")

// T-bv38f: tick 正在执行时可见性再变化，仅保留一次 follow-up；
// 普通 display beat 在忙期丢弃，最终可见性状态不丢。
var queuedTickItems: [DispatchWorkItem] = []
var coalescedStates: [Int] = []
var latestVisibilityState = 1
var busyGate: FollowTickCoalescer!
busyGate = FollowTickCoalescer(
    enqueue: { queuedTickItems.append($0) },
    tick: {
        coalescedStates.append(latestVisibilityState)
        if coalescedStates.count == 1 {
            latestVisibilityState = 2
            busyGate.requestWake()
            for _ in 0..<20 { busyGate.requestBeat() }
        }
    }
)
busyGate.requestWake()
check("T-bv38f1 首次wake只排队一个tick", queuedTickItems.count == 1, "queued=\(queuedTickItems.count)")
queuedTickItems.removeFirst().perform()
check("T-bv38f2 running期最终wake只保留一次follow-up",
      queuedTickItems.count == 1,
      "queued=\(queuedTickItems.count)")
queuedTickItems.removeFirst().perform()
check("T-bv38f3 重复转换最终状态不丢且无过期tick", coalescedStates == [1, 2] && queuedTickItems.isEmpty,
      "states=\(coalescedStates) queued=\(queuedTickItems.count)")

// T-sch1: stable one-shot 应锚定既定节拍。注入 30ms tick 工作后，连续 tick 启动间隔
// 仍应接近 100ms；若每次在工作完成后再排 100ms，会累积为约 130ms。
final class TestFollowTickTimer: FollowTickTimer {
    let interval: TimeInterval
    let repeats: Bool
    private let callback: () -> Void
    private(set) var invalidated = false

    init(interval: TimeInterval, repeats: Bool, callback: @escaping () -> Void) {
        self.interval = interval
        self.repeats = repeats
        self.callback = callback
    }

    func fire() {
        guard !invalidated else { return }
        callback()
    }

    func invalidate() { invalidated = true }
}

var stableClock: TimeInterval = 0
var stableStarts: [TimeInterval] = []
var stableTimers: [TestFollowTickTimer] = []
let stableCadenceScheduler = FollowTickScheduler(
    runTick: {
        stableStarts.append(stableClock)
        stableClock += 0.03
        return .stable
    },
    makeDisplayLink: { _, _ in nil },
    canUseDisplayLink: { false },
    maximumFramesPerSecond: { 60 },
    monotonicNow: { stableClock },
    makeTimer: { interval, repeats, callback in
        let timer = TestFollowTickTimer(interval: interval, repeats: repeats, callback: callback)
        stableTimers.append(timer)
        return timer
    }
)
stableCadenceScheduler.start()
stableCadenceScheduler.requestWake()
_ = waitPumpingMain { stableStarts.count == 1 }
for expectedCount in 2...4 {
    let timer = stableTimers.last!
    stableClock += timer.interval
    timer.fire()
    _ = waitPumpingMain { stableStarts.count == expectedCount }
}
stableCadenceScheduler.stop()
let stableIntervals = zip(stableStarts.dropFirst(), stableStarts).map { $0.0 - $0.1 }
check("T-sch1 stable节拍不累积tick工作耗时",
      stableIntervals.count == 3 && stableIntervals.allSatisfy { abs($0 - 0.1) < 0.000_001 },
      "intervals=\(stableIntervals)")

struct StableWakeTimingResult {
    let nextStart: TimeInterval
    let expectedLatestStart: TimeInterval
    let tickCount: Int
}

func stableWakeTiming(wakeAt: TimeInterval, workDuration: TimeInterval) -> StableWakeTimingResult {
    var clock: TimeInterval = 0
    var starts: [TimeInterval] = []
    var timers: [TestFollowTickTimer] = []
    let scheduler = FollowTickScheduler(
        runTick: {
            starts.append(clock)
            if starts.count == 2 { clock += workDuration }
            return starts.count < 3 ? .stable : .hidden
        },
        makeDisplayLink: { _, _ in nil },
        canUseDisplayLink: { false },
        maximumFramesPerSecond: { 60 },
        monotonicNow: { clock },
        makeTimer: { interval, repeats, callback in
            let timer = TestFollowTickTimer(interval: interval, repeats: repeats, callback: callback)
            timers.append(timer)
            return timer
        }
    )
    scheduler.start()
    scheduler.requestWake()
    _ = waitPumpingMain { starts.count == 1 }

    clock = wakeAt
    scheduler.requestWake()
    _ = waitPumpingMain { starts.count >= 2 }
    RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    if starts.count < 3, let timer = timers.last(where: { !$0.invalidated }) {
        clock += timer.interval
        timer.fire()
        _ = waitPumpingMain { starts.count >= 3 }
    }
    scheduler.stop()
    return StableWakeTimingResult(
        nextStart: starts.count >= 3 ? starts[2] : .infinity,
        expectedLatestStart: max(wakeAt + Follower.stableInterval, wakeAt + workDuration),
        tickCount: starts.count
    )
}

let alignedShort = stableWakeTiming(wakeAt: 0, workDuration: 0.03)
check("T-sch1c phase-aligned短工作按本tick起点deadline",
      abs(alignedShort.nextStart - alignedShort.expectedLatestStart) < 0.000_001,
      "next=\(alignedShort.nextStart) expected=\(alignedShort.expectedLatestStart)")
let offGridShort = stableWakeTiming(wakeAt: 0.04, workDuration: 0.02)
check("T-sch1d off-grid wake重置stable相位",
      abs(offGridShort.nextStart - offGridShort.expectedLatestStart) < 0.000_001,
      "next=\(offGridShort.nextStart) expected=\(offGridShort.expectedLatestStart)")
let offGridCrossOldPhase = stableWakeTiming(wakeAt: 0.09, workDuration: 0.02)
check("T-sch1e off-grid工作跨旧deadline仍不晚于本tick上限",
      offGridCrossOldPhase.nextStart <= offGridCrossOldPhase.expectedLatestStart + 0.000_001,
      "next=\(offGridCrossOldPhase.nextStart) max=\(offGridCrossOldPhase.expectedLatestStart)")
let deadlineCross = stableWakeTiming(wakeAt: 0.09, workDuration: 0.10)
check("T-sch1f 工作恰跨本tick deadline→完成后一次latest follow-up",
      deadlineCross.nextStart <= deadlineCross.expectedLatestStart + 0.000_001
        && deadlineCross.tickCount == 3,
      "next=\(deadlineCross.nextStart) max=\(deadlineCross.expectedLatestStart) ticks=\(deadlineCross.tickCount)")
let oneIntervalOverrun = stableWakeTiming(wakeAt: 0.09, workDuration: 0.15)
check("T-sch1g 工作超过一个interval→无额外完整interval等待",
      oneIntervalOverrun.nextStart <= oneIntervalOverrun.expectedLatestStart + 0.000_001
        && oneIntervalOverrun.tickCount == 3,
      "next=\(oneIntervalOverrun.nextStart) max=\(oneIntervalOverrun.expectedLatestStart) ticks=\(oneIntervalOverrun.tickCount)")
let multiIntervalOverrun = stableWakeTiming(wakeAt: 0.09, workDuration: 0.25)
check("T-sch1h 工作超过多个interval→仅一次latest follow-up无历史backlog",
      multiIntervalOverrun.nextStart <= multiIntervalOverrun.expectedLatestStart + 0.000_001
        && multiIntervalOverrun.tickCount == 3,
      "next=\(multiIntervalOverrun.nextStart) max=\(multiIntervalOverrun.expectedLatestStart) ticks=\(multiIntervalOverrun.tickCount)")

// T-sch2: repeating fallback 在 moving tick 时必须重读当前屏幕能力；60→120→60
// 均需观察并重配，不能因 activeSource 已是 repeatingTimer 就提前返回。
var fallbackFPS = 60
var fallbackTicks = 0
var fallbackTimers: [TestFollowTickTimer] = []
let fallbackScheduler = FollowTickScheduler(
    runTick: {
        fallbackTicks += 1
        return .moving
    },
    makeDisplayLink: { _, _ in nil },
    canUseDisplayLink: { false },
    maximumFramesPerSecond: { fallbackFPS },
    makeTimer: { interval, repeats, callback in
        let timer = TestFollowTickTimer(interval: interval, repeats: repeats, callback: callback)
        fallbackTimers.append(timer)
        return timer
    }
)
fallbackScheduler.start()
fallbackScheduler.requestWake()
_ = waitPumpingMain { fallbackTicks == 1 }
fallbackFPS = 120
fallbackScheduler.requestWake()
_ = waitPumpingMain { fallbackTicks == 2 }
fallbackFPS = 60
fallbackScheduler.requestWake()
_ = waitPumpingMain { fallbackTicks == 3 }
let repeatingFallbackTimers = fallbackTimers.filter { $0.repeats }
check("T-sch2a fallback moving跨屏60→120重建",
      repeatingFallbackTimers.count == 3
        && abs(repeatingFallbackTimers[0].interval - 1.0 / 60.0) < 0.000_001
        && abs(repeatingFallbackTimers[1].interval - 1.0 / 120.0) < 0.000_001
        && repeatingFallbackTimers[0].invalidated,
      "intervals=\(repeatingFallbackTimers.map { $0.interval })")
check("T-sch2b fallback moving跨屏120→60重读能力",
      repeatingFallbackTimers.count == 3
        && abs(repeatingFallbackTimers[2].interval - 1.0 / 60.0) < 0.000_001
        && repeatingFallbackTimers[1].invalidated,
      "intervals=\(repeatingFallbackTimers.map { $0.interval })")
fallbackScheduler.stop()

// T-sch3: active window display link 必须能在 screen liveness 变化时双向恢复。
// fake link 暴露与 CADisplayLink 相同的最小 add/invalidate 表面，避免依赖真实显示器。
final class TestLifecycleDisplayLink: NSObject, FollowDisplayLink {
    private(set) var added = false
    private(set) var invalidated = false

    func add(to runLoop: RunLoop, forMode mode: RunLoop.Mode) { added = true }
    func invalidate() { invalidated = true }
}

if #available(macOS 14.0, *) {
    var lifecycleHasScreen = true
    var lifecycleTicks = 0
    var lifecycleLinks: [TestLifecycleDisplayLink] = []
    var lifecycleTimers: [TestFollowTickTimer] = []
    let lifecycleScheduler = FollowTickScheduler(
        runTick: {
            lifecycleTicks += 1
            return .moving
        },
        makeDisplayLink: { _, _ in
            let link = TestLifecycleDisplayLink()
            lifecycleLinks.append(link)
            return link
        },
        canUseDisplayLink: { lifecycleHasScreen },
        maximumFramesPerSecond: { 60 },
        makeTimer: { interval, repeats, callback in
            let timer = TestFollowTickTimer(interval: interval, repeats: repeats, callback: callback)
            lifecycleTimers.append(timer)
            return timer
        }
    )
    lifecycleScheduler.start()
    lifecycleScheduler.requestWake()
    _ = waitPumpingMain { lifecycleTicks == 1 }
    check("T-sch3a screen存在→active display link",
          lifecycleLinks.count == 1 && lifecycleLinks[0].added
            && lifecycleTimers.filter { $0.repeats && !$0.invalidated }.isEmpty,
          "links=\(lifecycleLinks.count) added=\(lifecycleLinks.first?.added ?? false)")

    lifecycleHasScreen = false
    lifecycleScheduler.requestWake() // production 由 DockPanel screen-change event 走同一 wake
    _ = waitPumpingMain { lifecycleTicks == 2 }
    let fallbackAfterScreenLoss = lifecycleTimers.filter { $0.repeats && !$0.invalidated }
    check("T-sch3b active link失去screen→invalidate并启动fallback",
          lifecycleLinks[0].invalidated && fallbackAfterScreenLoss.count == 1,
          "invalidated=\(lifecycleLinks[0].invalidated) fallback=\(fallbackAfterScreenLoss.count)")

    lifecycleHasScreen = true
    lifecycleScheduler.requestWake()
    _ = waitPumpingMain { lifecycleTicks == 3 }
    check("T-sch3c screen恢复→fallback失效并重新选择display link",
          lifecycleLinks.count == 2 && lifecycleLinks[1].added
            && fallbackAfterScreenLoss.first?.invalidated == true,
          "links=\(lifecycleLinks.count) fallbackInvalidated=\(fallbackAfterScreenLoss.first?.invalidated ?? false)")
    lifecycleScheduler.stop()
} else {
    check("T-sch3a macOS14 display link生命周期（当前系统跳过）", true)
    check("T-sch3b macOS14 display link生命周期（当前系统跳过）", true)
    check("T-sch3c macOS14 display link生命周期（当前系统跳过）", true)
}

// T-sch4: stable scheduler 与生产 FollowLayoutPass/probe 必须共享同一可控时间线。
// tick 起点与实际 probe 之间存在工作偏移时，due miss 只能等待剩余 probe cadence，
// 不能重新等待完整 stable interval；in-flight 仍保持 single-flight 且不新增 backlog。
struct ProductionProbeCadenceResult {
    let probeAttempts: [TimeInterval]
    let captureStarts: [TimeInterval]
    let firedTimerIntervals: [TimeInterval]
    let remainingActiveTimerIntervals: [TimeInterval]
    let tickCount: Int
    let captureCallCount: Int
}

func productionProbeCadence(
    preProbeOffsets: [TimeInterval],
    postProbeOffsets: [TimeInterval] = [],
    keepFirstCaptureInFlight: Bool = false
) -> ProductionProbeCadenceResult {
    let clock = OSAllocatedUnfairLock(initialState: TimeInterval(0))
    var probeAttempts: [TimeInterval] = []
    var captureStarts: [TimeInterval] = []
    var lastObservedCapture = -TimeInterval.greatestFiniteMagnitude
    var timers: [TestFollowTickTimer] = []
    var firedIntervals: [TimeInterval] = []
    var ticks = 0
    let captureCalls = OSAllocatedUnfairLock(initialState: 0)
    let releaseFirstCapture = OSAllocatedUnfairLock(initialState: false)
    let mascot = mkw(603, layer: 2, petForCollapse, title: "Codex Pet Mascot Effect")
    let bubble = mkw(601, layer: 3, bubbleForCollapse)
    let capturer: BubbleCapturer = { _ in
        let call = captureCalls.withLock { count -> Int in
            count += 1
            return count
        }
        if keepFirstCaptureInFlight && call == 1 {
            while !releaseFirstCapture.withLock({ $0 }) {
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
        }
        return .stats(expandedS)
    }
    var probe: BubbleVisibilityProbe!
    let scheduler = FollowTickScheduler(
        runTick: {
            let tickIndex = ticks
            let offset = preProbeOffsets[min(tickIndex, preProbeOffsets.count - 1)]
            ticks += 1
            let probeTime = clock.withLock { value -> TimeInterval in
                value += offset
                return value
            }
            probeAttempts.append(probeTime)
            _ = FollowLayoutPass.placeDock(
                mascot: mascot,
                candidates: [mascot, bubble],
                bubbleProbe: probe,
                frameSink: { _, _ in true }
            )
            let capturedAt = probe.lock.withLock { $0.lastCaptureAt }
            if capturedAt != lastObservedCapture {
                lastObservedCapture = capturedAt
                captureStarts.append(capturedAt)
            }
            if tickIndex < postProbeOffsets.count {
                let postProbeOffset = postProbeOffsets[tickIndex]
                clock.withLock { $0 += postProbeOffset }
            }
            return .stable
        },
        makeDisplayLink: { _, _ in nil },
        canUseDisplayLink: { false },
        maximumFramesPerSecond: { 60 },
        monotonicNow: { clock.withLock { $0 } },
        stableDelayHint: { probe.takePendingRetryDelay() },
        makeTimer: { interval, repeats, callback in
            let timer = TestFollowTickTimer(interval: interval, repeats: repeats, callback: callback)
            timers.append(timer)
            return timer
        }
    )
    probe = BubbleVisibilityProbe(
        monotonicNow: { clock.withLock { $0 } },
        canCapture: { true },
        capturer: capturer
    )
    scheduler.start()
    scheduler.requestWake()
    _ = waitPumpingMain { ticks == 1 }

    for expectedTicks in 2...preProbeOffsets.count {
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        if ticks >= expectedTicks { continue }
        if !(keepFirstCaptureInFlight && expectedTicks == 2) {
            _ = waitPumpingMain { !probe.lock.withLock { $0.inFlight } }
        }
        guard let timer = timers.last(where: { !$0.invalidated }) else { break }
        firedIntervals.append(timer.interval)
        clock.withLock { $0 += timer.interval }
        timer.fire()
        _ = waitPumpingMain { ticks == expectedTicks }
        if keepFirstCaptureInFlight && expectedTicks == 2 {
            releaseFirstCapture.withLock { $0 = true }
        }
    }
    _ = waitPumpingMain { !probe.lock.withLock { $0.inFlight } }
    RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    let activeIntervals = timers.filter { !$0.invalidated }.map { $0.interval }
    scheduler.stop()
    return ProductionProbeCadenceResult(
        probeAttempts: probeAttempts,
        captureStarts: captureStarts,
        firedTimerIntervals: firedIntervals,
        remainingActiveTimerIntervals: activeIntervals,
        tickCount: ticks,
        captureCallCount: captureCalls.withLock { $0 }
    )
}

func cadenceTimesEqual(_ actual: [TimeInterval], _ expected: [TimeInterval]) -> Bool {
    actual.count == expected.count
        && zip(actual, expected).allSatisfy { abs($0 - $1) < 0.000_001 }
}

let alignedProbeCadence = productionProbeCadence(preProbeOffsets: [0, 0])
check("T-sch4a phase-aligned生产probe保持0.1s capture cadence",
      cadenceTimesEqual(alignedProbeCadence.captureStarts, [0, 0.1])
        && alignedProbeCadence.tickCount == 2,
      "attempts=\(alignedProbeCadence.probeAttempts) captures=\(alignedProbeCadence.captureStarts)")

let offsetProbeCadence = productionProbeCadence(preProbeOffsets: [0.02, 0.01, 0])
check("T-sch4b .020→.110 due miss仅等待剩余probe delay",
      cadenceTimesEqual(offsetProbeCadence.probeAttempts, [0.02, 0.11, 0.12])
        && cadenceTimesEqual(offsetProbeCadence.captureStarts, [0.02, 0.12])
        && offsetProbeCadence.firedTimerIntervals.count == 2
        && abs(offsetProbeCadence.firedTimerIntervals[1] - 0.01) < 0.000_001
        && offsetProbeCadence.tickCount == 3
        && offsetProbeCadence.remainingActiveTimerIntervals.count == 1,
      "attempts=\(offsetProbeCadence.probeAttempts) captures=\(offsetProbeCadence.captureStarts) "
        + "fired=\(offsetProbeCadence.firedTimerIntervals) active=\(offsetProbeCadence.remainingActiveTimerIntervals)")

let consumedProbeDelay = productionProbeCadence(
    preProbeOffsets: [0.02, 0.01, 0],
    postProbeOffsets: [0, 0.02, 0]
)
check("T-sch4c probe后工作跨due→完成后立即latest-only",
      cadenceTimesEqual(consumedProbeDelay.probeAttempts, [0.02, 0.11, 0.13])
        && cadenceTimesEqual(consumedProbeDelay.captureStarts, [0.02, 0.13])
        && consumedProbeDelay.firedTimerIntervals.count == 1
        && consumedProbeDelay.tickCount == 3
        && consumedProbeDelay.remainingActiveTimerIntervals.count == 1,
      "attempts=\(consumedProbeDelay.probeAttempts) captures=\(consumedProbeDelay.captureStarts) "
        + "fired=\(consumedProbeDelay.firedTimerIntervals) active=\(consumedProbeDelay.remainingActiveTimerIntervals)")

let inFlightProbeCadence = productionProbeCadence(
    preProbeOffsets: [0.02, 0.01],
    keepFirstCaptureInFlight: true
)
check("T-sch4d in-flight不留hint、不加retry source且无queued backlog",
      cadenceTimesEqual(inFlightProbeCadence.probeAttempts, [0.02, 0.11])
        && cadenceTimesEqual(inFlightProbeCadence.captureStarts, [0.02])
        && inFlightProbeCadence.captureCallCount == 1
        && inFlightProbeCadence.tickCount == 2
        && inFlightProbeCadence.remainingActiveTimerIntervals.count == 1
        && abs((inFlightProbeCadence.remainingActiveTimerIntervals.first ?? 0) - 0.09) < 0.000_001,
      "attempts=\(inFlightProbeCadence.probeAttempts) captures=\(inFlightProbeCadence.captureStarts) "
        + "calls=\(inFlightProbeCadence.captureCallCount) ticks=\(inFlightProbeCadence.tickCount) "
        + "active=\(inFlightProbeCadence.remainingActiveTimerIntervals)")

let hintClock = OSAllocatedUnfairLock(initialState: TimeInterval(13_000))
let hintCanCapture = OSAllocatedUnfairLock(initialState: true)
let hintProbe = BubbleVisibilityProbe(
    monotonicNow: { hintClock.withLock { $0 } },
    canCapture: { hintCanCapture.withLock { $0 } },
    capturer: { _ in .stats(expandedS) }
)
let hintCandidate = mkw(701, layer: 3, bubbleForCollapse)
hintProbe.probe(candidates: [hintCandidate])
_ = waitPumpingMain { !hintProbe.lock.withLock { $0.inFlight } }
hintClock.withLock { $0 = 13_000.05 }
hintProbe.probe(candidates: [hintCandidate])
hintProbe.reset()
let hintAfterReset = hintProbe.takePendingRetryDelay()

hintClock.withLock { $0 = 13_000.11 }
hintProbe.probe(candidates: [hintCandidate])
_ = waitPumpingMain { !hintProbe.lock.withLock { $0.inFlight } }
hintClock.withLock { $0 = 13_000.15 }
hintProbe.probe(candidates: [hintCandidate])
hintProbe.probe(candidates: [])
let hintAfterEmpty = hintProbe.takePendingRetryDelay()

hintClock.withLock { $0 = 13_000.22 }
hintProbe.probe(candidates: [hintCandidate])
_ = waitPumpingMain { !hintProbe.lock.withLock { $0.inFlight } }
hintClock.withLock { $0 = 13_000.26 }
hintProbe.probe(candidates: [hintCandidate])
hintCanCapture.withLock { $0 = false }
hintProbe.probe(candidates: [hintCandidate])
let hintAfterPermissionLoss = hintProbe.takePendingRetryDelay()
check("T-sch4e reset/空候选/权限false均不残留retry hint",
      hintAfterReset == nil && hintAfterEmpty == nil && hintAfterPermissionLoss == nil,
      "reset=\(String(describing: hintAfterReset)) empty=\(String(describing: hintAfterEmpty)) "
        + "permission=\(String(describing: hintAfterPermissionLoss))")

// T-sch4f (v5 source guard): cadence 生产文件不得引入墙上时间输入。
// break-loop 4 结论：局部 wall fake 未被 scheduler/probe 消费，不能证明墙钟独立性；
// cadence 生产契约本就不接受墙钟，因此用可执行 source/API guard 直接扫描
// cadence-owning 生产文件（scheduler/probe/Follower 时间语义/插值时钟域），
// 以及生产默认单调时钟 provider 所在的 main.swift（followMonotonicNow 注入上述全部消费者；
// 该闭包改用墙钟时，注入行为测试不会失败，必须由本 guard 拦截），
// 出现 Date/CFAbsoluteTime 等墙钟 API 即失败。不为测试向生产添加第二时钟。
let cadenceGuardRepoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let cadenceGuardFiles = [
    "Sources/PetDock/FollowTickPlan.swift",
    "Sources/PetDock/BubbleVisibility.swift",
    "Sources/PetDock/Follower.swift",
    "Sources/PetDock/DockPanel.swift",
    "Sources/PetDock/main.swift"
]
let wallClockAPIPattern = try! NSRegularExpression(
    pattern: "\\bDate\\b|\\bNSDate\\b|CFAbsoluteTime|timeIntervalSince|DispatchWallTime|gettimeofday"
)
var cadenceGuardViolations: [String] = []
var cadenceGuardReadFiles = 0
for cadenceGuardRelativePath in cadenceGuardFiles {
    let cadenceGuardURL = cadenceGuardRepoRoot.appendingPathComponent(cadenceGuardRelativePath)
    guard let cadenceGuardSource = try? String(contentsOf: cadenceGuardURL, encoding: .utf8) else {
        cadenceGuardViolations.append("\(cadenceGuardRelativePath): unreadable")
        continue
    }
    cadenceGuardReadFiles += 1
    let cadenceGuardRange = NSRange(cadenceGuardSource.startIndex..., in: cadenceGuardSource)
    if wallClockAPIPattern.firstMatch(in: cadenceGuardSource, range: cadenceGuardRange) != nil {
        cadenceGuardViolations.append(cadenceGuardRelativePath)
    }
}
check("T-sch4f cadence owner源码无墙钟API（source guard）",
      cadenceGuardReadFiles == cadenceGuardFiles.count && cadenceGuardViolations.isEmpty,
      "read=\(cadenceGuardReadFiles)/\(cadenceGuardFiles.count) violations=\(cadenceGuardViolations.joined(separator: ", "))")

// 实际 panel frame 断言 helper：setFrame 有像素对齐，位置容差 < 1.0（AppKit 约定），尺寸精确。
func dockFrameNear(_ actual: NSRect, _ expected: NSRect) -> Bool {
    abs(actual.origin.x - expected.origin.x) < 1.0
        && abs(actual.origin.y - expected.origin.y) < 1.0
        && actual.width == expected.width
        && actual.height == expected.height
}

// T-bv39: 生产 FollowLayoutPass 必须贯穿候选分类→probe cache→可见障碍→实际 DockPanel frame 所有者。
// 已有 stable one-shot 尚未触发时，visible→hidden wake 应提前执行且只执行一次完整 tick。
var transitionTime: TimeInterval = 11_000
var transitionClock: TimeInterval = 0
let transitionStats = OSAllocatedUnfairLock<BubbleCaptureOutcome>(initialState: .stats(expandedS))
let transitionTicks = OSAllocatedUnfairLock(initialState: 0)
let transitionOnMain = OSAllocatedUnfairLock(initialState: false)
let transitionObstacleCounts = OSAllocatedUnfairLock(initialState: [Int]())
var transitionTimers: [TestFollowTickTimer] = []
let transitionCap: BubbleCapturer = { _ in transitionStats.withLock { $0 } }
var transitionProbe: BubbleVisibilityProbe!
let transitionMascot = mkw(503, layer: 2, petForCollapse, title: "Codex Pet Mascot Effect")
let transitionCandidate = mkw(501, layer: 3, bubbleForCollapse)
let transitionDock = DockPanel()
let transitionDockBaseX = petForCollapse.origin.x + (petForCollapse.width - 200) / 2
let transitionAvoidAppKitFrame = Geometry.appKitRectFromQuartz(
    CGRect(x: transitionDockBaseX, y: avoidY, width: 200, height: 48))
let transitionBaseAppKitFrame = Geometry.appKitRectFromQuartz(
    CGRect(x: transitionDockBaseX, y: baseY, width: 200, height: 48))
let transitionScheduler = FollowTickScheduler(
    runTick: {
        transitionTicks.withLock { $0 += 1 }
        transitionOnMain.withLock { $0 = Thread.isMainThread }
        let placed = FollowLayoutPass.placeDock(
            mascot: transitionMascot,
            candidates: [transitionMascot, transitionCandidate],
            bubbleProbe: transitionProbe,
            frameSink: { pet, obstacles in
                transitionObstacleCounts.withLock { $0.append(obstacles.count) }
                return transitionDock.placeBelow(
                    petQuartzRect: pet,
                    avoiding: obstacles,
                    visibleScreen: nil,
                    movementChanged: false,
                    monotonicNow: transitionTime
                )
            }
        )
        return placed ? .stable : .hidden
    },
    makeDisplayLink: { _, _ in nil },
    canUseDisplayLink: { false },
    maximumFramesPerSecond: { 60 },
    monotonicNow: { transitionClock },
    makeTimer: { interval, repeats, callback in
        let timer = TestFollowTickTimer(interval: interval, repeats: repeats, callback: callback)
        transitionTimers.append(timer)
        return timer
    }
)
transitionProbe = BubbleVisibilityProbe(
    monotonicNow: { transitionTime },
    canCapture: { true },
    capturer: transitionCap,
    onVisibilityChange: transitionScheduler.visibilityChangeCallback
)
transitionProbe.probe(candidates: [transitionCandidate])
let transitionPump0 = Date().addingTimeInterval(5)
while transitionProbe.lock.withLock({ $0.inFlight }) && Date() < transitionPump0 {
    RunLoop.current.run(until: Date().addingTimeInterval(0.01))
}
check("T-bv39a 初始visible结果不调度", transitionTicks.withLock { $0 } == 0, "")
transitionScheduler.start()
transitionScheduler.requestWake()
_ = waitPumpingMain { transitionTicks.withLock { $0 } == 1 }
let stableTimerBeforeWake = transitionTimers.last
check("T-bv39b 生产布局链初始visible→实际panel避让frame",
      dockFrameNear(transitionDock.frame, transitionAvoidAppKitFrame)
        && transitionObstacleCounts.withLock { $0 } == [1]
        && stableTimerBeforeWake?.repeats == false,
      "frame=\(transitionDock.frame) expected=\(transitionAvoidAppKitFrame) obstacles=\(transitionObstacleCounts.withLock { $0 })")

transitionStats.withLock { $0 = .stats(collapsedS) }
transitionTime = 11_001
transitionProbe.probe(candidates: [transitionCandidate])
let transitionPump1 = Date().addingTimeInterval(5)
while (transitionProbe.lock.withLock({ $0.inFlight })
       || transitionTicks.withLock({ $0 }) < 2) && Date() < transitionPump1 {
    RunLoop.current.run(until: Date().addingTimeInterval(0.01))
}
RunLoop.current.run(until: Date().addingTimeInterval(0.02))
check("T-bv39c stable source未到期时wake仅提前执行一次生产tick",
      transitionTicks.withLock { $0 } == 2
        && transitionOnMain.withLock { $0 }
        && stableTimerBeforeWake?.invalidated == true,
      "ticks=\(transitionTicks.withLock { $0 })")
check("T-bv39d pet不变+生产链hidden cache→实际panel无障碍并复位基础frame",
      dockFrameNear(transitionDock.frame, transitionBaseAppKitFrame)
        && transitionObstacleCounts.withLock { $0 } == [1, 0],
      "frame=\(transitionDock.frame) expected=\(transitionBaseAppKitFrame) obstacles=\(transitionObstacleCounts.withLock { $0 })")

transitionTime = 11_002
transitionProbe.probe(candidates: [transitionCandidate])
let transitionPump2 = Date().addingTimeInterval(5)
while transitionProbe.lock.withLock({ $0.inFlight }) && Date() < transitionPump2 {
    RunLoop.current.run(until: Date().addingTimeInterval(0.01))
}
check("T-bv39e hidden不变不重复调度", transitionTicks.withLock { $0 } == 2, "")
transitionScheduler.stop()

// T-bv39f (v4 regression): CG 候选仍短暂残留，但一次成功取得的 SCK 清单已明确
// 不含目标 wid。typed outcome 必须把它和 generic unavailable 分开传到布局策略。
let redCaptureOutcome = OSAllocatedUnfairLock<BubbleCaptureOutcome>(initialState: .stats(expandedS))
let redCapture: BubbleCapturer = { _ in redCaptureOutcome.withLock { $0 } }
var redTime: TimeInterval = 12_100
let redProbe = BubbleVisibilityProbe(
    monotonicNow: { redTime }, canCapture: { true }, capturer: redCapture
)
let redMascot = mkw(513, layer: 2, petForCollapse, title: "Codex Pet Mascot Effect")
let redCandidate = mkw(511, layer: 3, bubbleForCollapse)
func redLayoutY() -> (obstacles: Int, y: CGFloat?) {
    var result: (Int, CGFloat?) = (0, nil)
    _ = FollowLayoutPass.placeDock(
        mascot: redMascot,
        candidates: [redMascot, redCandidate],
        bubbleProbe: redProbe,
        frameSink: { pet, obstacles in
            result.0 = obstacles.count
            result.1 = Geometry.safeDockFrame(
                pet: pet, avoiding: obstacles,
                dockSize: dockSizeBV, gap: gapBV, screen: nil
            ).frame?.origin.y
            return result.1 != nil
        }
    )
    return result
}
redProbe.probe(candidates: [redCandidate])
_ = waitPumpingMain { !redProbe.lock.withLock { $0.inFlight } }
let redExpandedLayout = redLayoutY()
check("T-bv39f1 red前置: same-WID expanded仍是障碍",
      redProbe.visibility(for: redCandidate.wid) == .visible
        && redExpandedLayout.obstacles == 1
        && redExpandedLayout.y == avoidY,
      "visibility=\(redProbe.visibility(for: redCandidate.wid)) obstacles=\(redExpandedLayout.obstacles) y=\(String(describing: redExpandedLayout.y))")

redCaptureOutcome.withLock { $0 = .targetMissing }
redTime += 1
redProbe.probe(candidates: [redCandidate])
_ = waitPumpingMain { !redProbe.lock.withLock { $0.inFlight } }
let redMissingLayout = redLayoutY()
check("T-bv39f2 RED targetMissing→same-WID obstacle失效并回基础位",
      redProbe.visibility(for: redCandidate.wid) == .hidden
        && redMissingLayout.obstacles == 0
        && redMissingLayout.y == baseY,
      "visibility=\(redProbe.visibility(for: redCandidate.wid)) obstacles=\(redMissingLayout.obstacles) y=\(String(describing: redMissingLayout.y))")

// 相邻安全态：首次观察即 targetMissing，以及已有观察后的 generic unavailable，
// 都必须继续 conservative visible。
redProbe.reset()
redCaptureOutcome.withLock { $0 = .targetMissing }
redTime += 1
redProbe.probe(candidates: [redCandidate])
_ = waitPumpingMain { !redProbe.lock.withLock { $0.inFlight } }
check("T-bv39f3 未成功观察过的 targetMissing→保守visible",
      redProbe.visibility(for: redCandidate.wid) == .visible, "")

redProbe.reset()
redCaptureOutcome.withLock { $0 = .stats(expandedS) }
redTime += 1
redProbe.probe(candidates: [redCandidate])
_ = waitPumpingMain { !redProbe.lock.withLock { $0.inFlight } }
redCaptureOutcome.withLock { $0 = .unavailable }
redTime += 1
redProbe.probe(candidates: [redCandidate])
_ = waitPumpingMain { !redProbe.lock.withLock { $0.inFlight } }
check("T-bv39f4 已观察后 generic unavailable→保守visible",
      redProbe.visibility(for: redCandidate.wid) == .visible, "")

// 候选消失必须结束成功观察生命周期；同一 WID 重现后的首次 targetMissing
// 不能继承旧 generation 的 hidden 资格。重复 full hide/show 也必须收敛。
redProbe.probe(candidates: [])
redTime += 1
redCaptureOutcome.withLock { $0 = .targetMissing }
redProbe.probe(candidates: [redCandidate])
_ = waitPumpingMain { !redProbe.lock.withLock { $0.inFlight } }
let reappearedMissing = redLayoutY()
check("T-bv39f5a 候选消失后同WID首次targetMissing仍保守visible",
      redProbe.visibility(for: redCandidate.wid) == .visible
        && reappearedMissing.obstacles == 1
        && reappearedMissing.y == avoidY, "")

var repeatedTransitionsOK = true
for cycle in 0..<3 {
    redCaptureOutcome.withLock { $0 = .stats(expandedS) }
    redTime += 1
    redProbe.probe(candidates: [redCandidate])
    _ = waitPumpingMain { !redProbe.lock.withLock { $0.inFlight } }
    let shown = redLayoutY()
    redCaptureOutcome.withLock { $0 = .targetMissing }
    redTime += 1
    redProbe.probe(candidates: [redCandidate])
    _ = waitPumpingMain { !redProbe.lock.withLock { $0.inFlight } }
    let hidden = redLayoutY()
    repeatedTransitionsOK = repeatedTransitionsOK
        && shown.obstacles == 1 && shown.y == avoidY
        && hidden.obstacles == 0 && hidden.y == baseY
    if cycle < 2 { redProbe.probe(candidates: []) }
}
check("T-bv39f5b repeated full hide/show无stale obstacle且回基础位", repeatedTransitionsOK, "")

// T-bv42 (v5): authoritative targetMissing 必须穿过真实生产组合：
// onVisibilityChange → FollowTickScheduler coalescer → 完整 FollowLayoutPass → 实际 DockPanel.placeBelow/frame。
// 起点 .stats(expanded) 且已排好未到期的 stable one-shot；targetMissing 后只允许一次提前 tick、
// 旧 stable timer 失效、最终零障碍且真实 panel frame 回基础位；hidden 不变不得重复 wake。
var missTime: TimeInterval = 15_000
var missClock: TimeInterval = 0
let missDock = DockPanel()
let missOutcome = OSAllocatedUnfairLock<BubbleCaptureOutcome>(initialState: .stats(expandedS))
let missCap: BubbleCapturer = { _ in missOutcome.withLock { $0 } }
let missTicks = OSAllocatedUnfairLock(initialState: 0)
let missOnMain = OSAllocatedUnfairLock(initialState: false)
let missObstacleCounts = OSAllocatedUnfairLock(initialState: [Int]())
var missTimers: [TestFollowTickTimer] = []
let missMascot = mkw(523, layer: 2, petForCollapse, title: "Codex Pet Mascot Effect")
let missCandidate = mkw(521, layer: 3, bubbleForCollapse)
let missDockBaseX = petForCollapse.origin.x + (petForCollapse.width - 200) / 2
let missAvoidAppKitFrame = Geometry.appKitRectFromQuartz(
    CGRect(x: missDockBaseX, y: avoidY, width: 200, height: 48))
let missBaseAppKitFrame = Geometry.appKitRectFromQuartz(
    CGRect(x: missDockBaseX, y: baseY, width: 200, height: 48))
var missProbe: BubbleVisibilityProbe!
let missScheduler = FollowTickScheduler(
    runTick: {
        missTicks.withLock { $0 += 1 }
        missOnMain.withLock { $0 = Thread.isMainThread }
        let placed = FollowLayoutPass.placeDock(
            mascot: missMascot,
            candidates: [missMascot, missCandidate],
            bubbleProbe: missProbe,
            frameSink: { pet, obstacles in
                missObstacleCounts.withLock { $0.append(obstacles.count) }
                return missDock.placeBelow(
                    petQuartzRect: pet,
                    avoiding: obstacles,
                    visibleScreen: nil,
                    movementChanged: false,
                    monotonicNow: missTime
                )
            }
        )
        return placed ? .stable : .hidden
    },
    makeDisplayLink: { _, _ in nil },
    canUseDisplayLink: { false },
    maximumFramesPerSecond: { 60 },
    monotonicNow: { missClock },
    stableDelayHint: { missProbe.takePendingRetryDelay() },
    makeTimer: { interval, repeats, callback in
        let timer = TestFollowTickTimer(interval: interval, repeats: repeats, callback: callback)
        missTimers.append(timer)
        return timer
    }
)
missProbe = BubbleVisibilityProbe(
    monotonicNow: { missTime },
    canCapture: { true },
    capturer: missCap,
    onVisibilityChange: missScheduler.visibilityChangeCallback
)
missProbe.probe(candidates: [missCandidate])
_ = waitPumpingMain { !missProbe.lock.withLock { $0.inFlight } }
check("T-bv42a 初始targetMissing链前置: expanded结果不调度", missTicks.withLock { $0 } == 0, "")
missScheduler.start()
missScheduler.requestWake()
_ = waitPumpingMain { missTicks.withLock { $0 } == 1 }
let missStableTimerBeforeWake = missTimers.last
check("T-bv42b expanded→实际panel避让frame+未到期stable one-shot",
      dockFrameNear(missDock.frame, missAvoidAppKitFrame)
        && missObstacleCounts.withLock { $0 } == [1]
        && missStableTimerBeforeWake?.repeats == false
        && missStableTimerBeforeWake?.invalidated == false,
      "frame=\(missDock.frame) expected=\(missAvoidAppKitFrame) obstacles=\(missObstacleCounts.withLock { $0 })")

missOutcome.withLock { $0 = .targetMissing }
missTime = 15_001
missProbe.probe(candidates: [missCandidate])
let missWakePump = Date().addingTimeInterval(5)
while (missProbe.lock.withLock({ $0.inFlight })
       || missTicks.withLock({ $0 }) < 2) && Date() < missWakePump {
    RunLoop.current.run(until: Date().addingTimeInterval(0.01))
}
RunLoop.current.run(until: Date().addingTimeInterval(0.02))
let missActiveTimersAfterWake = missTimers.filter { !$0.invalidated }
check("T-bv42c targetMissing→callback→coalescer仅一次提前完整tick",
      missTicks.withLock { $0 } == 2
        && missOnMain.withLock { $0 }
        && missStableTimerBeforeWake?.invalidated == true
        && missActiveTimersAfterWake.count == 1
        && missActiveTimersAfterWake.first?.repeats == false,
      "ticks=\(missTicks.withLock { $0 }) onMain=\(missOnMain.withLock { $0 }) "
        + "oldStableInvalidated=\(missStableTimerBeforeWake?.invalidated ?? false) "
        + "activeTimers=\(missActiveTimersAfterWake.count)")
check("T-bv42d 零障碍+实际DockPanel.frame回基础位",
      missObstacleCounts.withLock { $0 } == [1, 0]
        && dockFrameNear(missDock.frame, missBaseAppKitFrame),
      "frame=\(missDock.frame) expected=\(missBaseAppKitFrame) obstacles=\(missObstacleCounts.withLock { $0 })")

missTime = 15_002
missProbe.probe(candidates: [missCandidate])
_ = waitPumpingMain { !missProbe.lock.withLock { $0.inFlight } }
check("T-bv42e hidden不变不重复wake", missTicks.withLock { $0 } == 2, "ticks=\(missTicks.withLock { $0 })")
missScheduler.stop()

// T-re (v6 runtime evidence): 默认关闭、QA 显式启用的匿名聚合诊断。
// plumbing-only 声明：本节的 fake capturer / fixture 注入只证明
// “每个事件被生产对象消费并计数”，不证明真实图3 full-hide 产生同类 trigger；
// 症状结论必须等待同一候选的真机脱敏采样，不得据此宣称 image3 已修复。

// T-re1: 启用参数解析（缺省/非法 → 关闭；QA 显式提供候选 SHA → 启用）
check("T-re1a 无flag→disabled", RuntimeEvidenceFlag.parseCandidateSHA([]) == nil, "")
check("T-re1b 恰好40位小写hex→enabled",
      RuntimeEvidenceFlag.parseCandidateSHA(["--runtime-evidence=0123456789abcdef0123456789abcdef01234567"])
        == "0123456789abcdef0123456789abcdef01234567", "")
check("T-re1c 缩写与边界长度(7/39/41/64)→disabled",
      RuntimeEvidenceFlag.parseCandidateSHA(["-other", "--runtime-evidence=" + String(repeating: "a", count: 7)]) == nil
        && RuntimeEvidenceFlag.parseCandidateSHA(["--runtime-evidence=" + String(repeating: "a", count: 39)]) == nil
        && RuntimeEvidenceFlag.parseCandidateSHA(["--runtime-evidence=" + String(repeating: "a", count: 41)]) == nil
        && RuntimeEvidenceFlag.parseCandidateSHA(["--runtime-evidence=" + String(repeating: "a", count: 64)]) == nil, "")
check("T-re1d 大写/非hex/裸flag→disabled",
      RuntimeEvidenceFlag.parseCandidateSHA(["--runtime-evidence=" + String(repeating: "ABCDEF", count: 6) + "ABCD"]) == nil
        && RuntimeEvidenceFlag.parseCandidateSHA(["--runtime-evidence=" + String(repeating: "g", count: 40)]) == nil
        && RuntimeEvidenceFlag.parseCandidateSHA(["--runtime-evidence"]) == nil, "")
check("T-re1e 全角Unicode hex→disabled（ASCII-only合同）",
      RuntimeEvidenceFlag.parseCandidateSHA(["--runtime-evidence=" + String(repeating: "０", count: 40)]) == nil
        && RuntimeEvidenceFlag.parseCandidateSHA(["--runtime-evidence=" + String(repeating: "ａ", count: 40)]) == nil, "")

// T-re2/T-re3: 白名单序列化、禁止字段、record 不落盘、flush 私有权限
let reSHA = "0123456789abcdef0123456789abcdef01234567"
let reRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
    "pd-runtime-evidence-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
try? FileManager.default.removeItem(at: reRoot)
let reOutputURL = reRoot.appendingPathComponent(runtimeEvidenceOutputFileName)
let reCollector = makeRuntimeEvidenceRecorderForTesting(candidateSHA: reSHA, outputURL: reOutputURL, flushNow: { 100 })
reCollector.recordLayoutTick(bubbleObstacles: 1, controlObstacles: 0, visibleObstacles: 1)
reCollector.recordCapture(kind: .stats, visibility: .visible)
reCollector.recordLayoutTick(bubbleObstacles: 1, controlObstacles: 0, visibleObstacles: 0)
reCollector.recordCapture(kind: .targetMissing, visibility: .hidden)
reCollector.recordIdentityChange()
reCollector.recordWakeCallback()
reCollector.recordDockDyBucket(.upTo64)
reCollector.recordDockDyBucket(.base)
let reSnapshot = reCollector.snapshot()
let reExpectedKeys: Set<String> = [
    "schema", "candidateSHA", "tickCount",
    "bubbleObstacleCount", "controlObstacleCount", "visibleObstacleCount",
    "lastBubbleObstacleCount", "lastControlObstacleCount", "lastVisibleObstacleCount",
    "captureStatsCount", "captureTargetMissingCount", "captureUnavailableCount",
    "visibilityVisibleCount", "visibilityHiddenCount",
    "identityChangeCount", "wakeCallbackCount",
    "dockDyBaseCount", "dockDyUpTo32Count", "dockDyUpTo64Count", "dockDyAbove64Count",
    "lastDockDyBucket",
]
check("T-re2a 快照key集合=白名单（无多余/缺失）",
      Set(reSnapshot.keys) == reExpectedKeys,
      "extra=\(Set(reSnapshot.keys).subtracting(reExpectedKeys).sorted()) "
        + "missing=\(reExpectedKeys.subtracting(reSnapshot.keys).sorted())")
check("T-re2b 聚合计数正确",
      (reSnapshot["tickCount"] as? Int) == 2
        && (reSnapshot["bubbleObstacleCount"] as? Int) == 2
        && (reSnapshot["captureStatsCount"] as? Int) == 1
        && (reSnapshot["captureTargetMissingCount"] as? Int) == 1
        && (reSnapshot["visibilityVisibleCount"] as? Int) == 1
        && (reSnapshot["visibilityHiddenCount"] as? Int) == 1
        && (reSnapshot["identityChangeCount"] as? Int) == 1
        && (reSnapshot["wakeCallbackCount"] as? Int) == 1
        && (reSnapshot["dockDyUpTo64Count"] as? Int) == 1
        && (reSnapshot["dockDyBaseCount"] as? Int) == 1
        && (reSnapshot["lastDockDyBucket"] as? String) == DockDyBucket.base.rawValue, "")
let reJSONText = String(
    data: try! JSONSerialization.data(withJSONObject: reSnapshot, options: [.sortedKeys]),
    encoding: .utf8)!
let reForbiddenTokens = ["owner", "title", "windowID", "wid", "pid", "screen",
                         "alpha", "color", "image", "bounds", "process"]
check("T-re2c JSON文本无禁止字段token", reForbiddenTokens.allSatisfy { !reJSONText.contains($0) }, reJSONText)
check("T-re3a 仅record不创建诊断文件", !FileManager.default.fileExists(atPath: reOutputURL.path), "")
reCollector.flush()
let reFileMode = (try! FileManager.default.attributesOfItem(atPath: reOutputURL.path)[.posixPermissions] as! NSNumber).uint16Value & 0o777
let reDirMode = (try! FileManager.default.attributesOfItem(atPath: reRoot.path)[.posixPermissions] as! NSNumber).uint16Value & 0o777
let reWritten = try! JSONSerialization.jsonObject(with: Data(contentsOf: reOutputURL)) as! [String: Any]
check("T-re3b flush落盘：目录0700/文件0600/内容=快照",
      reFileMode == 0o600 && reDirMode == 0o700
        && (reWritten["candidateSHA"] as? String) == reSHA
        && (reWritten["tickCount"] as? Int) == 2,
      "file=0\(String(reFileMode, radix: 8)) dir=0\(String(reDirMode, radix: 8))")

// T-re4: symlink fail-closed —— 外部链接目标绝不接收诊断内容
let reEvilTarget = reRoot.appendingPathComponent("evil-target.json")
try! "SENTINEL".data(using: .utf8)!.write(to: reEvilTarget)
let reLinkURL = reRoot.appendingPathComponent("evidence-link.json")
try! FileManager.default.createSymbolicLink(at: reLinkURL, withDestinationURL: reEvilTarget)
let reLinkCollector = makeRuntimeEvidenceRecorderForTesting(candidateSHA: reSHA, outputURL: reLinkURL, flushNow: { 120 })
reLinkCollector.recordLayoutTick(bubbleObstacles: 0, controlObstacles: 0, visibleObstacles: 0)
reLinkCollector.flush()
let reEvilContent = try! String(contentsOf: reEvilTarget, encoding: .utf8)
// 注意：URL 实例会缓存 resourceValues（createSymbolicLink 后读旧值），
// 断言必须走 attributesOfItem 取文件系统真实状态。
let reLinkType = try! FileManager.default.attributesOfItem(atPath: reLinkURL.path)[.type] as? FileAttributeType
let reLinkReplacedWithEvidence = reLinkType == .typeRegular
    && ((try? JSONSerialization.jsonObject(with: Data(contentsOf: reLinkURL))) as? [String: Any]) != nil
check("T-re4 symlink目标不被写入（链接本体被安全替换）",
      reEvilContent == "SENTINEL" && reLinkReplacedWithEvidence,
      "evil=\(reEvilContent) linkType=\(reLinkType?.rawValue ?? "nil")")

// T-re5: 生产组合消费链 —— probe/FollowLayoutPass/DockPanel 各自消费事件并计数（plumbing-only）
var rePTime: TimeInterval = 17_000
var rePClock: TimeInterval = 0
let rePDock = DockPanel()
let rePOutcome = OSAllocatedUnfairLock<BubbleCaptureOutcome>(initialState: .stats(expandedS))
let rePCap: BubbleCapturer = { _ in rePOutcome.withLock { $0 } }
let rePSHA = "1234567890abcdef1234567890abcdef12345678"
let rePROot = FileManager.default.temporaryDirectory.appendingPathComponent(
    "pd-runtime-evidence-prod-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
try? FileManager.default.removeItem(at: rePROot)
let rePCollector = makeRuntimeEvidenceRecorderForTesting(
    candidateSHA: rePSHA,
    outputURL: rePROot.appendingPathComponent(runtimeEvidenceOutputFileName),
    flushNow: { rePTime })
let rePMascot = mkw(563, layer: 2, petForCollapse, title: "Codex Pet Mascot Effect")
let rePCandidate = mkw(561, layer: 3, bubbleForCollapse)
let rePBaseX = petForCollapse.origin.x + (petForCollapse.width - 200) / 2
let rePBaseAppKitFrame = Geometry.appKitRectFromQuartz(CGRect(x: rePBaseX, y: baseY, width: 200, height: 48))
let rePAvoidAppKitFrame = Geometry.appKitRectFromQuartz(CGRect(x: rePBaseX, y: avoidY, width: 200, height: 48))
var rePProbe: BubbleVisibilityProbe!
let rePScheduler = FollowTickScheduler(
    runTick: {
        FollowLayoutPass.placeDock(
            mascot: rePMascot,
            candidates: [rePMascot, rePCandidate],
            bubbleProbe: rePProbe,
            evidence: rePCollector,
            frameSink: { pet, obstacles in
                rePDock.placeBelow(
                    petQuartzRect: pet,
                    avoiding: obstacles,
                    visibleScreen: nil,
                    movementChanged: false,
                    monotonicNow: rePTime,
                    evidence: rePCollector
                )
            }
        ) ? .stable : .hidden
    },
    makeDisplayLink: { _, _ in nil },
    canUseDisplayLink: { false },
    maximumFramesPerSecond: { 60 },
    monotonicNow: { rePClock },
    makeTimer: { interval, repeats, callback in
        TestFollowTickTimer(interval: interval, repeats: repeats, callback: callback)
    }
)
rePProbe = BubbleVisibilityProbe(
    monotonicNow: { rePTime },
    canCapture: { true },
    capturer: rePCap,
    evidence: rePCollector,
    onVisibilityChange: rePScheduler.visibilityChangeCallback
)
rePProbe.probe(candidates: [rePCandidate])
_ = waitPumpingMain { !rePProbe.lock.withLock { $0.inFlight } }
let rePAfterFirstCapture = rePCollector.snapshot()
check("T-re5a probe消费fake capturer→outcome/visibility/identity计数",
      (rePAfterFirstCapture["captureStatsCount"] as? Int) == 1
        && (rePAfterFirstCapture["visibilityVisibleCount"] as? Int) == 1
        && (rePAfterFirstCapture["identityChangeCount"] as? Int) == 1,
      "identity=\(rePAfterFirstCapture["identityChangeCount"] ?? -1)")
rePScheduler.start()
rePScheduler.requestWake()
_ = waitPumpingMain { (rePCollector.snapshot()["tickCount"] as? Int ?? 0) == 1 }
let rePAfterTick1 = rePCollector.snapshot()
check("T-re5b FollowLayoutPass/DockPanel消费→kind/visible/dy计数+实际避让frame",
      (rePAfterTick1["tickCount"] as? Int) == 1
        && (rePAfterTick1["bubbleObstacleCount"] as? Int) == 1
        && (rePAfterTick1["controlObstacleCount"] as? Int) == 0
        && (rePAfterTick1["lastVisibleObstacleCount"] as? Int) == 1
        && (rePAfterTick1["dockDyUpTo64Count"] as? Int) == 1
        && (rePAfterTick1["lastDockDyBucket"] as? String) == DockDyBucket.upTo64.rawValue
        && dockFrameNear(rePDock.frame, rePAvoidAppKitFrame),
      "ticks=\(rePAfterTick1["tickCount"] ?? -1) frame=\(rePDock.frame)")
rePOutcome.withLock { $0 = .targetMissing }
rePTime = 17_001
rePProbe.probe(candidates: [rePCandidate])
let rePWakePump = Date().addingTimeInterval(5)
while (rePProbe.lock.withLock({ $0.inFlight })
       || ((rePCollector.snapshot()["tickCount"] as? Int ?? 0) < 2)) && Date() < rePWakePump {
    RunLoop.current.run(until: Date().addingTimeInterval(0.01))
}
RunLoop.current.run(until: Date().addingTimeInterval(0.02))
let rePAfterTick2 = rePCollector.snapshot()
check("T-re5c targetMissing→wake计数+完整tick→base bucket+实际frame复位",
      (rePAfterTick2["captureTargetMissingCount"] as? Int) == 1
        && (rePAfterTick2["visibilityHiddenCount"] as? Int) == 1
        && (rePAfterTick2["wakeCallbackCount"] as? Int) == 1
        && (rePAfterTick2["tickCount"] as? Int) == 2
        && (rePAfterTick2["bubbleObstacleCount"] as? Int) == 2
        && (rePAfterTick2["lastVisibleObstacleCount"] as? Int) == 0
        && (rePAfterTick2["dockDyBaseCount"] as? Int) == 1
        && (rePAfterTick2["lastDockDyBucket"] as? String) == DockDyBucket.base.rawValue
        && dockFrameNear(rePDock.frame, rePBaseAppKitFrame),
      "ticks=\(rePAfterTick2["tickCount"] ?? -1) frame=\(rePDock.frame)")
let rePJitter = mkw(561, layer: 3, CGRect(x: 80, y: 280, width: 345.4, height: 54))
rePTime = 17_002
rePProbe.probe(candidates: [rePJitter])
let rePAfterJitter = rePCollector.snapshot()
check("T-re5d 同WID bounds抖动→identity-change计数（H4b探针）",
      (rePAfterJitter["identityChangeCount"] as? Int) == 2,
      "identity=\(rePAfterJitter["identityChangeCount"] ?? -1)")
rePScheduler.stop()

// T-re6: control-kind 存在即占位 → kind/visible 计数 + dy bucket（生产 owner 消费）
let reCRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
    "pd-runtime-evidence-control-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
try? FileManager.default.removeItem(at: reCRoot)
let reCCollector = makeRuntimeEvidenceRecorderForTesting(
    candidateSHA: reSHA,
    outputURL: reCRoot.appendingPathComponent(runtimeEvidenceOutputFileName),
    flushNow: { 21_000 })
let reControlCandidate = mkw(566, layer: 3, CGRect(x: 140, y: 280, width: 60, height: 24))
check("T-re6a 前置: 60x24候选→control kind",
      PetTracker.obstacleKind(reControlCandidate, petMaxY: petForCollapse.maxY) == .control, "")
let reControlDock = DockPanel()
let reControlProbe = BubbleVisibilityProbe(
    monotonicNow: { 21_000 }, canCapture: { true }, capturer: { _ in .unavailable })
_ = FollowLayoutPass.placeDock(
    mascot: rePMascot,
    candidates: [rePMascot, rePCandidate, reControlCandidate],
    bubbleProbe: reControlProbe,
    evidence: reCCollector,
    frameSink: { pet, obstacles in
        reControlDock.placeBelow(
            petQuartzRect: pet, avoiding: obstacles, visibleScreen: nil,
            movementChanged: false, monotonicNow: 21_000, evidence: reCCollector)
    }
)
let reControlSnapshot = reCCollector.snapshot()
check("T-re6b control+bubble→kind计数/visible=2/避让bucket",
      (reControlSnapshot["bubbleObstacleCount"] as? Int) == 1
        && (reControlSnapshot["controlObstacleCount"] as? Int) == 1
        && (reControlSnapshot["lastVisibleObstacleCount"] as? Int) == 2
        && (reControlSnapshot["lastDockDyBucket"] as? String) == DockDyBucket.upTo64.rawValue,
      "bubble=\(reControlSnapshot["bubbleObstacleCount"] ?? -1) "
        + "control=\(reControlSnapshot["controlObstacleCount"] ?? -1) "
        + "visible=\(reControlSnapshot["lastVisibleObstacleCount"] ?? -1)")

// T-re7: 默认关闭（evidence=nil）→ 生产链行为不变、无诊断 writer
let reDisabledDock = DockPanel()
let reDisabledProbe = BubbleVisibilityProbe(
    monotonicNow: { 23_000 }, canCapture: { true }, capturer: { _ in .stats(expandedS) })
let reDisabledShown = FollowLayoutPass.placeDock(
    mascot: rePMascot,
    candidates: [rePMascot, rePCandidate],
    bubbleProbe: reDisabledProbe,
    frameSink: { pet, obstacles in
        reDisabledDock.placeBelow(
            petQuartzRect: pet, avoiding: obstacles, visibleScreen: nil,
            movementChanged: false, monotonicNow: 23_000)
    }
)
check("T-re7a evidence=nil生产链行为不变（避让frame）",
      reDisabledShown && dockFrameNear(reDisabledDock.frame, rePAvoidAppKitFrame),
      "frame=\(reDisabledDock.frame)")

// T-re8 (source guard): RuntimeEvidence.swift 不得引入捕获/计时/墙钟来源
let reGuardRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let reGuardSource = try! String(
    contentsOf: reGuardRoot.appendingPathComponent("Sources/PetDock/RuntimeEvidence.swift"), encoding: .utf8)
let reGuardPattern = try! NSRegularExpression(
    pattern: "\\bTimer\\b|DispatchSource|SCShareableContent|SCScreenshot|CGWindowList|\\bTask\\b|DispatchQueue|\\bDate\\b|async|ProcessInfo|CGPreflight|CGRequest"
)
let reGuardMatch = reGuardPattern.firstMatch(
    in: reGuardSource, range: NSRange(reGuardSource.startIndex..., in: reGuardSource))
check("T-re8 RuntimeEvidence.swift无捕获/计时/墙钟API且仅经PrivateStorage落盘（source guard）",
      reGuardMatch == nil && reGuardSource.contains("PrivateStorage.atomicWrite"),
      reGuardMatch != nil ? "violations found" : "")

// T-re9 (admission fix 1): not-due identity jitter —— capture cadence 未到也必须计 identity change。
// H4b 探针不能因 capture gate（未 due）漏计抖动；事件由真实 probe 消费。
var reJTime: TimeInterval = 25_000
let reJRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
    "pd-runtime-evidence-jitter-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
try? FileManager.default.removeItem(at: reJRoot)
let reJCollector = makeRuntimeEvidenceRecorderForTesting(
    candidateSHA: reSHA,
    outputURL: reJRoot.appendingPathComponent(runtimeEvidenceOutputFileName),
    flushNow: { reJTime })
let reJCaptureCalls = OSAllocatedUnfairLock(initialState: 0)
let reJCap: BubbleCapturer = { _ in
    reJCaptureCalls.withLock { $0 += 1 }
    return .stats(expandedS)
}
let reJProbe = BubbleVisibilityProbe(
    monotonicNow: { reJTime }, canCapture: { true }, capturer: reJCap, evidence: reJCollector)
let reJStable = mkw(581, layer: 3, bubbleForCollapse)
let reJJittered = mkw(581, layer: 3, CGRect(x: 80, y: 280, width: 345.3, height: 54))
reJProbe.probe(candidates: [reJStable])
_ = waitPumpingMain { !reJProbe.lock.withLock { $0.inFlight } }
let reJAfterFirst = reJCollector.snapshot()
check("T-re9a 前置: 首次probe→capture1次+identity1+stats1",
      reJCaptureCalls.withLock { $0 } == 1
        && (reJAfterFirst["identityChangeCount"] as? Int) == 1
        && (reJAfterFirst["captureStatsCount"] as? Int) == 1, "")
reJTime = 25_000.05   // 距上次捕获 0.05s < 0.1s cadence → capture 不启动
reJProbe.probe(candidates: [reJJittered])
let reJAfterNotDue = reJCollector.snapshot()
check("T-re9b not-due jitter→identity计1但capture不加（gate前计数）",
      (reJAfterNotDue["identityChangeCount"] as? Int) == 2
        && (reJAfterNotDue["captureStatsCount"] as? Int) == 1
        && reJCaptureCalls.withLock { $0 } == 1,
      "identity=\(reJAfterNotDue["identityChangeCount"] ?? -1) "
        + "calls=\(reJCaptureCalls.withLock { $0 })")

/// Test-only async entry gate（T-re10）：capturer 进入后挂起 continuation，
/// 不阻塞 cooperative executor 线程；release() 对每个等待者恰好 resume 一次，
/// 早到的 release 由下一个进入者消费。无 semaphore、无固定 sleep 窗口。
final class AsyncCaptureEntryGate: @unchecked Sendable {
    private struct GateState {
        var enteredCount = 0
        var pendingReleases = 0
        var continuation: CheckedContinuation<Void, Never>?
    }
    private let lock = OSAllocatedUnfairLock(initialState: GateState())

    var enteredCount: Int { lock.withLock { $0.enteredCount } }

    /// async 侧：记录进入；若 release 已先行到达则立即返回，否则挂起等待恰好一次 resume。
    func waitAfterEntry() async {
        let shouldSuspend = lock.withLock { state -> Bool in
            state.enteredCount += 1
            if state.pendingReleases > 0 {
                state.pendingReleases -= 1
                return false
            }
            return true
        }
        guard shouldSuspend else { return }
        await withCheckedContinuation { continuation in
            let resumeImmediately = lock.withLock { state -> Bool in
                if state.pendingReleases > 0 {
                    state.pendingReleases -= 1
                    return true
                }
                state.continuation = continuation
                return false
            }
            if resumeImmediately { continuation.resume() }
        }
    }

    /// 主线程侧：释放一个等待中（或下一个进入）的 capturer；continuation 恰好 resume 一次。
    func release() {
        let resume: CheckedContinuation<Void, Never>? = lock.withLock { state in
            if let continuation = state.continuation {
                state.continuation = nil
                return continuation
            }
            state.pendingReleases += 1
            return nil
        }
        resume?.resume()
    }
}

// T-re10 (review r1 P1 修复 / v7 P2-2): in-flight identity replacement ——
// capturer 进入后经 continuation gate 挂起（不阻塞 executor）；主线程 pump RunLoop
// 直到 entered/calls/inFlight 状态确定，再注入 identity replacement 并断言
// single-flight；手工 release 恰好 resume 一次后收尾。不使用固定 sleep 或时序巧合。
var reITime: TimeInterval = 27_000
let reIRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
    "pd-runtime-evidence-inflight-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
try? FileManager.default.removeItem(at: reIRoot)
let reICollector = makeRuntimeEvidenceRecorderForTesting(
    candidateSHA: reSHA,
    outputURL: reIRoot.appendingPathComponent(runtimeEvidenceOutputFileName),
    flushNow: { reITime })
let reICaptureCalls = OSAllocatedUnfairLock(initialState: 0)
let reIEntryGate = AsyncCaptureEntryGate()
let reICap: BubbleCapturer = { _ in
    reICaptureCalls.withLock { $0 += 1 }
    await reIEntryGate.waitAfterEntry()
    return .stats(expandedS)
}
let reIStable = mkw(591, layer: 3, bubbleForCollapse)
let reIJittered = mkw(591, layer: 3, CGRect(x: 80, y: 280, width: 345.5, height: 54))
let reIProbe = BubbleVisibilityProbe(
    monotonicNow: { reITime }, canCapture: { true }, capturer: reICap, evidence: reICollector)
reIProbe.probe(candidates: [reIStable])   // 慢捕获启动，保持 inFlight
check("T-re10 前置 gate: capturer已进入且calls==1",
      waitPumpingMain {
          reIEntryGate.enteredCount == 1
              && reICaptureCalls.withLock { $0 } == 1
              && reIProbe.lock.withLock { $0.inFlight }
      },
      "calls=\(reICaptureCalls.withLock { $0 })")
reITime = 27_000.01
reIProbe.probe(candidates: [reIJittered]) // in-flight 期间 identity 替换（single-flight 合并）
let reIAfterReplacement = reICollector.snapshot()
check("T-re10a in-flight jitter→identity计1且不启动第二捕获",
      (reIAfterReplacement["identityChangeCount"] as? Int) == 2
        && reICaptureCalls.withLock { $0 } == 1
        && reIProbe.lock.withLock { $0.inFlight },
      "identity=\(reIAfterReplacement["identityChangeCount"] ?? -1) "
        + "calls=\(reICaptureCalls.withLock { $0 })")
reIEntryGate.release()   // 手工释放第一段 in-flight（continuation 恰好 resume 一次）
_ = waitPumpingMain { !reIProbe.lock.withLock { $0.inFlight } }
let reIAfterStale = reICollector.snapshot()
check("T-re10b stale完成被拒绝→outcome/visibility/wake均不计入",
      (reIAfterStale["captureStatsCount"] as? Int) == 0
        && (reIAfterStale["visibilityVisibleCount"] as? Int) == 0
        && (reIAfterStale["wakeCallbackCount"] as? Int) == 0,
      "stats=\(reIAfterStale["captureStatsCount"] ?? -1) "
        + "visible=\(reIAfterStale["visibilityVisibleCount"] ?? -1) "
        + "wake=\(reIAfterStale["wakeCallbackCount"] ?? -1)")
reITime = 27_001   // 新 generation 下 due → 接受的捕获必须计数
reIProbe.probe(candidates: [reIJittered])
_ = waitPumpingMain { reIEntryGate.enteredCount == 2 && reICaptureCalls.withLock { $0 } == 2 }
reIEntryGate.release()   // 释放第二段捕获
_ = waitPumpingMain { !reIProbe.lock.withLock { $0.inFlight } }
let reIAfterAccepted = reICollector.snapshot()
check("T-re10c 接受的新捕获→outcome/visibility计入且visible不变无wake",
      (reIAfterAccepted["captureStatsCount"] as? Int) == 1
        && (reIAfterAccepted["visibilityVisibleCount"] as? Int) == 1
        && (reIAfterAccepted["wakeCallbackCount"] as? Int) == 0
        && reICaptureCalls.withLock { $0 } == 2,
      "stats=\(reIAfterAccepted["captureStatsCount"] ?? -1) "
        + "visible=\(reIAfterAccepted["visibilityVisibleCount"] ?? -1)")

// T-re11 (admission fix 3 + review r1 P2): flush dirty 抑制 + 最小 0.5s 单调节流。
// 首次证据立即写；窗口内连续 identity/layout 变化合并为零写；到期只写一次且计数完整；
// 失败重试同样受节流；无变化 tick 零写。时钟注入，不依赖墙钟/固定 sleep。
let reFRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
    "pd-runtime-evidence-flush-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
try? FileManager.default.removeItem(at: reFRoot)
let reFURL = reFRoot.appendingPathComponent(runtimeEvidenceOutputFileName)
var reFNow: TimeInterval = 100
let reFCollector = makeRuntimeEvidenceRecorderForTesting(candidateSHA: reSHA, outputURL: reFURL, flushNow: { reFNow })
reFCollector.recordLayoutTick(bubbleObstacles: 1, controlObstacles: 0, visibleObstacles: 1)
let reFFirstFlush = reFCollector.flush()
check("T-re11a 首个layout证据→立即flush写盘一次",
      reFFirstFlush && FileManager.default.fileExists(atPath: reFURL.path), "")
var reFUnchangedWrites = 0
for _ in 0..<100 {
    reFCollector.recordLayoutTick(bubbleObstacles: 1, controlObstacles: 0, visibleObstacles: 1)
    if reFCollector.flush() { reFUnchangedWrites += 1 }
}
let reFWritten = try! JSONSerialization.jsonObject(with: Data(contentsOf: reFURL)) as! [String: Any]
check("T-re11b 100个无变化tick→0次写盘（flush全false+文件tickCount停更）",
      reFUnchangedWrites == 0 && (reFWritten["tickCount"] as? Int) == 1,
      "writes=\(reFUnchangedWrites) fileTicks=\(reFWritten["tickCount"] ?? -1)")
var reFJitterWrites = 0
for _ in 0..<40 {
    reFNow += 0.01   // 100.01..100.40，全部在首次写后的 0.5s 窗口内
    reFCollector.recordIdentityChange()
    if reFCollector.flush() { reFJitterWrites += 1 }
}
check("T-re11g 窗口内40次identity抖动→0次额外写（dirty合并）",
      reFJitterWrites == 0, "writes=\(reFJitterWrites)")
reFNow += 0.5   // 距上次写 ≥0.5s，dirty 到期
let reFDueWritten = reFCollector.flush()
let reFDueRepeat = reFCollector.flush()
let reFDueContent = try! JSONSerialization.jsonObject(with: Data(contentsOf: reFURL)) as! [String: Any]
check("T-re11h 到期后下一次既有tick→只写一次且计数完整",
      reFDueWritten && !reFDueRepeat
        && (reFDueContent["identityChangeCount"] as? Int) == 40,
      "first=\(reFDueWritten) repeat=\(reFDueRepeat) "
        + "identity=\(reFDueContent["identityChangeCount"] ?? -1)")
// T-re11i: 失败重试受同一节流 —— 落盘位被目录阻塞一次后，窗口内即使路径恢复也不重试。
var reFRetryNow: TimeInterval = 200
let reFBlocker = reFRoot.appendingPathComponent("blocker")   // 常规文件：作为父路径使落盘失败
try! Data("x".utf8).write(to: reFBlocker)
let reFRetryURL = reFBlocker.appendingPathComponent("retry.json")
let reFRetryCollector = makeRuntimeEvidenceRecorderForTesting(
    candidateSHA: reSHA, outputURL: reFRetryURL, flushNow: { reFRetryNow })
reFRetryCollector.recordIdentityChange()
check("T-re11i-1 落盘失败→flush false且dirty保留",
      !reFRetryCollector.flush(), "")
try? FileManager.default.removeItem(at: reFBlocker)   // 移除阻塞文件，路径恢复可写
reFRetryNow = 200.2   // 窗口未到期：即使 dirty+路径可写也不得重试
check("T-re11i-2 失败重试受节流（窗口内不重试）", !reFRetryCollector.flush(), "")
reFRetryNow = 200.5   // 到期后重试成功
check("T-re11i-3 到期后重试成功且计数完整",
      reFRetryCollector.flush()
        && (try! JSONSerialization.jsonObject(with: Data(contentsOf: reFRetryURL)) as! [String: Any])["identityChangeCount"] as? Int == 1,
      "")
reFCollector.recordDockDyBucket(.upTo64)
reFNow += 0.5   // 跨节流窗口
check("T-re11j 新dy bucket→写盘", reFCollector.flush(), "")
reFCollector.recordDockDyBucket(.upTo64)
check("T-re11k 同值dy bucket→不写", !reFCollector.flush(), "")
reFCollector.recordLayoutTick(bubbleObstacles: 1, controlObstacles: 0, visibleObstacles: 0)
reFNow += 0.5
check("T-re11l layout state变化→写盘", reFCollector.flush(), "")
reFCollector.recordCapture(kind: .stats, visibility: .visible)
reFCollector.recordIdentityChange()
reFCollector.recordWakeCallback()
reFNow += 0.5
check("T-re11m accepted capture/identity/wake→写盘", reFCollector.flush(), "")

// T-re12 (v7 P2-1): owner read-back —— dy telemetry 只能消费 setFrame 后回读的真实 panel frame。
// 生产链 FollowTickScheduler → FollowLayoutPass.placeDock → DockPanel.placeBelow → collector；
// 先用同构探针 panel 实测本显示环境的 setFrame 对齐行为，构造 requested 与 owner 回读跨
// bucket 边界的 fractional 避让；若环境无法区分（requested == owner），行为断言退化为与
// owner 回读一致并标注 coverage-gap，可失败性由 T-re12b source guard 承担（不伪造区分证据）。
let reOTime: TimeInterval = 23_000
var reOClock: TimeInterval = 0
let reODock = DockPanel()
let reOCap: BubbleCapturer = { _ in .stats(expandedS) }
let reORoot = FileManager.default.temporaryDirectory.appendingPathComponent(
    "pd-runtime-evidence-owner-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
try? FileManager.default.removeItem(at: reORoot)
let reOCollector = makeRuntimeEvidenceRecorderForTesting(
    candidateSHA: reSHA,
    outputURL: reORoot.appendingPathComponent(runtimeEvidenceOutputFileName),
    flushNow: { reOTime })
let reOProbePanel = NSPanel(
    contentRect: NSRect(x: 0, y: 0, width: 200, height: 48),
    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
let reOProbeBaseY: CGFloat = 400
var reOFixtureDy: CGFloat?
for boundary in [CGFloat(32), 64] {
    for delta in [CGFloat(0.125), 0.2, 0.25, 0.3, 0.4, 0.5, 0.6, 0.75] {
        reOProbePanel.setFrame(
            NSRect(x: 86, y: reOProbeBaseY - (boundary + delta), width: 200, height: 48), display: true)
        let ownerDy = reOProbeBaseY - reOProbePanel.frame.minY
        if DockDyBucket.bucket(dy: boundary + delta) != DockDyBucket.bucket(dy: ownerDy) {
            reOFixtureDy = boundary + delta
            break
        }
    }
    if reOFixtureDy != nil { break }
}
let reOFixtureDyValue = reOFixtureDy ?? 64.125   // 无区分环境也走同一生产链（断言退化为 owner 等值）
let reOMascot = mkw(583, layer: 2, petForCollapse, title: "Codex Pet Mascot Effect")
let reOBubbleRect = CGRect(x: 80, y: petForCollapse.maxY + reOFixtureDyValue - 54, width: 345, height: 54)
let reOCandidate = mkw(581, layer: 3, reOBubbleRect)
let reOActiveCandidates = OSAllocatedUnfairLock(initialState: [reOMascot])   // tick A：无障碍基础位
let reOBaseAppKit = Geometry.appKitRectFromQuartz(CGRect(
    x: petForCollapse.origin.x + (petForCollapse.width - 200) / 2,
    y: petForCollapse.maxY + gapBV, width: 200, height: 48))
let reOAvoidQuartz = Geometry.safeDockFrame(
    pet: petForCollapse, avoiding: [reOBubbleRect], dockSize: dockSizeBV, gap: gapBV, screen: nil).frame!
let reOAvoidRequested = Geometry.appKitRectFromQuartz(reOAvoidQuartz)
var reOProbe: BubbleVisibilityProbe!
let reOScheduler = FollowTickScheduler(
    runTick: {
        FollowLayoutPass.placeDock(
            mascot: reOMascot,
            candidates: reOActiveCandidates.withLock { $0 },
            bubbleProbe: reOProbe,
            evidence: reOCollector,
            frameSink: { pet, obstacles in
                reODock.placeBelow(
                    petQuartzRect: pet,
                    avoiding: obstacles,
                    visibleScreen: nil,
                    movementChanged: false,
                    monotonicNow: reOTime,
                    evidence: reOCollector
                )
            }
        ) ? .stable : .hidden
    },
    makeDisplayLink: { _, _ in nil },
    canUseDisplayLink: { false },
    maximumFramesPerSecond: { 60 },
    monotonicNow: { reOClock },
    makeTimer: { interval, repeats, callback in
        TestFollowTickTimer(interval: interval, repeats: repeats, callback: callback)
    }
)
reOProbe = BubbleVisibilityProbe(
    monotonicNow: { reOTime },
    canCapture: { true },
    capturer: reOCap,
    evidence: reOCollector,
    onVisibilityChange: reOScheduler.visibilityChangeCallback
)
reOProbe.probe(candidates: [reOCandidate])   // cache：fractional bubble → visible（plumbing-only）
_ = waitPumpingMain { !reOProbe.lock.withLock { $0.inFlight } }
reOScheduler.start()
reOScheduler.requestWake()
_ = waitPumpingMain { (reOCollector.snapshot()["tickCount"] as? Int ?? 0) >= 1 }
let reOBaseOwnerFrame = reODock.frame
reOActiveCandidates.withLock { $0 = [reOMascot, reOCandidate] }   // tick B：fractional 避让
reOScheduler.requestWake()
_ = waitPumpingMain { (reOCollector.snapshot()["tickCount"] as? Int ?? 0) >= 2 }
let reOAvoidOwnerFrame = reODock.frame
reOScheduler.stop()
let reOExpectedOwnerBucket = DockDyBucket.bucket(dy: abs(reOAvoidOwnerFrame.midY - reOBaseAppKit.midY))
let reOExpectedRequestedBucket = DockDyBucket.bucket(dy: abs(reOAvoidRequested.midY - reOBaseAppKit.midY))
let reORecorded = reOCollector.snapshot()["lastDockDyBucket"] as? String
check("T-re12a placeBelow后dy bucket=owner回读frame（非请求frame）",
      reORecorded == reOExpectedOwnerBucket.rawValue
        && (reOFixtureDy == nil || reOExpectedOwnerBucket != reOExpectedRequestedBucket),
      "recorded=\(reORecorded ?? "nil") owner=\(reOExpectedOwnerBucket.rawValue) "
        + "requested=\(reOExpectedRequestedBucket.rawValue) "
        + (reOFixtureDy == nil
           ? "[coverage-gap: requested==owner in this display environment]"
           : String(format: "fixtureDy=%.3f", reOFixtureDy!)))

// T-re12b (owner-read-back absence guard): DockPanel 源码必须在 setFrame 之后回读 panel.frame，
// 且只把 owner 回读值传给 dyBucket；mutation 把消费值改回请求 frame 时本 guard FAIL。
let reOOwnerGuardRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let reOOwnerSource = try! String(
    contentsOf: reOOwnerGuardRoot.appendingPathComponent("Sources/PetDock/DockPanel.swift"), encoding: .utf8)
let reOOwnerFlat = String(reOOwnerSource.filter { !$0.isWhitespace })
let reOSetFrameRange = reOOwnerFlat.range(of: "panel.setFrame(frame,display:true)")
let reOReadBackRange = reOOwnerFlat.range(of: "letownerFrame=panel.frame")
let reOConsumeRange = reOOwnerFlat.range(of: "dyBucket(actualAppKitFrame:ownerFrame")
check("T-re12b dy telemetry输入=setFrame后panel.frame回读（source guard）",
      reOSetFrameRange != nil && reOReadBackRange != nil && reOConsumeRange != nil
        && reOSetFrameRange!.lowerBound < reOReadBackRange!.lowerBound
        && reOReadBackRange!.lowerBound < reOConsumeRange!.lowerBound,
      "setFrame=\(reOSetFrameRange != nil) readBack=\(reOReadBackRange != nil) consume=\(reOConsumeRange != nil)")

// T-bv40: reset 后旧 generation 的成功结果不得通知布局。
let staleNotifications = OSAllocatedUnfairLock(initialState: 0)
let staleCap: BubbleCapturer = { _ in
    try? await Task.sleep(nanoseconds: 100_000_000)
    return .stats(collapsedS)
}
let staleProbe = BubbleVisibilityProbe(
    monotonicNow: { 12_000 },
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

// P1 red regression: 同 WID 但 bounds/ownerPID/ownerName/layer 变化时，旧身份的在途结果
// 不能写入新候选的 cache、通知布局或把新身份误判为 targetMissing hidden。
let identityCaptureCalls = OSAllocatedUnfairLock(initialState: 0)
let identityObserved = OSAllocatedUnfairLock(initialState: [(CGWindowID, CGRect, Int32, String, Int)]())
let identityNotifications = OSAllocatedUnfairLock(initialState: 0)
let identityTime = OSAllocatedUnfairLock(initialState: TimeInterval(14_000))
let identityCap: BubbleCapturer = { candidate in
    identityObserved.withLock { $0.append((candidate.wid, candidate.bounds, candidate.ownerPID, candidate.ownerName, candidate.layer)) }
    let call = identityCaptureCalls.withLock { count -> Int in
        count += 1
        return count
    }
    if call == 1 { return .stats(expandedS) }
    try? await Task.sleep(nanoseconds: 200_000_000)
    return .targetMissing
}
let identityProbe = BubbleVisibilityProbe(
    monotonicNow: { identityTime.withLock { $0 } },
    canCapture: { true },
    capturer: identityCap,
    onVisibilityChange: { identityNotifications.withLock { $0 += 1 } }
)
let identityOld = WinCandidate(
    wid: CGWindowID(520), ownerPID: 11111, ownerName: "ChatGPT", title: "",
    layer: 3, alpha: 1.0, isOnscreen: true, sharingState: 1,
    bounds: CGRect(x: 80, y: 280, width: 345, height: 54)
)
let identityReplacement = WinCandidate(
    wid: CGWindowID(520), ownerPID: 22222, ownerName: "Other", title: "",
    layer: 7, alpha: 1.0, isOnscreen: true, sharingState: 1,
    bounds: CGRect(x: 100, y: 300, width: 320, height: 64)
)
identityProbe.probe(candidates: [identityOld])
_ = waitPumpingMain { !identityProbe.lock.withLock { $0.inFlight } }
check("T-bv41a identity前置:旧候选成功expanded→visible",
      identityProbe.visibility(for: identityOld.wid) == .visible, "")
identityTime.withLock { $0 += 1 }
identityProbe.probe(candidates: [identityOld])
check("T-bv41b identity旧候选第二次capture在途", identityProbe.lock.withLock { $0.inFlight }, "")
identityProbe.probe(candidates: [identityReplacement])
let identityChanged = identityOld.bounds != identityReplacement.bounds
    && identityOld.ownerPID != identityReplacement.ownerPID
    && identityOld.ownerName != identityReplacement.ownerName
    && identityOld.layer != identityReplacement.layer
let identityPump = Date().addingTimeInterval(5)
while identityProbe.lock.withLock({ $0.inFlight }) && Date() < identityPump {
    RunLoop.current.run(until: Date().addingTimeInterval(0.01))
}
let identityCached = identityProbe.lock.withLock { $0.cached[identityReplacement.wid] }
let identitySeenOld = identityObserved.withLock { seen in
    seen.count == 2
        && seen.allSatisfy { $0.0 == identityOld.wid }
        && seen.allSatisfy { $0.1 == identityOld.bounds }
        && seen.allSatisfy { $0.2 == identityOld.ownerPID }
        && seen.allSatisfy { $0.3 == identityOld.ownerName }
        && seen.allSatisfy { $0.4 == identityOld.layer }
}
check("T-bv41c RED 同WID身份变化使旧in-flight结果失效",
      identityChanged
        && identitySeenOld
        && identityCaptureCalls.withLock { $0 } == 2
        && identityProbe.visibility(for: identityReplacement.wid) == .visible
        && identityCached == nil
        && identityNotifications.withLock { $0 } == 0,
      "changed=\(identityChanged) seenOld=\(identitySeenOld) calls=\(identityCaptureCalls.withLock { $0 }) "
        + "visibility=\(identityProbe.visibility(for: identityReplacement.wid)) cached=\(String(describing: identityCached)) "
        + "notifications=\(identityNotifications.withLock { $0 })")

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
