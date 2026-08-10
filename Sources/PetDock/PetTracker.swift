import Cocoa

/// 宠物窗口识别阈值（候选，与 docs/pet-window-detection.md 对应，待真实数据校准）。
enum PetHeuristics {
    static let mainMinArea: CGFloat = 150_000   // 主聊天窗口面积下限
    static let mainMinSide: CGFloat = 400       // 主窗口最大边下限
    static let petMaxArea: CGFloat = 70_000     // 宠物面积上限
    static let petMaxSide: CGFloat = 300        // 宠物最大边上限
    static let petMinSide: CGFloat = 50         // 宠物最小边下限（排除 18x6 等细长 / 过小辅助控件）
    /// 位置容差：origin 位移 ≤ 此值视为「位置不变」，吸收 Electron 渲染亚像素抖动，
    /// 使 Follower 能进入 stable 降频（否则微抖动下精确 != 永真、永不降频）。尺寸变化不受此容差影响。
    static let positionTolerance: CGFloat = 1.0
    // 会话气泡（短浮层）几何窗：用于动态识别 pet 底部下方的障碍，不依赖 title。
    static let bubbleHeightMin: CGFloat = 32    // 高度下限（排除 17x6 voice controls）
    static let bubbleHeightMax: CGFloat = 223   // 高度上限（排除 512x223 wrapper —— 它包含整个 pet）
    static let bubbleMinYSlack: CGFloat = 32    // bubble.minY 允许高于 pet 底部的偏差（约一行气泡）
    // 控制按钮（移动/交互时出现的独立动态占用区域）：消息框在 pet 上方时，pet 正下方出现的紧凑按钮簇。
    // 与气泡互补（高度 < bubbleHeightMin），用相对 pet 位置/尺寸的非内容元数据形成最小安全候选规则。
    static let ctrlHeightMax: CGFloat = 32      // 控制按钮高度上限（与气泡 bubbleHeightMin 互补，不重叠）
    static let ctrlMinSide: CGFloat = 18        // 最小边下限（排除 17x6 细长 voice control：minSide=6）
    static let ctrlMaxSide: CGFloat = 160       // 最大边上限（紧凑控件，排除大面合成层）
}

/// 一个可观测的窗口候选（来自 CGWindowList）。
struct WinCandidate: Sendable {
    let wid: CGWindowID
    let ownerPID: Int32
    let ownerName: String
    let title: String
    let layer: Int
    let alpha: Double
    let isOnscreen: Bool
    let sharingState: Int
    let bounds: CGRect          // Quartz 全局坐标

    var area: CGFloat { bounds.width * bounds.height }
    var maxSide: CGFloat { max(bounds.width, bounds.height) }

    /// R3：是否像主聊天窗口（用于排除）。
    var isLikelyMainWindow: Bool {
        layer == 0 && (area >= PetHeuristics.mainMinArea || maxSide >= PetHeuristics.mainMinSide)
    }
    /// R4.3：尺寸是否符合宠物范围（且非主窗口）。
    var isPetShaped: Bool {
        !isLikelyMainWindow
            && maxSide <= PetHeuristics.petMaxSide
            && area <= PetHeuristics.petMaxArea
    }

    /// 已知辅助控件（Mascot 周边的合成面 / 语音控件），识别时排除。
    var isAuxiliaryTitle: Bool {
        let t = title.lowercased()
        return ["voice control", "composition surface", "backing", "glass"].contains { t.contains($0) }
    }

    /// R4.4 合理宠物候选：petShaped + 最小边（排除 18x6 等细长 / 过小）+ 非辅助控件 title。
    /// Mascot 172x179 合理；384x95（maxSide>300）、18x6（minSide<50）、Voice Controls / Composition 排除。
    var isReasonablePet: Bool {
        isPetShaped
            && bounds.width >= PetHeuristics.petMinSide
            && bounds.height >= PetHeuristics.petMinSide
            && !isAuxiliaryTitle
    }

    func detailed() -> String {
        let tag = isLikelyMainWindow ? "[MAIN]" : (isPetShaped ? "[pet?]" : "[?]")
        return "\(tag) wid=\(wid) pid=\(ownerPID) owner=\"\(ownerName)\" title=\"\(title)\" "
            + "layer=\(layer) alpha=\(alpha) onscreen=\(isOnscreen) sharing=\(sharingState) "
            + "\(Int(bounds.width))x\(Int(bounds.height)) area=\(Int(area)) "
            + "bounds=(\(Int(bounds.origin.x)),\(Int(bounds.origin.y)))"
    }
}

struct SelectionResult {
    let selected: WinCandidate?
    let reason: String
    let hitFlags: [String]
    let allCandidates: [WinCandidate]
}

/// 纯函数式的窗口枚举 + 宠物识别。无单例、无副作用，便于测试与诊断复用。
enum PetTracker {

    static let bundleID = "com.openai.codex"

    // MARK: - 可注入的运行时源（测试替换；默认调系统 API）

    /// 全局窗口枚举源。默认调 `CGWindowListCopyWindowInfo`；测试可注入 mock + 计数。
    static var infosProvider: () -> [[String: Any]]? = {
        CGWindowListCopyWindowInfo([], kCGNullWindowID) as? [[String: Any]]
    }
    /// codex 主进程 PID 源。默认查 `NSRunningApplication`；测试可注入 mock + 计数。
    static var runningAppsProvider: () -> [Int32] = {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .map { $0.processIdentifier }.filter { $0 != 0 }
    }
    /// 时钟源（PID 缓存 TTL 判断用）。测试可注入固定时钟。
    static var nowProvider: () -> Date = { Date() }

    // MARK: - PID 缓存（1s TTL，moving 态 20Hz 下避免每 tick 查 NSRunningApplication）

    static let pidCacheTTL: TimeInterval = 1.0
    private static let pidLock = NSLock()
    private static var cachedPIDs: [Int32] = []
    private static var cachedPIDsAt: Date = .distantPast
    private static var hasPIDCache = false

    /// R1：通过 bundle id 拿 codex 主进程 PID 集合（结果在 `pidCacheTTL` 内缓存）。
    /// PID 极少变化，1s TTL 足够；moving 态 20Hz 下从 20 次/秒降为 ~1 次/秒。
    static func codexPIDs() -> [Int32] {
        pidLock.lock()
        if hasPIDCache, nowProvider().timeIntervalSince(cachedPIDsAt) < pidCacheTTL {
            let cached = cachedPIDs; pidLock.unlock(); return cached
        }
        pidLock.unlock()
        let pids = runningAppsProvider()
        pidLock.lock()
        cachedPIDs = pids; cachedPIDsAt = nowProvider(); hasPIDCache = true
        pidLock.unlock()
        return pids
    }

    /// 测试用：清空 PID 缓存。
    static func resetPIDCacheForTesting() {
        pidLock.lock(); cachedPIDs = []; hasPIDCache = false; pidLock.unlock()
    }

    /// R1+R2：按 PID 集合枚举窗口（经 `infosProvider` 取一次全局窗口）。
    static func enumerate(pids: [Int32]) -> [WinCandidate] {
        guard let infos = infosProvider() else { return [] }
        return enumerate(pids: pids, from: infos)
    }

    /// 按 PID 集合从已枚举的 `infos` 过滤（共享单次枚举结果，避免重复系统调用）。
    static func enumerate(pids: [Int32], from infos: [[String: Any]]) -> [WinCandidate] {
        let pidSet = Set(pids)
        return infos.compactMap { dict -> WinCandidate? in
            guard let c = parse(dict) else { return nil }
            return pidSet.contains(c.ownerPID) ? c : nil
        }
    }

    /// 扩展通道（诊断用）：按 ownerName 包含关系枚举，用于发现 Electron helper 归属的窗口。
    static func enumerateByOwnerName(_ names: [String]) -> [WinCandidate] {
        guard let infos = infosProvider() else { return [] }
        return enumerateByOwnerName(names, from: infos)
    }

    /// 按 ownerName 从已枚举的 `infos` 过滤（共享单次枚举结果）。
    static func enumerateByOwnerName(_ names: [String], from infos: [[String: Any]]) -> [WinCandidate] {
        infos.compactMap { dict -> WinCandidate? in
            guard let c = parse(dict) else { return nil }
            return names.contains { c.ownerName.localizedCaseInsensitiveContains($0) } ? c : nil
        }
    }

    /// R3–R5：从候选中选出宠物窗口。纯函数。
    static func selectPet(candidates: [WinCandidate], lastWID: CGWindowID?) -> SelectionResult {
        let visible = candidates.filter(\.isOnscreen)
        let nonMain = visible.filter { !$0.isLikelyMainWindow }

        // R4.1 滞回：上次选中的仍有效则沿用
        if let last = lastWID, let w = nonMain.first(where: { $0.wid == last }) {
            return SelectionResult(
                selected: w,
                reason: "滞回：沿用上次选中 wid=\(last) (\(Int(w.bounds.width))x\(Int(w.bounds.height)), layer=\(w.layer))",
                hitFlags: ["hysteresis:lastWID=\(last)"],
                allCandidates: candidates
            )
        }

        // R4.0 title 含 "Mascot"（吉祥物本体稳定标识）：优先于周边 layer 更高的合成面/语音控件。
        // 实测：吉祥物本体 layer=2，而其 Composition Surface / Voice Controls 子窗口 layer=3，
        // 单纯"高 layer 优先"会误选子窗口，故用 title 精确锁定吉祥物本体。
        let mascot = nonMain.filter { $0.title.localizedCaseInsensitiveContains("Mascot") }
        if let best = mascot.min(by: { $0.area < $1.area }) {
            return SelectionResult(
                selected: best,
                reason: "title 含 'Mascot'（吉祥物本体），取面积最小者 (\(Int(best.bounds.width))x\(Int(best.bounds.height)), layer=\(best.layer))",
                hitFlags: ["title~Mascot"],
                allCandidates: candidates
            )
        }

        // R4.2 高 layer 优先（浮层宠物）—— 须为合理宠物候选，排除辅助控件 / 极端几何
        let highLayer = nonMain.filter { $0.layer > 0 && $0.isReasonablePet }
        if let best = highLayer.sorted(by: { lhs, rhs in
            if lhs.layer != rhs.layer { return lhs.layer > rhs.layer }
            return lhs.area < rhs.area
        }).first {
            return SelectionResult(
                selected: best,
                reason: "layer=\(best.layer) 浮层候选中取面积最小者 (\(Int(best.bounds.width))x\(Int(best.bounds.height)))",
                hitFlags: ["layer>0", "layer=\(best.layer)"],
                allCandidates: candidates
            )
        }

        // R4.3 尺寸符合宠物范围（合理候选：排除辅助控件 / 极端几何）
        let petShaped = nonMain.filter { $0.isReasonablePet }
        if let best = petShaped.min(by: { $0.area < $1.area }) {
            return SelectionResult(
                selected: best,
                reason: "尺寸符合宠物范围，取面积最小者 (\(Int(best.bounds.width))x\(Int(best.bounds.height)))",
                hitFlags: ["petShaped", "area=\(Int(best.area))"],
                allCandidates: candidates
            )
        }

        // R5 无候选
        if visible.isEmpty {
            return SelectionResult(selected: nil, reason: "无可见窗口", hitFlags: ["no-visible"], allCandidates: candidates)
        }
        if nonMain.isEmpty {
            return SelectionResult(selected: nil, reason: "所有可见窗口均判为主窗口，不选（避免误绑主聊天窗口）", hitFlags: ["no-pet:all-main"], allCandidates: candidates)
        }
        return SelectionResult(selected: nil, reason: "无非主窗口候选符合宠物特征", hitFlags: ["no-pet:nonmain-notshaped"], allCandidates: candidates)
    }

    /// 运行模式使用的候选集：PID 通道 ∪ ownerName 关键词通道（按 wid 去重）。
    /// Electron 应用的窗口可能挂在 helper/renderer PID 上（非主 PID），故同时用 ownerName 兜底。
    /// **单次 `CGWindowListCopyWindowInfo` 枚举**：两通道共享 `infosProvider()` 结果，
    /// moving 态 20Hz 下从 40 次/秒降为 20 次/秒。
    static func unionCandidates() -> [WinCandidate] {
        guard let infos = infosProvider() else { return [] }
        let byPID = enumerate(pids: codexPIDs(), from: infos)
        let byName = enumerateByOwnerName(["Chat", "GPT", "Codex", "OpenAI"], from: infos)
        var seen = Set<CGWindowID>()
        var merged: [WinCandidate] = []
        for w in byPID + byName where !seen.contains(w.wid) {
            seen.insert(w.wid); merged.append(w)
        }
        return merged
    }

    /// 与选中 Mascot 同 owner 的障碍（用于底座避让），合并两类**独立动态占用区域**：
    /// - **会话气泡**（消息框展开）：高度 ∈ [bubbleHeightMin, bubbleHeightMax)，minY 允许小负偏差。
    /// - **控制按钮**（移动/交互时出现）：高度 < bubbleHeightMin，minY 严格 ≥ petMaxY（pet 正下方紧邻）。
    ///
    /// 两类分别基于当前帧几何判定（消息框在上/下与按钮出现/消失互不依赖），再合并成唯一障碍集。
    /// **动态几何窗，不依赖 title**：共用前置（同 owner / onscreen / alpha>0 / layer>=3 / 非主窗 / 水平投影与 pet 重叠）。
    /// 排除 Mascot 自身与 main(layer0)。**不改变 selectPet 的合理回退**（障碍仅用于几何避让）。
    static func obstaclesNear(mascot: WinCandidate, candidates: [WinCandidate]) -> [WinCandidate] {
        guard !mascot.ownerName.isEmpty else { return [] }
        let pet = mascot.bounds
        let petMaxY = pet.maxY
        return candidates.filter { c in
            // 共用前置：同 owner / 在屏 / 可见 / 浮层 / 非主窗 / 排除 mascot 自身 / 水平投影与 pet 重叠
            c.wid != mascot.wid
                && c.ownerName == mascot.ownerName
                && c.isOnscreen && c.alpha > 0 && c.layer >= 3
                && !c.isLikelyMainWindow
                && c.bounds.origin.x < pet.maxX && c.bounds.origin.x + c.bounds.width > pet.minX
                && (isBubbleObstacle(c, petMaxY: petMaxY) || isControlObstacle(c, petMaxY: petMaxY))
        }
    }

    /// 障碍种类：决定可见性判定方式（消息框 vs 控制按钮分别基于当前帧计算）。
    enum ObstacleKind { case bubble, control }

    /// 判定候选相对 petMaxY 的障碍种类（已被 obstaclesNear 纳入的候选）。
    /// - `.bubble`：会话气泡，可见性由像素 alpha（bubbleProbe）判定（展开/收起）。
    /// - `.control`：控制按钮，可见性即窗口存在性（已在 obstaclesNear 的 isOnscreen/alpha>0 保证），
    ///   不经像素探测 —— 避免小窗口 SC 捕获失败(nil)被误判收起。
    static func obstacleKind(_ c: WinCandidate, petMaxY: CGFloat) -> ObstacleKind {
        isBubbleObstacle(c, petMaxY: petMaxY) ? .bubble : .control
    }

    /// 会话气泡障碍：高度 ∈ [bubbleHeightMin, bubbleHeightMax)，maxSide<=600，
    /// minY 在 pet 底部附近（允许小负偏差，排除从 pet 中部开始的 wrapper/384x95）。
    private static func isBubbleObstacle(_ c: WinCandidate, petMaxY: CGFloat) -> Bool {
        c.bounds.height >= PetHeuristics.bubbleHeightMin
            && c.bounds.height < PetHeuristics.bubbleHeightMax
            && c.maxSide <= 600
            && c.bounds.minY >= petMaxY - PetHeuristics.bubbleMinYSlack
    }

    /// 控制按钮障碍（独立动态占用区域，与气泡互补）：高度 < ctrlHeightMax（与 bubbleHeightMin 衔接），
    /// minSide>=ctrlMinSide（排除 17x6 细长 voice control），maxSide<=ctrlMaxSide（紧凑控件），
    /// minY 严格 ≥ petMaxY（pet 正下方紧邻，排除 pet 内部噪声窗）。按钮只有出现时才占位，消失即复位。
    private static func isControlObstacle(_ c: WinCandidate, petMaxY: CGFloat) -> Bool {
        c.bounds.height < PetHeuristics.ctrlHeightMax
            && c.bounds.width >= PetHeuristics.ctrlMinSide
            && c.bounds.height >= PetHeuristics.ctrlMinSide
            && c.maxSide <= PetHeuristics.ctrlMaxSide
            && c.bounds.minY >= petMaxY
    }

    // MARK: - 解析

    private static func parse(_ w: [String: Any]) -> WinCandidate? {
        let wid = CGWindowID((w[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0)
        let bounds = readBounds(w)
        if bounds.width < 1 || bounds.height < 1 { return nil }   // R2
        return WinCandidate(
            wid: wid,
            ownerPID: (w[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? -1,
            ownerName: (w[kCGWindowOwnerName as String] as? String) ?? "",
            title: (w[kCGWindowName as String] as? String) ?? "",
            layer: (w[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0,
            alpha: (w[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1.0,
            isOnscreen: (w[kCGWindowIsOnscreen as String] as? Bool) ?? false,
            sharingState: (w[kCGWindowSharingState as String] as? NSNumber)?.intValue ?? 0,
            bounds: bounds
        )
    }

    private static func readBounds(_ w: [String: Any]) -> CGRect {
        guard let bd = w[kCGWindowBounds as String] as? [String: Any] else { return .zero }
        func n(_ k: String) -> CGFloat { CGFloat((bd[k] as? NSNumber)?.doubleValue ?? 0) }
        return CGRect(x: n("X"), y: n("Y"), width: n("Width"), height: n("Height"))
    }
}
