import Cocoa

// MARK: - 诊断模式（--diagnose）：跑一次识别，打印 + 写文件后退出

func runDiagnoseAndExit() -> Never {
    var out = ""
    let pids = PetTracker.codexPIDs()
    out += "=== 进程定位 ===\n"
    out += "bundle id : \(PetTracker.bundleID)\n"
    out += "主进程 PID: \(pids)\n"
    out += "屏幕录制权限(preflight): \(CGPreflightScreenCaptureAccess())  (false→CGWindowList 被系统过滤为空)\n\n"

    let byPID = PetTracker.enumerate(pids: pids)
    out += "=== 按 PID 过滤的候选窗口（\(byPID.count)）===\n"
    for (i, w) in byPID.enumerated() { out += "[\(i)] \(w.detailed())\n" }

    let byOwner = PetTracker.enumerateByOwnerName(["Chat", "GPT", "Codex", "OpenAI"])
    let extra = byOwner.filter { w in !byPID.contains { $0.wid == w.wid } }
    out += "\n=== ownerName 命中（关键词 Chat/GPT/Codex/OpenAI）但 PID 不在主进程集的窗口（\(extra.count)）===\n"
    for (i, w) in extra.enumerated() { out += "[\(i)] \(w.detailed())\n" }

    // 全局统计：授权后确认 CGWindowList 实际可见性，并定位 ChatGPT 窗口的真实 ownerName/ownerPID。
    let allInfos = CGWindowListCopyWindowInfo([], kCGNullWindowID) as? [[String: Any]] ?? []
    out += "\n=== 全局窗口统计（总数 \(allInfos.count)）===\n"
    var ownerCount: [String: Int] = [:]
    for w in allInfos {
        let name = (w[kCGWindowOwnerName as String] as? String) ?? "(空)"
        ownerCount[name, default: 0] += 1
    }
    let keywords = ["chat", "gpt", "codex", "openai"]
    for (name, cnt) in ownerCount.sorted(by: { $0.value > $1.value }) {
        let hit = keywords.contains { name.lowercased().contains($0) } ? "  ← 候选" : ""
        out += "  \(name): \(cnt)\(hit)\n"
    }

    let union = PetTracker.unionCandidates()
    let sel = PetTracker.selectPet(candidates: union, lastWID: nil)
    out += "\n=== 识别结果（union 通道，候选 \(union.count)，运行模式使用）===\n"
    out += "选中 : \(sel.selected?.detailed() ?? "nil")\n"
    out += "理由 : \(sel.reason)\n"
    out += "命中 : \(sel.hitFlags.joined(separator: ", "))\n"

    out += "\n=== 屏幕（AppKit 左下原点）===\n"
    for (i, s) in NSScreen.screens.enumerated() {
        out += "[screen \(i)] \(s.localizedName) frame=\(s.frame) visibleFrame=\(s.visibleFrame)\n"
    }

    print(out)
    let url = URL(fileURLWithPath: "/tmp/petdock-diagnose.txt")
    try? out.write(to: url, atomically: true, encoding: .utf8)
    exit(0)
}

// MARK: - 运行模式

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let panel = DockPanel()
    private var lastWID: CGWindowID?
    private var timer: Timer?
    private let logURL = URL(fileURLWithPath: "/tmp/petdock.log")

    func applicationDidFinishLaunching(_ n: Notification) {
        // 无屏幕录制权限时，主动触发系统授权弹窗（用户授权后需重启本 app 才能枚举窗口）。
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
        }
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let wins = PetTracker.unionCandidates()
        let sel = PetTracker.selectPet(candidates: wins, lastWID: lastWID)

        let line: String
        if let pet = sel.selected {
            lastWID = pet.wid
            panel.placeBelow(petQuartzRect: pet.bounds)
            panel.showIfNeeded()
            let dockAppKit = Geometry.appKitRectFromQuartz(CGRect(
                x: pet.bounds.origin.x,
                y: pet.bounds.origin.y + pet.bounds.height + panel.gap,
                width: max(panel.dockWidth, pet.bounds.width),
                height: panel.dockHeight))
            let scr = Geometry.screenContaining(quartzCenterX: pet.bounds.midX, pet.bounds.midY)
            line = "[tick] PET wid=\(pet.wid) layer=\(pet.layer) "
                + "\(Int(pet.bounds.width))x\(Int(pet.bounds.height)) "
                + "quartz=(\(Int(pet.bounds.origin.x)),\(Int(pet.bounds.origin.y))) "
                + "dockAppKit=(\(Int(dockAppKit.origin.x)),\(Int(dockAppKit.origin.y)) "
                + "\(Int(dockAppKit.width))x\(Int(dockAppKit.height))) "
                + "screen=\"\(scr?.localizedName ?? "?")\" reason=\(sel.reason)\n"
        } else {
            lastWID = nil
            panel.hideIfNeeded()
            line = "[tick] NO-PET candidates=\(wins.count) reason=\(sel.reason)\n"
        }
        appendLog(line)
    }

    private func appendLog(_ s: String) {
        guard let data = s.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: logURL.path),
           let h = try? FileHandle(forWritingTo: logURL) {
            h.seekToEndOfFile(); h.write(data); try? h.close()
        } else {
            try? data.write(to: logURL)
        }
    }
}

// MARK: - 入口

if CommandLine.arguments.contains("--diagnose") {
    runDiagnoseAndExit()
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // 不显示 Dock 图标，作为后台辅助应用
let delegate = AppDelegate()
app.delegate = delegate
app.run()
