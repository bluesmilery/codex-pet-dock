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

/// 生产布局 two-tick helper 的统一完成谓词：主导探测与参考通道都空闲后才消费 tick-2。
/// 只等 `inFlight` 会在参考通道尚未落 cache 时读到回退锚，造成 T-cs7/T-cs11 类时序 flake。
func waitProbeChannelsIdle(_ probe: BubbleVisibilityProbe, timeout: TimeInterval = 5) -> Bool {
    waitPumpingMain({
        probe.lock.withLock { !$0.inFlight && !$0.referenceInFlight }
    }, timeout: timeout)
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
              _ layer: Int, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
              onscreen: Bool = true) -> [String: Any] {
    return [
        (kCGWindowNumber as String): NSNumber(value: wid),
        (kCGWindowOwnerPID as String): NSNumber(value: pid),
        (kCGWindowOwnerName as String): owner,
        (kCGWindowName as String): title,
        (kCGWindowLayer as String): NSNumber(value: layer),
        (kCGWindowAlpha as String): NSNumber(value: 1.0),
        (kCGWindowIsOnscreen as String): onscreen,
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

// T-enum5: onscreenOnly 枚举瘦身的语义安全网（R6 改动 A）。全量形状的 mock infos
// 混入 offscreen 窗口（kCGWindowIsOnscreen=false，模拟 .optionOnScreenOnly 之前
// CGWindowListCopyWindowInfo([]) 会返回的数据）：下游 selectPet 不得选中 offscreen
// 宠物形窗口——证明换选项后（offscreen 窗口不再出现在数据里）识别语义不变。
PetTracker.infosProvider = { [
    infoDict(40, 11111, "ChatGPT", "ChatGPT", 0, 0, 0, 1728, 1050),
    infoDict(41, 11111, "ChatGPT", "Codex Pet Mascot Effect", 2, 100, 100, 172, 179, onscreen: false),
] }
let enum5Union = PetTracker.unionCandidates()
let enum5Sel = PetTracker.selectPet(candidates: enum5Union, lastWID: nil)
check("T-enum5 selectPet不选中offscreen宠物形窗口",
      enum5Union.contains { $0.wid == 41 } && enum5Sel.selected == nil,
      "selected=\(String(describing: enum5Sel.selected?.wid)) reason=\(enum5Sel.reason)")

// T-enum5b: 同一安全网的避让半边：offscreen 气泡形窗口（宠物正下方、几何完全合规）
// 不得进入 obstaclesNear；同形状窗口 onscreen 时必须被纳入（阳性对照，证明排除
// 确由 isOnscreen 前置造成，而非几何巧合）。
func enum5bRun(bubbleOnscreen: Bool) -> (mascotWid: UInt32?, obstacleWids: [UInt32]) {
    PetTracker.infosProvider = { [
        infoDict(43, 11111, "ChatGPT", "Codex Pet Mascot Effect", 2, 100, 100, 172, 179),
        infoDict(44, 11111, "ChatGPT", "Chat", 3, 100, 300, 172, 120, onscreen: bubbleOnscreen),
    ] }
    let union = PetTracker.unionCandidates()
    let sel = PetTracker.selectPet(candidates: union, lastWID: nil)
    guard let mascot = sel.selected else { return (nil, []) }
    let obs = PetTracker.obstaclesNear(mascot: mascot, candidates: union)
    return (mascot.wid, obs.map { $0.wid })
}
let enum5bOffscreen = enum5bRun(bubbleOnscreen: false)
let enum5bOnscreen = enum5bRun(bubbleOnscreen: true)
check("T-enum5b obstaclesNear不含offscreen气泡(阳性对照含onscreen同形状)",
      enum5bOffscreen.mascotWid == 43 && enum5bOffscreen.obstacleWids.isEmpty
        && enum5bOnscreen.mascotWid == 43 && enum5bOnscreen.obstacleWids == [44],
      "offscreen=\(enum5bOffscreen) onscreen=\(enum5bOnscreen)")

// T-enum6: WinCandidate 解析在 onscreenOnly 数据形状下字段正确
// （kCGWindowIsOnscreen=true 映射 isOnscreen，全字段 round-trip）。
let enum6Info: [String: Any] = [
    (kCGWindowNumber as String): NSNumber(value: 50),
    (kCGWindowOwnerPID as String): NSNumber(value: 11111),
    (kCGWindowOwnerName as String): "ChatGPT",
    (kCGWindowName as String): "Codex Pet Mascot Effect",
    (kCGWindowLayer as String): NSNumber(value: 2),
    (kCGWindowAlpha as String): NSNumber(value: 0.75),
    (kCGWindowIsOnscreen as String): true,
    (kCGWindowSharingState as String): NSNumber(value: 1),
    (kCGWindowBounds as String): ["X": 12.5, "Y": 34.5, "Width": 172, "Height": 179] as [String: Any],
]
let enum6Parsed = PetTracker.enumerate(pids: [11111], from: [enum6Info])
let e6 = enum6Parsed.first
check("T-enum6 onscreenOnly形状解析字段正确",
      enum6Parsed.count == 1 && e6?.wid == 50 && e6?.ownerPID == 11111
        && e6?.ownerName == "ChatGPT" && e6?.title == "Codex Pet Mascot Effect"
        && e6?.layer == 2 && e6?.alpha == 0.75 && e6?.isOnscreen == true
        && e6?.sharingState == 1
        && e6?.bounds == CGRect(x: 12.5, y: 34.5, width: 172, height: 179),
      "parsed=\(String(describing: e6?.detailed()))")
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
_ = baseInterpolator.snap(to: interpA)
let interpStart = baseInterpolator.update(to: interpB, at: 0)
let interp16 = baseInterpolator.frame(at: 0.016)
let interp32 = baseInterpolator.frame(at: DockFrameInterpolator.maximumDuration)
check("T-ip1 0ms从起点开始且16ms在线段中点", rectNear(interpStart, interpA) && rectNear(interp16, NSRect(x: 50, y: 40, width: 200, height: 48)),
      "start=\(String(describing: interpStart)) mid=\(String(describing: interp16))")
check("T-ip2 32ms精确到终点且segment结束", rectNear(interp32, interpB) && baseInterpolator.segmentStartedAt == nil,
      "frame=\(String(describing: interp32)) started=\(String(describing: baseInterpolator.segmentStartedAt))")

func interpolationSamples(at times: [TimeInterval]) -> [NSRect] {
    var interpolator = DockFrameInterpolator()
    _ = interpolator.snap(to: interpA)
    _ = interpolator.update(to: interpB, at: 0)
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
_ = retargetInterpolator.snap(to: interpA)
_ = retargetInterpolator.update(to: interpB, at: 0)
let retargetSource = retargetInterpolator.frame(at: 0.016)
let retargetStart = retargetInterpolator.update(to: interpC, at: 0.016)
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

var stationaryInterpolator = DockFrameInterpolator()
_ = stationaryInterpolator.snap(to: interpA)
let stationaryStart = stationaryInterpolator.updateAvoidance(to: interpC, at: 0)
let stationaryKindActive = stationaryInterpolator.segmentKind == .avoidance   // 采样前快照
let stationaryMid = stationaryInterpolator.frame(at: 0.1)
let stationaryEnd = stationaryInterpolator.frame(at: DockFrameInterpolator.avoidanceDuration)
check("T-ip5 静止目标变化(内容/障碍/锚)走avoidance平滑非snap(语义来源:movementChanged分类)",
      rectNear(stationaryStart, interpA)
        && stationaryKindActive
        && !rectNear(stationaryMid, interpA) && !rectNear(stationaryMid, interpC)
        && between(stationaryMid!.origin.x, interpA.origin.x, interpC.origin.x)
        && rectNear(stationaryEnd, interpC),
      "start=\(String(describing: stationaryStart)) mid=\(String(describing: stationaryMid)) end=\(String(describing: stationaryEnd))")
stationaryInterpolator.reset()
check("T-ip6 reset用于隐藏/无screen/首次显示路径", stationaryInterpolator.renderedFrame == nil
        && stationaryInterpolator.targetFrame == nil && stationaryInterpolator.segmentStartedAt == nil, "")

var stableInterpolator = DockFrameInterpolator()
_ = stableInterpolator.snap(to: interpA)
_ = stableInterpolator.update(to: interpB, at: 0)
let stableFinal = stableInterpolator.frame(at: Follower.stationaryDuration)
check("T-ip7 stable阈值前最终插值段已精确到位", rectNear(stableFinal, interpB),
      "stableDuration=\(Follower.stationaryDuration) final=\(String(describing: stableFinal))")

let panelPetA = CGRect(x: 100, y: 100, width: 172, height: 179)
let panelPetB = panelPetA.offsetBy(dx: 100, dy: 0)
if let interpolationScreen = NSScreen.screens.first {
    var ipAvoLinks: [TestAnimationDisplayLink] = []
    let panelInterpolator = DockPanel(
        makeAnimationDisplayLink: { target, selector in
            let link = TestAnimationDisplayLink(target: target, selector: selector)
            ipAvoLinks.append(link)
            return link
        },
        makeAnimationTimer: { interval, repeats, callback in
            TestFollowTickTimer(interval: interval, repeats: repeats, callback: callback)
        },
        animationMonotonicNow: { 0.016 }
    )
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
    let panelAvoidPlaced = panelInterpolator.frame
    let panelSafetyTarget = Geometry.appKitRectFromQuartz(
        Geometry.safeDockFrame(
            pet: panelPetB,
            avoiding: [panelObstacle],
            dockSize: CGSize(width: panelInterpolator.dockWidth, height: panelInterpolator.dockHeight),
            gap: panelInterpolator.gap,
            screen: interpolationScreen
        ).frame!
    )
    _ = panelInterpolator.placeBelow(
        petQuartzRect: panelPetB,
        avoiding: [panelObstacle],
        visibleScreen: interpolationScreen,
        movementChanged: false,
        monotonicNow: 0.032
    )
    let panelAvoidMid = panelInterpolator.frame
    _ = panelInterpolator.placeBelow(
        petQuartzRect: panelPetB,
        avoiding: [panelObstacle],
        visibleScreen: interpolationScreen,
        movementChanged: false,
        monotonicNow: 0.08
    )
    check("T-ip9 拖动中障碍出现走32ms movement插值(静止出现走avoidance见T-avo1;安全路径仍snap)",
          abs(panelAvoidPlaced.origin.y - panelMovingMid.origin.y) < 1.0
            && between(panelAvoidMid.origin.y,
                       min(panelMovingMid.origin.y, panelSafetyTarget.origin.y) + 4,
                       max(panelMovingMid.origin.y, panelSafetyTarget.origin.y) - 4)
            && abs(panelInterpolator.frame.origin.y - panelSafetyTarget.origin.y) < 1.0
            && ipAvoLinks.isEmpty,
          "placed=\(panelAvoidPlaced) mid=\(panelAvoidMid) final=\(panelInterpolator.frame) target=\(panelSafetyTarget)")
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

// ---- T-avo: 障碍出现/消失平滑过渡（200ms ease-in-out + DockPanel 自有显示节拍渲染源） ----
// 用户症状：控制按钮出现/消失时 dock 瞬间跳变（基线 obstaclesChanged → snap；基线红测
// T-avo1/2/3 在 5fbe237 上 3 failed 已记录）。新语义（movementChanged 驱动分类）：宠物窗口
// 实质移动 → 32ms movement 插值；静止时内容/障碍/锚目标变化 → 200ms ease-in-out
// avoidance segment，动画期间由 DockPanel 自有 display link（macOS13/不可用 → 60Hz
// repeating Timer fallback）以显示节拍渲染（stable follow tick 恒 0.1s，只靠 tick 采样
// 每段仅 ~1-2 点呈台阶）；无屏/换屏/隐藏/越界等安全路径仍立即 snap。
let avoBase = fail, avoPass = pass

/// 可注入合成屏（NSScreen 是系统只读集合；headless 无 WindowServer 时 screens 为空）。
final class AvoTestScreen: NSScreen {
    private let f: NSRect
    private let v: NSRect
    init(frame: NSRect, visible: NSRect) {
        self.f = frame
        self.v = visible
        super.init()
    }
    override var frame: NSRect { f }
    override var visibleFrame: NSRect { v }
}

/// avoidance 动画渲染源 fake：记录 add/invalidate；fire() 经生产 selector 驱动真实渲染 tick。
final class TestAnimationDisplayLink: NSObject, FollowDisplayLink {
    private let target: NSObject
    private let selector: Selector
    private(set) var added = false
    private(set) var invalidated = false

    init(target: NSObject, selector: Selector) {
        self.target = target
        self.selector = selector
    }

    func add(to runLoop: RunLoop, forMode mode: RunLoop.Mode) { added = true }

    func fire() {
        guard !invalidated else { return }
        _ = target.perform(selector, with: self)
    }

    func invalidate() { invalidated = true }
}

func avoFrameNear(_ lhs: NSRect, _ rhs: NSRect) -> Bool {
    abs(lhs.origin.x - rhs.origin.x) < 1.0 && abs(lhs.origin.y - rhs.origin.y) < 1.0
        && abs(lhs.width - rhs.width) < 1.0 && abs(lhs.height - rhs.height) < 1.0
}
/// 期望值 helper：base→target 按进度插值（与 DockFrameInterpolator.interpolate 同式）。
func avoLerp(_ a: NSRect, _ b: NSRect, _ p: CGFloat) -> NSRect {
    NSRect(x: a.origin.x + (b.origin.x - a.origin.x) * p,
           y: a.origin.y + (b.origin.y - a.origin.y) * p,
           width: a.width + (b.width - a.width) * p,
           height: a.height + (b.height - a.height) * p)
}

let avoScreen = AvoTestScreen(
    frame: NSRect(x: -10000, y: -10000, width: 20000, height: 20000),
    visible: NSRect(x: -10000, y: -10000, width: 20000, height: 20000))
let avoScreen2 = AvoTestScreen(
    frame: NSRect(x: -10000, y: -10000, width: 20000, height: 20000),
    visible: NSRect(x: -10000, y: -10000, width: 20000, height: 20000))
let avoPet = CGRect(x: 100, y: 100, width: 172, height: 179)            // maxY=279
let avoObstacle = CGRect(x: 120, y: 279, width: 60, height: 24)          // 控制按钮 279..303
let avoBaseQuartz = Geometry.safeDockFrame(
    pet: avoPet, avoiding: [], dockSize: CGSize(width: 200, height: 48), gap: 2, screen: avoScreen).frame!
let avoAvoidQuartz = Geometry.safeDockFrame(
    pet: avoPet, avoiding: [avoObstacle], dockSize: CGSize(width: 200, height: 48), gap: 2, screen: avoScreen).frame!
check("T-avo0 前置：基础位281/避让位305（Quartz）",
      avoBaseQuartz.origin.y == 281 && avoAvoidQuartz.origin.y == 305,
      "base=\(avoBaseQuartz.origin.y) avoid=\(avoAvoidQuartz.origin.y)")
let avoBaseAppKit = Geometry.appKitRectFromQuartz(avoBaseQuartz)
let avoAvoidAppKit = Geometry.appKitRectFromQuartz(avoAvoidQuartz)

var avoClock: TimeInterval = 0
var avoLinks: [TestAnimationDisplayLink] = []
var avoTimers: [TestFollowTickTimer] = []
func avoMakeDock(linkFactory: @escaping (NSObject, Selector) -> FollowDisplayLink?) -> DockPanel {
    DockPanel(
        makeAnimationDisplayLink: linkFactory,
        makeAnimationTimer: { interval, repeats, callback in
            let timer = TestFollowTickTimer(interval: interval, repeats: repeats, callback: callback)
            avoTimers.append(timer)
            return timer
        },
        animationMonotonicNow: { avoClock }
    )
}
let avoDock = avoMakeDock(linkFactory: { target, selector in
    let link = TestAnimationDisplayLink(target: target, selector: selector)
    avoLinks.append(link)
    return link
})

// T-avo1 按钮出现（障碍 0→1）：放置拍停在起点，fake link 显示节拍推进，200ms 精确到位。
_ = avoDock.placeBelow(petQuartzRect: avoPet, avoiding: [], visibleScreen: avoScreen,
                       movementChanged: false, monotonicNow: 0)
let avoAppearStart = avoDock.frame
check("T-avo1a 出现首拍：snap 基础位且无动画源",
      avoFrameNear(avoAppearStart, avoBaseAppKit) && avoLinks.isEmpty && avoTimers.isEmpty,
      "start=\(avoAppearStart)")
avoClock = 10
_ = avoDock.placeBelow(petQuartzRect: avoPet, avoiding: [avoObstacle], visibleScreen: avoScreen,
                       movementChanged: false, monotonicNow: 10)
var avoAppearFrames = [avoDock.frame]
for avoOffset in [0.05, 0.1, 0.15, 0.2] {
    avoClock = 10 + avoOffset
    avoLinks.last?.fire()
    avoAppearFrames.append(avoDock.frame)
}
let avoAppearExpected = [0.05, 0.1, 0.15, 0.2].map {
    avoLerp(avoBaseAppKit, avoAvoidAppKit,
            CGFloat(DockFrameInterpolator.smoothstep($0 / DockFrameInterpolator.avoidanceDuration)))
}
var avoAppearProgressiveOK = avoFrameNear(avoAppearFrames[0], avoBaseAppKit)
for avoIdx in 0..<4 {
    avoAppearProgressiveOK = avoAppearProgressiveOK
        && avoFrameNear(avoAppearFrames[avoIdx + 1], avoAppearExpected[avoIdx])
}
check("T-avo1b 出现：ease-in-out 曲线帧(0.15625/0.5/0.84375/1)渐进且前半慢于线性",
      avoAppearProgressiveOK
        && DockFrameInterpolator.smoothstep(0.25) > 0
        && DockFrameInterpolator.smoothstep(0.25) < 0.25,
      "frames=\(avoAppearFrames)")
check("T-avo1c 出现：200ms 精确落终点且段完成 invalidate 链接",
      avoFrameNear(avoAppearFrames[4], avoAvoidAppKit)
        && abs(avoAppearFrames[4].origin.y - avoAvoidAppKit.origin.y) < 0.51
        && avoLinks.count == 1 && avoLinks[0].added && avoLinks[0].invalidated,
      "final=\(avoAppearFrames[4]) links=\(avoLinks.count)")

// T-avo2 按钮消失（障碍 1→0）：从避让位渐进回基础位，完成后 invalidate。
avoClock = 11
_ = avoDock.placeBelow(petQuartzRect: avoPet, avoiding: [], visibleScreen: avoScreen,
                       movementChanged: false, monotonicNow: 11)
var avoVanishFrames = [avoDock.frame]
for avoOffset in [0.05, 0.1, 0.15, 0.2] {
    avoClock = 11 + avoOffset
    avoLinks.last?.fire()
    avoVanishFrames.append(avoDock.frame)
}
let avoVanishExpected = [0.05, 0.1, 0.15, 0.2].map {
    avoLerp(avoAvoidAppKit, avoBaseAppKit,
            CGFloat(DockFrameInterpolator.smoothstep($0 / DockFrameInterpolator.avoidanceDuration)))
}
check("T-avo2 消失：渐进回基础位且完成后 invalidate",
      avoFrameNear(avoVanishFrames[0], avoAvoidAppKit)
        && (0..<4).allSatisfy { avoFrameNear(avoVanishFrames[$0 + 1], avoVanishExpected[$0]) }
        && avoFrameNear(avoVanishFrames[4], avoBaseAppKit)
        && avoLinks.count == 2 && avoLinks[1].invalidated,
      "frames=\(avoVanishFrames)")

// T-avo3 障碍纯平移：movementChanged=true（宠物实质移动、目标随动）→ 拖动走 32ms
// movement 插值（语义来源：movementChanged 分类，不再比对障碍数量/相对范围），不启动动画源。
let avoMovedPet = avoPet.offsetBy(dx: 60, dy: 0)
let avoMovedObstacle = avoObstacle.offsetBy(dx: 60, dy: 0)
let avoMovedAvoidAppKit = Geometry.appKitRectFromQuartz(avoAvoidQuartz.offsetBy(dx: 60, dy: 0))
let avoMoveDock = avoMakeDock(linkFactory: { target, selector in
    let link = TestAnimationDisplayLink(target: target, selector: selector)
    avoLinks.append(link)
    return link
})
_ = avoMoveDock.placeBelow(petQuartzRect: avoPet, avoiding: [avoObstacle], visibleScreen: avoScreen,
                           movementChanged: false, monotonicNow: 12)
let avoMoveStart = avoMoveDock.frame
avoClock = 13
_ = avoMoveDock.placeBelow(petQuartzRect: avoMovedPet, avoiding: [avoMovedObstacle], visibleScreen: avoScreen,
                           movementChanged: true, monotonicNow: 13)
avoClock = 13.016
_ = avoMoveDock.placeBelow(petQuartzRect: avoMovedPet, avoiding: [avoMovedObstacle], visibleScreen: avoScreen,
                           movementChanged: false, monotonicNow: 13.016)
let avoMoveMid = avoMoveDock.frame
avoClock = 13.04
_ = avoMoveDock.placeBelow(petQuartzRect: avoMovedPet, avoiding: [avoMovedObstacle], visibleScreen: avoScreen,
                           movementChanged: false, monotonicNow: 13.04)
let avoMoveFinal = avoMoveDock.frame
check("T-avo3 障碍纯平移：32ms movement 插值且不启动动画源",
      avoFrameNear(avoMoveStart, avoAvoidAppKit)
        && between(avoMoveMid.origin.x,
                   min(avoAvoidAppKit.origin.x, avoMovedAvoidAppKit.origin.x) + 8,
                   max(avoAvoidAppKit.origin.x, avoMovedAvoidAppKit.origin.x) - 8)
        && !avoFrameNear(avoMoveMid, avoAvoidAppKit) && !avoFrameNear(avoMoveMid, avoMovedAvoidAppKit)
        && avoFrameNear(avoMoveFinal, avoMovedAvoidAppKit)
        && avoLinks.count == 2 && avoTimers.isEmpty,
      "start=\(avoMoveStart) mid=\(avoMoveMid) final=\(avoMoveFinal)")

// T-avo4 插值器数学（纯值）：smoothstep 单调、200ms 精确、无过冲、retarget/movement 覆盖/snap。
var avoMath = DockFrameInterpolator()
_ = avoMath.snap(to: interpA)
let avoMathStart = avoMath.updateAvoidance(to: interpB, at: 0)
let avoMathKindActive = avoMath.segmentKind == .avoidance     // 采样前快照（采样会推进/完成段）
let avoMathEase = [0.05, 0.1, 0.15].map { avoMath.frame(at: $0)! }
let avoMathEnd = avoMath.frame(at: DockFrameInterpolator.avoidanceDuration)!
let avoMathAfterEnd = avoMath.frame(at: DockFrameInterpolator.avoidanceDuration + 0.05)!
let avoMathEaseExpected = [0.05, 0.1, 0.15].map {
    avoLerp(interpA, interpB,
            CGFloat(DockFrameInterpolator.smoothstep($0 / DockFrameInterpolator.avoidanceDuration)))
}
check("T-avo4a avoidance 数学：smoothstep 单调、200ms 精确到 target、无过冲",
      rectNear(avoMathStart, interpA)
        && avoMathKindActive
        && (0..<3).allSatisfy { rectNear(avoMathEase[$0], avoMathEaseExpected[$0]) }
        && (0..<2).allSatisfy {
            abs(avoMathEase[$0 + 1].origin.x - avoMathEase[$0].origin.x) > 0.01
        }
        && rectNear(avoMathEnd, interpB) && avoMath.segmentStartedAt == nil && avoMath.segmentKind == nil
        && rectNear(avoMathAfterEnd, interpB),
      "ease=\(avoMathEase) end=\(avoMathEnd)")
check("T-avo4b smoothstep：中点=线性中点、1/4点介于 step 与线性之间",
      DockFrameInterpolator.smoothstep(0.5) == 0.5
        && DockFrameInterpolator.smoothstep(0.25) > 0
        && DockFrameInterpolator.smoothstep(0.25) < 0.25
        && DockFrameInterpolator.smoothstep(0.75) > 0.75
        && DockFrameInterpolator.smoothstep(0.75) < 1,
      "s0.25=\(DockFrameInterpolator.smoothstep(0.25))")
let avoRetargetStarted = avoMath.updateAvoidance(to: interpC, at: 0.3)
let avoRetargetFrom = avoMath.frame(at: 0.35)!
let avoRetargetRestart = avoMath.updateAvoidance(to: interpA, at: 0.35)
let avoRetargetKindActive = avoMath.segmentKind == .avoidance
let avoRetargetMid = avoMath.frame(at: 0.45)!   // 0.1s/0.2s = 50% ease 中点
let avoRetargetExpectedMid = avoLerp(avoRetargetFrom, interpA, CGFloat(DockFrameInterpolator.smoothstep(0.5)))
check("T-avo4c 动画中 avoidance retarget：从当前渲染帧起新段（latest-only）",
      rectNear(avoRetargetStarted, interpB) && rectNear(avoRetargetRestart, avoRetargetFrom)
        && rectNear(avoRetargetMid, avoRetargetExpectedMid)
        && avoRetargetKindActive,
      "started=\(avoRetargetStarted) from=\(avoRetargetFrom) mid=\(avoRetargetMid)")
_ = avoMath.frame(at: 0.38)!
let avoOverrideStart = avoMath.update(to: interpB, at: 0.38)
let avoOverrideKindMovement = avoMath.segmentKind == .movement
let avoOverrideMid = avoMath.frame(at: 0.396)!
let avoOverrideEnd = avoMath.frame(at: 0.413)!
let avoOverrideExpectedMid = avoLerp(avoOverrideStart, interpB, 0.5)
check("T-avo4d 动画中 movement 到来：立即切 32ms 线性段并精确到位",
      avoOverrideKindMovement
        && rectNear(avoOverrideMid, avoOverrideExpectedMid)
        && rectNear(avoOverrideEnd, interpB),
      "mid=\(avoOverrideMid) end=\(avoOverrideEnd)")
let avoStationaryStart = avoMath.updateAvoidance(to: interpA, at: 0.42)
let avoStationaryKindActive = avoMath.segmentKind == .avoidance
let avoStationaryMid = avoMath.frame(at: 0.52)!
avoMath.reset()
let avoResetSnap = avoMath.updateAvoidance(to: interpB, at: 0.6)
check("T-avo4e 静止目标变化起avoidance段；reset后updateAvoidance立即snap不留段(安全路径)",
      rectNear(avoStationaryStart, interpB) && avoStationaryKindActive
        && !rectNear(avoStationaryMid, interpA) && !rectNear(avoStationaryMid, interpB)
        && between(avoStationaryMid.origin.x, interpA.origin.x, interpB.origin.x)
        && rectNear(avoResetSnap, interpB) && avoMath.segmentStartedAt == nil && avoMath.segmentKind == nil,
      "start=\(avoStationaryStart) mid=\(avoStationaryMid) resetSnap=\(avoResetSnap)")

// T-avo5 生命周期：hide/换屏路径 invalidate；hide 后重现首放 snap。
avoClock = 20
_ = avoDock.placeBelow(petQuartzRect: avoPet, avoiding: [], visibleScreen: avoScreen,
                       movementChanged: false, monotonicNow: 20)
let avoHideLinksBefore = avoLinks.count
avoClock = 20.5
_ = avoDock.placeBelow(petQuartzRect: avoPet, avoiding: [avoObstacle], visibleScreen: avoScreen,
                       movementChanged: false, monotonicNow: 20.5)
avoDock.hideIfNeeded()
let avoHideLinksAfterHide = avoLinks.count
_ = avoDock.placeBelow(petQuartzRect: avoPet, avoiding: [], visibleScreen: avoScreen,
                       movementChanged: false, monotonicNow: 21)
check("T-avo5a 隐藏路径：invalidate 动画源且重现首放 snap（不再动画）",
      avoHideLinksAfterHide == avoHideLinksBefore + 1
        && avoLinks.last?.invalidated == true
        && avoLinks.count == avoHideLinksAfterHide
        && avoFrameNear(avoDock.frame, avoBaseAppKit),
      "links=\(avoLinks.count) frame=\(avoDock.frame)")
avoClock = 21.5
_ = avoDock.placeBelow(petQuartzRect: avoPet, avoiding: [avoObstacle], visibleScreen: avoScreen,
                       movementChanged: false, monotonicNow: 21.5)
avoClock = 21.6
_ = avoDock.placeBelow(petQuartzRect: avoPet, avoiding: [avoObstacle], visibleScreen: avoScreen2,
                       movementChanged: false, monotonicNow: 21.6)
check("T-avo5b 换屏路径：立即 snap 到目标且 invalidate 动画源",
      avoFrameNear(avoDock.frame, avoAvoidAppKit) && avoLinks.last?.invalidated == true,
      "frame=\(avoDock.frame)")

// T-avo6 macOS13 fallback：display link 工厂返回 nil → 60Hz repeating Timer 渲染渐进并完成失效。
let avoFallbackDock = avoMakeDock(linkFactory: { _, _ in nil })
_ = avoFallbackDock.placeBelow(petQuartzRect: avoPet, avoiding: [], visibleScreen: avoScreen,
                               movementChanged: false, monotonicNow: 22)
let avoFallbackTimersBefore = avoTimers.count
_ = avoFallbackDock.placeBelow(petQuartzRect: avoPet, avoiding: [avoObstacle], visibleScreen: avoScreen,
                               movementChanged: false, monotonicNow: 22.5)
let avoFallbackTimer = avoTimers.last!
avoClock = 22.6
avoFallbackTimer.fire()
let avoFallbackMid = avoFallbackDock.frame
avoClock = 22.75
avoFallbackTimer.fire()
let avoFallbackFinal = avoFallbackDock.frame
check("T-avo6 macOS13 fallback：nil link→60Hz repeating Timer 渲染渐进并完成失效",
      avoTimers.count == avoFallbackTimersBefore + 1
        && avoFallbackTimer.repeats
        && abs(avoFallbackTimer.interval - DockPanel.avoidanceFallbackInterval) < 0.0001
        && between(avoFallbackMid.origin.y,
                   min(avoBaseAppKit.origin.y, avoAvoidAppKit.origin.y) + 4,
                   max(avoBaseAppKit.origin.y, avoAvoidAppKit.origin.y) - 4)
        && !avoFrameNear(avoFallbackMid, avoBaseAppKit) && !avoFrameNear(avoFallbackMid, avoAvoidAppKit)
        && avoFrameNear(avoFallbackFinal, avoAvoidAppKit)
        && avoFallbackTimer.invalidated,
      "mid=\(avoFallbackMid) final=\(avoFallbackFinal)")

// T-avo7 生产组合：FollowLayoutPass → 真实 DockPanel.placeBelow + fake link 手动 fire。
// 按钮出现 → dock 渐进下移（≥3 个中间帧递增）；消失 → 渐进上移；最终帧精确。
let avoProdMascot = mkw(9701, layer: 2, avoPet, title: "Codex Pet Mascot Effect")
let avoProdControl = mkw(9702, layer: 3, CGRect(x: 140, y: 279, width: 60, height: 24))
let avoProdProbe = BubbleVisibilityProbe(
    monotonicNow: { 50_000 }, canCapture: { true }, capturer: { _ in .unavailable })
let avoProdDock = avoMakeDock(linkFactory: { target, selector in
    let link = TestAnimationDisplayLink(target: target, selector: selector)
    avoLinks.append(link)
    return link
})
var avoProdObstacleCounts: [Int] = []
func avoProdPlace(candidates: [WinCandidate]) -> Bool {
    FollowLayoutPass.placeDock(
        mascot: avoProdMascot,
        candidates: candidates,
        bubbleProbe: avoProdProbe,
        frameSink: { pet, obstacles in
            avoProdObstacleCounts.append(obstacles.count)
            return avoProdDock.placeBelow(
                petQuartzRect: pet,
                avoiding: obstacles,
                visibleScreen: avoScreen,
                movementChanged: false,
                monotonicNow: avoClock)
        })
}
avoClock = 30
_ = avoProdPlace(candidates: [avoProdMascot])
let avoProdLinksBefore = avoLinks.count
avoClock = 30.1
let avoProdShown = avoProdPlace(candidates: [avoProdMascot, avoProdControl])
var avoProdFrames = [avoProdDock.frame]
for avoOffset in [0.05, 0.09, 0.13, 0.17, 0.21] {
    avoClock = 30.1 + avoOffset
    avoLinks.last?.fire()
    avoProdFrames.append(avoProdDock.frame)
}
let avoProdLo = min(avoBaseAppKit.origin.y, avoAvoidAppKit.origin.y)
let avoProdHi = max(avoBaseAppKit.origin.y, avoAvoidAppKit.origin.y)
check("T-avo7a 生产组合按钮出现：渐进下移（≥3 中间帧严格递增）且最终精确",
      avoProdShown && avoProdObstacleCounts == [0, 1]
        && avoLinks.count == avoProdLinksBefore + 1
        // 前三个中间帧必须严格处于两端内部（远离边界）；第四帧处于 95% 采样点，
        // ease-in-out 尾段天然贴近目标（smoothstep(0.95)≈0.993），像素对齐后可能与
        // lo+1 重合——只要求严格未达最终值（< hi 且 > lo），最终精确由 frames[5] 断言。
        && (1..<4).allSatisfy { avoProdFrames[$0].origin.y > avoProdLo + 1 && avoProdFrames[$0].origin.y < avoProdHi - 1 }
        && avoProdFrames[4].origin.y > avoProdLo && avoProdFrames[4].origin.y < avoProdHi
        && (1..<4).allSatisfy {
            abs(avoProdFrames[$0 + 1].origin.y - avoBaseAppKit.origin.y)
                > abs(avoProdFrames[$0].origin.y - avoBaseAppKit.origin.y)
        }
        && avoFrameNear(avoProdFrames[5], avoAvoidAppKit),
      "frames=\(avoProdFrames)")
avoClock = 31
_ = avoProdPlace(candidates: [avoProdMascot])
var avoProdVanishFrames = [avoProdDock.frame]
for avoOffset in [0.05, 0.12, 0.19, 0.24] {
    avoClock = 31 + avoOffset
    avoLinks.last?.fire()
    avoProdVanishFrames.append(avoProdDock.frame)
}
check("T-avo7b 生产组合按钮消失：渐进回基础位、最终精确、链接失效",
      avoProdObstacleCounts == [0, 1, 0]
        && !avoFrameNear(avoProdVanishFrames[1], avoBaseAppKit)
        && !avoFrameNear(avoProdVanishFrames[1], avoAvoidAppKit)
        && avoFrameNear(avoProdVanishFrames[4], avoBaseAppKit)
        && avoLinks.last?.invalidated == true,
      "frames=\(avoProdVanishFrames)")
print("\n[障碍平滑过渡] \(pass - avoPass) passed, \(fail - avoBase) failed")


// ---- T-p1: P1 回归（review-smooth 首轮 P1-1/P1-2；movementChanged 驱动分类）----
// 症状：分类只认障碍 count/range 时，CS 锚变化（气泡展开/收起：CS 障碍 rect 与
// adjustedPet.maxY 协变，count 1→1、range 恒 0）落入 movement 路径，movementChanged=false
// 的目标变化被 snap（P1-1：470↔362 跳变）；在途 avoidance 动画中锚 ±1px 微变同样走
// movement 路径 snap，截断动画（P1-2：~12px 跳变）。新语义：movementChanged（宠物窗口
// 是否实质移动，来自 Follower.shouldSetFrame）是区分“移动”与“内容/障碍/锚变化”的权威
// 信号——静止时任何目标变化统一走 200ms avoidance 平滑（latest-only retarget 平滑续接）。
let pavoBase = fail, pavoPass = pass

// 生产组合 fixture（现场几何，与 T-cs 同构）：宠物 172x179 maxY=386；Composition Surface
// 768x912@(-3)，3 个同 bounds 重复实例去重为代表；无 ACT（保持触发形态 count 1→1）。
let pavoPet = CGRect(x: 1487, y: 207, width: 172, height: 179)
let pavoMascot = mkw(9801, layer: 2, pavoPet, title: "Codex Pet Mascot Effect")
let pavoSurfaceBounds = CGRect(x: 1189, y: -3, width: 768, height: 912)
let pavoSurfaces = [28901, 28902, 28903].map {
    mkw(UInt32($0), layer: 3, pavoSurfaceBounds, title: "Codex Pet Composition Surface")
}
func pavoAppKitDockFrame(y: CGFloat) -> NSRect {
    Geometry.appKitRectFromQuartz(CGRect(
        x: pavoPet.minX + (pavoPet.width - 200) / 2, y: y, width: 200, height: 48))
}
var pavoStats: [CGWindowID: BubbleAlphaStats] = [
    CGWindowID(28901): BubbleAlphaStats(nonTransparentPixelCount: 30_000, contentBottom: 470),
]
let pavoRelease = OSAllocatedUnfairLock(initialState: true)
let pavoProbe = BubbleVisibilityProbe(
    monotonicNow: { avoClock }, canCapture: { true },
    capturer: { c in
        while !pavoRelease.withLock({ $0 }) {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        return .stats(pavoStats[c.wid] ?? BubbleAlphaStats(nonTransparentPixelCount: 0, contentBottom: -1))
    })
var pavoShapeLog: [(count: Int, range: CGFloat)] = []
func pavoPlace(dock: DockPanel) -> Bool {
    FollowLayoutPass.placeDock(
        mascot: pavoMascot,
        candidates: [pavoMascot] + pavoSurfaces,
        bubbleProbe: pavoProbe,
        frameSink: { pet, obstacles in
            pavoShapeLog.append((obstacles.count, obstacles.first.map { $0.maxY - pet.maxY } ?? 0))
            return dock.placeBelow(
                petQuartzRect: pet, avoiding: obstacles, visibleScreen: avoScreen,
                movementChanged: false, monotonicNow: avoClock)
        })
}

// T-p1a 前置（冷启动→展开 470）：首 tick 无 cache → CS 跳过、基础位回退窗口底 388；
// 观察（contentBottom=470）到达后目标 470 经 avoidance 平滑到位。
let pavoDock = avoMakeDock(linkFactory: { target, selector in
    let link = TestAnimationDisplayLink(target: target, selector: selector)
    avoLinks.append(link)
    return link
})
avoClock = 40
_ = pavoPlace(dock: pavoDock)
check("T-p1a 冷启动首tick无cache→基础位回退窗口底388",
      avoFrameNear(pavoDock.frame, pavoAppKitDockFrame(y: 388)) && pavoShapeLog.last?.count == 0,
      "frame=\(pavoDock.frame) shapes=\(pavoShapeLog)")
_ = waitPumpingMain { !pavoProbe.lock.withLock { $0.inFlight } }
avoClock = 40.2
_ = pavoPlace(dock: pavoDock)
for pavoOffset in [0.05, 0.1, 0.15, 0.21] {
    avoClock = 40.2 + pavoOffset
    avoLinks.last?.fire()
}
check("T-p1a2 展开470观察到达→avoidance渐进到位(前置)",
      avoFrameNear(pavoDock.frame, pavoAppKitDockFrame(y: 470))
        && avoLinks.last?.invalidated == true,
      "frame=\(pavoDock.frame)")

// T-p1b 收起（P1-1 正片）：contentBottom 470→362（count 1→1、range 恒 0、
// movementChanged=false）→ dock 渐进回基础位 362（≥3 中间帧严格趋近、非 snap），
// 动画源期间活跃、最终精确到位并失效。
pavoStats[CGWindowID(28901)] = BubbleAlphaStats(nonTransparentPixelCount: 30_000, contentBottom: 362)
pavoShapeLog.removeAll()
let pavoCollapseLinksBefore = avoLinks.count
avoClock = 41
pavoRelease.withLock { $0 = false }
_ = pavoPlace(dock: pavoDock)                    // 重捕获在途（旧 cache 470 仍生效）→ hold
pavoRelease.withLock { $0 = true }
_ = waitPumpingMain { !pavoProbe.lock.withLock { $0.inFlight } }
avoClock = 41.2
_ = pavoPlace(dock: pavoDock)                    // cache 362 → 静止目标变化 → avoidance 段
let pavoCollapsePlaced = pavoDock.frame
var pavoCollapseFrames = [pavoCollapsePlaced]
var pavoCollapseMidLinkActive = false
for pavoOffset in [0.05, 0.1, 0.15] {
    avoClock = 41.2 + pavoOffset
    avoLinks.last?.fire()
    pavoCollapseFrames.append(pavoDock.frame)
    pavoCollapseMidLinkActive = avoLinks.last?.invalidated == false
}
avoClock = 41.41   // 越过 41.2+0.2 的浮点表示边界，确保段完成判定（帧值仍精确到终点）
avoLinks.last?.fire()
pavoCollapseFrames.append(pavoDock.frame)
let pavoCollapseExpected = [0.05, 0.1, 0.15, 0.2].map {
    avoLerp(pavoAppKitDockFrame(y: 470), pavoAppKitDockFrame(y: 362),
            CGFloat(DockFrameInterpolator.smoothstep($0 / DockFrameInterpolator.avoidanceDuration)))
}
check("T-p1b 收起(P1-1):count1→1/range0→0/静止→渐进回基础位362(非snap)",
      pavoShapeLog.count == 2
        && pavoShapeLog.allSatisfy { $0.count == 1 && abs($0.range) < 0.000_001 }
        && avoFrameNear(pavoCollapsePlaced, pavoAppKitDockFrame(y: 470))
        && avoLinks.count == pavoCollapseLinksBefore + 1
        && pavoCollapseMidLinkActive
        && (0..<4).allSatisfy { avoFrameNear(pavoCollapseFrames[$0 + 1], pavoCollapseExpected[$0]) }
        && (1..<4).allSatisfy {
            abs(pavoCollapseFrames[$0].origin.y - pavoAppKitDockFrame(y: 362).origin.y)
                > abs(pavoCollapseFrames[$0 + 1].origin.y - pavoAppKitDockFrame(y: 362).origin.y) + 4
        }
        && avoFrameNear(pavoCollapseFrames[4], pavoAppKitDockFrame(y: 362))
        && avoLinks.last?.invalidated == true,
      "shapes=\(pavoShapeLog) frames=\(pavoCollapseFrames)")

// T-p1c 展开（P1-1 反向）：362→470 同触发形态（count 1→1、range 0→0）→ 同样渐进。
pavoStats[CGWindowID(28901)] = BubbleAlphaStats(nonTransparentPixelCount: 30_000, contentBottom: 470)
pavoShapeLog.removeAll()
let pavoExpandLinksBefore = avoLinks.count
avoClock = 42
pavoRelease.withLock { $0 = false }
_ = pavoPlace(dock: pavoDock)
pavoRelease.withLock { $0 = true }
_ = waitPumpingMain { !pavoProbe.lock.withLock { $0.inFlight } }
avoClock = 42.2
_ = pavoPlace(dock: pavoDock)
var pavoExpandFrames = [pavoDock.frame]
for pavoOffset in [0.05, 0.1, 0.15, 0.21] {
    avoClock = 42.2 + pavoOffset
    avoLinks.last?.fire()
    pavoExpandFrames.append(pavoDock.frame)
}
let pavoExpandExpected = [0.05, 0.1, 0.15, 0.2].map {
    avoLerp(pavoAppKitDockFrame(y: 362), pavoAppKitDockFrame(y: 470),
            CGFloat(DockFrameInterpolator.smoothstep($0 / DockFrameInterpolator.avoidanceDuration)))
}
check("T-p1c 展开(P1-1反向):362→470渐进到位(非snap)",
      pavoShapeLog.count == 2
        && pavoShapeLog.allSatisfy { $0.count == 1 && abs($0.range) < 0.000_001 }
        && avoLinks.count == pavoExpandLinksBefore + 1
        && (0..<4).allSatisfy { avoFrameNear(pavoExpandFrames[$0 + 1], pavoExpandExpected[$0]) }
        && (1..<4).allSatisfy {
            abs(pavoExpandFrames[$0].origin.y - pavoAppKitDockFrame(y: 470).origin.y)
                > abs(pavoExpandFrames[$0 + 1].origin.y - pavoAppKitDockFrame(y: 470).origin.y) + 4
        }
        && avoFrameNear(pavoExpandFrames[4], pavoAppKitDockFrame(y: 470)),
      "shapes=\(pavoShapeLog) frames=\(pavoExpandFrames)")

// T-p1d（P1-2）：按钮消失回落动画进行中（0.08s 处），下一 tick 锚 contentBottom +1px →
// latest-only retarget 平滑续接：retarget 拍帧 = 旧段该时刻采样值（而非新终点 snap 截断），
// 后续帧按新段曲线单调趋近 ±1px 新基础位，最终精确；同目标 stable tick（hold）不重置进度。
let pav2Dock = avoMakeDock(linkFactory: { target, selector in
    let link = TestAnimationDisplayLink(target: target, selector: selector)
    avoLinks.append(link)
    return link
})
avoClock = 45
_ = pav2Dock.placeBelow(petQuartzRect: avoPet, avoiding: [avoObstacle], visibleScreen: avoScreen,
                      movementChanged: false, monotonicNow: 45)
avoClock = 45.2
_ = pav2Dock.placeBelow(petQuartzRect: avoPet, avoiding: [], visibleScreen: avoScreen,
                      movementChanged: false, monotonicNow: 45.2)   // 消失回落段起点
avoClock = 45.28
avoLinks.last?.fire()                                                // 0.08s 中点采样
let pav2MidFrame = pav2Dock.frame
let pav2Base281AppKit = Geometry.appKitRectFromQuartz(
    CGRect(x: avoBaseQuartz.origin.x, y: 281, width: 200, height: 48))
let pav2Base282AppKit = Geometry.appKitRectFromQuartz(
    CGRect(x: avoBaseQuartz.origin.x, y: 282, width: 200, height: 48))
let pav2RetargetLinksBefore = avoLinks.count
avoClock = 45.3
_ = pav2Dock.placeBelow(petQuartzRect: avoPet.offsetBy(dx: 0, dy: 1), avoiding: [],
                      visibleScreen: avoScreen, movementChanged: false, monotonicNow: 45.3)
let pav2RetargetFrame = pav2Dock.frame
let pav2ExpectedRetarget = avoLerp(avoAvoidAppKit, pav2Base281AppKit,
                                 CGFloat(DockFrameInterpolator.smoothstep(0.5)))
var pav2Frames = [pav2RetargetFrame]
var pav2Expected = [pav2ExpectedRetarget]
for pav2Offset in [0.02, 0.06] {
    avoClock = 45.3 + pav2Offset
    avoLinks.last?.fire()
    pav2Frames.append(pav2Dock.frame)
    pav2Expected.append(avoLerp(pav2ExpectedRetarget, pav2Base282AppKit,
                              CGFloat(DockFrameInterpolator.smoothstep(pav2Offset / DockFrameInterpolator.avoidanceDuration))))
}
avoClock = 45.38
_ = pav2Dock.placeBelow(petQuartzRect: avoPet.offsetBy(dx: 0, dy: 1), avoiding: [],
                      visibleScreen: avoScreen, movementChanged: false, monotonicNow: 45.38)
let pav2HoldFrame = pav2Dock.frame
for pav2Offset in [0.1] {
    avoClock = 45.3 + pav2Offset
    avoLinks.last?.fire()
    pav2Frames.append(pav2Dock.frame)
    pav2Expected.append(avoLerp(pav2ExpectedRetarget, pav2Base282AppKit,
                              CGFloat(DockFrameInterpolator.smoothstep(pav2Offset / DockFrameInterpolator.avoidanceDuration))))
}
avoClock = 45.51   // 越过 45.3+0.2 的浮点表示边界；段完成精确落终点
avoLinks.last?.fire()
pav2Frames.append(pav2Dock.frame)
pav2Expected.append(pav2Base282AppKit)
check("T-p1d (P1-2)回落动画中锚+1px→latest-only续接(无snap截断),hold不重置,最终精确",
      avoFrameNear(pav2MidFrame, avoLerp(avoAvoidAppKit, pav2Base281AppKit,
                                       CGFloat(DockFrameInterpolator.smoothstep(0.4))))
        && avoFrameNear(pav2RetargetFrame, pav2ExpectedRetarget)
        && abs(pav2RetargetFrame.origin.y - pav2Base282AppKit.origin.y) > 2
        && avoLinks.count == pav2RetargetLinksBefore
        && avoFrameNear(pav2HoldFrame, avoLerp(pav2ExpectedRetarget, pav2Base282AppKit,
                                             CGFloat(DockFrameInterpolator.smoothstep(0.4))))
        && (0..<5).allSatisfy { avoFrameNear(pav2Frames[$0], pav2Expected[$0]) }
        && avoFrameNear(pav2Frames[4], pav2Base282AppKit)
        && avoLinks.last?.invalidated == true,
      "mid=\(pav2MidFrame) retarget=\(pav2RetargetFrame) hold=\(pav2HoldFrame) frames=\(pav2Frames)")

// T-p1m：avoidance 动画中 movementChanged=true（拖动）→ 立即切 32ms movement 段并
// invalidate 动画源（movement 覆盖语义；拖动中障碍平移走 movement 插值而非 avoidance，
// 与 T-avo3 同源；纯值层见 T-avo4d）。
let pavoMoveDock = avoMakeDock(linkFactory: { target, selector in
    let link = TestAnimationDisplayLink(target: target, selector: selector)
    avoLinks.append(link)
    return link
})
avoClock = 46
_ = pavoMoveDock.placeBelow(petQuartzRect: avoPet, avoiding: [], visibleScreen: avoScreen,
                          movementChanged: false, monotonicNow: 46)
avoClock = 46.2
_ = pavoMoveDock.placeBelow(petQuartzRect: avoPet, avoiding: [avoObstacle], visibleScreen: avoScreen,
                          movementChanged: false, monotonicNow: 46.2)   // avoidance 段 + link
avoClock = 46.25
avoLinks.last?.fire()
let pavoMoveMid = pavoMoveDock.frame
let pavoMoveLinksBefore = avoLinks.count
avoClock = 46.25
_ = pavoMoveDock.placeBelow(petQuartzRect: avoMovedPet, avoiding: [avoMovedObstacle],
                          visibleScreen: avoScreen, movementChanged: true, monotonicNow: 46.25)
let pavoMovePlaced = pavoMoveDock.frame
avoClock = 46.266
_ = pavoMoveDock.placeBelow(petQuartzRect: avoMovedPet, avoiding: [avoMovedObstacle],
                          visibleScreen: avoScreen, movementChanged: false, monotonicNow: 46.266)
let pavoMoveFollow = pavoMoveDock.frame
avoClock = 46.3
_ = pavoMoveDock.placeBelow(petQuartzRect: avoMovedPet, avoiding: [avoMovedObstacle],
                          visibleScreen: avoScreen, movementChanged: false, monotonicNow: 46.3)
check("T-p1m 动画中movementChanged=true→切32ms段+invalidate动画源(障碍平移走movement)",
      !avoFrameNear(pavoMoveMid, avoAvoidAppKit) && !avoFrameNear(pavoMoveMid, avoBaseAppKit)
        && avoLinks.count == pavoMoveLinksBefore && avoLinks.last?.invalidated == true
        && avoFrameNear(pavoMovePlaced, pavoMoveMid)
        && between(pavoMoveFollow.origin.x,
                   min(pavoMoveMid.origin.x, avoMovedAvoidAppKit.origin.x) + 8,
                   max(pavoMoveMid.origin.x, avoMovedAvoidAppKit.origin.x) - 8)
        && !avoFrameNear(pavoMoveFollow, pavoMoveMid)
        && avoFrameNear(pavoMoveDock.frame, avoMovedAvoidAppKit),
      "mid=\(pavoMoveMid) placed=\(pavoMovePlaced) follow=\(pavoMoveFollow) final=\(pavoMoveDock.frame)")
print("\n[P1回归 movementChanged分类] \(pass - pavoPass) passed, \(fail - pavoBase) failed")


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

// ---- T-bv: BubbleVisibility 分类（纯函数·内容噪声下限）+ 调度（0.1s/single-flight/reset）+ 异步集成（generation/strict single-flight）----
let bvBase = fail, bvPass = pass
// 进程内权限请求 gate：preflight=false 只请求一次；preflight=true 不请求。
var requestGate = ScreenCapturePermissionRequestGate()
check("T-bv0a preflight=false首次请求", requestGate.shouldRequest(preflightGranted: false), "")
check("T-bv0b preflight=false重复检查不再请求", !requestGate.shouldRequest(preflightGranted: false), "")
var grantedGate = ScreenCapturePermissionRequestGate()
check("T-bv0c preflight=true不请求", !grantedGate.shouldRequest(preflightGranted: true), "")
check("T-bv0d preflight后续false仍可首次请求", grantedGate.shouldRequest(preflightGranted: false), "")
// 噪声下限现场校准（2026-08-24 像素级重测）：宿主收起后 ACT 容器仅剩 39-57 个非透明
// 像素的不可见小点（6-7px 宽、窗口内 y[21,28]，截屏放大肉眼不可见）；控制按钮出现时
// 实测 189-194px。minContentPixels=80（上 margin 57<80、下 margin 80<189，双向 ≥40% 余量）。
// 旧阈值 3 基于“25/34px 可见横条”旧测量，已被该现场证据取代：低于 80 → hidden。
let collapsedS = BubbleAlphaStats(nonTransparentPixelCount: 41, contentBottom: 28)
let expandedS = BubbleAlphaStats(nonTransparentPixelCount: 189, contentBottom: 53)
let noiseS = BubbleAlphaStats(nonTransparentPixelCount: 2, contentBottom: 21)
let floorS = BubbleAlphaStats(nonTransparentPixelCount: 80, contentBottom: 21)
let bv1Obs = BubbleVisibilityClassifier.classify(stats: collapsedS)
check("T-bv1 收起噪声点(41px<80)→hidden(2026-08-24现场校准)",
      bv1Obs.visibility == .hidden && bv1Obs.contentBottom == nil, "")
let bv2Obs = BubbleVisibilityClassifier.classify(stats: expandedS)
check("T-bv2 expanded(189px)→visible+内容底53",
      bv2Obs.visibility == .visible && bv2Obs.contentBottom == 53, "")
check("T-bv3 低于噪声下限(2px)→hidden(无滞回,不沿用previous)",
      BubbleVisibilityClassifier.classify(stats: noiseS).visibility == .hidden, "")
check("T-bv4 恰达噪声下限(80px)→visible(边界)",
      BubbleVisibilityClassifier.classify(stats: floorS).visibility == .visible, "")
check("T-bv4b 校准边界:噪声上margin 57px→hidden,控制按钮189px→visible",
      BubbleVisibilityClassifier.classify(
        stats: BubbleAlphaStats(nonTransparentPixelCount: 57, contentBottom: 28)).visibility == .hidden
        && BubbleVisibilityClassifier.classify(
          stats: BubbleAlphaStats(nonTransparentPixelCount: 189, contentBottom: 38)).visibility == .visible,
      "")
// P1 unavailable 保守语义（README: capture failure conservatively avoids）：
// 当前仍存在的气泡，SC 捕获失败（macOS13/TCC 抖动/窗口刚注册未进 SC content）
// 必须保守判 visible 且无内容底边（整窗避让），不能因捕获失败当成收起导致底座重叠气泡。
let bv5Obs = BubbleVisibilityClassifier.classify(outcome: .unavailable, hasSuccessfulObservation: true)
check("T-bv5 unavailable(已成功观察过)→保守visible无内容底(整窗避让)",
      bv5Obs.visibility == .visible && bv5Obs.contentBottom == nil, "")
let bv5bObs = BubbleVisibilityClassifier.classify(outcome: .unavailable, hasSuccessfulObservation: false)
check("T-bv5b unavailable(从未观察)→保守visible",
      bv5bObs.visibility == .visible && bv5bObs.contentBottom == nil, "")
let bv5cObs = BubbleVisibilityClassifier.classify(outcome: .targetMissing, hasSuccessfulObservation: false)
check("T-bv5c 首次观察即targetMissing→保守visible",
      bv5cObs.visibility == .visible, "")

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
probe.lock.withLock {
    $0.inFlight = false
    $0.cached = [CGWindowID(1): BubbleObservation(visibility: .visible, contentBottom: nil)]
}
probe.reset()
check("T-bv11 reset→cached空(inFlight不变)", probe.lock.withLock { $0.cached.isEmpty && !$0.inFlight }, "")
probe.lock.withLock { $0.inFlight = false }
check("T-bv12 wid不在当前候选集→hidden(当前帧失效)", probe.visibility(for: CGWindowID(99)) == .hidden, "")

// T-bv13 (v6): 窗口身份稳定时使用 1s 心跳；身份变化立即恢复 0.1s 快速节奏。
// factory/capture 计数证明同一轮候选共享一个 capturer，ScreenCaptureKit 清单枚举只发生一次。
do {
    let stableClock = OSAllocatedUnfairLock(initialState: TimeInterval(4_000))
    let factoryCalls = OSAllocatedUnfairLock(initialState: 0)
    let captureCalls = OSAllocatedUnfairLock(initialState: 0)
    let makeCapturer: BubbleCapturerFactory = {
        factoryCalls.withLock { $0 += 1 }
        return { _ in
            captureCalls.withLock { $0 += 1 }
            return .stats(expandedS)
        }
    }
    let stableBounds = CGRect(x: 0, y: 580, width: 345, height: 64)
    let stableCandidate = mkw(101, layer: 3, stableBounds, title: "Codex Bubble")
    let stableProbe = BubbleVisibilityProbe(
        monotonicNow: { stableClock.withLock { $0 } }, canCapture: { true }, makeCapturer: makeCapturer)

    stableProbe.probe(candidates: [stableCandidate])
    _ = waitPumpingMain { !stableProbe.lock.withLock { $0.inFlight } }
    stableClock.withLock { $0 = 4_000.5 }
    stableProbe.probe(candidates: [stableCandidate])
    stableClock.withLock { $0 = 4_001 }
    stableProbe.probe(candidates: [stableCandidate])
    _ = waitPumpingMain { !stableProbe.lock.withLock { $0.inFlight } }
    check("T-bv13a 稳定身份0.5s不捕获、1.0s捕获",
          factoryCalls.withLock { $0 } == 2 && captureCalls.withLock { $0 } == 2,
          "factory=\(factoryCalls.withLock { $0 }) captures=\(captureCalls.withLock { $0 })")

    stableClock.withLock { $0 = 4_001.05 }
    let identityChangedCandidate = mkw(
        101, layer: 3, stableBounds.offsetBy(dx: 2, dy: 0),
        title: "Codex Bubble Changed", alpha: 0.99)
    stableProbe.probe(candidates: [identityChangedCandidate])
    let gatedCalls = (factoryCalls.withLock { $0 }, captureCalls.withLock { $0 })
    stableClock.withLock { $0 = 4_001.101 }
    stableProbe.probe(candidates: [identityChangedCandidate])
    _ = waitPumpingMain { !stableProbe.lock.withLock { $0.inFlight } }
    check("T-bv13b 身份变化后0.1s内恢复快速捕获",
          gatedCalls.0 == 2 && gatedCalls.1 == 2
                && factoryCalls.withLock { $0 } == 3
                && captureCalls.withLock { $0 } == 3,
          "gated=\(gatedCalls.0)/\(gatedCalls.1) "
              + "factory=\(factoryCalls.withLock { $0 }) captures=\(captureCalls.withLock { $0 })")
}

do {
    let sharedTime: TimeInterval = 4_100
    let sharedFactoryCalls = OSAllocatedUnfairLock(initialState: 0)
    let sharedCaptureCalls = OSAllocatedUnfairLock(initialState: 0)
    let sharedMakeCapturer: BubbleCapturerFactory = {
        sharedFactoryCalls.withLock { $0 += 1 }
        return { _ in
            sharedCaptureCalls.withLock { $0 += 1 }
            return .stats(expandedS)
        }
    }
    let sharedProbe = BubbleVisibilityProbe(
        monotonicNow: { sharedTime }, canCapture: { true }, makeCapturer: sharedMakeCapturer)
    sharedProbe.probe(candidates: [
        mkw(102, layer: 3, CGRect(x: 0, y: 580, width: 345, height: 64)),
        mkw(103, layer: 3, CGRect(x: 20, y: 580, width: 345, height: 64))
    ])
    _ = waitPumpingMain { !sharedProbe.lock.withLock { $0.inFlight } }
    check("T-bv13c 一轮N候选仅调用一次capturer工厂",
          sharedFactoryCalls.withLock { $0 } == 1
                && sharedCaptureCalls.withLock { $0 } == 2,
          "factory=\(sharedFactoryCalls.withLock { $0 }) captures=\(sharedCaptureCalls.withLock { $0 })")
}

// 异步集成（fake capturer + RunLoop pump）：pending capture 完成 → cached 更新
var fakeTime: TimeInterval = 2000
let fakeHidden: BubbleCapturer = { _ in .stats(noiseS) }
let asyncProbe = BubbleVisibilityProbe(monotonicNow: { fakeTime }, canCapture: { true }, capturer: fakeHidden)
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
    return .stats(noiseS)
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
cacheProbe.lock.withLock {
    $0.cached = [CGWindowID(7): BubbleObservation(visibility: .visible, contentBottom: nil)]
    $0.inFlight = false
}
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
    .stats(expandedS)   // expanded → visible
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
let vanishStats = OSAllocatedUnfairLock<BubbleCaptureOutcome>(initialState: .stats(expandedS))
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
    .stats(expandedS)   // expanded → visible
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
      p1CachedResidue?.visibility == .visible, "cached[A]=\(String(describing: p1CachedResidue))")
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
    return .stats(expandedS)   // visible
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

// T-sch5: moving 态 display link 饿死回归（真实 NSPanel + 真实 CADisplayLink + 真实 runloop Timer）。
// 生产冻结配置：moving + panel 可见 + window-bound display link 永久沉默 + 无兜底节拍源。
// 不注入 fake：makeDisplayLink/canUseDisplayLink 走真实 DockPanel（生产 wiring）。
// 显示服务器不驱动本进程 vsync 时（如本测试环境），恰好构成该冻结配置的确定性复现；
// 能驱动 vsync 的环境中，(b) 的 orderOut 仍保证 link 静默 → 同样确定性复现。
let guiDock = DockPanel()
guiDock.showIfNeeded()
var sch5State: FollowState = .moving
var sch5Ticks = 0
var sch5TickTimes: [TimeInterval] = []
let sch5Now = { ProcessInfo.processInfo.systemUptime }
let sch5Scheduler = FollowTickScheduler(
    runTick: {
        sch5Ticks += 1
        sch5TickTimes.append(sch5Now())
        return sch5State
    },
    makeDisplayLink: { target, selector in
        guard #available(macOS 14.0, *) else { return nil }
        return guiDock.makeDisplayLink(target: target, selector: selector)
    },
    canUseDisplayLink: { guiDock.isDisplayLinkEligible },
    maximumFramesPerSecond: { guiDock.maximumFramesPerSecond }
)
sch5Scheduler.start()
sch5Scheduler.requestWake()
_ = waitPumpingMain { sch5Ticks >= 1 }

// (a0) 首个 moving tick 后：panel 可见 → 生产 wiring 必须选择 window-bound display link。
var sch5LinkExpected = false
if #available(macOS 14.0, *) { sch5LinkExpected = true }
check("T-sch5a0 moving可见panel选择display link",
      sch5Scheduler.isDisplayLinkActive == sch5LinkExpected,
      "isDisplayLinkActive=\(sch5Scheduler.isDisplayLinkActive)")

// (a) moving 态可见 panel：follow tick 不得饿死（link 驱动，或 link 沉默时 watchdog 兜底）。
let sch5BaseA = sch5Ticks
_ = waitPumpingMain({ sch5Ticks >= sch5BaseA + 2 }, timeout: 1.0)
check("T-sch5a moving可见panel节拍持续",
      sch5Ticks >= sch5BaseA + 2,
      "ticksDelta=\(sch5Ticks - sch5BaseA)")

// (b) tick 间隙 panel 被 orderOut（模拟 placeBelow 越界隐藏等窗口生命周期事件）：
// link 静默且 scheduler 无 reconfigure 机会 → 当前唯一节拍源消失。moving tick 仍必须继续。
let sch5BaseB = sch5Ticks
guiDock.hideIfNeeded()
let sch5RecoveredHidden = waitPumpingMain({ sch5Ticks >= sch5BaseB + 2 }, timeout: 1.0)
check("T-sch5b orderOut后moving tick不饿死",
      sch5RecoveredHidden,
      "ticksDelta=\(sch5Ticks - sch5BaseB)")
check("T-sch5b2 饿死保护降级repeating Timer",
      sch5Scheduler.isRepeatingTimerActive,
      "isRepeatingTimerActive=\(sch5Scheduler.isRepeatingTimerActive)")

// (c) panel 恢复显示：moving 节拍持续；转 stable 后恢复 0.1s one-shot cadence；
// 再入 moving 重新选择节拍源（不因上一 episode 的降级 latch 永久锁死 Timer）。
let sch5BaseC = sch5Ticks
guiDock.showIfNeeded()
_ = waitPumpingMain({ sch5Ticks >= sch5BaseC + 2 }, timeout: 1.0)
check("T-sch5c panel恢复显示后moving节拍持续",
      sch5Ticks >= sch5BaseC + 2,
      "ticksDelta=\(sch5Ticks - sch5BaseC)")

sch5State = .stable
let sch5StableStart = sch5Ticks
_ = waitPumpingMain({ sch5Ticks >= sch5StableStart + 3 }, timeout: 1.0)
let sch5StableGap = sch5TickTimes.count >= 2
    ? sch5TickTimes[sch5TickTimes.count - 1] - sch5TickTimes[sch5TickTimes.count - 2]
    : 0
check("T-sch5c2 stable恢复0.1s cadence",
      sch5Ticks >= sch5StableStart + 3 && sch5StableGap >= 0.09 && sch5StableGap <= 0.5,
      "ticksDelta=\(sch5Ticks - sch5StableStart) lastGap=\(String(format: "%.3f", sch5StableGap))")

sch5State = .moving
let sch5BaseD = sch5Ticks
_ = waitPumpingMain({ sch5Ticks >= sch5BaseD + 2 }, timeout: 1.0)
check("T-sch5c3 再入moving节拍恢复",
      sch5Ticks >= sch5BaseD + 2,
      "ticksDelta=\(sch5Ticks - sch5BaseD)")

sch5Scheduler.stop()
guiDock.hideIfNeeded()

// T-sch6: stable cadence 恒 0.1s（真实 runloop Timer，无退避）。R6 决策：用户实测
// 0.2s 退避封底的起步延迟体验不可接受，且窗口枚举已改 .optionOnScreenOnly 瘦身
// （8.6ms/602 窗 → 1.26ms/56 窗），静止 CPU 不再需要以起步延迟换功耗。
// (a) 静止 <1s 与 ≥1s 两个区间的 tick gaps 恒 [0.05, 0.15]；(c) material-change
// 恢复护栏穿过真实 Follower.decide（扰动→首条 moving 拍 ≤0.15s，防未来再引入
// 退避）；(d) probe retry hint 仍取更早者（min 语义不破坏）。
var sch6Ticks = 0
var sch6TickTimes: [TimeInterval] = []
let sch6Now = { ProcessInfo.processInfo.systemUptime }
let sch6Start = sch6Now()
let sch6Scheduler = FollowTickScheduler(
    runTick: {
        sch6Ticks += 1
        sch6TickTimes.append(sch6Now())
        return .stable
    },
    makeDisplayLink: { _, _ in nil },
    canUseDisplayLink: { false },
    maximumFramesPerSecond: { 60 }
)
sch6Scheduler.start()
sch6Scheduler.requestWake()
// 采样窗口跨过静止 1s 界（旧退避的切换点），两侧 gaps 必须同处 [0.05, 0.15]。
_ = waitPumpingMain({ sch6Now() - sch6Start >= 1.35 }, timeout: 4.0)
sch6Scheduler.stop()
let sch6Gaps = zip(sch6TickTimes.dropFirst(), sch6TickTimes).map { $0.0 - $0.1 }
check("T-sch6a stable cadence恒0.1s(跨静止1s界gaps[0.05,0.15])",
      sch6Gaps.count >= 8 && sch6Gaps.allSatisfy { $0 >= 0.05 && $0 <= 0.15 },
      "gaps=\(sch6Gaps.map { String(format: "%.3f", $0) })")

// T-sch6c: material-change 恢复必须穿过生产决策链（真实 Follower.decide + 真实
// runloop Timer）。与 main.swift 同构：tick 内 decide 更新 stationaryAnchor/
// lastMaterialChangeAt。先静止 ≥1s（当前恒 0.1s；若未来有人再加退避，此处恰为
// 退避激活区），再在一拍结束后注入宠物 bounds 扰动（模拟开始拖动，拖动期间逐拍
// 持续位移）：下一拍最迟 = stable 间隔 0.1s，decide 必须判 moving，scheduler 立即
// 切回 moving repeating 节拍。stable 间隔再被拉长（如 0.2s 封底）时，扰动到首条
// moving 拍的耗时随之超过 0.15s → 本断言红（起步延迟回归护栏）。
var sch6cTicks = 0
var sch6cPet = CGRect(x: 100, y: 100, width: 172, height: 179)
var sch6cAnchor: CGRect?
var sch6cChangedAt: TimeInterval?
var sch6cDisturbanceAt: TimeInterval?
var sch6cFirstMovingAt: TimeInterval?
var sch6cMovingTimes: [TimeInterval] = []
let sch6cNow = { ProcessInfo.processInfo.systemUptime }
let sch6cScheduler = FollowTickScheduler(
    runTick: {
        sch6cTicks += 1
        let t = sch6cNow()
        if sch6cDisturbanceAt != nil {
            sch6cPet = sch6cPet.offsetBy(dx: 2, dy: 0)   // 拖动中逐拍持续实质位移
        }
        let d = Follower.decide(pet: sch6cPet, stationaryAnchor: sch6cAnchor,
                                lastMaterialChangeAt: sch6cChangedAt, now: t)
        sch6cAnchor = d.stationaryAnchor
        sch6cChangedAt = d.lastMaterialChangeAt
        if sch6cDisturbanceAt != nil && d.state == .moving {
            if sch6cFirstMovingAt == nil { sch6cFirstMovingAt = t }
            sch6cMovingTimes.append(t)
        }
        return d.state
    },
    makeDisplayLink: { _, _ in nil },
    canUseDisplayLink: { false },
    maximumFramesPerSecond: { 60 }
)
sch6cScheduler.start()
sch6cScheduler.requestWake()
_ = waitPumpingMain({
    guard let changedAt = sch6cChangedAt else { return false }
    return sch6cNow() - changedAt >= 1.15
}, timeout: 3.0)
let sch6cBase = sch6cTicks
_ = waitPumpingMain { sch6cTicks >= sch6cBase + 1 }
sch6cDisturbanceAt = sch6cNow()
sch6cPet = sch6cPet.offsetBy(dx: 50, dy: 0)   // 远超容差的实质移动：模拟开始拖动
_ = waitPumpingMain({ sch6cFirstMovingAt != nil }, timeout: 2.0)
let sch6cRecovery = (sch6cFirstMovingAt ?? .infinity) - (sch6cDisturbanceAt ?? 0)
_ = waitPumpingMain({ sch6cMovingTimes.count >= 3 }, timeout: 1.0)
let sch6cMovingGaps = zip(sch6cMovingTimes.dropFirst(), sch6cMovingTimes).map { $0.0 - $0.1 }
check("T-sch6c 生产decide链:扰动后≤0.15s内恢复moving",
      sch6cRecovery >= 0 && sch6cRecovery <= 0.15
        && sch6cMovingTimes.count >= 3
        && sch6cMovingGaps.allSatisfy { $0 >= 0.005 && $0 <= 0.05 }
        && sch6cScheduler.isRepeatingTimerActive,
      "recovery=\(String(format: "%.3f", sch6cRecovery)) "
        + "gaps=\(sch6cMovingGaps.map { String(format: "%.3f", $0) }) "
        + "repeating=\(sch6cScheduler.isRepeatingTimerActive)")
sch6cScheduler.stop()

// T-sch6d: probe pendingRetryAt hint 与 stable 恒 0.1s 间隔仍取更早者（min 语义不破坏）。
var sch6dTicks = 0
var sch6dTimers: [TestFollowTickTimer] = []
var sch6dClock: TimeInterval = 0
let sch6dScheduler = FollowTickScheduler(
    runTick: {
        sch6dTicks += 1
        return sch6dTicks == 1 ? .stable : .hidden
    },
    makeDisplayLink: { _, _ in nil },
    canUseDisplayLink: { false },
    maximumFramesPerSecond: { 60 },
    monotonicNow: { sch6dClock },
    stableDelayHint: { 0.05 },
    makeTimer: { interval, repeats, callback in
        let timer = TestFollowTickTimer(interval: interval, repeats: repeats, callback: callback)
        sch6dTimers.append(timer)
        return timer
    }
)
sch6dScheduler.start()
sch6dScheduler.requestWake()
_ = waitPumpingMain { sch6dTicks == 1 }
let sch6dStableTimer = sch6dTimers.last!
check("T-sch6d probe retry hint(0.05s)仍早于stable恒0.1s间隔",
      !sch6dStableTimer.repeats && abs(sch6dStableTimer.interval - 0.05) < 0.000_001,
      "interval=\(sch6dStableTimer.interval) repeats=\(sch6dStableTimer.repeats)")
sch6dScheduler.stop()

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
    let bubbleAlpha = OSAllocatedUnfairLock(initialState: 1.0)
    let mascot = mkw(603, layer: 2, petForCollapse, title: "Codex Pet Mascot Effect")
    let capturer: BubbleCapturer = { c in
        captureCalls.withLock { $0 += 1 }
        // Hold the first main-probe (bubble) capture, not whichever channel
        // happens to enter the shared capturer first. T-sch4d samples the
        // remaining scheduler timer while the obstacle channel is still in-flight.
        if keepFirstCaptureInFlight && c.wid != mascot.wid
            && !releaseFirstCapture.withLock({ $0 }) {
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
            let bubble = bubbleAlpha.withLock { alpha -> WinCandidate in
                alpha = alpha >= 1 ? 0.99 : alpha + 0.01
                return mkw(601, layer: 3, bubbleForCollapse, alpha: alpha)
            }
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
    // Do not pump waitProbeChannelsIdle here: in-flight T-sch4d samples the
    // remaining timer immediately after tick 2. Extra RunLoop pumping lets the
    // reference-channel completion rewrite that timer (0.09 -> ~0.01).
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
        && inFlightProbeCadence.captureCallCount == 2   // 主导探测捕获气泡 1 次 + 参考通道仅捕获 Mascot 1 次
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

do {
    let stableClock = OSAllocatedUnfairLock(initialState: TimeInterval(14_000))
    let stableCaptureCalls = OSAllocatedUnfairLock(initialState: 0)
    let stableCandidate = mkw(801, layer: 3, bubbleForCollapse, title: "Codex Bubble")
    var stableTicks = 0
    var pendingRetryInsideTick: TimeInterval?
    var heartbeatPendingInsideTick: TimeInterval?
    var stableTimers: [TestFollowTickTimer] = []
    var stableProbe: BubbleVisibilityProbe!
    let stableScheduler = FollowTickScheduler(
        runTick: {
            stableTicks += 1
            stableProbe.probe(candidates: [stableCandidate])
            pendingRetryInsideTick = stableProbe.lock.withLock { $0.pendingRetryAt }
            if stableTicks == 2 {
                heartbeatPendingInsideTick = pendingRetryInsideTick
            }
            return .stable
        },
        makeDisplayLink: { _, _ in nil },
        canUseDisplayLink: { false },
        maximumFramesPerSecond: { 60 },
        monotonicNow: { stableClock.withLock { $0 } },
        stableDelayHint: { stableProbe.takePendingRetryDelay() },
        makeTimer: { interval, repeats, callback in
            let timer = TestFollowTickTimer(interval: interval, repeats: repeats, callback: callback)
            stableTimers.append(timer)
            return timer
        }
    )
    stableProbe = BubbleVisibilityProbe(
        monotonicNow: { stableClock.withLock { $0 } },
        canCapture: { true },
        capturer: { _ in
            stableCaptureCalls.withLock { $0 += 1 }
            return .stats(expandedS)
        })
    stableScheduler.start()
    stableScheduler.requestWake()
    _ = waitPumpingMain { stableTicks == 1 }
    _ = waitPumpingMain { !stableProbe.lock.withLock { $0.inFlight } }

    stableClock.withLock { $0 = 14_000.95 }
    let stableTickTimer = stableTimers.last { !$0.invalidated }!
    stableTickTimer.fire()
    _ = waitPumpingMain { stableTicks == 2 }
    let retryTimer = stableTimers.last!

    stableClock.withLock { $0 = 14_001 }
    retryTimer.fire()
    _ = waitPumpingMain { stableTicks == 3 }
    _ = waitPumpingMain { !stableProbe.lock.withLock { $0.inFlight } }
    check("T-sch4g 固定identity心跳hint→scheduler安排1.0s界one-shot",
          heartbeatPendingInsideTick == 14_001
                && !retryTimer.repeats
                && abs(retryTimer.interval - 0.05) < 0.000_001
                && stableCaptureCalls.withLock { $0 } == 2,
          "pending=\(String(describing: heartbeatPendingInsideTick)) "
              + "interval=\(retryTimer.interval) calls=\(stableCaptureCalls.withLock { $0 })")
    stableScheduler.stop()
}

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

transitionStats.withLock { $0 = .stats(noiseS) }
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
    "containerPlacementShownCount", "containerPlacementHiddenCount",
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

// T-re2d..2i: container 通道 outcome 计数（08-28 修复批次）：placement shown/hidden 计数 +
// dirty 抑制（首个样本/状态变化才 dirty；稳态同值布局 tick 不产生写盘）。
let reContRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
    "pd-runtime-evidence-container-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
try? FileManager.default.removeItem(at: reContRoot)
var reContNow: TimeInterval = 200_000
let reContCollector = makeRuntimeEvidenceRecorderForTesting(
    candidateSHA: reSHA,
    outputURL: reContRoot.appendingPathComponent(runtimeEvidenceOutputFileName),
    flushNow: { reContNow })
reContCollector.recordContainerPlacement(shown: true)
reContCollector.recordContainerPlacement(shown: true)   // 同值重复 → 不产生新证据
let reContSnap1 = reContCollector.snapshot()
check("T-re2d container placement 计数正确",
      (reContSnap1["containerPlacementShownCount"] as? Int) == 2
        && (reContSnap1["containerPlacementHiddenCount"] as? Int) == 0, "")
reContNow = 200_001
check("T-re2e 首样本 dirty→flush 落盘", reContCollector.flush(), "")
let reContWritten1 = try! JSONSerialization.jsonObject(
    with: Data(contentsOf: reContRoot.appendingPathComponent(runtimeEvidenceOutputFileName))) as! [String: Any]
check("T-re2f 落盘内容含 container 计数",
      (reContWritten1["containerPlacementShownCount"] as? Int) == 2
        && (reContWritten1["containerPlacementHiddenCount"] as? Int) == 0, "")
reContCollector.recordContainerPlacement(shown: true)   // 同值重复 → 仍无新证据
reContNow = 200_002
check("T-re2g 稳态同值不触发写盘", !reContCollector.flush(), "")
reContCollector.recordContainerPlacement(shown: false)  // shown 状态变化 → dirty
reContNow = 200_003
check("T-re2h hidden 变化→flush", reContCollector.flush(), "")
let reContSnap2 = reContCollector.snapshot()
check("T-re2i shown/hidden 计数累计",
      (reContSnap2["containerPlacementShownCount"] as? Int) == 3
        && (reContSnap2["containerPlacementHiddenCount"] as? Int) == 1, "")
try? FileManager.default.removeItem(at: reContRoot)

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

// T-re10 (review r1 P1 修复 / v7 P2-2): in-flight bounds-only move ——
// capturer 进入后经 continuation gate 挂起（不阻塞 executor）；主线程 pump RunLoop
// 直到 entered/calls/inFlight 状态确定，再注入同 WID 纯几何平移（bounds 345→345.5，
// 粘性语义：cache 保留、generation 不变）并断言 single-flight；手工 release 恰好
// resume 一次后收尾。stale 完成的拒绝由写入校验的 knownCandidates 精确不等保证
//（generation 在纯几何路径不递增）。不使用固定 sleep 或时序巧合。
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
reIProbe.probe(candidates: [reIJittered]) // in-flight 期间 bounds-only 平移（粘性保留 cache；single-flight 合并）
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
reITime = 27_001   // 同一 generation 下 due（knownCandidates 已更新为 jittered）→ 接受的捕获必须计数
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

// T-bv43 (拖动期间空白症状回归): 拖动时气泡窗口 bounds 逐 tick 平移/缩放，但 WID、owner、
// title、layer、alpha、isOnscreen、sharingState 均不变。基线把每次 bounds 变化当作候选
// identity 变化 → generation 递增 + cached/successfullyObservedWids 清空 → visibility(for:)
// 对仍在 knownWids 中的 WID 回落默认 .visible（保守避让）→ dock 在整个拖动期间持续避让
// 隐藏气泡 → 宠物与 dock 之间出现空白；拖动停止后 identity 稳定，下一次捕获（≤0.1s cadence
// + 捕获耗时）才恢复，与用户观察的 ~0.3s 延迟吻合。
// 修复合同：纯几何（仅 bounds）变化保留既有 cache 与成功观察集合（粘性），不递增 generation；
// 真正身份变化（WID 集合或任一非 bounds 身份字段）维持现行 generation 递增 + 清空 + 保守
// visible。写入校验保持现行严格语义：完成回调仍要求 generation 与 knownCandidates 完全
// 一致，bounds 平移期间启动的旧捕获结果一律丢弃，绝不写入新几何；粘性只影响 cache 保留。
    // 权衡：拖动期间展开/收起的真实状态变化最迟在拖动结束后的稳定心跳捕获（≤1s）收敛，见
// docs/architecture/dock-obstacle-avoidance.md「拖动期间的粘性可见性」。
var dragTime: TimeInterval = 16_500
let dragOutcome = OSAllocatedUnfairLock<BubbleCaptureOutcome>(initialState: .stats(noiseS))
let dragWakes = OSAllocatedUnfairLock(initialState: 0)
let dragCap: BubbleCapturer = { _ in dragOutcome.withLock { $0 } }
let dragWid = CGWindowID(531)
let dragStart = CGRect(x: 80, y: 280, width: 200, height: 54)
let dragProbe = BubbleVisibilityProbe(
    monotonicNow: { dragTime },
    canCapture: { true },
    capturer: dragCap,
    onVisibilityChange: { dragWakes.withLock { $0 += 1 } }
)
dragProbe.probe(candidates: [mkw(531, layer: 3, dragStart)])
_ = waitPumpingMain { !dragProbe.lock.withLock { $0.inFlight } }
check("T-bv43a 前置: 拖动前噪声(无内容)捕获→hidden",
      dragProbe.visibility(for: dragWid) == .hidden, "")

/// 拖动序列：宠物每 tick 位移 (7,5) 带动气泡平移，中途叠加尺寸变化（复现 Activity Stack
/// Backing 200x54→216x64 形态）；每步时间推进 < 0.1s cadence，避免与在途捕获交织。
func bv43DragTicks(_ probe: BubbleVisibilityProbe, wid: UInt32, start: CGRect,
                   ticks: Int, expected: BubbleVisibility) -> (stayed: Bool, finalBounds: CGRect) {
    var stayed = true
    var bounds = start
    for index in 0..<ticks {
        bounds.origin.x += 7
        bounds.origin.y += 5
        if index == 2 { bounds.size = CGSize(width: 216, height: 64) }
        dragTime += 0.016
        probe.probe(candidates: [mkw(wid, layer: 3, bounds)])
        if probe.visibility(for: CGWindowID(wid)) != expected { stayed = false }
    }
    return (stayed, bounds)
}

let dragHiddenRun = bv43DragTicks(dragProbe, wid: 531, start: dragStart, ticks: 10, expected: .hidden)
check("T-bv43b RED 拖动期间bounds逐tick平移→visibility保持拖动前hidden",
      dragHiddenRun.stayed
        && dragProbe.lock.withLock { $0.cached[dragWid]?.visibility } == .hidden,
      "visibility=\(dragProbe.visibility(for: dragWid)) "
        + "cached=\(String(describing: dragProbe.lock.withLock { $0.cached[dragWid] }))")

let dragVisProbe = BubbleVisibilityProbe(
    monotonicNow: { dragTime },
    canCapture: { true },
    capturer: { _ in .stats(expandedS) }
)
dragVisProbe.probe(candidates: [mkw(531, layer: 3, dragStart)])
_ = waitPumpingMain { !dragVisProbe.lock.withLock { $0.inFlight } }
let dragVisibleRun = bv43DragTicks(dragVisProbe, wid: 531, start: dragStart, ticks: 10, expected: .visible)
check("T-bv43c 拖动期间visible同样保持（粘性对称）",
      dragVisProbe.visibility(for: dragWid) == .visible && dragVisibleRun.stayed, "")

// 纯几何拖动保留成功观察资格（successfullyObservedWids 粘性）：拖动结束后（identity 稳定）
// 一次权威 targetMissing 仍判 hidden，与 T-bv39f 语义一致。
_ = waitPumpingMain { !dragProbe.lock.withLock { $0.inFlight } }
dragOutcome.withLock { $0 = .targetMissing }
dragTime += 1.01
dragProbe.probe(candidates: [mkw(531, layer: 3, dragHiddenRun.finalBounds)])
_ = waitPumpingMain { !dragProbe.lock.withLock { $0.inFlight } }
check("T-bv43d 纯几何拖动保留成功观察资格→targetMissing权威hidden",
      dragProbe.visibility(for: dragWid) == .hidden, "")

// 拖动结束后正常捕获刷新：hidden→visible 状态变化必须写回并唤醒一次布局。
dragOutcome.withLock { $0 = .stats(expandedS) }
let wakesBeforeRefresh = dragWakes.withLock { $0 }
dragTime += 1.01
dragProbe.probe(candidates: [mkw(531, layer: 3, dragHiddenRun.finalBounds)])
_ = waitPumpingMain { !dragProbe.lock.withLock { $0.inFlight } }
check("T-bv43f 拖动结束后捕获刷新hidden→visible并唤醒一次",
      dragProbe.visibility(for: dragWid) == .visible
        && dragWakes.withLock { $0 } == wakesBeforeRefresh + 1,
      "visibility=\(dragProbe.visibility(for: dragWid)) wakes=\(dragWakes.withLock { $0 })")

// 拖动中在途捕获（bounds 平移后释放）：写入校验按现行严格语义拒绝（knownCandidates 精确
// 相等），粘性 cache 不被旧结果覆盖，也不因 single-flight 合并启动第二捕获。
let inflightCalls = OSAllocatedUnfairLock(initialState: 0)
let inflightGate = AsyncCaptureEntryGate()
let inflightCap: BubbleCapturer = { _ in
    inflightCalls.withLock { $0 += 1 }
    await inflightGate.waitAfterEntry()
    return .stats(noiseS)
}
let inflightProbe = BubbleVisibilityProbe(
    monotonicNow: { dragTime }, canCapture: { true }, capturer: inflightCap)
let inflightStable = mkw(537, layer: 3, dragStart)
inflightProbe.probe(candidates: [inflightStable])
let inflightEntered1 = waitPumpingMain {
    inflightGate.enteredCount == 1 && inflightProbe.lock.withLock { $0.inFlight }
}
inflightGate.release()
_ = waitPumpingMain { !inflightProbe.lock.withLock { $0.inFlight } }
let inflightPreHidden = inflightProbe.visibility(for: inflightStable.wid) == .hidden
dragTime += 1.01
let inflightMoved = CGRect(x: dragStart.origin.x + 7, y: dragStart.origin.y + 5,
                           width: dragStart.width, height: dragStart.height)
inflightProbe.probe(candidates: [mkw(537, layer: 3, inflightMoved)])
let inflightEntered2 = waitPumpingMain {
    inflightGate.enteredCount == 2 && inflightProbe.lock.withLock { $0.inFlight }
}
dragTime += 0.016
inflightProbe.probe(candidates: [mkw(537, layer: 3, inflightMoved.offsetBy(dx: 7, dy: 5))])
inflightGate.release()
_ = waitPumpingMain { !inflightProbe.lock.withLock { $0.inFlight } }
check("T-bv43g 拖动中in-flight旧结果拒绝写入且cache保持粘性hidden",
      inflightEntered1 && inflightPreHidden && inflightEntered2
        && inflightCalls.withLock { $0 } == 2
        && inflightProbe.lock.withLock { $0.cached[inflightStable.wid]?.visibility } == .hidden
        && inflightProbe.visibility(for: inflightStable.wid) == .hidden,
      "entered1=\(inflightEntered1) preHidden=\(inflightPreHidden) entered2=\(inflightEntered2) "
        + "calls=\(inflightCalls.withLock { $0 }) "
        + "cached=\(String(describing: inflightProbe.lock.withLock { $0.cached[inflightStable.wid] }))")

// 真正身份变化（WID 集合变化 / owner 变化 / layer 变化）→ 维持现行清空 + 保守 visible，
// 且成功观察资格同步清空（变化后首次 targetMissing 仍保守 visible，T-bv39f3 语义）。
let idChangeOutcome = OSAllocatedUnfairLock<BubbleCaptureOutcome>(initialState: .stats(noiseS))
let idChangeCap: BubbleCapturer = { _ in idChangeOutcome.withLock { $0 } }
func bv43MakeIdentityProbe() -> BubbleVisibilityProbe {
    BubbleVisibilityProbe(monotonicNow: { dragTime }, canCapture: { true }, capturer: idChangeCap)
}

let ownerProbe = bv43MakeIdentityProbe()
let ownerStable = mkw(534, layer: 3, dragStart)
ownerProbe.probe(candidates: [ownerStable])
_ = waitPumpingMain { !ownerProbe.lock.withLock { $0.inFlight } }
let ownerHiddenEstablished = ownerProbe.visibility(for: ownerStable.wid) == .hidden
let ownerChanged = WinCandidate(
    wid: ownerStable.wid, ownerPID: ownerStable.ownerPID, ownerName: "Other", title: "",
    layer: 3, alpha: 1.0, isOnscreen: true, sharingState: 1, bounds: ownerStable.bounds)
dragTime += 0.016   // 未到 cadence：本 probe 只做身份切换+清 cache，不启动捕获
ownerProbe.probe(candidates: [ownerChanged])
let ownerClearedToVisible = ownerProbe.visibility(for: ownerChanged.wid) == .visible
idChangeOutcome.withLock { $0 = .targetMissing }
dragTime += 0.11
ownerProbe.probe(candidates: [ownerChanged])
_ = waitPumpingMain { !ownerProbe.lock.withLock { $0.inFlight } }
check("T-bv43h1 owner变化→清cache回保守visible且观察资格清空",
      ownerHiddenEstablished && ownerClearedToVisible
        && ownerProbe.visibility(for: ownerChanged.wid) == .visible,
      "established=\(ownerHiddenEstablished) cleared=\(ownerClearedToVisible) "
        + "afterMissing=\(ownerProbe.visibility(for: ownerChanged.wid))")
idChangeOutcome.withLock { $0 = .stats(noiseS) }

let layerProbe = bv43MakeIdentityProbe()
let layerStable = mkw(535, layer: 3, dragStart)
layerProbe.probe(candidates: [layerStable])
_ = waitPumpingMain { !layerProbe.lock.withLock { $0.inFlight } }
let layerHiddenEstablished = layerProbe.visibility(for: layerStable.wid) == .hidden
dragTime += 0.016   // 未到 cadence：与 h1 相同的确定性路径——身份切换+清 cache，不启动
                    // 新捕获（0.11 会触发捕获，其后台完成与下方断言存在竞态，历史上偶发红）
layerProbe.probe(candidates: [mkw(535, layer: 4, dragStart)])
check("T-bv43h2 layer变化→清cache回保守visible",
      layerHiddenEstablished && layerProbe.visibility(for: layerStable.wid) == .visible,
      "established=\(layerHiddenEstablished) "
        + "visibility=\(layerProbe.visibility(for: layerStable.wid))")

let widProbe = bv43MakeIdentityProbe()
let widStable = mkw(536, layer: 3, dragStart)
widProbe.probe(candidates: [widStable])
_ = waitPumpingMain { !widProbe.lock.withLock { $0.inFlight } }
let widHiddenEstablished = widProbe.visibility(for: widStable.wid) == .hidden
dragTime += 0.016   // 未到 cadence：与 h1/h2 相同的确定性路径——WID 集合变化的同步保守
                    // 默认不需要新捕获（0.11 会触发捕获，其后台完成与下方断言存在竞态）
widProbe.probe(candidates: [mkw(538, layer: 3, dragStart)])
check("T-bv43h3 WID集合变化→新wid保守visible",
      widHiddenEstablished && widProbe.visibility(for: CGWindowID(538)) == .visible,
      "established=\(widHiddenEstablished) newWid=\(widProbe.visibility(for: CGWindowID(538)))")

// T-bv44 (拖动期间空白·生产组合回归): 拖动序列穿过真实生产链
// FollowLayoutPass.placeDock → bubbleProbe.probe/visibility → frameSink → 真实 DockPanel.placeBelow。
// 气泡已捕获为 hidden 时，拖动期间（宠物与气泡 bounds 逐 tick 平移）dock 必须保持无障碍
// 基础位，不被默认保守 visible 的隐藏气泡窗口推开；拖动结束后第一次真实捕获刷新
// （hidden→visible）仍经 onVisibilityChange → scheduler coalescer → 完整 tick 写回避让 frame。
var bv44Time: TimeInterval = 18_000
var bv44Clock: TimeInterval = 0
let bv44Dock = DockPanel()
let bv44Outcome = OSAllocatedUnfairLock<BubbleCaptureOutcome>(initialState: .stats(noiseS))
let bv44Cap: BubbleCapturer = { _ in bv44Outcome.withLock { $0 } }
let bv44Ticks = OSAllocatedUnfairLock(initialState: 0)
let bv44ObstacleCounts = OSAllocatedUnfairLock(initialState: [Int]())
var bv44Timers: [TestFollowTickTimer] = []
var bv44PetBounds = petForCollapse
var bv44BubbleBounds = bubbleForCollapse
func bv44BaseFrame() -> NSRect {
    Geometry.appKitRectFromQuartz(CGRect(
        x: bv44PetBounds.origin.x + (bv44PetBounds.width - 200) / 2,
        y: bv44PetBounds.maxY + 2, width: 200, height: 48))
}
func bv44AvoidFrame() -> NSRect {
    Geometry.appKitRectFromQuartz(CGRect(
        x: bv44PetBounds.origin.x + (bv44PetBounds.width - 200) / 2,
        y: bv44BubbleBounds.maxY + 2, width: 200, height: 48))
}
var bv44Probe: BubbleVisibilityProbe!
let bv44Scheduler = FollowTickScheduler(
    runTick: {
        bv44Ticks.withLock { $0 += 1 }
        let mascot = mkw(543, layer: 2, bv44PetBounds, title: "Codex Pet Mascot Effect")
        let bubble = mkw(541, layer: 3, bv44BubbleBounds)
        let placed = FollowLayoutPass.placeDock(
            mascot: mascot,
            candidates: [mascot, bubble],
            bubbleProbe: bv44Probe,
            frameSink: { pet, obstacles in
                bv44ObstacleCounts.withLock { $0.append(obstacles.count) }
                return bv44Dock.placeBelow(
                    petQuartzRect: pet,
                    avoiding: obstacles,
                    visibleScreen: nil,
                    movementChanged: true,
                    monotonicNow: bv44Time
                )
            }
        )
        return placed ? .stable : .hidden
    },
    makeDisplayLink: { _, _ in nil },
    canUseDisplayLink: { false },
    maximumFramesPerSecond: { 60 },
    monotonicNow: { bv44Clock },
    makeTimer: { interval, repeats, callback in
        let timer = TestFollowTickTimer(interval: interval, repeats: repeats, callback: callback)
        bv44Timers.append(timer)
        return timer
    }
)
bv44Probe = BubbleVisibilityProbe(
    monotonicNow: { bv44Time },
    canCapture: { true },
    capturer: bv44Cap,
    onVisibilityChange: bv44Scheduler.visibilityChangeCallback
)
bv44Probe.probe(candidates: [mkw(541, layer: 3, bv44BubbleBounds)])
_ = waitPumpingMain { !bv44Probe.lock.withLock { $0.inFlight } }
bv44Scheduler.start()
bv44Scheduler.requestWake()
_ = waitPumpingMain { bv44Ticks.withLock { $0 } == 1 }
let bv44StableTimerBeforeWake = bv44Timers.last
check("T-bv44a 前置: 拖动前hidden→实际panel基础位+未到期stable one-shot",
      dockFrameNear(bv44Dock.frame, bv44BaseFrame())
        && bv44ObstacleCounts.withLock { $0 } == [0]
        && bv44StableTimerBeforeWake?.repeats == false,
      "frame=\(bv44Dock.frame) expected=\(bv44BaseFrame()) "
        + "obstacles=\(bv44ObstacleCounts.withLock { $0 })")

var bv44DragFramesOK = true
for _ in 0..<8 {
    bv44PetBounds.origin.x += 7
    bv44PetBounds.origin.y += 5
    bv44BubbleBounds.origin.x += 7
    bv44BubbleBounds.origin.y += 5
    bv44Time += 0.016
    bv44Scheduler.requestWake()
    let expectedTicks = bv44Ticks.withLock { $0 } + 1
    _ = waitPumpingMain { bv44Ticks.withLock { $0 } == expectedTicks }
    if !dockFrameNear(bv44Dock.frame, bv44BaseFrame()) { bv44DragFramesOK = false }
}
check("T-bv44b RED 拖动期间dock保持无障碍基础位(隐藏气泡不推开)",
      bv44DragFramesOK && bv44ObstacleCounts.withLock { $0 } == Array(repeating: 0, count: 9),
      "framesOK=\(bv44DragFramesOK) obstacles=\(bv44ObstacleCounts.withLock { $0 }) "
        + "frame=\(bv44Dock.frame) expected=\(bv44BaseFrame())")

bv44Outcome.withLock { $0 = .stats(expandedS) }
bv44Time += 1.01
bv44Scheduler.requestWake()
let bv44RefreshTick = bv44Ticks.withLock { $0 } + 1
_ = waitPumpingMain { bv44Ticks.withLock { $0 } == bv44RefreshTick }
_ = waitPumpingMain { bv44Ticks.withLock { $0 } == bv44RefreshTick + 1 }
check("T-bv44c 拖动结束后真实捕获刷新→wake→完整tick→实际panel避让frame",
      bv44ObstacleCounts.withLock { $0 }.last == 1
        && dockFrameNear(bv44Dock.frame, bv44AvoidFrame()),
      "obstacles=\(bv44ObstacleCounts.withLock { $0 }) frame=\(bv44Dock.frame) "
        + "expected=\(bv44AvoidFrame())")
bv44Scheduler.stop()

// T-bv45 (气泡障碍按可见内容 bbox 避让·现场形态回归): 宿主状态卡容器窗口 200x54，
// 可见内容只占窗口内 y[15,21]，底部 32px 全透明。内容量按 2026-08-24 校准取
// 控制按钮级（194px ≥ minContentPixels 80）；25px 旧测量已被判为不可见噪声。
// 旧 open/close 比例阈值把该形态滞回成 visible→整窗避让（多让 32px 透明尾巴，图2 症状）
// 或 hidden→遮住横条；新语义：有内容（非透明像素 ≥80）→ 障碍高度=contentBottom+1，
// dock 紧贴内容底+gap；无内容→不避让；保守 visible（unavailable）→ 整窗 bounds。
let bv45Base = fail
let bv45Pet = CGRect(x: 362, y: 382, width: 172, height: 62)      // maxY=444
let bv45Bubble = CGRect(x: 376, y: 446, width: 200, height: 54)    // 现场形态窗口
let bv45BarStats = BubbleAlphaStats(nonTransparentPixelCount: 194, contentBottom: 21)
var bv45Time: TimeInterval = 19_000
func bv45MakeProbe(
    outcome: BubbleCaptureOutcome,
    onVisibilityChange: @escaping @Sendable () -> Void = {}
) -> BubbleVisibilityProbe {
    let locked = OSAllocatedUnfairLock<BubbleCaptureOutcome>(initialState: outcome)
    return BubbleVisibilityProbe(
        monotonicNow: { bv45Time }, canCapture: { true },
        capturer: { _ in locked.withLock { $0 } },
        onVisibilityChange: onVisibilityChange)
}
func bv45LayoutObstacles(_ probe: BubbleVisibilityProbe, bubble: CGRect) -> [CGRect] {
    var obstacles: [CGRect] = []
    _ = FollowLayoutPass.placeDock(
        mascot: mkw(545, layer: 2, bv45Pet, title: "Codex Pet Mascot Effect"),
        candidates: [
            mkw(545, layer: 2, bv45Pet, title: "Codex Pet Mascot Effect"),
            mkw(544, layer: 3, bubble)
        ],
        bubbleProbe: probe,
        frameSink: { _, obs in obstacles = obs; return true })
    return obstacles
}

// (a) 小横条：障碍高度 = contentBottom+1 = 22，水平仍整窗 bounds
let bv45BarProbe = bv45MakeProbe(outcome: .stats(bv45BarStats))
bv45BarProbe.probe(candidates: [mkw(544, layer: 3, bv45Bubble)])
_ = waitPumpingMain { !bv45BarProbe.lock.withLock { $0.inFlight } }
let bv45BarObstacles = bv45LayoutObstacles(bv45BarProbe, bubble: bv45Bubble)
check("T-bv45a 内容条(194px,y15-21)→障碍高度22(contentBottom+1),水平仍整窗",
      bv45BarObstacles == [CGRect(x: 376, y: 446, width: 200, height: 22)],
      "obstacles=\(bv45BarObstacles)")

// (b) 展开大卡：内容底达窗口底（53）→ 障碍高度 = 54（整窗，语义与旧行为一致）
let bv45ExpandedProbe = bv45MakeProbe(outcome: .stats(expandedS))
bv45ExpandedProbe.probe(candidates: [mkw(544, layer: 3, bv45Bubble)])
_ = waitPumpingMain { !bv45ExpandedProbe.lock.withLock { $0.inFlight } }
let bv45ExpandedObstacles = bv45LayoutObstacles(bv45ExpandedProbe, bubble: bv45Bubble)
check("T-bv45b 展开大卡(内容底53)→障碍高度54(contentBottom+1=整窗)",
      bv45ExpandedObstacles == [CGRect(x: 376, y: 446, width: 200, height: 54)],
      "obstacles=\(bv45ExpandedObstacles)")

// (c) 噪声（2px）与完全透明 → 无障碍
let bv45NoiseProbe = bv45MakeProbe(outcome: .stats(noiseS))
bv45NoiseProbe.probe(candidates: [mkw(544, layer: 3, bv45Bubble)])
_ = waitPumpingMain { !bv45NoiseProbe.lock.withLock { $0.inFlight } }
check("T-bv45c 2px噪声(低于下限)→无障碍",
      bv45LayoutObstacles(bv45NoiseProbe, bubble: bv45Bubble).isEmpty, "")
let bv45TransparentProbe = bv45MakeProbe(
    outcome: .stats(BubbleAlphaStats(nonTransparentPixelCount: 0, contentBottom: -1)))
bv45TransparentProbe.probe(candidates: [mkw(544, layer: 3, bv45Bubble)])
_ = waitPumpingMain { !bv45TransparentProbe.lock.withLock { $0.inFlight } }
check("T-bv45d 完全透明→无障碍",
      bv45LayoutObstacles(bv45TransparentProbe, bubble: bv45Bubble).isEmpty, "")

// (d) unavailable → 保守 visible 且无内容底边 → 整窗 bounds 避让（不回归）
let bv45UnavailableProbe = bv45MakeProbe(outcome: .unavailable)
bv45UnavailableProbe.probe(candidates: [mkw(544, layer: 3, bv45Bubble)])
_ = waitPumpingMain { !bv45UnavailableProbe.lock.withLock { $0.inFlight } }
let bv45UnavailableObstacles = bv45LayoutObstacles(bv45UnavailableProbe, bubble: bv45Bubble)
check("T-bv45e unavailable→保守visible整窗障碍54(无内容信息)",
      bv45UnavailableObstacles == [CGRect(x: 376, y: 446, width: 200, height: 54)]
        && bv45UnavailableProbe.observation(for: CGWindowID(544)).contentBottom == nil,
      "obstacles=\(bv45UnavailableObstacles)")

// (e) 生产组合：FollowLayoutPass → 真实 DockPanel.placeBelow → 实际 frame 紧贴内容底+2。
// dock x=348（pet 中心），基础 y=446 与横条障碍(446..468)重叠 → 避让到 470；
// 整窗避让则会到 502（用户看到的图2 多余 32px 空白）。
let bv45Dock = DockPanel()
let bv45ProdProbe = bv45MakeProbe(outcome: .stats(bv45BarStats))
bv45ProdProbe.probe(candidates: [mkw(544, layer: 3, bv45Bubble)])
_ = waitPumpingMain { !bv45ProdProbe.lock.withLock { $0.inFlight } }
let bv45ProdPlaced = FollowLayoutPass.placeDock(
    mascot: mkw(545, layer: 2, bv45Pet, title: "Codex Pet Mascot Effect"),
    candidates: [
        mkw(545, layer: 2, bv45Pet, title: "Codex Pet Mascot Effect"),
        mkw(544, layer: 3, bv45Bubble)
    ],
    bubbleProbe: bv45ProdProbe,
    frameSink: { pet, obstacles in
        bv45Dock.placeBelow(
            petQuartzRect: pet, avoiding: obstacles, visibleScreen: nil,
            movementChanged: false, monotonicNow: bv45Time)
    })
let bv45ContentAvoidFrame = Geometry.appKitRectFromQuartz(
    CGRect(x: 348, y: 470, width: 200, height: 48))
check("T-bv45f 横条→实际panel frame紧贴内容底+2(y=470,非整窗502)",
      bv45ProdPlaced && dockFrameNear(bv45Dock.frame, bv45ContentAvoidFrame),
      "frame=\(bv45Dock.frame) expected=\(bv45ContentAvoidFrame)")

// (f) 无内容（噪声）→ 实际 panel 回基础位（pet 底+2 = 446）
let bv45BaseDock = DockPanel()
let bv45BaseProbe = bv45MakeProbe(outcome: .stats(noiseS))
bv45BaseProbe.probe(candidates: [mkw(544, layer: 3, bv45Bubble)])
_ = waitPumpingMain { !bv45BaseProbe.lock.withLock { $0.inFlight } }
let bv45BasePlaced = FollowLayoutPass.placeDock(
    mascot: mkw(545, layer: 2, bv45Pet, title: "Codex Pet Mascot Effect"),
    candidates: [
        mkw(545, layer: 2, bv45Pet, title: "Codex Pet Mascot Effect"),
        mkw(544, layer: 3, bv45Bubble)
    ],
    bubbleProbe: bv45BaseProbe,
    frameSink: { pet, obstacles in
        bv45BaseDock.placeBelow(
            petQuartzRect: pet, avoiding: obstacles, visibleScreen: nil,
            movementChanged: false, monotonicNow: bv45Time)
    })
let bv45BaseFrame = Geometry.appKitRectFromQuartz(
    CGRect(x: 348, y: 446, width: 200, height: 48))
check("T-bv45g 无内容→实际panel回基础位(pet底+2)",
      bv45BasePlaced && dockFrameNear(bv45BaseDock.frame, bv45BaseFrame),
      "frame=\(bv45BaseDock.frame) expected=\(bv45BaseFrame)")

// (g) 拖动粘性：bounds 纯平移期间 cache 的 contentBottom（窗口内相对坐标）继续有效，
// 障碍矩形随窗口平移且高度保持 22。
var bv45DragBubble = bv45Bubble
var bv45DragObstaclesOK = true
let bv45DragProbe = bv45MakeProbe(outcome: .stats(bv45BarStats))
bv45DragProbe.probe(candidates: [mkw(544, layer: 3, bv45DragBubble)])
_ = waitPumpingMain { !bv45DragProbe.lock.withLock { $0.inFlight } }
for _ in 0..<4 {
    bv45DragBubble.origin.x += 7
    bv45DragBubble.origin.y += 5
    bv45Time += 0.016
    let expected = CGRect(x: bv45DragBubble.minX, y: bv45DragBubble.minY,
                          width: bv45DragBubble.width, height: 22)
    if bv45LayoutObstacles(bv45DragProbe, bubble: bv45DragBubble) != [expected] {
        bv45DragObstaclesOK = false
    }
}
check("T-bv45h 拖动平移期间contentBottom粘性保留→障碍矩形随窗口平移(高度22)",
      bv45DragObstaclesOK
        && bv45DragProbe.observation(for: CGWindowID(544)).contentBottom == 21,
      "obstaclesOK=\(bv45DragObstaclesOK)")

// (h) wake 语义保持：只有可见性状态变化唤醒；同一 probe 的内容底变化（visible→visible）
    // 不额外唤醒，由既有稳定心跳的下一次完整 tick 应用。
let bv45Wakes = OSAllocatedUnfairLock(initialState: 0)
let bv45WakeStats = OSAllocatedUnfairLock<BubbleCaptureOutcome>(initialState: .stats(bv45BarStats))
let bv45WakeProbe = BubbleVisibilityProbe(
    monotonicNow: { bv45Time }, canCapture: { true },
    capturer: { _ in bv45WakeStats.withLock { $0 } },
    onVisibilityChange: { bv45Wakes.withLock { $0 += 1 } })
bv45WakeProbe.probe(candidates: [mkw(544, layer: 3, bv45Bubble)])
_ = waitPumpingMain { !bv45WakeProbe.lock.withLock { $0.inFlight } }
let bv45WakesAfterBar = bv45Wakes.withLock { $0 }
let bv45BottomAfterBar = bv45WakeProbe.observation(for: CGWindowID(544)).contentBottom
    // 同一 probe：cache 已写入 visible/21，稳定心跳后二次捕获内容底 53（visible→visible）
bv45WakeStats.withLock { $0 = .stats(expandedS) }
bv45Time += 1.01
bv45WakeProbe.probe(candidates: [mkw(544, layer: 3, bv45Bubble)])
_ = waitPumpingMain { !bv45WakeProbe.lock.withLock { $0.inFlight } }
check("T-bv45i 同probe内容底21→53(visible→visible)不wake且观察更新",
      bv45WakesAfterBar == 0 && bv45BottomAfterBar == 21
        && bv45Wakes.withLock { $0 } == 0
        && bv45WakeProbe.observation(for: CGWindowID(544)).visibility == .visible
        && bv45WakeProbe.observation(for: CGWindowID(544)).contentBottom == 53,
      "afterBar=\(bv45WakesAfterBar) bottomAfterBar=\(String(describing: bv45BottomAfterBar)) "
        + "wakes=\(bv45Wakes.withLock { $0 })")
// 随后无内容（hidden 状态变化）→ 恰一次唤醒
bv45Time += 0.11
let bv45WakeHide = bv45MakeProbe(
    outcome: .stats(noiseS),
    onVisibilityChange: { bv45Wakes.withLock { $0 += 1 } })
bv45WakeHide.probe(candidates: [mkw(544, layer: 3, bv45Bubble)])
_ = waitPumpingMain { !bv45WakeHide.lock.withLock { $0.inFlight } }
check("T-bv45j hidden状态变化→恰一次wake(状态唤醒语义保持)",
      bv45Wakes.withLock { $0 } == 1
        && bv45WakeHide.observation(for: CGWindowID(544)).visibility == .hidden,
      "wakes=\(bv45Wakes.withLock { $0 })")

// (i) 粘性缩窗 cap：障碍高度 = min(contentBottom+1, bounds.height)。粘性期间窗口纯几何
// 收高（216x64 → 200x54），stale contentBottom+1(64) 超过当前高度 → cap 到 54，
// 不产生越界/超高矩形；等值边界（contentBottom+1 == height）已由 T-bv45b 覆盖。
let bv45ShrinkProbe = bv45MakeProbe(
    outcome: .stats(BubbleAlphaStats(nonTransparentPixelCount: 194, contentBottom: 63)))
let bv45ShrinkWindow216 = CGRect(x: 376, y: 446, width: 216, height: 64)
bv45ShrinkProbe.probe(candidates: [mkw(544, layer: 3, bv45ShrinkWindow216)])
_ = waitPumpingMain { !bv45ShrinkProbe.lock.withLock { $0.inFlight } }
bv45Time += 0.016   // 0.1s cadence 内不重捕获：布局消费 stale 粘性 cache
let bv45ShrinkWindow54 = CGRect(x: 376, y: 446, width: 200, height: 54)
let bv45ShrinkObstacles = bv45LayoutObstacles(bv45ShrinkProbe, bubble: bv45ShrinkWindow54)
check("T-bv45k 粘性缩窗stale contentBottom+1(64)>高度54→cap到54不越界",
      bv45ShrinkObstacles == [CGRect(x: 376, y: 446, width: 200, height: 54)]
        && bv45ShrinkProbe.observation(for: CGWindowID(544)).contentBottom == 63,
      "obstacles=\(bv45ShrinkObstacles)")

print("\n[BubbleVisibility] \(pass - bvPass) passed, \(fail - bvBase) failed")

// ---- T-cs: Composition Surface 气泡渲染通道 + 噪声下限校准（2026-08-24 现场像素级 fixture）----
// 现场几何：宠物 172x179@(1487,207)（petMaxY=386、centerX=1573）；
// Composition Surface 768x912@(1189,-3) ×7 个同 bounds 重复实例（气泡卡只渲染在该大窗，
// 展开内容延伸到 abs y467）；ACT "Codex Pet Activity Stack Backing" 214x74@(1466,384)
// 只承载控制按钮（189-194px）与收起噪声点（39-57px）。
let csBase = fail, csPass = pass
let csPet = CGRect(x: 1487, y: 207, width: 172, height: 179)   // petMaxY=386
let csMascot = mkw(900, layer: 2, csPet, title: "Codex Pet Mascot Effect")
let csSurfaceBounds = CGRect(x: 1189, y: -3, width: 768, height: 912)
let csSurfaces = [27814, 27815, 27816, 27817, 28787, 28788, 28789].map {
    mkw(UInt32($0), layer: 3, csSurfaceBounds, title: "Codex Pet Composition Surface")
}
let csAct = mkw(27900, layer: 3, CGRect(x: 1466, y: 384, width: 214, height: 74),
                title: "Codex Pet Activity Stack Backing")
let csDockX = csPet.minX + (csPet.width - 200) / 2   // pet 中心对齐（1473）
func csAppKitFrame(y: CGFloat) -> NSRect {
    Geometry.appKitRectFromQuartz(CGRect(x: csDockX, y: y, width: 200, height: 48))
}

// 单元：标题通道纳入 + 7 重复实例去重（wid 升序代表 27814）+ obstacleKind 像素探测。
let csObstacles = PetTracker.obstaclesNear(mascot: csMascot, candidates: [csMascot] + csSurfaces + [csAct])
check("T-cs4 标题通道纳入Composition Surface且7实例去重为1代表(wid升序27814)+ACT",
      csObstacles.count == 2
        && csObstacles.filter { $0.title == "Codex Pet Composition Surface" }.count == 1
        && csObstacles.first { $0.title == "Codex Pet Composition Surface" }?.wid == CGWindowID(27814),
      "obstacles=\(csObstacles.map { (Int($0.wid), $0.title) })")
// 三类分类契约：CS 标题通道优先 → .compositionSurface（仍走像素探测）；ACT 等几何小窗 →
// .bubble；控制按钮 → .control（由 T-ctrl10b/c 覆盖）。
check("T-cs3 obstacleKind三类:CS=.compositionSurface(标题优先),ACT=.bubble",
      PetTracker.obstacleKind(csSurfaces[0], petMaxY: csPet.maxY) == .compositionSurface
        && PetTracker.obstacleKind(csAct, petMaxY: csPet.maxY) == .bubble, "")
// 标题不匹配的同尺寸大窗不纳入（标题精确匹配，不做几何猜测）。
let csMismatch = [28100, 28101, 28102].map {
    mkw(UInt32($0), layer: 3, csSurfaceBounds, title: "Codex Pet Other Surface")
}
check("T-cs5 标题不匹配的同尺寸大窗不纳入(精确标题通道)",
      PetTracker.obstaclesNear(mascot: csMascot, candidates: [csMascot] + csMismatch).isEmpty, "")

// 生产组合：FollowLayoutPass → 真实 DockPanel.placeBelow → DockPanel.frame。
// tick1 启动捕获（首次观察前保守 visible），捕获完成后 tick2（0.1s cadence 内不重捕获）
// 应用缓存结果——与生产 0.1s 节拍消费路径一致。
var csTime: TimeInterval = 22_000
func csRunTwoTickLayout(
    probe: BubbleVisibilityProbe,
    dock: DockPanel,
    obstacleCounts: OSAllocatedUnfairLock<[Int]>,
    candidates: [WinCandidate],
    holdFirstCapture: OSAllocatedUnfairLock<Bool>? = nil
) -> Bool {
    func place() -> Bool {
        FollowLayoutPass.placeDock(
            mascot: csMascot,
            candidates: candidates,
            bubbleProbe: probe,
            frameSink: { pet, obstacles in
                obstacleCounts.withLock { $0.append(obstacles.count) }
                return dock.placeBelow(
                    petQuartzRect: pet, avoiding: obstacles, visibleScreen: nil,
                    movementChanged: false, monotonicNow: csTime)
            })
    }
    _ = place()
    holdFirstCapture?.withLock { $0 = true }
    let completed = waitProbeChannelsIdle(probe)
    _ = place()
    return completed
}

// RED-S1 展开态：气泡卡渲染进 Composition Surface（内容底 abs y467 → 窗口内 contentBottom=470）；
// ACT 承载控制按钮（194px、内容底 abs y422 → 窗口内 38）。期望 dock 避让到气泡内容底+2
//（abs y470）；基线（标题通道缺失）只避让 ACT → y425，压在气泡中段。
let csExpandedCaptured = OSAllocatedUnfairLock(initialState: [CGWindowID]())
let csExpandedStats: [CGWindowID: BubbleAlphaStats] = [
    CGWindowID(27814): BubbleAlphaStats(nonTransparentPixelCount: 30_000, contentBottom: 470),
    CGWindowID(27900): BubbleAlphaStats(nonTransparentPixelCount: 194, contentBottom: 38),
]
let csExpandedCap: BubbleCapturer = { c in
    csExpandedCaptured.withLock { $0.append(c.wid) }
    return .stats(csExpandedStats[c.wid]
        ?? BubbleAlphaStats(nonTransparentPixelCount: 0, contentBottom: -1))
}
let csExpandedProbe = BubbleVisibilityProbe(
    monotonicNow: { csTime }, canCapture: { true }, capturer: csExpandedCap)
let csExpandedDock = DockPanel()
let csExpandedObstacleCounts = OSAllocatedUnfairLock(initialState: [Int]())
let csExpandedOK = csRunTwoTickLayout(
    probe: csExpandedProbe, dock: csExpandedDock,
    obstacleCounts: csExpandedObstacleCounts, candidates: [csMascot] + csSurfaces + [csAct])
check("T-cs1 RED-S1 展开态→实际panel避让到气泡内容底+2(y=470,非仅ACT的~425)",
      csExpandedOK && dockFrameNear(csExpandedDock.frame, csAppKitFrame(y: 470)),
      "frame=\(csExpandedDock.frame) expected=\(csAppKitFrame(y: 470))")
check("T-cs2 7重复实例去重→主导探测捕获ACT+单CS代表;参考通道仅Mascot",
      csExpandedCaptured.withLock { $0 }.contains(CGWindowID(27900))
        && csExpandedCaptured.withLock { $0 }.filter { $0 == CGWindowID(27814) }.count == 1
        && csExpandedCaptured.withLock { $0 }.filter { $0 == CGWindowID(900) }.count == 1,
      "captured=\(csExpandedCaptured.withLock { $0.map { Int($0) } })")

// RED-S2 收起态：Composition Surface 内容全在 petMaxY 以上（contentBottom=362 → 可见内容底
// abs y360），Mascot 窗口底 386 以下有 26px 透明 padding；ACT 仅剩 41px 不可见噪声点
// （窗口内 y[21,28]）。期望 dock 基础位锚定可见内容底 360+2=362（T-anc 语义），而非窗口底
// petMaxY+2=388；更早基线（下限 3）把 41px 判 visible → 停 y415。
csTime = 23_000
let csCollapsedStats: [CGWindowID: BubbleAlphaStats] = [
    CGWindowID(27814): BubbleAlphaStats(nonTransparentPixelCount: 30_000, contentBottom: 362),
    CGWindowID(27900): BubbleAlphaStats(nonTransparentPixelCount: 41, contentBottom: 28),
]
let csCollapsedCap: BubbleCapturer = { c in
    .stats(csCollapsedStats[c.wid]
        ?? BubbleAlphaStats(nonTransparentPixelCount: 0, contentBottom: -1))
}
let csCollapsedProbe = BubbleVisibilityProbe(
    monotonicNow: { csTime }, canCapture: { true }, capturer: csCollapsedCap)
let csCollapsedDock = DockPanel()
let csCollapsedObstacleCounts = OSAllocatedUnfairLock(initialState: [Int]())
let csCollapsedOK = csRunTwoTickLayout(
    probe: csCollapsedProbe, dock: csCollapsedDock,
    obstacleCounts: csCollapsedObstacleCounts, candidates: [csMascot] + csSurfaces + [csAct])
check("T-cs6 RED-S2 收起态噪声点(41px)→hidden→实际panel回内容底基础位362(非窗口底388)",
      csCollapsedOK && dockFrameNear(csCollapsedDock.frame, csAppKitFrame(y: 362)),
      "frame=\(csCollapsedDock.frame) expected=\(csAppKitFrame(y: 362))")
check("T-cs6b ACT噪声点观察=hidden;Composition代表=visible(宠物像素)",
      csCollapsedProbe.observation(for: CGWindowID(27900)).visibility == .hidden
        && csCollapsedProbe.observation(for: CGWindowID(27814)).visibility == .visible, "")

// 收起态仅有 Composition Surface（内容=宠物像素，可见底 abs y360 在窗口底 386 以上）→
// 避让矩形与 dock 无垂直重叠 → 不避让；基础位锚定可见内容底 362（T-anc 语义），防止标题
// 通道引入过度避让。首 tick 无观察数据 → 回退窗口底锚 388 且跳过（计数 0）；次 tick
// stats visible 内容 bbox 进入障碍集（计数 1）但锚定内容底、无垂直重叠。
csTime = 24_000
let csSurfOnlyRelease = OSAllocatedUnfairLock(initialState: false)
let csSurfOnlyCap: BubbleCapturer = { _ in
    while !csSurfOnlyRelease.withLock({ $0 }) {
        try? await Task.sleep(nanoseconds: 2_000_000)
    }
    return .stats(BubbleAlphaStats(nonTransparentPixelCount: 30_000, contentBottom: 362))
}
let csSurfOnlyProbe = BubbleVisibilityProbe(
    monotonicNow: { csTime }, canCapture: { true }, capturer: csSurfOnlyCap)
let csSurfOnlyDock = DockPanel()
let csSurfOnlyCounts = OSAllocatedUnfairLock(initialState: [Int]())
let csSurfOnlyOK = csRunTwoTickLayout(
    probe: csSurfOnlyProbe, dock: csSurfOnlyDock,
    obstacleCounts: csSurfOnlyCounts, candidates: [csMascot] + csSurfaces,
    holdFirstCapture: csSurfOnlyRelease)
check("T-cs7 收起态仅Composition(内容底abs360)→无垂直重叠→dock内容底基础位362",
      csSurfOnlyOK && dockFrameNear(csSurfOnlyDock.frame, csAppKitFrame(y: 362))
        && csSurfOnlyCounts.withLock { $0 } == [0, 1],
      "frame=\(csSurfOnlyDock.frame) counts=\(csSurfOnlyCounts.withLock { $0 })")

// Reviewer P1 回归（保守路径不整窗避让）：Composition Surface 是常驻大窗（768x912），障碍性
// 完全取决于宠物下方的像素内容；保守 visible 无 contentBottom（macOS 13 / TCC 拒绝 / 捕获失败 /
// 冷启动首次观察前）时没有任何依据整窗避让——旧行为把 dock 推到大窗底部且降级模式下永久如此。
// 跳过后降级模式与本功能引入前一致。
csTime = 24_500
let csDegradeProbe = BubbleVisibilityProbe(
    monotonicNow: { csTime }, canCapture: { true }, capturer: { _ in .unavailable })
let csDegradeDock = DockPanel()
let csDegradeCounts = OSAllocatedUnfairLock(initialState: [Int]())
let csDegradeOK = csRunTwoTickLayout(
    probe: csDegradeProbe, dock: csDegradeDock,
    obstacleCounts: csDegradeCounts, candidates: [csMascot] + csSurfaces)
check("T-cs10 恒unavailable(macOS13/捕获失败)→CS无观察数据不作障碍→dock基础位388(非大窗底)",
      csDegradeOK && dockFrameNear(csDegradeDock.frame, csAppKitFrame(y: 388))
        && csDegradeCounts.withLock { $0 } == [0, 0]
        && csDegradeProbe.observation(for: CGWindowID(27814)).visibility == .visible
        && csDegradeProbe.observation(for: CGWindowID(27814)).contentBottom == nil,
      "frame=\(csDegradeDock.frame) counts=\(csDegradeCounts.withLock { $0 })")

csTime = 24_600
let csTccProbe = BubbleVisibilityProbe(
    monotonicNow: { csTime }, canCapture: { false }, capturer: { _ in .unavailable })
let csTccDock = DockPanel()
let csTccCounts = OSAllocatedUnfairLock(initialState: [Int]())
let csTccOK = csRunTwoTickLayout(
    probe: csTccProbe, dock: csTccDock,
    obstacleCounts: csTccCounts, candidates: [csMascot] + csSurfaces)
check("T-cs10b TCC拒绝(canCapture=false)→CS保守visible无数据同样跳过→基础位388",
      csTccOK && dockFrameNear(csTccDock.frame, csAppKitFrame(y: 388))
        && csTccCounts.withLock { $0 } == [0, 0],
      "frame=\(csTccDock.frame) counts=\(csTccCounts.withLock { $0 })")

// 降级下 ACT（.bubble 几何小窗）保守整窗避让语义不回归：只被 ACT 整窗（maxY 458）推到 460，
// 不再被 CS 大窗叠加推到大窗底部。
csTime = 24_700
let csDegradeActProbe = BubbleVisibilityProbe(
    monotonicNow: { csTime }, canCapture: { true }, capturer: { _ in .unavailable })
let csDegradeActDock = DockPanel()
let csDegradeActCounts = OSAllocatedUnfairLock(initialState: [Int]())
let csDegradeActOK = csRunTwoTickLayout(
    probe: csDegradeActProbe, dock: csDegradeActDock,
    obstacleCounts: csDegradeActCounts, candidates: [csMascot] + csSurfaces + [csAct])
check("T-cs10c 降级下ACT(.bubble)保守整窗避让不回归→仅ACT整窗推到460(CS跳过)",
      csDegradeActOK && dockFrameNear(csDegradeActDock.frame, csAppKitFrame(y: 460))
        && csDegradeActCounts.withLock { $0 } == [1, 1],
      "frame=\(csDegradeActDock.frame) counts=\(csDegradeActCounts.withLock { $0 })")

// Reviewer P1 回归（冷启动闪跳消除）：首 tick 无 cache → CS 跳过，dock 停基础位；第二 tick
// stats 到达 → 按内容 bbox 避让。序列 = [基础位 388 → 内容位 470]，不再出现首 tick 整窗
// 避让闪跳到大窗底部再回来。
csTime = 24_800
let csColdRelease = OSAllocatedUnfairLock(initialState: false)
let csColdProbe = BubbleVisibilityProbe(
    monotonicNow: { csTime }, canCapture: { true },
    capturer: { _ in
        while !csColdRelease.withLock({ $0 }) {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        return .stats(BubbleAlphaStats(nonTransparentPixelCount: 30_000, contentBottom: 470))
    })
let csColdDock = DockPanel()
let csColdFrames = OSAllocatedUnfairLock(initialState: [NSRect]())
let csColdCounts = OSAllocatedUnfairLock(initialState: [Int]())
func csColdPlace() -> Bool {
    let placed = FollowLayoutPass.placeDock(
        mascot: csMascot,
        candidates: [csMascot] + csSurfaces,
        bubbleProbe: csColdProbe,
        frameSink: { pet, obstacles in
            csColdCounts.withLock { $0.append(obstacles.count) }
            return csColdDock.placeBelow(
                petQuartzRect: pet, avoiding: obstacles, visibleScreen: nil,
                movementChanged: false, monotonicNow: csTime)
        })
    csColdFrames.withLock { $0.append(csColdDock.frame) }
    return placed
}
_ = csColdPlace()   // tick1：门闩未放行 → 无 cache → 跳过（基础位）
csColdRelease.withLock { $0 = true }
let csColdCompleted = waitProbeChannelsIdle(csColdProbe)
_ = csColdPlace()   // tick2：stats 已入 cache → 内容 bbox 避让
check("T-cs11 冷启动首tick无cache→基础位388;次tick stats→内容避让470(序列无大窗底闪跳)",
      csColdCompleted
        && csColdFrames.withLock { $0.count } == 2
        && dockFrameNear(csColdFrames.withLock { $0 }[0], csAppKitFrame(y: 388))
        && dockFrameNear(csColdFrames.withLock { $0 }[1], csAppKitFrame(y: 470))
        && csColdCounts.withLock { $0 } == [0, 1],
      "frames=\(csColdFrames.withLock { $0 }) counts=\(csColdCounts.withLock { $0 })")

// 大窗捕获降采样（性能保护）：>100k 面积候选等比缩到 maxSide<=240（保持纵横比）；
// 小窗（ACT）不降采样、路径不变。
let csSize = BubbleVisibilityProbe.downsampleCaptureSize(width: 768, height: 912)
check("T-cs8 大窗(768x912,699k px)→降采样(202,240)纵横比保持",
      csSize?.width == 202 && csSize?.height == 240,
      "size=\(String(describing: csSize))")
check("T-cs8b 小窗(ACT 214x74)不降采样(路径不变)",
      BubbleVisibilityProbe.downsampleCaptureSize(width: 214, height: 74) == nil, "")

// 换算正确性（纯函数，>100k 候选 768x912 → cap 202x240）：已知内容位置——原始行 470
//（展开气泡内容底）对应 cap 行 470*240/912≈123.7；捕获统计报 124 → rescale 回原始行
// 误差 ≤2px；像素计数按面积比 origArea/capArea 放大（202px → 2918px 等价）。
if let size = csSize {
    let captured = BubbleAlphaStats(nonTransparentPixelCount: 202, contentBottom: 124)
    let rescaled = BubbleVisibilityProbe.rescaleDownsampledStats(
        captured, captureWidth: size.width, captureHeight: size.height,
        originalWidth: 768, originalHeight: 912)
    let expectedCount = Int((202.0 * 768.0 * 912.0 / (202.0 * 240.0)).rounded())
    check("T-cs9 降采样contentBottom换算误差<=2px(原行470)",
          abs(rescaled.contentBottom - 470) <= 2,
          "rescaled=\(rescaled.contentBottom)")
    check("T-cs9b 像素计数按面积比换算(origArea/capArea)",
          rescaled.nonTransparentPixelCount == expectedCount,
          "rescaled=\(rescaled.nonTransparentPixelCount) expected=\(expectedCount)")
} else {
    check("T-cs9/T-cs9b 降采样尺寸", false, "size=\(String(describing: csSize))")
}

print("\n[Composition Surface 气泡通道] \(pass - csPass) passed, \(fail - csBase) failed")

// ---- T-cla: Composition Surface 活层代表选择（2026-08-26 死层残影回归症状）----
// 现场形态（坐标/wid 合成，保持现场相对几何）：宿主同时挂多个 CS 层；CGWindowList
// 顺序死层在前（过期残影：bounds 固定、内容底显著偏离当前脚底），活层在后且随宠物移动。
// 旧代表选择取输入顺序首个 CS → 死层 contentBottom 进入布局锚 → dock 被推到幽灵内容下方。
// 修复语义：Mascot 实测脚底做一致性参照（仅参考通道），全部标题命中 CS 由主导探测参与判定，
// 代表 = 活层集中最小 csBottomAbs；无可判定活层 → 显式回退 Mascot 窗口底。
let claBase = fail, claPass = pass
let claPet = CGRect(x: 1487, y: 190, width: 172, height: 179)   // petMaxY=369（现场几何）
let claMascot = mkw(900, layer: 2, claPet, title: "Codex Pet Mascot Effect")
let claDeadBounds = CGRect(x: 1189, y: -3, width: 768, height: 912)
let claLiveBounds = CGRect(x: 1487, y: -41, width: 768, height: 952)
let claDead = mkw(8001, layer: 3, claDeadBounds, title: "Codex Pet Composition Surface")
let claLive = mkw(8010, layer: 4, claLiveBounds, title: "Codex Pet Composition Surface")
let claDockX = claPet.minX + (claPet.width - 200) / 2
func claAppKitFrame(y: CGFloat) -> NSRect {
    Geometry.appKitRectFromQuartz(CGRect(x: claDockX, y: y, width: 200, height: 48))
}
// 生产组合（与 ancRunTwoTickLayout 同构）：FollowLayoutPass.placeDock →
// 真 DockPanel.placeBelow → 断言实际 DockPanel.frame。
func claRunTwoTickLayout(
    probe: BubbleVisibilityProbe,
    dock: DockPanel,
    mascot: WinCandidate,
    candidates: [WinCandidate],
    petRects: OSAllocatedUnfairLock<[CGRect]>,
    obstacleCounts: OSAllocatedUnfairLock<[Int]>
) -> Bool {
    func place() -> Bool {
        FollowLayoutPass.placeDock(
            mascot: mascot,
            candidates: candidates,
            bubbleProbe: probe,
            frameSink: { pet, obstacles in
                petRects.withLock { $0.append(pet) }
                obstacleCounts.withLock { $0.append(obstacles.count) }
                return dock.placeBelow(
                    petQuartzRect: pet, avoiding: obstacles, visibleScreen: nil,
                    movementChanged: false, monotonicNow: csTime)
            })
    }
    _ = place()
    let completed = waitProbeChannelsIdle(probe)
    // 参考通道结果到达后补一拍，使活层选择在最新 cache 上生效。
    _ = place()
    _ = place()
    return completed
}

// AC1 主症状：死层在前 + 活层在后 + Mascot 参照窗。petFoot=330；
// 活层 csBottomAbs = 331 ∈ [328,502] 且为窗口内最小；死层 abs570 > 上界 → 排除。
// 期望实际 frame 锚活层内容底 333，而非死层幽灵底 572。
csTime = 26_000
let claCapturedRefs = OSAllocatedUnfairLock(initialState: [CGWindowID]())
let claStats: [CGWindowID: BubbleAlphaStats] = [
    CGWindowID(900): BubbleAlphaStats(nonTransparentPixelCount: 30_000, contentBottom: 139),
    CGWindowID(8001): BubbleAlphaStats(nonTransparentPixelCount: 30_000, contentBottom: 570),
    CGWindowID(8010): BubbleAlphaStats(nonTransparentPixelCount: 30_000, contentBottom: 371),
]
let claCap: BubbleCapturer = { c in
    if c.wid == CGWindowID(900) { claCapturedRefs.withLock { $0.append(c.wid) } }
    return .stats(claStats[c.wid] ?? BubbleAlphaStats(nonTransparentPixelCount: 0, contentBottom: -1))
}
let claProbe = BubbleVisibilityProbe(monotonicNow: { csTime }, canCapture: { true }, capturer: claCap)
let claDock = DockPanel()
let claPetRects = OSAllocatedUnfairLock(initialState: [CGRect]())
let claCounts = OSAllocatedUnfairLock(initialState: [Int]())
let claOK = claRunTwoTickLayout(
    probe: claProbe, dock: claDock,
    mascot: claMascot, candidates: [claMascot, claDead, claLive],
    petRects: claPetRects, obstacleCounts: claCounts)
check("T-cla1 RED-S3 死层排前→dock锚活层内容底333(非死层幽灵底572)",
      claOK && dockFrameNear(claDock.frame, claAppKitFrame(y: 333)),
      "frame=\(claDock.frame) expected=\(claAppKitFrame(y: 333)) counts=\(claCounts.withLock { $0 })")
check("T-cla1b cache生效后锚活层(abs331,origin/width不变)",
      claPetRects.withLock { $0 }.last?.maxY == 331
        && claPetRects.withLock { $0 }.last?.origin == claPet.origin
        && claPetRects.withLock { $0 }.last?.width == claPet.width,
      "pets=\(claPetRects.withLock { $0 })")
check("T-cla1c Mascot仅走参考通道捕获(不进障碍候选cached语义)",
      claCapturedRefs.withLock { $0 } == [CGWindowID(900)]
        && claProbe.lock.withLock { $0.knownWids } == Set([CGWindowID(8001), CGWindowID(8010)])
        && claProbe.lock.withLock { $0.referenceKnownWids } == Set([CGWindowID(900)]),
      "refs=\(claCapturedRefs.withLock { $0.map { Int($0) } }) knownWids=\(claProbe.lock.withLock { Array($0.knownWids.map { Int($0) }) }.sorted()) refKnown=\(claProbe.lock.withLock { Array($0.referenceKnownWids.map { Int($0) }) }.sorted())")

// AC3/R3 边界：活层恰在一致性下界（abs=foot-2）→ 唯一活层候选保留为代表。
csTime = 26_100
let claLowerEdge = mkw(8020, layer: 4, CGRect(x: 1487, y: -40, width: 768, height: 820),
                       title: "Codex Pet Composition Surface")
let claLowerProbe = BubbleVisibilityProbe(
    monotonicNow: { csTime }, canCapture: { true },
    capturer: { c in
        switch c.wid {
        case CGWindowID(900): return .stats(BubbleAlphaStats(nonTransparentPixelCount: 30_000, contentBottom: 139))
        case CGWindowID(8020): return .stats(BubbleAlphaStats(nonTransparentPixelCount: 30_000, contentBottom: 367))
        default: return .stats(BubbleAlphaStats(nonTransparentPixelCount: 30_000, contentBottom: 600))
        }
    })
let claLowerDock = DockPanel()
let claLowerPetRects = OSAllocatedUnfairLock(initialState: [CGRect]())
let claLowerCounts = OSAllocatedUnfairLock(initialState: [Int]())
_ = claRunTwoTickLayout(
    probe: claLowerProbe, dock: claLowerDock,
    mascot: claMascot, candidates: [claMascot, claDead, claLowerEdge],
    petRects: claLowerPetRects, obstacleCounts: claLowerCounts)
// 第三 tick：参考与障碍 cache 均已就绪，活层判定在本 tick 命中下界容差候选。
_ = claRunTwoTickLayout(
    probe: claLowerProbe, dock: claLowerDock,
    mascot: claMascot, candidates: [claMascot, claDead, claLowerEdge],
    petRects: claLowerPetRects, obstacleCounts: claLowerCounts)
check("T-cla2 活层内容底恰在窗口下界(abs328=petFoot-2容差)仍为代表→frame.y330",
      dockFrameNear(claLowerDock.frame, claAppKitFrame(y: 330)),
      "frame=\(claLowerDock.frame) expected=\(claAppKitFrame(y: 330))")

// AC3/R3 边界：全部候选出窗（无候选满足一致性窗口）→ 显式回退 Mascot 窗口底 369+2=371。
csTime = 26_200
let claOutProbe = BubbleVisibilityProbe(
    monotonicNow: { csTime }, canCapture: { true },
    capturer: { c in
        switch c.wid {
        case CGWindowID(900): return .stats(BubbleAlphaStats(nonTransparentPixelCount: 30_000, contentBottom: 139))
        case CGWindowID(8001), CGWindowID(8010): return .stats(BubbleAlphaStats(nonTransparentPixelCount: 30_000, contentBottom: 700))
        default: return .unavailable
        }
    })
let claOutDock = DockPanel()
let claOutPetRects = OSAllocatedUnfairLock(initialState: [CGRect]())
let claOutCounts = OSAllocatedUnfairLock(initialState: [Int]())
let claOutOK = claRunTwoTickLayout(
    probe: claOutProbe, dock: claOutDock,
    mascot: claMascot, candidates: [claMascot, claDead, claLive],
    petRects: claOutPetRects, obstacleCounts: claOutCounts)
check("T-cla3 全部候选出窗→显式回退Mascot窗口底371(CS不作锚)",
      claOutOK && dockFrameNear(claOutDock.frame, claAppKitFrame(y: 371)),
      "frame=\(claOutDock.frame) expected=\(claAppKitFrame(y: 371)) pets=\(claOutPetRects.withLock { $0.map { $0.maxY } })")

// R3 观察不可用（unavailable/降级/首 tick 无 cache）：单 CS 代表路径不变，保守回退窗口底。
csTime = 26_300
let claDegradeProbe = BubbleVisibilityProbe(
    monotonicNow: { csTime }, canCapture: { true }, capturer: { _ in .unavailable })
let claDegradeDock = DockPanel()
let claDegradePetRects = OSAllocatedUnfairLock(initialState: [CGRect]())
let claDegradeCounts = OSAllocatedUnfairLock(initialState: [Int]())
let claDegradeOK = claRunTwoTickLayout(
    probe: claDegradeProbe, dock: claDegradeDock,
    mascot: claMascot, candidates: [claMascot, claLive],
    petRects: claDegradePetRects, obstacleCounts: claDegradeCounts)
check("T-cla4 观察不可用(单CS/unavailable)→保守回退窗口底371(petRects两tick均=窗口)",
      claDegradeOK && dockFrameNear(claDegradeDock.frame, claAppKitFrame(y: 371))
        && claDegradePetRects.withLock { $0 }.allSatisfy { $0 == claPet },
      "frame=\(claDegradeDock.frame) pets=\(claDegradePetRects.withLock { $0 })")

// AC6 体验不回归：稳定身份的多不同签名 CS + Mascot 生产链。参考通道只捕获 Mascot；
// CS 只出现在主导探测 capturer 列表；identityDirty 清掉后下一次参考捕获间隔 ~1.0s
// 而非固定 0.1s。断言仍落到真实 DockPanel.frame（活层内容底 333）。
csTime = 0
let cla6Clock = OSAllocatedUnfairLock(initialState: TimeInterval(0))
let cla6Captured = OSAllocatedUnfairLock(initialState: [CGWindowID]())
var cla6Probe: BubbleVisibilityProbe!
let cla6Cap: BubbleCapturer = { c in
    cla6Captured.withLock { $0.append(c.wid) }
    return .stats(claStats[c.wid]
        ?? BubbleAlphaStats(nonTransparentPixelCount: 0, contentBottom: -1))
}
cla6Probe = BubbleVisibilityProbe(
    monotonicNow: { cla6Clock.withLock { $0 } }, canCapture: { true }, capturer: cla6Cap)
let cla6Dock = DockPanel()
func cla6Place() -> Bool {
    csTime = cla6Clock.withLock { $0 }
    return FollowLayoutPass.placeDock(
        mascot: claMascot,
        candidates: [claMascot, claDead, claLive],
        bubbleProbe: cla6Probe,
        frameSink: { pet, obstacles in
            cla6Dock.placeBelow(
                petQuartzRect: pet, avoiding: obstacles, visibleScreen: nil,
                movementChanged: false, monotonicNow: csTime)
        })
}
_ = cla6Place()
let cla6FirstIdle = waitProbeChannelsIdle(cla6Probe)
_ = cla6Place()
let cla6CapturedAfterFirst = cla6Captured.withLock { $0 }
let cla6IdentityDirtyAfterFirst = cla6Probe.lock.withLock { $0.identityDirty }
let cla6KnownAfterFirst = cla6Probe.lock.withLock { $0.knownWids }
let cla6RefKnownAfterFirst = cla6Probe.lock.withLock { $0.referenceKnownWids }
let cla6FirstRefAt = cla6Probe.lock.withLock { $0.lastReferenceCaptureAt }
check("T-cla6a 稳定多CS:参考通道仅Mascot;CS仅主导探测;dock仍锚活层333",
      cla6FirstIdle
        && !cla6IdentityDirtyAfterFirst
        && cla6CapturedAfterFirst.filter { $0 == CGWindowID(900) }.count == 1
        && cla6CapturedAfterFirst.filter { $0 == CGWindowID(8001) }.count == 1
        && cla6CapturedAfterFirst.filter { $0 == CGWindowID(8010) }.count == 1
        && Set(cla6CapturedAfterFirst) == Set([CGWindowID(900), CGWindowID(8001), CGWindowID(8010)])
        && cla6RefKnownAfterFirst == Set([CGWindowID(900)])
        && cla6KnownAfterFirst == Set([CGWindowID(8001), CGWindowID(8010)])
        && dockFrameNear(cla6Dock.frame, claAppKitFrame(y: 333)),
      "captured=\(cla6CapturedAfterFirst.map { Int($0) }) "
        + "refKnown=\(cla6RefKnownAfterFirst.map { Int($0) }.sorted()) "
        + "known=\(cla6KnownAfterFirst.map { Int($0) }.sorted()) "
        + "dirty=\(cla6IdentityDirtyAfterFirst) frame=\(cla6Dock.frame) "
        + "expected=\(claAppKitFrame(y: 333))")

cla6Clock.withLock { $0 = cla6FirstRefAt + 0.11 }
_ = cla6Place()
let cla6IdleAfter01 = waitProbeChannelsIdle(cla6Probe)
let cla6RefAtAfter01 = cla6Probe.lock.withLock { $0.lastReferenceCaptureAt }
let cla6CapturedAfter01 = cla6Captured.withLock { $0 }
cla6Clock.withLock { $0 = cla6FirstRefAt + 1.0 }
_ = cla6Place()
let cla6IdleAfter10 = waitProbeChannelsIdle(cla6Probe)
let cla6RefAtAfter10 = cla6Probe.lock.withLock { $0.lastReferenceCaptureAt }
let cla6RefGap = cla6RefAtAfter10 - cla6FirstRefAt
let cla6CapturedAfter10 = cla6Captured.withLock { $0 }
check("T-cla6b identityDirty清后参考通道下次捕获间隔~1.0s(非0.1s)且仍仅Mascot",
      cla6IdleAfter01 && cla6IdleAfter10
        && cla6FirstRefAt == 0
        && cla6RefAtAfter01 == cla6FirstRefAt
        && abs(cla6RefGap - 1.0) < 0.000_001
        && cla6CapturedAfter01 == cla6CapturedAfterFirst
        && cla6CapturedAfter10.filter { $0 == CGWindowID(900) }.count == 2
        && dockFrameNear(cla6Dock.frame, claAppKitFrame(y: 333)),
      "firstAt=\(cla6FirstRefAt) after01=\(cla6RefAtAfter01) "
        + "after10=\(cla6RefAtAfter10) gap=\(cla6RefGap) "
        + "captured01=\(cla6CapturedAfter01.map { Int($0) }) "
        + "captured10=\(cla6CapturedAfter10.map { Int($0) }) frame=\(cla6Dock.frame)")

print("\n[CS 活层代表选择] \(pass - claPass) passed, \(fail - claBase) failed")

// ---- T-csm: 多尺寸 Composition Surface 幽灵内容回归（2026-08-24 现场 e1d94c6 症状）----
// 现场症状（用户截图 + 主 Agent qa_snapshot 取证，坐标/wid 已脱敏为合成值，保持现场相对几何）：
// 气泡在宠物**上方**时，宿主同时存在多种 bounds 的 Composition Surface 窗口（CGWindowList
// 顺序前到后：前层新 768x978 / 后层旧 768x912，后层顶沿比前层低 66px，全部 onscreen layer3）。
// desktopIndependentWindow
// 捕获窗口自身内容、感知不到前层遮挡：后层残留宿主布局切换前的旧气泡卡（内容延伸到
// 宠物下方 86px 的幽灵）；旧去重按 (owner,title,layer,bounds) 签名——bounds
// 不同不去重 → 后层幽灵与真实内容都成为障碍/锚 → dock 被推到幽灵内容底+gap（比正确位
// 多让 31px），宠物与 dock 之间出现大气泡尺寸空白。前层真实可见内容只到宠物下方 55px
//（控制按钮）。修复语义：CS 通道按标题去重——candidates 输入顺序（=CGWindowList
// 前到后）首个 CS 实例保留为唯一代表，其余 CS 实例不论 bounds 全部跳过；被遮挡的后层
// 残影不再产生障碍/锚/像素捕获。
let csmBase = fail, csmPass = pass
let csmPet = CGRect(x: 398, y: 485, width: 172, height: 179)   // 合成坐标（petMaxY=664）
let csmMascot = mkw(910, layer: 2, csmPet, title: "Codex Pet Mascot Effect")
let csmFront = mkw(9002, layer: 3, CGRect(x: 100, y: 209, width: 768, height: 978),
                   title: "Codex Pet Composition Surface")   // 前层（新，wid 故意大于后层）
let csmBack = mkw(9001, layer: 3, CGRect(x: 100, y: 275, width: 768, height: 912),
                  title: "Codex Pet Composition Surface")   // 后层（旧，幽灵内容，wid 最小）
let csmAct = mkw(9003, layer: 3, CGRect(x: 377, y: 663, width: 214, height: 74),
                 title: "Codex Pet Activity Stack Backing")
let csmDockX = csmPet.minX + (csmPet.width - 200) / 2
func csmAppKitFrame(y: CGFloat) -> NSRect {
    Geometry.appKitRectFromQuartz(CGRect(x: csmDockX, y: y, width: 200, height: 48))
}

// 单元：CS 标题级去重（跨 bounds）→ 仅输入顺序首位（前层）成为唯一 CS 障碍。
check("T-csm1 多尺寸CS不同签名实例均保留为活层候选集(9002+9001)",
      PetTracker.obstaclesNear(mascot: csmMascot, candidates: [csmMascot, csmFront, csmBack, csmAct])
        .filter { $0.title == PetHeuristics.compositionSurfaceTitle }.map { $0.wid }.sorted() == [CGWindowID(9001), CGWindowID(9002)], "")
// 顺序合同锁定：前层 wid 更大时仍按输入顺序首位（而非 wid 最小）保留——wid 升序只是
// 输出稳定性排序，绝不参与 CS 代表选择（若按 wid 排序后取首位，会选中后层残影）。
check("T-csm7 前后层不同签名均保留(wid大小不影响候选集;活层由一致性窗口裁决)",
      PetTracker.obstaclesNear(mascot: csmMascot, candidates: [csmMascot,
        mkw(9020, layer: 3, CGRect(x: 100, y: 209, width: 768, height: 978),
            title: "Codex Pet Composition Surface"),
        mkw(9015, layer: 3, CGRect(x: 100, y: 275, width: 768, height: 912),
            title: "Codex Pet Composition Surface"), csmAct])
        .filter { $0.title == PetHeuristics.compositionSurfaceTitle }.map { $0.wid }.sorted() == [CGWindowID(9015), CGWindowID(9020)], "")
// 顺序敏感性：candidates 反转（后层在前）→ 代表随列表首位变化，证明是前到后列表顺序
// 语义而非 wid 排序（旧去重代表由 wid 升序决定）。
check("T-csm2 candidates顺序反转→两签名候选仍在集合(顺序不改变集合内容)",
      PetTracker.obstaclesNear(mascot: csmMascot, candidates: [csmMascot, csmBack, csmFront, csmAct])
        .filter { $0.title == PetHeuristics.compositionSurfaceTitle }.map { $0.wid }.sorted() == [CGWindowID(9001), CGWindowID(9002)], "")
// 既有同 bounds 多实例语义：仍恰好 1 个 CS 障碍，代表=输入顺序首位（wid 乱序输入）。
let csmSameBounds = CGRect(x: 100, y: 275, width: 768, height: 912)
let csmDupes = [9005, 9004, 9007, 9006].map {
    mkw(UInt32($0), layer: 3, csmSameBounds, title: "Codex Pet Composition Surface")
}
check("T-csm3 同bounds多实例CS仍去重为1(wid升序代表9004,与几何通道签名去重一致)",
      PetTracker.obstaclesNear(mascot: csmMascot, candidates: [csmMascot] + csmDupes)
        .filter { $0.title == PetHeuristics.compositionSurfaceTitle }.map { $0.wid } == [CGWindowID(9004)], "")
// 非 CS 通道既有签名去重不回归：同 bounds 重复 ACT → 1 个障碍；不同 bounds → 保留两个。
let csmActDupes = [
    mkw(9011, layer: 3, CGRect(x: 377, y: 663, width: 214, height: 74),
        title: "Codex Pet Activity Stack Backing"),
    mkw(9012, layer: 3, CGRect(x: 377, y: 663, width: 214, height: 74),
        title: "Codex Pet Activity Stack Backing"),
]
check("T-csm4 非CS同bounds重复窗口仍按签名去重为1",
      PetTracker.obstaclesNear(mascot: csmMascot, candidates: [csmMascot] + csmActDupes).count == 1, "")
check("T-csm4b 非CS不同bounds双实例不去重(签名含bounds语义保持)",
      PetTracker.obstaclesNear(mascot: csmMascot, candidates: [csmMascot, csmActDupes[0],
        mkw(9013, layer: 3, CGRect(x: 377, y: 666, width: 214, height: 74),
            title: "Codex Pet Activity Stack Backing")]).count == 2, "")

// 生产组合：FollowLayoutPass → 真实 DockPanel.placeBelow → DockPanel.frame（两 tick，
// 与 csRunTwoTickLayout 同构）。capturer 按 wid 区分前后层：前层真实可见内容
// contentBottom=454 → 内容底 abs 664 == Mascot 脚底( maxY 664 )；后层幽灵
// contentBottom=700 → abs 976 显著偏离脚底一致性窗口 [662,836] 被排除；
// ACT 仅 41px 噪声 → hidden。期望实际 frame 锚前层可见内容底 209+454+1+2=666。
csTime = 24_000
let csmCaptured = OSAllocatedUnfairLock(initialState: [CGWindowID]())
let csmStats: [CGWindowID: BubbleAlphaStats] = [
    CGWindowID(9002): BubbleAlphaStats(nonTransparentPixelCount: 30_000, contentBottom: 454),
    CGWindowID(9001): BubbleAlphaStats(nonTransparentPixelCount: 30_000, contentBottom: 700),
    CGWindowID(9003): BubbleAlphaStats(nonTransparentPixelCount: 41, contentBottom: 28),
]
let csmCap: BubbleCapturer = { c in
    csmCaptured.withLock { $0.append(c.wid) }
    return .stats(csmStats[c.wid]
        ?? BubbleAlphaStats(nonTransparentPixelCount: 0, contentBottom: -1))
}
let csmProbe = BubbleVisibilityProbe(
    monotonicNow: { csTime }, canCapture: { true }, capturer: csmCap)
let csmDock = DockPanel()
let csmObstacleCounts = OSAllocatedUnfairLock(initialState: [Int]())
func csmPlace(_ candidates: [WinCandidate]) -> Bool {
    func place() -> Bool {
        FollowLayoutPass.placeDock(
            mascot: csmMascot, candidates: candidates, bubbleProbe: csmProbe,
            frameSink: { pet, obstacles in
                csmObstacleCounts.withLock { $0.append(obstacles.count) }
                return csmDock.placeBelow(
                    petQuartzRect: pet, avoiding: obstacles, visibleScreen: nil,
                    movementChanged: false, monotonicNow: csTime)
            })
    }
    _ = place()
    let completed = waitProbeChannelsIdle(csmProbe)
    _ = place()
    return completed
}
let csmOK = csmPlace([csmMascot, csmFront, csmBack, csmAct])
check("T-csm5 现场多尺寸CS→实际panel锚前层可见内容底(y=666)而非窗口底(y=666+?)",
      csmOK && dockFrameNear(csmDock.frame, csmAppKitFrame(y: 666)),
      "frame=\(csmDock.frame) expected=\(csmAppKitFrame(y: 666))")
check("T-csm6 全部CS签名+ACT进入probe候选集(Mascot走参考通道不在其中)",
      csmCaptured.withLock { $0 }.contains(CGWindowID(9001))
        && csmCaptured.withLock { $0 }.contains(CGWindowID(9002))
        && csmCaptured.withLock { $0 }.contains(CGWindowID(9003)), "")

print("\n[Composition Surface 多尺寸幽灵] \(pass - csmPass) passed, \(fail - csmBase) failed")

// ---- T-anc: dock 基础位锚定宠物可见内容底（2026-08-24 现场像素级症状）----
// 现场症状（主 Agent 截屏取证）：收起态宠物可见内容（绿色椭圆底座）底在 abs y≈328，
// Mascot 窗口底在 369 → 基线 dock 停 371，视觉空白 ≈44px。根因：基础位锚 Mascot 窗口底
// （bounds.maxY+gap），而 Mascot 窗口底部有大量透明 padding；宠物像素实际渲染在
// Composition Surface，其 contentBottom 观察就是宠物可见内容的实时底边。
// 语义（与避让矩形同一 contentBottom 口径）：可见内容底边 abs y = 代表.bounds.minY +
// contentBottom + 1（contentBottom 为窗口内像素行），基础位 = 内容底边 + gap。
let ancBase = fail, ancPass = pass
let ancPet = CGRect(x: 1487, y: 190, width: 172, height: 179)   // petMaxY=369（现场）
let ancMascot = mkw(900, layer: 2, ancPet, title: "Codex Pet Mascot Effect")
let ancDockX = ancPet.minX + (ancPet.width - 200) / 2   // 水平仍按 Mascot 窗口居中
func ancAppKitFrame(y: CGFloat) -> NSRect {
    Geometry.appKitRectFromQuartz(CGRect(x: ancDockX, y: y, width: 200, height: 48))
}
// 生产组合（与 csRunTwoTickLayout 同构，mascot/candidates 参数化；petRects 记录
// frameSink 实收的布局锚，用于断言 anchor 契约本身）。
func ancRunTwoTickLayout(
    probe: BubbleVisibilityProbe,
    dock: DockPanel,
    mascot: WinCandidate,
    candidates: [WinCandidate],
    petRects: OSAllocatedUnfairLock<[CGRect]>,
    obstacleCounts: OSAllocatedUnfairLock<[Int]>
) -> Bool {
    func place() -> Bool {
        FollowLayoutPass.placeDock(
            mascot: mascot,
            candidates: candidates,
            bubbleProbe: probe,
            frameSink: { pet, obstacles in
                petRects.withLock { $0.append(pet) }
                obstacleCounts.withLock { $0.append(obstacles.count) }
                return dock.placeBelow(
                    petQuartzRect: pet, avoiding: obstacles, visibleScreen: nil,
                    movementChanged: false, monotonicNow: csTime)
            })
    }
    _ = place()
    // 与 cla/cs 助手一致：参考通道完成后才消费 tick-2 状态，消除双通道完成顺序竞态。
    let completed = waitProbeChannelsIdle(probe)
    _ = place()
    return completed
}

// RED：现场收起态。CS 代表（去重后 wid 27814）contentBottom=331（窗口内）→ 可见内容底边
// abs y329（= -3 + 331 + 1，与避让矩形高度 contentBottom+1 同口径）；ACT 仅 41px 噪声点 →
// hidden。期望基础位 = 329+2 = 331，而非基线窗口底 369+2 = 371（44px 视觉空白来源）。
csTime = 25_000
let ancCollapsedStats: [CGWindowID: BubbleAlphaStats] = [
    CGWindowID(27814): BubbleAlphaStats(nonTransparentPixelCount: 30_000, contentBottom: 331),
    CGWindowID(27900): BubbleAlphaStats(nonTransparentPixelCount: 41, contentBottom: 28),
]
let ancCollapsedCap: BubbleCapturer = { c in
    .stats(ancCollapsedStats[c.wid]
        ?? BubbleAlphaStats(nonTransparentPixelCount: 0, contentBottom: -1))
}
let ancCollapsedProbe = BubbleVisibilityProbe(
    monotonicNow: { csTime }, canCapture: { true }, capturer: ancCollapsedCap)
let ancCollapsedDock = DockPanel()
let ancCollapsedPetRects = OSAllocatedUnfairLock(initialState: [CGRect]())
let ancCollapsedCounts = OSAllocatedUnfairLock(initialState: [Int]())
let ancCollapsedOK = ancRunTwoTickLayout(
    probe: ancCollapsedProbe, dock: ancCollapsedDock,
    mascot: ancMascot, candidates: [ancMascot] + csSurfaces + [csAct],
    petRects: ancCollapsedPetRects, obstacleCounts: ancCollapsedCounts)
check("T-anc1 RED 现场收起态→实际panel锚内容底331(非窗口底371,消44px空白)",
      ancCollapsedOK && dockFrameNear(ancCollapsedDock.frame, ancAppKitFrame(y: 331)),
      "frame=\(ancCollapsedDock.frame) expected=\(ancAppKitFrame(y: 331))")
// anchor 契约：首 tick 无 cache → 回退窗口底锚（petRects[0].maxY=369）；次 tick stats 到达
// → frameSink 收到调整后 pet（origin/width 不变、maxY=329，高度 139）。
check("T-anc1b cache生效后调整pet(maxY329,origin/width不变)",
      ancCollapsedPetRects.withLock { $0 }.last
        == CGRect(x: ancPet.minX, y: ancPet.minY, width: ancPet.width, height: 139),
      "pets=\(ancCollapsedPetRects.withLock { $0 })")

// 展开态回归（无双重下移）：气泡卡渲染进 CS（contentBottom=470 窗口内 → 内容底边 abs 468）
// → 基础位本身 = 468+2 = 470；CS 内容障碍底边同为 468，与基础位 dock 无垂直相交 → 不再
// 下移，最终 470 与基线避让结果一致。
csTime = 25_100
let ancExpandedStats: [CGWindowID: BubbleAlphaStats] = [
    CGWindowID(27814): BubbleAlphaStats(nonTransparentPixelCount: 30_000, contentBottom: 470),
    CGWindowID(27900): BubbleAlphaStats(nonTransparentPixelCount: 194, contentBottom: 38),
]
let ancExpandedCap: BubbleCapturer = { c in
    .stats(ancExpandedStats[c.wid]
        ?? BubbleAlphaStats(nonTransparentPixelCount: 0, contentBottom: -1))
}
let ancExpandedProbe = BubbleVisibilityProbe(
    monotonicNow: { csTime }, canCapture: { true }, capturer: ancExpandedCap)
let ancExpandedDock = DockPanel()
let ancExpandedPetRects = OSAllocatedUnfairLock(initialState: [CGRect]())
let ancExpandedCounts = OSAllocatedUnfairLock(initialState: [Int]())
let ancExpandedOK = ancRunTwoTickLayout(
    probe: ancExpandedProbe, dock: ancExpandedDock,
    mascot: ancMascot, candidates: [ancMascot] + csSurfaces + [csAct],
    petRects: ancExpandedPetRects, obstacleCounts: ancExpandedCounts)
check("T-anc2 展开态内容底470→dock仍470(基础位即内容底,无双重下移)",
      ancExpandedOK && dockFrameNear(ancExpandedDock.frame, ancAppKitFrame(y: 470)),
      "frame=\(ancExpandedDock.frame) expected=\(ancAppKitFrame(y: 470))")
check("T-anc2b 展开态anchor=内容底468(避让起点与障碍底同源,一步到位)",
      ancExpandedPetRects.withLock { $0 }.count == 2
        && ancExpandedPetRects.withLock { $0 }[1].maxY == 468
        && ancExpandedCounts.withLock { $0 } == [1, 2],
      "pets=\(ancExpandedPetRects.withLock { $0 }) counts=\(ancExpandedCounts.withLock { $0 })")

// 降级回退：CS 恒 unavailable（macOS 13 / TCC 拒绝 / 捕获失败同路径）→ 无 contentBottom →
// 基础位回退 Mascot 窗口底 369+2=371（现状不变；与 T-cs10 系列同语义、现场几何）。
csTime = 25_200
let ancDegradeProbe = BubbleVisibilityProbe(
    monotonicNow: { csTime }, canCapture: { true }, capturer: { _ in .unavailable })
let ancDegradeDock = DockPanel()
let ancDegradePetRects = OSAllocatedUnfairLock(initialState: [CGRect]())
let ancDegradeCounts = OSAllocatedUnfairLock(initialState: [Int]())
let ancDegradeOK = ancRunTwoTickLayout(
    probe: ancDegradeProbe, dock: ancDegradeDock,
    mascot: ancMascot, candidates: [ancMascot] + csSurfaces,
    petRects: ancDegradePetRects, obstacleCounts: ancDegradeCounts)
check("T-anc3 降级CS无观察→基础位回退窗口底371(petRects两tick均=窗口)",
      ancDegradeOK && dockFrameNear(ancDegradeDock.frame, ancAppKitFrame(y: 371))
        && ancDegradePetRects.withLock { $0 } == [ancPet, ancPet]
        && ancDegradeCounts.withLock { $0 } == [0, 0],
      "frame=\(ancDegradeDock.frame) pets=\(ancDegradePetRects.withLock { $0 }) counts=\(ancDegradeCounts.withLock { $0 })")

// 拖动粘性：CS/宠物整体平移 (+40,-25)、0.1s cadence 内不重捕获（捕获计数不增）→
// contentBottom cache 粘性保留 → adjustedPet 随宠物移动，dock 相对可见内容底偏移不变。
csTime = 25_300
let ancDragCaptured = OSAllocatedUnfairLock(initialState: 0)
let ancDragProbe = BubbleVisibilityProbe(
    monotonicNow: { csTime }, canCapture: { true },
    capturer: { _ in
        ancDragCaptured.withLock { $0 += 1 }
        return .stats(BubbleAlphaStats(nonTransparentPixelCount: 30_000, contentBottom: 331))
    })
let ancDragDock = DockPanel()
let ancDragPetRects = OSAllocatedUnfairLock(initialState: [CGRect]())
let ancDragCounts = OSAllocatedUnfairLock(initialState: [Int]())
_ = ancRunTwoTickLayout(
    probe: ancDragProbe, dock: ancDragDock,
    mascot: ancMascot, candidates: [ancMascot] + csSurfaces,
    petRects: ancDragPetRects, obstacleCounts: ancDragCounts)
let ancDragCapturesBefore = ancDragCaptured.withLock { $0 }
csTime += 0.05   // cadence 内：不重捕获，cache 粘性
let ancPetMoved = ancPet.offsetBy(dx: 40, dy: -25)
let ancMascotMoved = mkw(900, layer: 2, ancPetMoved, title: "Codex Pet Mascot Effect")
let ancSurfacesMoved = [27814, 27815, 27816, 27817, 28787, 28788, 28789].map {
    mkw(UInt32($0), layer: 3, csSurfaceBounds.offsetBy(dx: 40, dy: -25),
        title: "Codex Pet Composition Surface")
}
let ancDragMovedPetRects = OSAllocatedUnfairLock(initialState: [CGRect]())
let ancDragMovedPlaced = FollowLayoutPass.placeDock(
    mascot: ancMascotMoved, candidates: [ancMascotMoved] + ancSurfacesMoved,
    bubbleProbe: ancDragProbe,
    frameSink: { pet, obstacles in
        ancDragMovedPetRects.withLock { $0.append(pet) }
        return ancDragDock.placeBelow(
            petQuartzRect: pet, avoiding: obstacles, visibleScreen: nil,
            movementChanged: false, monotonicNow: csTime)
    })
check("T-anc4 拖动(+40,-25)cache粘性→dock随动(y306=331-25,x+40;不重捕获)",
      ancDragMovedPlaced
        && ancDragCaptured.withLock { $0 } == ancDragCapturesBefore
        && dockFrameNear(
            ancDragDock.frame,
            Geometry.appKitRectFromQuartz(
                CGRect(x: ancDockX + 40, y: 331 - 25, width: 200, height: 48)))
        && ancDragMovedPetRects.withLock { $0 } == [
            CGRect(x: ancPet.minX + 40, y: ancPet.minY - 25, width: ancPet.width, height: 139)],
      "frame=\(ancDragDock.frame) pets=\(ancDragMovedPetRects.withLock { $0 }) captures=\(ancDragCaptured.withLock { $0 })")

// ACT 控制按钮出现（现场 194px、contentBottom=38 → 内容底边 abs 423）：内容底基础位 362 的
// dock(362..410) 与 ACT 内容矩形(384..423) 相交 → 在基础位之上正确避让到 425（避让链路
// 不因基础位下移而丢失；基线窗口底锚 388 同样避让到 425）。
csTime = 25_400
let ancActStats: [CGWindowID: BubbleAlphaStats] = [
    CGWindowID(27814): BubbleAlphaStats(nonTransparentPixelCount: 30_000, contentBottom: 362),
    CGWindowID(27900): BubbleAlphaStats(nonTransparentPixelCount: 194, contentBottom: 38),
]
let ancActCap: BubbleCapturer = { c in
    .stats(ancActStats[c.wid]
        ?? BubbleAlphaStats(nonTransparentPixelCount: 0, contentBottom: -1))
}
let ancActProbe = BubbleVisibilityProbe(
    monotonicNow: { csTime }, canCapture: { true }, capturer: ancActCap)
let ancActDock = DockPanel()
let ancActPetRects = OSAllocatedUnfairLock(initialState: [CGRect]())
let ancActCounts = OSAllocatedUnfairLock(initialState: [Int]())
let ancActOK = ancRunTwoTickLayout(
    probe: ancActProbe, dock: ancActDock,
    mascot: csMascot, candidates: [csMascot] + csSurfaces + [csAct],
    petRects: ancActPetRects, obstacleCounts: ancActCounts)
check("T-anc5 收起+ACT按钮(障碍底423)→dock避让425(内容底基础位362之上)",
      ancActOK && dockFrameNear(ancActDock.frame, csAppKitFrame(y: 425))
        && ancActCounts.withLock { $0 } == [1, 2],
      "frame=\(ancActDock.frame) counts=\(ancActCounts.withLock { $0 })")

print("\n[dock 基础位内容底锚定] \(pass - ancPass) passed, \(fail - ancBase) failed")

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

check("P10a 首个petVisible上升沿后的数据刷新延迟5s",
      FollowTickPlanner.initialDataRefreshDelay(hasCompletedFirstRefresh: false) == 5.0,
      "delay=\(FollowTickPlanner.initialDataRefreshDelay(hasCompletedFirstRefresh: false))")
check("P10b 首刷完成后resume恢复立即刷新",
      FollowTickPlanner.initialDataRefreshDelay(hasCompletedFirstRefresh: true) == 0,
      "delay=\(FollowTickPlanner.initialDataRefreshDelay(hasCompletedFirstRefresh: true))")

print("\n[FollowTickPlan] \(pass - plPass) passed, \(fail - plBase) failed")

// ---- T-hj: 宠物识别被隐藏气泡窗口劫持（2026-08-23 现场证据回归） ----
// 现场：宿主收起会话 UI 后保留隐藏气泡窗口（title 仅应用名、384x95、layer=3、与宠物水平精确居中、
// 垂直覆盖宠物下半部且底部低于宠物）。旧滞回只校验 wid 存在，瞬时误选/窗口世代切换后底座被永久
// 锚定到该隐藏窗口（底座 frame = 气泡底部+gap 而非 Mascot 底部+gap）。
let hjBase = fail, hjPass = pass
let hjPetRect = CGRect(x: 100, y: 100, width: 172, height: 179)                  // Mascot 本体 172x179
// 隐藏气泡窗口：384x95、与宠物水平居中（中心差 0）、minY 在 pet 中部（几何上不是障碍），底部低于宠物 45px
let hjBubbleRect = CGRect(x: hjPetRect.midX - 192, y: hjPetRect.maxY - 50, width: 384, height: 95)
let hjMain = mk(804, layer: 0, w: 1728, h: 1050, title: "ChatGPT")
let hjMascot = mkw(802, layer: 2, hjPetRect, title: "Codex Pet Mascot Effect")
let hjHiddenBubble = mkw(801, layer: 3, hjBubbleRect, title: "Codex")            // title 仅应用名

// T-hj1: 滞回锁定隐藏气泡窗口 → 必须不再沿用，回落 title 规则找回真 Mascot
let hj1 = PetTracker.selectPet(candidates: [hjMain, hjMascot, hjHiddenBubble], lastWID: hjHiddenBubble.wid)
check("T-hj1 滞回锁定隐藏气泡(384x95,title=应用名)→找回Mascot",
      hj1.selected?.wid == hjMascot.wid, hj1.selected?.detailed() ?? hj1.reason)

// T-hj2: 滞回锁定 768x912 组合面 → 不再沿用，回落 Mascot
let hj2 = PetTracker.selectPet(candidates: [
    hjMain, hjMascot,
    mkw(803, layer: 3, CGRect(x: 0, y: 0, width: 768, height: 912), title: "Codex Pet Composition Surface")
], lastWID: 803)
check("T-hj2 滞回锁定组合面(768x912)→找回Mascot", hj2.selected?.wid == hjMascot.wid, hj2.reason)

// T-hj3: 滞回锁定 24x6 控件 → 不再沿用，回落 Mascot
let hj3 = PetTracker.selectPet(candidates: [
    hjMain, hjMascot,
    mkw(805, layer: 3, CGRect(x: 150, y: 300, width: 24, height: 6), title: "Codex Pet Voice Controls Backing")
], lastWID: 805)
check("T-hj3 滞回锁定控件(24x6)→找回Mascot", hj3.selected?.wid == hjMascot.wid, hj3.reason)

// T-hj4: 真 Mascot 窗口滞回行为不变（title 含 Mascot 且 isReasonablePet）
let hj4 = PetTracker.selectPet(candidates: [hjMain, hjMascot, hjHiddenBubble], lastWID: hjMascot.wid)
check("T-hj4 滞回沿用真Mascot不变", hj4.selected?.wid == hjMascot.wid
      && hj4.hitFlags.contains { $0.hasPrefix("hysteresis:lastWID=") }, hj4.reason)

// T-hj5: 仅满足 isReasonablePet 的回退选中窗口（title 无 Mascot）滞回行为不变
let hjFallback = mkw(806, layer: 3, CGRect(x: 100, y: 100, width: 120, height: 120), title: "Codex Pet Something")
let hj5 = PetTracker.selectPet(candidates: [hjMain, hjMascot, hjFallback], lastWID: hjFallback.wid)
check("T-hj5 滞回沿用合理回退窗口(isReasonablePet)不变", hj5.selected?.wid == hjFallback.wid, hj5.reason)

// T-hj6: 生产组合 —— selectPet(lastWID=气泡wid) → FollowLayoutPass.placeDock → 实际 DockPanel.placeBelow。
// 劫持态下底座最终 frame 必须回到真 Mascot 正下方基础位，而不是隐藏气泡窗口下方。
let hjDock = DockPanel()
let hjObstacleCounts = OSAllocatedUnfairLock(initialState: [Int]())
let hjProbe = BubbleVisibilityProbe(
    monotonicNow: { 21_000 }, canCapture: { true }, capturer: { _ in .unavailable }
)
let hjSelection = PetTracker.selectPet(candidates: [hjMain, hjMascot, hjHiddenBubble], lastWID: hjHiddenBubble.wid)
check("T-hj6a 生产组合:劫持态selectPet找回Mascot", hjSelection.selected?.wid == hjMascot.wid, hjSelection.reason)
let hjPlaced = FollowLayoutPass.placeDock(
    mascot: hjSelection.selected!,
    candidates: [hjMain, hjMascot, hjHiddenBubble],
    bubbleProbe: hjProbe,
    frameSink: { pet, obstacles in
        hjObstacleCounts.withLock { $0.append(obstacles.count) }
        return hjDock.placeBelow(
            petQuartzRect: pet,
            avoiding: obstacles,
            visibleScreen: nil,
            movementChanged: false,
            monotonicNow: 21_000
        )
    }
)
let hjDockBaseX = hjPetRect.origin.x + (hjPetRect.width - 200) / 2
let hjExpectedFrame = Geometry.appKitRectFromQuartz(
    CGRect(x: hjDockBaseX, y: hjPetRect.maxY + 2, width: 200, height: 48))
check("T-hj6b 劫持态底座实际frame回到真Mascot下方(非气泡下方)",
      hjPlaced && dockFrameNear(hjDock.frame, hjExpectedFrame)
        && hjObstacleCounts.withLock { $0 } == [0],
      "frame=\(hjDock.frame) expected=\(hjExpectedFrame) obstacles=\(hjObstacleCounts.withLock { $0 })")

print("\n[pet-selection hijack] \(pass - hjPass) passed, \(fail - hjBase) failed")

// ============================================================
// 容器宠物通道（08-28-pet-window-adaptation：宿主新窗口结构回退通道）
// ============================================================
let cpPass = pass, cpBase = fail

// 共享 fixture：容器 800x1600 @ (100,100)，捕获 200x400（scale 恰为 4/4，断言精确）。
let cpBounds = CGRect(x: 100, y: 100, width: 800, height: 1600)
let cpStatsA = ContainerAlphaStats(nonTransparentPixelCount: 800, minX: 10, minY: 20, maxX: 29, maxY: 59,
                                   captureWidth: 200, captureHeight: 400)
let cpStatsB = ContainerAlphaStats(nonTransparentPixelCount: 800, minX: 30, minY: 40, maxX: 49, maxY: 79,
                                   captureWidth: 200, captureHeight: 400)
let cpRectA = CGRect(x: 140, y: 180, width: 80, height: 160)
let cpRectB = CGRect(x: 220, y: 260, width: 80, height: 160)
func cpContainer(_ wid: UInt32) -> WinCandidate { mkw(wid, layer: 3, cpBounds) }

// ---- C1 容器签名选择（纯函数，AC1）----
let cpNew = cpContainer(501)
check("T-cp1 新结构容器候选(layer3, 1.28M, onscreen, 非主窗)被接受",
      ContainerPetSelector.selectContainer(candidates: [cpNew])?.wid == 501, "")
check("T-cp2 layer0 主窗口被拒绝",
      ContainerPetSelector.selectContainer(candidates: [
        mkw(502, layer: 0, CGRect(x: 0, y: 0, width: 1728, height: 1050))]) == nil, "")
check("T-cp3 普通尺寸辅助窗(345x64)被拒绝(面积低于minArea)",
      ContainerPetSelector.selectContainer(candidates: [
        mkw(503, layer: 3, CGRect(x: 0, y: 0, width: 345, height: 64))]) == nil, "")
check("T-cp4 offscreen 大窗被拒绝",
      ContainerPetSelector.selectContainer(candidates: [
        mk(504, layer: 3, w: 1000, h: 1200, onscreen: false)]) == nil, "")
check("T-cp5 layer<2 大窗被拒绝",
      ContainerPetSelector.selectContainer(candidates: [
        mkw(505, layer: 1, CGRect(x: 0, y: 0, width: 1000, height: 1200))]) == nil, "")
let cpMascot = mk(506, layer: 2, w: 172, h: 179, title: "Codex Pet Mascot Effect")
check("T-cp6 混合候选(主窗+Mascot+容器)→选容器",
      ContainerPetSelector.selectContainer(candidates: [
        mkw(507, layer: 0, CGRect(x: 0, y: 0, width: 1728, height: 1050)), cpMascot, cpNew])?.wid == 501, "")
let cpOldCS = mkw(508, layer: 3, CGRect(x: 0, y: 0, width: 768, height: 912), title: "Codex Pet Composition Surface")
check("T-cp7 旧结构CS(768x912<minArea)+小辅助→nil(R6 不干扰主通道)",
      ContainerPetSelector.selectContainer(candidates: [
        mkw(509, layer: 0, CGRect(x: 0, y: 0, width: 1728, height: 1050)), cpMascot, cpOldCS,
        mkw(510, layer: 3, CGRect(x: 0, y: 0, width: 17, height: 6))]) == nil, "")
let cpSmallContainer = mkw(511, layer: 2, CGRect(x: 0, y: 0, width: 1000, height: 1100))
check("T-cp8 多容器命中→面积最大者",
      ContainerPetSelector.selectContainer(candidates: [cpSmallContainer, cpNew])?.wid == 501, "")
let cpTieB = mkw(513, layer: 2, CGRect(x: 50, y: 50, width: 1000, height: 1000))
let cpTieA = mkw(512, layer: 2, CGRect(x: 0, y: 0, width: 1000, height: 1000))
check("T-cp9 面积并列→wid 较小者(确定性)",
      ContainerPetSelector.selectContainer(candidates: [cpTieB, cpTieA])?.wid == 512, "")

// ---- C2 captureSize（等比降采样）----
let cpSize1 = ContainerPetChannel.captureSize(width: 800, height: 1600)
check("T-cp10 captureSize 等比降采样至长边400",
      cpSize1?.width == 200 && cpSize1?.height == 400, "actual=\(String(describing: cpSize1))")
check("T-cp11 captureSize 长边≤400→nil(无需降采样)",
      ContainerPetChannel.captureSize(width: 200, height: 400) == nil
        && ContainerPetChannel.captureSize(width: 100, height: 200) == nil, "")
let cpSize2 = ContainerPetChannel.captureSize(width: 1600, height: 3)
check("T-cp12 captureSize 极端纵横比→边长至少1px",
      cpSize2?.width == 400 && cpSize2?.height == 1, "actual=\(String(describing: cpSize2))")

// ---- C3 mapToPetRect（AC2：黄金案例 + 门限/退化）----
// 黄金案例输入取自 design.md（121x400 捕获，bbox (54,194)-(61,209)，容器 772x2549 @(1482,-267)）。
// 期望值按 design 规范以 CGWindowList bounds 为唯一 origin/size 权威源计算；design 中的字面
// 黄金输出 (1776,918,51,101) 混入了探测期 SCWindow.frame 与 CG bounds 的 ~50px 偏差（PRD
// 已知风险），权威映射下尺寸一致、origin 相应修正。
let cpGoldenStats = ContainerAlphaStats(nonTransparentPixelCount: 128, minX: 54, minY: 194, maxX: 61, maxY: 209,
                                        captureWidth: 121, captureHeight: 400)
let cpGoldenBounds = CGRect(x: 1482, y: -267, width: 772, height: 2549)
if let cpGolden = ContainerPetChannel.mapToPetRect(stats: cpGoldenStats, captureWidth: 121, captureHeight: 400,
                                                   containerBounds: cpGoldenBounds) {
    let cpGoldenX = 1482.0 + 54.0 * 772.0 / 121.0
    let cpGoldenY = -267.0 + 194.0 * 2549.0 / 400.0
    let cpGoldenW = 8.0 * 772.0 / 121.0
    let cpGoldenH = 16.0 * 2549.0 / 400.0
    check("T-cp13 黄金案例映射(CG bounds 权威源)",
          abs(cpGolden.minX - cpGoldenX) < 0.01 && abs(cpGolden.minY - cpGoldenY) < 0.01
            && abs(cpGolden.width - cpGoldenW) < 0.01 && abs(cpGolden.height - cpGoldenH) < 0.01,
          "actual=\(cpGolden)")
} else {
    check("T-cp13 黄金案例映射(CG bounds 权威源)", false, "mapToPetRect 返回 nil")
}
let cpDense = ContainerAlphaStats(nonTransparentPixelCount: 4840, minX: 0, minY: 0, maxX: 120, maxY: 399,
                                  captureWidth: 121, captureHeight: 400)
check("T-cp14 非透明占比超 gate→nil(防劫持)",
      ContainerPetChannel.mapToPetRect(stats: cpDense, captureWidth: 121, captureHeight: 400,
                                       containerBounds: cpGoldenBounds) == nil, "")
let cpNoOpaque = ContainerAlphaStats(nonTransparentPixelCount: 0, minX: -1, minY: -1, maxX: -1, maxY: -1,
                                     captureWidth: 121, captureHeight: 400)
check("T-cp15 无非透明像素→nil",
      ContainerPetChannel.mapToPetRect(stats: cpNoOpaque, captureWidth: 121, captureHeight: 400,
                                       containerBounds: cpGoldenBounds) == nil, "")
let cpSparseWide = ContainerAlphaStats(nonTransparentPixelCount: 484, minX: 0, minY: 0, maxX: 120, maxY: 399,
                                       captureWidth: 121, captureHeight: 400)
check("T-cp16 占比恰在 gate(=0.01) 但映射边长超上限→nil",
      ContainerPetChannel.mapToPetRect(stats: cpSparseWide, captureWidth: 121, captureHeight: 400,
                                       containerBounds: cpGoldenBounds) == nil, "")
let cpPixel = ContainerAlphaStats(nonTransparentPixelCount: 1, minX: 60, minY: 200, maxX: 60, maxY: 200,
                                  captureWidth: 121, captureHeight: 400)
check("T-cp17 单像素 bbox→映射边长<petMinSide→nil(取整退化)",
      ContainerPetChannel.mapToPetRect(stats: cpPixel, captureWidth: 121, captureHeight: 400,
                                       containerBounds: cpGoldenBounds) == nil, "")
check("T-cp18 捕获尺寸非法→nil",
      ContainerPetChannel.mapToPetRect(stats: cpStatsA, captureWidth: 0, captureHeight: 400,
                                       containerBounds: cpBounds) == nil, "")

// ---- C4 ContainerPetProbe（fake capturer + fake clock：首观察/节奏/单飞/代际/unavailable/wake）----
do {
    let clock = OSAllocatedUnfairLock(initialState: TimeInterval(10_000))
    let calls = OSAllocatedUnfairLock(initialState: 0)
    let wakes = OSAllocatedUnfairLock(initialState: 0)
    let outcomeBox = OSAllocatedUnfairLock<ContainerCaptureOutcome>(initialState: .stats(cpStatsA))
    let probe = ContainerPetProbe(
        monotonicNow: { clock.withLock { $0 } },
        canCapture: { true },
        capturer: { _, _ in
            calls.withLock { $0 += 1 }
            return outcomeBox.withLock { $0 }
        },
        onFirstObservation: { wakes.withLock { $0 += 1 } })
    let container = cpContainer(520)
    check("T-cp20 首次locate→empty(尚未观察)", probe.locate(container: container) == .empty, "")
    check("T-cp20b 首次locate→调度后台捕获(inFlight)", probe.lock.withLock { $0.inFlight }, "")
    _ = waitPumpingMain({ !probe.lock.withLock { $0.inFlight } })
    check("T-cp21 首次捕获完成→bounds(当前containerBounds映射)",
          probe.locate(container: container) == .bounds(cpRectA), "")
    check("T-cp22 首个有效观察触发 onFirstObservation 恰一次",
          wakes.withLock { $0 } == 1, "wakes=\(wakes.withLock { $0 })")
    clock.withLock { $0 = 10_000.5 }
    _ = probe.locate(container: container)
    check("T-cp23 stable 0.5s→不捕获", calls.withLock { $0 } == 1, "calls=\(calls.withLock { $0 })")
    clock.withLock { $0 = 10_001 }
    _ = probe.locate(container: container)
    _ = waitPumpingMain({ !probe.lock.withLock { $0.inFlight } })
    check("T-cp24 stable 1.0s→捕获(1Hz 心跳)", calls.withLock { $0 } == 2, "calls=\(calls.withLock { $0 })")
    check("T-cp24b 同 bbox 再观察→不重复 wake", wakes.withLock { $0 } == 1, "wakes=\(wakes.withLock { $0 })")

    // bbox 变化 → 0.1s 快速节奏保持 movingHoldDuration，随后回到 stable 1s。
    clock.withLock { $0 = 10_002 }
    outcomeBox.withLock { $0 = .stats(cpStatsB) }
    _ = probe.locate(container: container)
    _ = waitPumpingMain({ !probe.lock.withLock { $0.inFlight } })
    check("T-cp25 bbox变化→新观察生效", probe.locate(container: container) == .bounds(cpRectB),
          "calls=\(calls.withLock { $0 })")
    clock.withLock { $0 = 10_002.05 }
    _ = probe.locate(container: container)
    check("T-cp26 快速节奏 0.05s→不捕获", calls.withLock { $0 } == 3, "calls=\(calls.withLock { $0 })")
    clock.withLock { $0 = 10_002.1 }
    _ = probe.locate(container: container)
    _ = waitPumpingMain({ !probe.lock.withLock { $0.inFlight } })
    check("T-cp27 快速节奏 0.1s→捕获", calls.withLock { $0 } == 4, "calls=\(calls.withLock { $0 })")
    check("T-cp28 快速节奏期间无 bbox 变化→不重复 wake", wakes.withLock { $0 } == 1, "wakes=\(wakes.withLock { $0 })")
    clock.withLock { $0 = 10_002.2 }
    _ = probe.locate(container: container)
    _ = waitPumpingMain({ !probe.lock.withLock { $0.inFlight } })
    check("T-cp29 保持期内 0.2s→第5捕(0.1s cadence)", calls.withLock { $0 } == 5, "calls=\(calls.withLock { $0 })")
    clock.withLock { $0 = 10_003.0 }
    _ = probe.locate(container: container)
    _ = waitPumpingMain({ !probe.lock.withLock { $0.inFlight } })
    check("T-cp30 保持期内 10_003 仍按 0.1s→第6捕", calls.withLock { $0 } == 6, "calls=\(calls.withLock { $0 })")
    clock.withLock { $0 = 10_003.5 }
    _ = probe.locate(container: container)
    _ = waitPumpingMain({ !probe.lock.withLock { $0.inFlight } })
    check("T-cp31 保持期内 10_003.5→第7捕", calls.withLock { $0 } == 7, "calls=\(calls.withLock { $0 })")
    clock.withLock { $0 = 10_004.0 }
    _ = probe.locate(container: container)
    check("T-cp32 保持期结束(10_004)→回到 stable，0.5s 不捕获",
          calls.withLock { $0 } == 7, "calls=\(calls.withLock { $0 })")
    clock.withLock { $0 = 10_004.5 }
    _ = probe.locate(container: container)
    _ = waitPumpingMain({ !probe.lock.withLock { $0.inFlight } })
    check("T-cp33 保持期结束 1.0s→捕获(stable 恢复)", calls.withLock { $0 } == 8, "calls=\(calls.withLock { $0 })")
}

// single-flight：在途捕获不重复
do {
    let clock = OSAllocatedUnfairLock(initialState: TimeInterval(20_000))
    let calls = OSAllocatedUnfairLock(initialState: 0)
    let slowCap: ContainerCapturer = { _, _ in
        calls.withLock { $0 += 1 }
        try? await Task.sleep(nanoseconds: 300_000_000)
        return .stats(cpStatsA)
    }
    let probe = ContainerPetProbe(monotonicNow: { clock.withLock { $0 } }, canCapture: { true }, capturer: slowCap)
    let container = cpContainer(521)
    _ = probe.locate(container: container)
    check("T-cp34 首次locate→inFlight", probe.lock.withLock { $0.inFlight }, "")
    _ = waitPumpingMain({ calls.withLock { $0 } >= 1 })   // 等待后台 Task 真正进入 capturer
    clock.withLock { $0 = 20_000.5 }
    _ = probe.locate(container: container)
    check("T-cp35 在途重复locate→不重复捕获(single-flight)",
          calls.withLock { $0 } == 1 && probe.lock.withLock { $0.inFlight },
          "calls=\(calls.withLock { $0 })")
    _ = waitPumpingMain({ !probe.lock.withLock { $0.inFlight } })
    check("T-cp36 完成后→bounds", probe.locate(container: container) == .bounds(cpRectA), "")
}

// reset：清缓存 + generation++，旧在途结果作废（旧 Task 自清 inFlight）
do {
    let clock = OSAllocatedUnfairLock(initialState: TimeInterval(30_000))
    let calls = OSAllocatedUnfairLock(initialState: 0)
    let slowCap: ContainerCapturer = { _, _ in
        calls.withLock { $0 += 1 }
        try? await Task.sleep(nanoseconds: 300_000_000)
        return .stats(cpStatsA)
    }
    let probe = ContainerPetProbe(monotonicNow: { clock.withLock { $0 } }, canCapture: { true }, capturer: slowCap)
    let container = cpContainer(522)
    _ = probe.locate(container: container)
    _ = waitPumpingMain({ calls.withLock { $0 } >= 1 })   // 等待后台 Task 真正进入 capturer
    check("T-cp37 前置:捕获在途", probe.lock.withLock { $0.inFlight }, "")
    probe.reset()
    check("T-cp38 reset不清inFlight(旧Task自责)", probe.lock.withLock { $0.inFlight }, "")
    clock.withLock { $0 = 30_100 }
    check("T-cp39 reset后locate→empty且不重复捕获",
          probe.locate(container: container) == .empty
            && calls.withLock { $0 } == 1 && probe.lock.withLock { $0.inFlight },
          "calls=\(calls.withLock { $0 })")
    _ = waitPumpingMain({ !probe.lock.withLock { $0.inFlight } })
    check("T-cp40 旧Task完成→inFlight=false", !probe.lock.withLock { $0.inFlight }, "")
    check("T-cp41 旧结果generation过期→不写缓存", probe.lock.withLock { $0.cached == nil }, "")
    clock.withLock { $0 = 30_200 }
    check("T-cp42 新locate→empty并调度", probe.locate(container: container) == .empty, "")
    _ = waitPumpingMain({ !probe.lock.withLock { $0.inFlight } })
    check("T-cp43 新捕获生效→bounds", probe.locate(container: container) == .bounds(cpRectA), "")
}

// wid 变化：同步清缓存 + 旧在途结果不串台
do {
    let clock = OSAllocatedUnfairLock(initialState: TimeInterval(40_000))
    let calls = OSAllocatedUnfairLock(initialState: 0)
    let slowCap: ContainerCapturer = { _, _ in
        calls.withLock { $0 += 1 }
        try? await Task.sleep(nanoseconds: 300_000_000)
        return .stats(cpStatsA)
    }
    let probe = ContainerPetProbe(monotonicNow: { clock.withLock { $0 } }, canCapture: { true }, capturer: slowCap)
    let containerA = cpContainer(523)
    let containerB = cpContainer(524)
    _ = probe.locate(container: containerA)
    _ = waitPumpingMain({ calls.withLock { $0 } >= 1 })   // 等待后台 Task 真正进入 capturer
    check("T-cp44 前置:A在途", probe.lock.withLock { $0.inFlight }, "")
    check("T-cp45 wid变化→locate同步empty", probe.locate(container: containerB) == .empty, "")
    check("T-cp45b wid变化不重复捕获(在途token)", calls.withLock { $0 } == 1, "calls=\(calls.withLock { $0 })")
    _ = waitPumpingMain({ !probe.lock.withLock { $0.inFlight } })
    check("T-cp46 A的旧结果不写B的缓存(wid/generation失效)", probe.lock.withLock { $0.cached == nil }, "")
    clock.withLock { $0 = 40_100 }
    _ = probe.locate(container: containerB)
    _ = waitPumpingMain({ !probe.lock.withLock { $0.inFlight } })
    check("T-cp47 B重新捕获→bounds", probe.locate(container: containerB) == .bounds(cpRectA), "")
}

// wid 变化（已有缓存时同步失效）
do {
    let clock = OSAllocatedUnfairLock(initialState: TimeInterval(45_000))
    let probe = ContainerPetProbe(monotonicNow: { clock.withLock { $0 } }, canCapture: { true },
                                  capturer: { _, _ in .stats(cpStatsA) })
    let containerA = cpContainer(525)
    let containerB = cpContainer(526)
    _ = probe.locate(container: containerA)
    _ = waitPumpingMain({ !probe.lock.withLock { $0.inFlight } })
    check("T-cp48 前置:A已观察", probe.locate(container: containerA) == .bounds(cpRectA), "")
    check("T-cp49 wid变化→已有缓存同步失效(empty)", probe.locate(container: containerB) == .empty, "")
    clock.withLock { $0 = 45_100 }
    check("T-cp50 前置:locate(B)调度新捕获", probe.locate(container: containerB) == .empty, "")
    _ = waitPumpingMain({ !probe.lock.withLock { $0.inFlight } })
    check("T-cp50b B重新捕获→恢复bounds", probe.locate(container: containerB) == .bounds(cpRectA), "")
}

// canCapture false → unavailable 且丢弃陈旧缓存
do {
    let allow = OSAllocatedUnfairLock(initialState: true)
    let clock = OSAllocatedUnfairLock(initialState: TimeInterval(50_000))
    let calls = OSAllocatedUnfairLock(initialState: 0)
    let probe = ContainerPetProbe(
        monotonicNow: { clock.withLock { $0 } },
        canCapture: { allow.withLock { $0 } },
        capturer: { _, _ in
            calls.withLock { $0 += 1 }
            return .stats(cpStatsA)
        })
    let container = cpContainer(527)
    _ = probe.locate(container: container)
    _ = waitPumpingMain({ !probe.lock.withLock { $0.inFlight } })
    check("T-cp51 前置:已观察→bounds", probe.locate(container: container) == .bounds(cpRectA), "")
    allow.withLock { $0 = false }
    check("T-cp52 canCapture false→unavailable", probe.locate(container: container) == .unavailable, "")
    check("T-cp53 unavailable→不调度捕获", calls.withLock { $0 } == 1, "calls=\(calls.withLock { $0 })")
    allow.withLock { $0 = true }
    clock.withLock { $0 = 50_100 }
    check("T-cp54 陈旧缓存已丢弃→重新从empty开始", probe.locate(container: container) == .empty, "")
    _ = waitPumpingMain({ !probe.lock.withLock { $0.inFlight } })
    check("T-cp55 重新观察→bounds", probe.locate(container: container) == .bounds(cpRectA), "")
}

// onFirstObservation 每个 disappearance episode 恰一次（reset / wid 变化开启新 episode）
do {
    let clock = OSAllocatedUnfairLock(initialState: TimeInterval(60_000))
    let wakes = OSAllocatedUnfairLock(initialState: 0)
    let probe = ContainerPetProbe(
        monotonicNow: { clock.withLock { $0 } },
        canCapture: { true },
        capturer: { _, _ in .stats(cpStatsA) },
        onFirstObservation: { wakes.withLock { $0 += 1 } })
    let containerA = cpContainer(528)
    let containerB = cpContainer(529)
    _ = probe.locate(container: containerA)
    _ = waitPumpingMain({ !probe.lock.withLock { $0.inFlight } })
    check("T-cp56 首次观察→wake 1次", wakes.withLock { $0 } == 1, "wakes=\(wakes.withLock { $0 })")
    clock.withLock { $0 = 60_100 }
    _ = probe.locate(container: containerA)
    _ = waitPumpingMain({ !probe.lock.withLock { $0.inFlight } })
    check("T-cp57 后续观察不重复wake", wakes.withLock { $0 } == 1, "wakes=\(wakes.withLock { $0 })")
    probe.reset()
    clock.withLock { $0 = 60_200 }
    _ = probe.locate(container: containerA)
    _ = waitPumpingMain({ !probe.lock.withLock { $0.inFlight } })
    check("T-cp58 reset后新episode→再wake 1次", wakes.withLock { $0 } == 2, "wakes=\(wakes.withLock { $0 })")
    clock.withLock { $0 = 60_300 }
    _ = probe.locate(container: containerB)
    _ = waitPumpingMain({ !probe.lock.withLock { $0.inFlight } })
    check("T-cp59 wid变化新episode→再wake 1次", wakes.withLock { $0 } == 3, "wakes=\(wakes.withLock { $0 })")
}

// ---- C5 tick 编排（plan 级：AppDelegate.tick 未编入测试入口；hidden→moving→hidden + reset）----
do {
    let clock = OSAllocatedUnfairLock(initialState: TimeInterval(70_000))
    let probe = ContainerPetProbe(monotonicNow: { clock.withLock { $0 } }, canCapture: { true },
                                  capturer: { _, _ in .stats(cpStatsA) })
    let container = cpContainer(530)
    var wasPetVisible = false
    var stationaryAnchor: CGRect?
    var lastMaterialChangeAt: TimeInterval?
    // tick1：主通道无 Mascot + 容器未观察 → 无 petRect → hidden（生产此分支执行 containerProbe.reset()）
    var d = Follower.decide(pet: nil, stationaryAnchor: stationaryAnchor,
                            lastMaterialChangeAt: lastMaterialChangeAt, now: 70_000)
    var plan = FollowTickPlanner.decide(input: FollowTickInput(
        petVisible: d.showDock, wasPetVisible: wasPetVisible, dockVisible: true))
    check("T-cp60 tick1 无观察→hidden+petDisappeared",
          d.state == .hidden && plan.petDisappeared && plan.hideUI && !plan.showUI, "")
    probe.reset()
    wasPetVisible = d.showDock
    // tick2：容器观察落 cache → 合成 rect → moving + showUI + resumeData（计划输出不变）
    clock.withLock { $0 = 70_001 }
    _ = probe.locate(container: container)
    _ = waitPumpingMain({ !probe.lock.withLock { $0.inFlight } })
    if case .bounds(let rect) = probe.locate(container: container) {
        check("T-cp61 容器观察→合成rect几何正确", rect == cpRectA, "rect=\(rect)")
        d = Follower.decide(pet: rect, stationaryAnchor: stationaryAnchor,
                            lastMaterialChangeAt: lastMaterialChangeAt, now: 70_001)
        plan = FollowTickPlanner.decide(input: FollowTickInput(
            petVisible: d.showDock, wasPetVisible: wasPetVisible, dockVisible: true))
        check("T-cp62 容器观察→hidden→moving+showUI+resumeData",
              d.state == .moving && d.showDock && plan.showUI && plan.resumeData && !plan.petDisappeared,
              "state=\(d.state.rawValue) plan=\(plan)")
        stationaryAnchor = d.stationaryAnchor
        lastMaterialChangeAt = d.lastMaterialChangeAt
        wasPetVisible = d.showDock
    } else {
        check("T-cp61 容器观察→合成rect几何正确", false, "locate 未产出 bounds")
    }
    // tick3：容器消失（不在候选集）→ 无 petRect → hidden + pauseData + petDisappeared（生产执行 reset()）
    d = Follower.decide(pet: nil, stationaryAnchor: stationaryAnchor,
                        lastMaterialChangeAt: lastMaterialChangeAt, now: 70_002)
    plan = FollowTickPlanner.decide(input: FollowTickInput(
        petVisible: d.showDock, wasPetVisible: wasPetVisible, dockVisible: true))
    check("T-cp63 容器消失→hidden+pauseData+petDisappeared",
          d.state == .hidden && plan.pauseData && plan.petDisappeared && plan.hideUI, "")
    probe.reset()
check("T-cp64 消失路径 reset→缓存清空(下一episode重新捕获)", probe.lock.withLock { $0.cached == nil }, "")
}

// ---- C4b 保守保留语义（真实完成链）：targetMissing / unavailable / 超门限 stats 均不
// 擦除既有有效观察（stale 失败必须保守处理，SC/CG 清单竞态不产生错误空窗）。
do {
    let clock = OSAllocatedUnfairLock(initialState: TimeInterval(80_000))
    let outcomeBox = OSAllocatedUnfairLock<ContainerCaptureOutcome>(initialState: .stats(cpStatsA))
    let probe = ContainerPetProbe(
        monotonicNow: { clock.withLock { $0 } },
        canCapture: { true },
        capturer: { _, _ in outcomeBox.withLock { $0 } })
    let container = cpContainer(531)
    // 前置：首捕有效观察
    _ = probe.locate(container: container)
    _ = waitPumpingMain({ !probe.lock.withLock { $0.inFlight } })
    check("T-cp65 前置:首捕→bounds", probe.locate(container: container) == .bounds(cpRectA), "")
    // (a) targetMissing（SCK 清单缺 WID）→ 保留既有观察
    outcomeBox.withLock { $0 = .targetMissing }
    clock.withLock { $0 = 80_001 }
    _ = probe.locate(container: container)
    _ = waitPumpingMain({ !probe.lock.withLock { $0.inFlight } })
    check("T-cp66 targetMissing→保留既有有效观察",
          probe.locate(container: container) == .bounds(cpRectA), "")
    // (b) unavailable（捕获失败，非权限缺失）→ 保留既有观察
    outcomeBox.withLock { $0 = .unavailable }
    clock.withLock { $0 = 80_002 }
    _ = probe.locate(container: container)
    _ = waitPumpingMain({ !probe.lock.withLock { $0.inFlight } })
    check("T-cp67 unavailable→保留既有有效观察",
          probe.locate(container: container) == .bounds(cpRectA), "")
    // (c) 超门限 stats（fraction > gate）→ 不接纳新观察 + 保留既有观察
    let cpDenseStats = ContainerAlphaStats(nonTransparentPixelCount: 4840, minX: 10, minY: 20,
                                           maxX: 29, maxY: 59, captureWidth: 200, captureHeight: 400)
    outcomeBox.withLock { $0 = .stats(cpDenseStats) }
    clock.withLock { $0 = 80_003 }
    _ = probe.locate(container: container)
    _ = waitPumpingMain({ !probe.lock.withLock { $0.inFlight } })
    check("T-cp68 超门限stats→不接纳+保留既有观察",
          probe.locate(container: container) == .bounds(cpRectA)
            && probe.lock.withLock { $0.cached?.nonTransparentPixelCount == cpStatsA.nonTransparentPixelCount },
          "")
    // 恢复：新的有效观察重新生效（bbox 变化 → 快速节奏窗口）
    outcomeBox.withLock { $0 = .stats(cpStatsB) }
    clock.withLock { $0 = 80_004 }
    _ = probe.locate(container: container)
    _ = waitPumpingMain({ !probe.lock.withLock { $0.inFlight } })
check("T-cp69 新有效观察→bounds更新",
      probe.locate(container: container) == .bounds(cpRectB), "")
}

// ---- C6 QA P0 修复回归：hidden tick 的容器 reset 门控（候选在场不得饿死在途捕获）----
// 纯 helper：在场 → false（不 reset）；缺席 → true（真正容器消失路径才 reset）。
check("T-cp70 候选在场→containerProbeReset=false",
      FollowTickPlanner.containerProbeReset(containerCandidatePresent: true) == false, "")
check("T-cp71 候选缺席→containerProbeReset=true",
      FollowTickPlanner.containerProbeReset(containerCandidatePresent: false) == true, "")

// 组合回归：首 locate 在途/empty 的 hidden tick 不 reset → 捕获完成后观察可落地；
// 对照：候选缺席路径 reset 会真正失效缓存。
do {
    let clock = OSAllocatedUnfairLock(initialState: TimeInterval(90_000))
    let wakes = OSAllocatedUnfairLock(initialState: 0)
    let slowCap: ContainerCapturer = { _, _ in
        try? await Task.sleep(nanoseconds: 300_000_000)
        return .stats(cpStatsA)
    }
    let probe = ContainerPetProbe(
        monotonicNow: { clock.withLock { $0 } },
        canCapture: { true },
        capturer: slowCap,
        onFirstObservation: { wakes.withLock { $0 += 1 } })
    let container = cpContainer(532)
    _ = probe.locate(container: container)
    check("T-cp72 前置:首捕在途→locate empty",
          probe.lock.withLock { $0.inFlight } && probe.locate(container: container) == .empty, "")
    // 生产消失分支（修复后接线）：候选在场 → helper false → 不调用 reset。
    if FollowTickPlanner.containerProbeReset(containerCandidatePresent: true) {
        probe.reset()
    }
    _ = waitPumpingMain({ !probe.lock.withLock { $0.inFlight } })
    check("T-cp73 候选在场+hidden tick 不 reset→在途捕获落地为观察",
          probe.locate(container: container) == .bounds(cpRectA), "")
    check("T-cp74 首观察 wake 恰一次", wakes.withLock { $0 } == 1, "wakes=\(wakes.withLock { $0 })")
    // 对照（候选缺席 → helper true → reset）：缓存真正失效，等待重现重捕。
    if FollowTickPlanner.containerProbeReset(containerCandidatePresent: false) {
        probe.reset()
    }
    clock.withLock { $0 = 90_100 }
    check("T-cp75 候选缺席 reset→缓存失效(empty)",
          probe.locate(container: container) == .empty && probe.lock.withLock { $0.cached == nil }, "")
}

print("\n[container pet channel] \(pass - cpPass) passed, \(fail - cpBase) failed")

print("\n=== 总计 \(pass) passed, \(fail) failed ===")
exit(fail == 0 ? 0 : 1)
