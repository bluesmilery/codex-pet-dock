import Cocoa

// MARK: - 诊断模式（--diagnose）：跑一次识别，打印 + 写文件后退出

func runDiagnoseAndExit() -> Never {
    var out = ""
    let pids = PetTracker.codexPIDs()
    out += "=== 进程定位 ===\n"
    out += "bundle id : \(PetTracker.bundleID)\n"
    out += "主进程数量: \(pids.count)\n"
    out += "屏幕录制权限(preflight): \(CGPreflightScreenCaptureAccess())  (false→CGWindowList 被系统过滤为空)\n\n"

    let byPID = PetTracker.enumerate(pids: pids)
    out += "=== 按主进程过滤的候选窗口（\(byPID.count)）===\n"
    for (i, w) in byPID.enumerated() { out += "[\(i)] \(DiagnosticFormatter.candidateSummary(w))\n" }

    let byOwner = PetTracker.enumerateByOwnerName(["Chat", "GPT", "Codex", "OpenAI"])
    let extra = byOwner.filter { w in !byPID.contains { $0.wid == w.wid } }
    out += "\n=== 关键词通道命中但不在主进程集的窗口（\(extra.count)）===\n"
    for (i, w) in extra.enumerated() { out += "[\(i)] \(DiagnosticFormatter.candidateSummary(w))\n" }

    // 全局统计：授权后确认 CGWindowList 的实际可见性；只保留数量，不记录窗口身份。
    let allInfos = CGWindowListCopyWindowInfo([], kCGNullWindowID) as? [[String: Any]] ?? []
    out += "\n=== 全局窗口统计（总数 \(allInfos.count)，仅记录数量）===\n"

    let union = PetTracker.unionCandidates()
    let sel = PetTracker.selectPet(candidates: union, lastWID: nil)
    out += "\n=== 识别结果（union 通道，候选 \(union.count)，运行模式使用）===\n"
    out += DiagnosticFormatter.selectionSummary(sel) + "\n"

    out += "\n=== 屏幕统计（AppKit）===\n"
    out += "screenCount=\(NSScreen.screens.count)\n"

    print(out)
    let url = PrivateStorage.diagnosticsURL.appendingPathComponent("diagnose.txt")
    if let data = out.data(using: .utf8) {
        try? PrivateStorage.atomicWrite(data, to: url)
    }
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

    /// 一次跟随 tick：枚举 → 识别 → Follower 决策（频率/setFrame）→ FollowTickPlan 纯编排
    /// （数据 pause/resume、UI show/hide）→ 执行计划输出（应用位置/可见性）→ 重排。
    /// tick 只执行纯计划输出；编排判断（边沿/dockVisible/候选为空）集中在 FollowTickPlanner。
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

        // 纯编排决策：数据探测仅跟随宠物可见性；UI 可见 = 宠物可见 && 用户可见。
        let petVisible = d.showDock
        let plan = FollowTickPlanner.decide(
            input: FollowTickInput(petVisible: petVisible,
                                   wasPetVisible: wasPetVisible,
                                   dockVisible: settings.dockVisible))
        // 执行数据边沿（petVisible 边沿驱动 pause/resume，与 UI 解耦）。
        if plan.resumeData {
            provider.resume()
            refreshData()
        } else if plan.pauseData {
            provider.pause()
            stopDataRefresh()
        }
        wasPetVisible = petVisible

        if petVisible {
            lastPet = pet
            lastWID = sel.selected?.wid
            if plan.showUI {
                renderSnapshot()
                if let mascot = sel.selected {
                    // 障碍避让（每 tick 基于当前帧宠物+可见辅助窗几何重算唯一期望 frame，不复用上帧偏移）：
                    // - 会话气泡（消息框）：像素 alpha 可见性（bubbleProbe）决定是否占位；
                    // - 控制按钮：窗口存在性即占位（obstaclesNear 已过滤 isOnscreen/alpha>0）。
                    // 两类分别基于当前帧计算，再合并成唯一障碍集交 safeDockFrame 链式避让。
                    let obstacles = PetTracker.obstaclesNear(mascot: mascot, candidates: wins)
                    let petMaxY = mascot.bounds.maxY
                    // 每个 obstacle 的种类只分类一次（obstaclesNear 已用 isBubble/isControl 过滤，
                    // 这里仅区分气泡 vs 控制按钮以决定可见性判定路径），避免对同一候选重复调用 obstacleKind。
                    let classified = obstacles.map { ($0, PetTracker.obstacleKind($0, petMaxY: petMaxY)) }
                    // 只对气泡类候选做像素可见性探测（控制按钮不经 SC，避免小窗捕获失败被误判收起）。
                    let bubbleCandidates = classified.filter { $0.1 == .bubble }.map { $0.0 }
                    bubbleProbe.probe(candidates: bubbleCandidates)
                    // 合并：气泡(visible) + 控制按钮(全部)，各自当前帧可见性。顺序与 obstacles 一致。
                    let visibleObstacles = classified.filter { pair in
                        pair.1 == .control ? true : bubbleProbe.visibility(for: pair.0.wid) == .visible
                    }.map { $0.0 }
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
                // plan.hideUI：宠物可见但用户隐藏 → 只关 UI，仍跟踪宠物（lastPet/lastWID 已更新）。
                dock.hideIfNeeded()
                detail.close()
            }
        } else {
            // plan.petDisappeared：宠物消失 → 隐藏 UI + 详情，清状态，等待重现重捕。
            dock.hideIfNeeded()
            detail.close()
            lastPet = nil
            lastWID = nil
            bubbleProbe.reset()
        }
        state = d.state
        stableCount = d.stableCount

        log("follow state=\(d.state.rawValue) pet=\(petVisible) show=\(plan.showUI) setFrame=\(d.shouldSetFrame) "
            + "interval=\(d.nextInterval) stable=\(d.stableCount) selected=\(sel.selected != nil)")

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
