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

// MARK: - 运行模式：Follower 自适应跟随 + DockPanel + DetailPanel + 静态假数据

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let dock = DockPanel()
    private let detail = DetailPanel()
    private let provider: DockModelProvider = StaticDockProvider()
    private var lastPet: CGRect?
    private var lastWID: CGWindowID?
    private var state: FollowState = .hidden
    private var stableCount = 0
    private var timer: Timer?
    private let logURL = URL(fileURLWithPath: "/tmp/petdock.log")

    func applicationDidFinishLaunching(_ n: Notification) {
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
        }
        dock.onTap = { [weak self] in self?.toggleDetail() }
        renderSnapshot()
        schedule(after: Follower.hiddenInterval)
    }

    /// 点击底座：切换详情卡展开/关闭。
    private func toggleDetail() {
        guard dock.isVisible else { return }
        detail.toggle(relativeTo: dock.frame)
        log("ui toggle detail isOpen=\(detail.isVisible)")
    }

    /// 拉取展示快照并刷新底座与详情卡。
    private func renderSnapshot() {
        let s = provider.currentSnapshot()
        dock.render(s)
        detail.render(s)
    }

    /// 动态重新调度（频率随 Follower 决策变化）。
    private func schedule(after interval: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.tick()
        }
    }

    /// 一次跟随 tick：枚举 → 识别 → Follower 决策 → 应用可见性/setFrame → 按决策间隔重排。
    private func tick() {
        let wins = PetTracker.unionCandidates()
        let sel = PetTracker.selectPet(candidates: wins, lastWID: lastWID)
        let pet = sel.selected?.bounds
        let d = Follower.decide(pet: pet, lastPet: lastPet, state: state, stableCount: stableCount)

        if d.showDock {
            renderSnapshot()
            if d.shouldSetFrame, let p = pet {
                dock.placeBelow(petQuartzRect: p)
                if detail.isVisible { detail.placeBelow(dockFrame: dock.frame) }
            }
            dock.showIfNeeded()
            lastPet = pet
            lastWID = sel.selected?.wid
        } else {
            // 宠物消失：隐藏底座 + 详情，清状态，等待重现重捕
            dock.hideIfNeeded()
            detail.close()
            lastPet = nil
            lastWID = nil
        }
        state = d.state
        stableCount = d.stableCount

        log("follow state=\(d.state.rawValue) show=\(d.showDock) setFrame=\(d.shouldSetFrame) "
            + "interval=\(d.nextInterval) stable=\(d.stableCount) wid=\(sel.selected?.wid ?? 0)")

        schedule(after: d.nextInterval)
    }

    private func log(_ s: String) {
        let line = "[\(s)]\n"
        guard let data = line.data(using: .utf8) else { return }
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
