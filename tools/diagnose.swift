// diagnose.swift — Codex 宠物窗口枚举诊断工具（纯公开 API）
// 用途：枚举 bundle id com.openai.codex 主进程名下窗口的脱敏结构特征，
//       输出候选数量、层级与可见性，供人工提炼"宠物窗口"识别规则。
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
    print("主进程数量: 1")
    print("屏幕数量: \(NSScreen.screens.count)")
    print("\n=== 该应用名下的脱敏窗口特征 ===")
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
    let layer: Int
    let alpha: Double
    let isOnscreen: Bool
    let sharingState: Int
    let storeType: Int
    let sizeClass: String
}

var wins: [WinInfo] = []
for w in infos {
    let op = num(w, kCGWindowOwnerPID as String)?.int32Value ?? -1
    guard op == pid else { continue }
    let rect = readRect(w)
    let maxSide = max(rect.width, rect.height)
    let sizeClass = maxSide <= 64 ? "tiny" : (maxSide <= 320 ? "small" : (maxSide <= 800 ? "medium" : "large"))
    wins.append(WinInfo(
        layer: num(w, kCGWindowLayer as String)?.intValue ?? 0,
        alpha: num(w, kCGWindowAlpha as String)?.doubleValue ?? 1.0,
        isOnscreen: (w[kCGWindowIsOnscreen as String] as? Bool) ?? false,
        sharingState: num(w, kCGWindowSharingState as String)?.intValue ?? 0,
        storeType: num(w, kCGWindowStoreType as String)?.intValue ?? 0,
        sizeClass: sizeClass
    ))
}

func short(_ r: CGRect) -> String {
    return String(format: "(%.0f,%.0f %.gx%.g)", r.origin.x, r.origin.y, r.width, r.height)
}

if jsonMode {
    var arr: [[String: Any]] = []
    for x in wins {
        arr.append([
            "layer": x.layer, "alpha": x.alpha, "onscreen": x.isOnscreen,
            "sharing": x.sharingState, "store": x.storeType, "sizeClass": x.sizeClass
        ])
    }
    let data = (try? JSONSerialization.data(withJSONObject: ["windowCount": wins.count, "windows": arr], options: [.prettyPrinted])) ?? Data()
    print(String(data: data, encoding: .utf8) ?? "{}")
} else {
    for (i, x) in wins.enumerated() {
        print("[\(i + 1)] sizeClass=\(x.sizeClass) layer=\(x.layer) alpha=\(x.alpha) onscreen=\(x.isOnscreen) sharing=\(x.sharingState) store=\(x.storeType)")
    }
    print("\n共 \(wins.count) 个窗口。")
}
