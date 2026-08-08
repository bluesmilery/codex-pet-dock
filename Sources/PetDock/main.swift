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

// MARK: - 运行模式：Follower 自适应跟随 + DockPanel + DetailPanel + LiveDockProvider 真实数据

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let dock = DockPanel()
    private let detail = DetailPanel()
    private let provider: LiveDockProvider
    private let bubbleProbe = BubbleVisibilityProbe()
    private let settings = Settings()
    private var themeStore: ThemeStore?
    private var externalThemes: [ThemeSpec] = []
    private var statusBar: StatusBar?
    private var lastPet: CGRect?
    private var lastWID: CGWindowID?
    private var state: FollowState = .hidden
    private var stableCount = 0
    private var timer: Timer?               // 跟随（高频：窗口枚举 + 位置）
    private var dataTimer: Timer?           // 数据刷新（低频：退避间隔）
    private var wasPetVisible = false       // 数据 pause/resume 的边沿触发（跟随宠物可见性）
    private var consecutiveEmptyTicks = 0   // 连续无候选 tick 计数（TCC 缺失降级提示用）
    private let logger = PetLogger()

    override init() {
        // 数据栈：RateLimitClient 经 codex app-server JSON-RPC 取官方周额度；
        //          TokenUsageLogReader 解析 ~/.codex/sessions 本机周 token（仅取数值，不读正文）。
        let sessionsRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")
        let tokenLog = TokenUsageLogReader(sessionsRoot: sessionsRoot,
                                           cacheURL: LiveDockProvider.tokenCacheURL())
        let service = PetDockDataService(rateLimit: RateLimitClient(), tokenLog: tokenLog)
        self.provider = LiveDockProvider(service: service)
        super.init()
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        DebugLog.applyOverrides(arguments: CommandLine.arguments)
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
        }
        dock.onTap = { [weak self] in self?.toggleDetail() }
        // 真实数据在后台刷新，完成后切回主线程回调重渲染（不阻塞 UI）。
        provider.onUpdated = { [weak self] _ in self?.renderSnapshot() }
        setupShell()                  // 主题 / 状态栏 / 自启 / 外部主题热加载
        renderSnapshot()
        schedule(after: Follower.hiddenInterval)
    }

    // MARK: - 产品外壳（主题 / 状态栏 / 自启）

    /// 全部主题：内置 + 外部（Application Support 热加载）。
    private var allThemes: [ThemeSpec] { Theme.builtins + externalThemes }

    /// 按 id 解析主题；未命中回落到内置默认，绝不返回 nil。
    private func resolveTheme(id: String) -> ThemeSpec {
        allThemes.first { $0.id == id } ?? Theme.holographic
    }

    private func setupShell() {
        themeStore = try? ThemeStore()
        if let ts = themeStore { externalThemes = ts.loadAll() }

        dock.applyTheme(resolveTheme(id: settings.themeID).metrics)

        statusBar = StatusBar(
            themes: allThemes,
            currentThemeID: settings.themeID,
            dockVisible: settings.dockVisible,
            launchAtLogin: AutoStart.current() == .enabled,
            actions: StatusBar.Actions(
                onSelectTheme: { [weak self] id in self?.selectTheme(id: id) },
                onToggleVisible: { [weak self] v in self?.setVisible(v) },
                onToggleLaunchAtLogin: { [weak self] v in self?.setLaunchAtLogin(v) },
                onQuit: { [weak self] in self?.quit() }))

        // 外部主题目录变化 → 重新加载并刷新菜单（回调在主线程）。
        themeStore?.start { [weak self] external in
            guard let self = self else { return }
            self.externalThemes = external
            self.statusBar?.updateThemes(self.allThemes)
        }
    }

    /// 主题选择：持久化 + 即时换皮 + 菜单勾选。
    private func selectTheme(id: String) {
        settings.themeID = id
        dock.applyTheme(resolveTheme(id: id).metrics)
        statusBar?.updateThemeSelection(id)
        log("theme select \(id)")
    }

    /// 状态栏「显示/隐藏底座」：同时控底座与详情，且不破坏宠物不可见逻辑
    /// （UI 可见 = 宠物可见 && 用户可见；数据探测仅跟随宠物可见性）。
    private func setVisible(_ v: Bool) {
        settings.dockVisible = v
        if !v { dock.hideIfNeeded(); detail.close() }
        statusBar?.updateDockVisible(v)
        log("dockVisible=\(v)")
    }

    /// 登录自启：经 SMAppService，失败可解释不崩；菜单按真实状态勾选。
    private func setLaunchAtLogin(_ v: Bool) {
        let status = AutoStart.set(enabled: v)
        statusBar?.updateLaunchAtLogin(status == .enabled)
        if case .unavailable(let msg) = status {
            log("autostart \(v) 失败：\(msg)")
        }
    }

    /// 退出：停止热加载、取消数据调度、停止数据探测（拒绝后续刷新 / 在途任务无 UI 副作用）后终止进程。
    private func quit() {
        themeStore?.stop()
        stopDataRefresh()
        provider.stop()
        log("quit")
        NSApplication.shared.terminate(nil)
    }

    // MARK: - 详情 / 渲染

    /// 点击底座：切换详情卡展开/关闭。
    private func toggleDetail() {
        guard dock.isVisible else { return }
        detail.toggle(relativeTo: dock.frame)
        log("ui toggle detail isOpen=\(detail.isVisible)")
    }

    /// 拉取展示快照并刷新底座与详情卡（主线程读 provider 缓存，O(1)，不阻塞）。
    private func renderSnapshot() {
        let s = provider.currentSnapshot()
        dock.render(s)
        detail.render(s)
    }

    /// 跟随 timer 动态重新调度（频率随 Follower 决策变化）。加入 .common 模式，
    /// 使事件跟踪 / 模态等非 default 模式下仍能触发，避免跟随卡顿。
    private func schedule(after interval: TimeInterval) {
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: false) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// 数据刷新：后台抓取两源（不阻塞主线程），完成后按退避间隔重排。
    private func refreshData() {
        provider.refresh { [weak self] in self?.scheduleDataRefresh() }
    }

    /// 数据刷新调度：取两源退避间隔较大者（任一失败即拉长；正常均 5min）。加入 .common 模式。
    private func scheduleDataRefresh() {
        dataTimer?.invalidate()
        let interval = max(provider.weekLeftNextDelay, provider.weekTokensNextDelay)
        let t = Timer(timeInterval: interval, repeats: false) { [weak self] _ in self?.refreshData() }
        RunLoop.main.add(t, forMode: .common)
        dataTimer = t
    }

    private func stopDataRefresh() {
        dataTimer?.invalidate()
        dataTimer = nil
    }

    /// 一次跟随 tick：枚举 → 识别 → Follower 决策 → 数据 pause/resume（跟随宠物）→
    /// UI 可见性（宠物 && 用户）→ 应用位置 → 重排。
    private func tick() {
        let wins = PetTracker.unionCandidates()
        let sel = PetTracker.selectPet(candidates: wins, lastWID: lastWID)
        let pet = sel.selected?.bounds
        let d = Follower.decide(pet: pet, lastPet: lastPet, state: state, stableCount: stableCount)

        // TCC 缺失降级提示：连续无候选 + 屏幕录制权限未授予 → 状态栏提示（避免静默失败）。
        // 权限授予后 CGWindowList 返候选，或 preflight 转 true → 提示自动消失。
        if sel.selected == nil {
            consecutiveEmptyTicks += 1
        } else {
            consecutiveEmptyTicks = 0
        }
        let needsTCCWarning = consecutiveEmptyTicks >= 3 && !CGPreflightScreenCaptureAccess()
        statusBar?.updatePermissionWarning(needsTCCWarning)

        // 数据探测仅跟随宠物可见性（与用户是否隐藏 UI 解耦）。
        let petVisible = d.showDock
        if petVisible && !wasPetVisible {
            provider.resume()
            refreshData()
        } else if !petVisible && wasPetVisible {
            provider.pause()
            stopDataRefresh()
        }
        wasPetVisible = petVisible

        // UI 可见 = 宠物可见 && 用户可见；用户隐藏只关 UI，仍跟踪宠物。
        let showUI = petVisible && settings.dockVisible
        if petVisible {
            lastPet = pet
            lastWID = sel.selected?.wid
            if showUI {
                renderSnapshot()
                if let mascot = sel.selected {
                    // 会话气泡避让：pet 下方同 owner 浮层障碍下移；越出 screen 可见区则隐藏底座+详情。
                    let obstacles = PetTracker.obstaclesNear(mascot: mascot, candidates: wins)
                    // 异步探测 bubble 可见性（ScreenCaptureKit 像素 alpha）；只将 visible 候选作为障碍。
                    bubbleProbe.probe(candidates: obstacles)
                    let visibleObstacles = obstacles.filter { bubbleProbe.visibility(for: $0.wid) == .visible }
                    let scr = Geometry.screenContaining(quartzCenterX: mascot.bounds.midX, mascot.bounds.midY)
                    let shown = dock.placeBelow(petQuartzRect: mascot.bounds,
                                                avoiding: visibleObstacles.map { $0.bounds }, visibleScreen: scr)
                    if shown {
                        dock.showIfNeeded()
                        if detail.isVisible { detail.placeBelow(dockFrame: dock.frame, visibleScreen: scr) }
                    } else {
                        dock.hideIfNeeded()
                        detail.close()
                    }
                }
            } else {
                dock.hideIfNeeded()
                detail.close()
            }
        } else {
            // 宠物消失：隐藏 UI + 详情，清状态，等待重现重捕
            dock.hideIfNeeded()
            detail.close()
            lastPet = nil
            lastWID = nil
            bubbleProbe.reset()
        }
        state = d.state
        stableCount = d.stableCount

        log("follow state=\(d.state.rawValue) pet=\(petVisible) show=\(showUI) setFrame=\(d.shouldSetFrame) "
            + "interval=\(d.nextInterval) stable=\(d.stableCount) wid=\(sel.selected?.wid ?? 0)")

        schedule(after: d.nextInterval)
    }

    private func log(_ s: String) {
        logger.log(s)
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
