// diagnose.swift — Codex 宠物窗口枚举诊断工具（纯公开 API）
// 用途：枚举 bundle id com.openai.codex 主进程名下所有窗口及其属性，
//       输出每个窗口的可观测特征，供人工提炼"宠物窗口"识别规则。
// 运行：swift diagnose.swift            （可读文本）
//       swift diagnose.swift --json     （机器可读，便于测试）
// 说明：只读取窗口元数据，不修改 Codex，不触碰任何认证文件。

import Cocoa

let bundleID = "com.openai.codex"
let jsonMode = CommandLine.arguments.contains("--json")

// --- 工具：CFNumber 安全读取 ---
func num(_ w: [String: Any], _ key: String) -> NSNumber? {
    return w[key] as? NSNumber
}

// --- 1. 通过 bundle id 定位主应用进程 ---
let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
guard let app = apps.first, app.processIdentifier != 0 else {
    let msg = "未找到运行中的应用：bundle id = \(bundleID)"
    if jsonMode { print("{\"error\":\"\(msg)\"}") } else { print(msg) }
    exit(1)
}
let pid = app.processIdentifier

if !jsonMode {
    print("=== 进程定位 ===")
    print("bundle id : \(bundleID)")
    print("name      : \(app.localizedName ?? "?")")
    print("pid       : \(pid)")
    print("bundleURL : \(app.bundleURL?.path ?? "?")")
    print("\n=== 屏幕（NSScreen，AppKit 左下原点）===")
    for (i, s) in NSScreen.screens.enumerated() {
        print("[screen \(i)] frame=\(s.frame) visibleFrame=\(s.visibleFrame)")
    }
    print("\n=== 该 PID 名下的窗口（CGWindowList，Quartz 左上原点）===")
}

// --- 2. 枚举窗口 ---
let options: CGWindowListOption = []  // kCGWindowListOptionAll(0) + kCGNullWindowID = 枚举所有窗口
guard let infos = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
    if jsonMode { print("{\"error\":\"CGWindowListCopyWindowInfo 失败\"}") }
    exit(1)
}

// --- 3. 解析 ---
func readRect(_ w: [String: Any]) -> CGRect {
    guard let bd = w[kCGWindowBounds as String] as? [String: Any] else { return .zero }
    func v(_ k: String) -> CGFloat {
        if let n = bd[k] as? NSNumber { return CGFloat(n.doubleValue) }
        return 0
    }
    return CGRect(x: v("X"), y: v("Y"), width: v("Width"), height: v("Height"))
}

struct WinInfo {
    let wid: CGWindowID
    let title: String
    let ownerName: String
    let layer: Int
    let alpha: Double
    let isOnscreen: Bool
    let sharingState: Int
    let storeType: Int
    let quartzBounds: CGRect
}

var wins: [WinInfo] = []
for w in infos {
    let op = num(w, kCGWindowOwnerPID as String)?.int32Value ?? -1
    guard op == pid else { continue }
    wins.append(WinInfo(
        wid: CGWindowID(num(w, kCGWindowNumber as String)?.uint32Value ?? 0),
        title: (w[kCGWindowName as String] as? String) ?? "",
        ownerName: (w[kCGWindowOwnerName as String] as? String) ?? "",
        layer: num(w, kCGWindowLayer as String)?.intValue ?? 0,
        alpha: num(w, kCGWindowAlpha as String)?.doubleValue ?? 1.0,
        isOnscreen: (w[kCGWindowIsOnscreen as String] as? Bool) ?? false,
        sharingState: num(w, kCGWindowSharingState as String)?.intValue ?? 0,
        storeType: num(w, kCGWindowStoreType as String)?.intValue ?? 0,
        quartzBounds: readRect(w)
    ))
}

func short(_ r: CGRect) -> String {
    return String(format: "(%.0f,%.0f %.gx%.g)", r.origin.x, r.origin.y, r.width, r.height)
}

if jsonMode {
    var arr: [[String: Any]] = []
    for x in wins {
        arr.append([
            "wid": x.wid, "title": x.title, "owner": x.ownerName,
            "layer": x.layer, "alpha": x.alpha, "onscreen": x.isOnscreen,
            "sharing": x.sharingState, "store": x.storeType,
            "bounds": ["x": x.quartzBounds.origin.x, "y": x.quartzBounds.origin.y,
                       "w": x.quartzBounds.width, "h": x.quartzBounds.height]
        ])
    }
    let data = (try? JSONSerialization.data(withJSONObject: ["pid": pid, "windows": arr], options: [.prettyPrinted])) ?? Data()
    print(String(data: data, encoding: .utf8) ?? "{}")
} else {
    for (i, x) in wins.enumerated() {
        print("[\(i + 1)] wid=\(x.wid)")
        print("    title      = \"\(x.title)\"")
        print("    owner      = \(x.ownerName)")
        print("    layer      = \(x.layer)        (0=普通桌面层; >0 浮于桌面之上)")
        print("    alpha      = \(x.alpha)")
        print("    onscreen   = \(x.isOnscreen)")
        print("    sharing    = \(x.sharingState) (0=不可捕捉;1=只读;2=共享)")
        print("    store      = \(x.storeType)")
        print("    bounds(Q)  = \(short(x.quartzBounds))   (Quartz 左上原点)")
    }
    print("\n共 \(wins.count) 个窗口。")
}
