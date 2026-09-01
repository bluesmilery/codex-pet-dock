import Cocoa

/// 宠物窗口识别阈值（与 docs/architecture/pet-window-detection.md 对应）。
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
    /// Composition Surface 气泡通道标题：宿主实测稳定标识（2026-08-24 现场像素级取证，
    /// 展开气泡卡只渲染在该标题的大窗内），与 selectPet 依赖的 "Mascot" 标题同级。
    /// 精确匹配（非包含），避免误纳同尺寸的其他宿主窗口。
    static let compositionSurfaceTitle = "Codex Pet Composition Surface"
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

/// 主通道选择来源的类型化可信度。R3（菜单误跟随修复）：来源路由按
/// strong Mascot → 容器 → 仅无容器时 generic 回退解析唯一宠物来源，消费方不得解析
/// reason / hitFlags 字符串判断来源。
enum PrimarySelectionSource: Equatable, Sendable {
    /// 独立 Mascot 身份：title 含 Mascot，或滞回沿用的窗口本身就是 Mascot（R1 主通道）。
    case strongMascot
    /// 通用几何回退（高 layer / 尺寸合理候选 / 非 Mascot 滞回）。容器候选在场时不得接管。
    case genericWindow
    /// 无主通道选择。
    case none
}

struct SelectionResult {
    let selected: WinCandidate?
    /// 本次的类型化来源（与 selected 同步：strong/generic ⇒ selected 非 nil）。
    let source: PrimarySelectionSource
    let reason: String
    let hitFlags: [String]
    let allCandidates: [WinCandidate]
}

/// 纯函数式的窗口枚举 + 宠物识别。无单例、无副作用，便于测试与诊断复用。
enum PetTracker {

    static let bundleID = "com.openai.codex"

    // MARK: - 可注入的运行时源（测试替换；默认调系统 API）

    /// 全局窗口枚举源。默认调 `CGWindowListCopyWindowInfo`；测试可注入 mock + 计数。
    /// 枚举选项用 `.optionOnScreenOnly`（R6 瘦身）：所有下游消费者都只消费
    /// isOnscreen 窗口——selectPet 先 `filter(\.isOnscreen)`，obstaclesNear 前置
    /// 要求 `c.isOnscreen`，气泡像素探测只吃 obstaclesNear 输出——offscreen 窗口
    /// 全是白算。实测全量 `[]` 枚举 8.6ms/602 窗，onscreenOnly 1.26ms/56 窗（约 7 倍）。
    static var infosProvider: () -> [[String: Any]]? = {
        CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
    }
    /// codex 主进程 PID 源。默认查 `NSRunningApplication`；测试可注入 mock + 计数。
    static var runningAppsProvider: () -> [Int32] = {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .map { $0.processIdentifier }.filter { $0 != 0 }
    }
    /// 时钟源（PID 缓存 TTL 判断用）。测试可注入固定时钟。
    static var nowProvider: () -> Date = { Date() }

    // MARK: - PID 缓存（1s TTL，moving 态高频轮询时避免每 tick 查 NSRunningApplication）

    static let pidCacheTTL: TimeInterval = 1.0
    private static let pidLock = NSLock()
    private static var cachedPIDs: [Int32] = []
    private static var cachedPIDsAt: Date = .distantPast
    private static var hasPIDCache = false

    /// R1：通过 bundle id 拿 codex 主进程 PID 集合（结果在 `pidCacheTTL` 内缓存）。
    /// PID 极少变化，1s TTL 足够；moving 态高频轮询时降为约 1 次/秒。
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

        // R4.1 滞回：上次选中的仍有效则沿用。沿用前再校验该窗口仍具宠物特征
        // （合理候选或 title 含 Mascot）：宿主收起会话 UI 后隐藏气泡窗口仍存活（onscreen、
        // 与宠物居中），瞬时误选或窗口世代切换一旦把它写入 lastWID，仅凭 wid 存在的滞回会
        // 永久锁定该窗口；不满足则落入后续规则链（title 规则找回真 Mascot）。
        if let last = lastWID, let w = nonMain.first(where: { $0.wid == last }),
           w.isReasonablePet || w.title.localizedCaseInsensitiveContains("Mascot") {
            let source: PrimarySelectionSource = w.title.localizedCaseInsensitiveContains("Mascot")
                ? .strongMascot : .genericWindow
            return SelectionResult(
                selected: w,
                source: source,
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
                source: .strongMascot,
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
                source: .genericWindow,
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
                source: .genericWindow,
                reason: "尺寸符合宠物范围，取面积最小者 (\(Int(best.bounds.width))x\(Int(best.bounds.height)))",
                hitFlags: ["petShaped", "area=\(Int(best.area))"],
                allCandidates: candidates
            )
        }

        // R5 无候选
        if visible.isEmpty {
            return SelectionResult(selected: nil, source: .none, reason: "无可见窗口", hitFlags: ["no-visible"], allCandidates: candidates)
        }
        if nonMain.isEmpty {
            return SelectionResult(selected: nil, source: .none, reason: "所有可见窗口均判为主窗口，不选（避免误绑主聊天窗口）", hitFlags: ["no-pet:all-main"], allCandidates: candidates)
        }
        return SelectionResult(selected: nil, source: .none, reason: "无非主窗口候选符合宠物特征", hitFlags: ["no-pet:nonmain-notshaped"], allCandidates: candidates)
    }

    /// 运行模式使用的候选集：PID 通道 ∪ ownerName 关键词通道（按 wid 去重）。
    /// Electron 应用的窗口可能挂在 helper/renderer PID 上（非主 PID），故同时用 ownerName 兜底。
    /// **单次 `CGWindowListCopyWindowInfo` 枚举**：两通道共享 `infosProvider()` 结果，
    /// moving 态高频轮询时从每 tick 两次枚举降为一次。
    /// `infosProvider` 默认 `.optionOnScreenOnly`：本函数的全部下游（selectPet /
    /// obstaclesNear / 气泡探测）都只消费 isOnscreen 窗口，offscreen 枚举纯属白算。
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

    /// 与选中 Mascot 同 owner 的障碍（用于底座避让），合并三类**独立动态占用区域**：
    /// - **会话气泡**（消息框展开）：高度 ∈ [bubbleHeightMin, bubbleHeightMax)，minY 允许小负偏差。
    /// - **控制按钮**（移动/交互时出现）：高度 < bubbleHeightMin，minY 严格 ≥ petMaxY（pet 正下方紧邻）。
    /// - **Composition Surface 气泡卡**：标题精确匹配通道（见 isCompositionSurfaceObstacle），
    ///   展开气泡卡渲染在该大窗里，几何上限不适用。
    ///
    /// 三类分别基于当前帧判定（消息框在上/下与按钮出现/消失互不依赖），再合并成唯一障碍集。
    /// 前两类为**动态几何窗**，第三类依赖宿主实测稳定标题：共用前置（同 owner / onscreen / alpha>0 / layer>=3 / 非主窗 / 水平投影与 pet 重叠）。
    /// 排除 Mascot 自身与 main(layer0)。**不改变 selectPet 的合理回退**（障碍仅用于几何避让）。
    ///
    /// Composition Surface 通道按**标题**命中（跨 bounds）：全部命中实例经签名去重后
    /// 保留为代表候选集——同一签名（owner/title/layer/bounds 完全相同）的重复实例按
    /// 输入顺序取首个；不同签名的实例全部保留，由 FollowLayoutPass 的活层代表选择
    /// （Mascot 脚底一致性窗口 + 最小 csBottomAbs）裁决唯一布局锚代表。2026-08-26 现场：
    /// 死层残影排在活层前面，"列表首层=活层"假设失效；仅像素几何一致性可区分死/活层。
    static func obstaclesNear(mascot: WinCandidate, candidates: [WinCandidate]) -> [WinCandidate] {
        guard !mascot.ownerName.isEmpty else { return [] }
        let pet = mascot.bounds
        let petMaxY = pet.maxY
        var compositionSurfaceCandidates: [WinCandidate] = []
        var geometricObstacles: [WinCandidate] = []
        for c in candidates {
            // 共用前置：同 owner / 在屏 / 可见 / 浮层 / 非主窗 / 排除 mascot 自身 / 水平投影与 pet 重叠
            guard c.wid != mascot.wid,
                  c.ownerName == mascot.ownerName,
                  c.isOnscreen, c.alpha > 0, c.layer >= 3,
                  !c.isLikelyMainWindow,
                  c.bounds.origin.x < pet.maxX, c.bounds.origin.x + c.bounds.width > pet.minX
            else { continue }
            if isCompositionSurfaceObstacle(c, petMaxY: petMaxY) {
                // 标题命中 + 签名去重（跨 bounds 保留不同签名实例）：唯一布局锚代表
                // 由 FollowLayoutPass 的活层一致性窗口裁决（见函数头注释）。
                compositionSurfaceCandidates.append(c)
            } else if isBubbleObstacle(c, petMaxY: petMaxY) || isControlObstacle(c, petMaxY: petMaxY) {
                geometricObstacles.append(c)
            }
        }
        var obstacles = deduplicatedObstacles(geometricObstacles)
        obstacles += deduplicatedObstacles(compositionSurfaceCandidates)
        // wid 升序仅是输出稳定性排序，不参与 CS 代表选择——活层代表由
        // FollowLayoutPass 按 Mascot 脚底一致性窗口在候选集内裁决。
        return obstacles.sorted { $0.wid < $1.wid }
    }

    /// 障碍种类：决定可见性判定方式与保守降级语义（三类，见 obstacleKind）。
    enum ObstacleKind { case bubble, control, compositionSurface }

    /// 判定候选相对 petMaxY 的障碍种类（已被 obstaclesNear 纳入的候选）。
    /// - `.bubble`：会话气泡（ACT 等几何小窗），可见性由像素 alpha（bubbleProbe）判定（展开/收起）；
    ///   保守 visible 无 contentBottom 时整窗 bounds 避让（降级语义与既有版本一致）。
    /// - `.control`：控制按钮，可见性即窗口存在性（已在 obstaclesNear 的 isOnscreen/alpha>0 保证），
    ///   不经像素探测 —— 避免小窗口 SC 捕获失败(nil)被误判收起。
    /// - `.compositionSurface`：Composition Surface 常驻大窗的气泡卡。标题通道命中时优先返回该
    ///   种类（几何通道的高度/边长上限本就排除该大窗）；其障碍性完全取决于宠物下方像素内容，
    ///   无观察数据时跳过避让（见 FollowLayoutPass），不做整窗保守避让。
    static func obstacleKind(_ c: WinCandidate, petMaxY: CGFloat) -> ObstacleKind {
        if isCompositionSurfaceObstacle(c, petMaxY: petMaxY) { return .compositionSurface }
        return isBubbleObstacle(c, petMaxY: petMaxY) ? .bubble : .control
    }

    /// Composition Surface 气泡通道：展开气泡卡渲染在该标题的大窗（现场实测 768x912、
    /// layer 3、与宠物水平重叠、bounds 延伸到宠物下方）里；纯几何通道的
    /// bubbleHeightMax/maxSide 会把它排除（S1 症状根因）。标题精确匹配取代几何猜测，
    /// 不受高度/边长上限约束（共用前置已由 obstaclesNear 保证，此处只补标题与 petMaxY 关系）。
    private static func isCompositionSurfaceObstacle(_ c: WinCandidate, petMaxY: CGFloat) -> Bool {
        c.title == PetHeuristics.compositionSurfaceTitle && c.bounds.maxY > petMaxY
    }

    /// 障碍去重（非 Composition Surface 通道）：宿主可能为同一窗口注册多个同
    /// (owner,title,layer,bounds) 实例。wid 升序取首个代表，避免重复像素捕获。
    /// 去重发生在 obstaclesNear 输出边界，保证布局障碍集与 BubbleVisibilityProbe 候选集
    /// 一致——代表以外的实例不会因无 cache 回退保守 visible 的整窗 bounds 避让。
    /// Composition Surface 通道同样经过此处（签名 = owner/title/layer/bounds）：
    /// 同签名重复实例去重，不同签名实例保留给活层代表选择（见 obstaclesNear）。
    private static func deduplicatedObstacles(_ obstacles: [WinCandidate]) -> [WinCandidate] {
        struct Signature: Hashable {
            let ownerName: String
            let title: String
            let layer: Int
            let bounds: CGRect
        }
        var seen = Set<Signature>()
        var deduplicated: [WinCandidate] = []
        for obstacle in obstacles.sorted(by: { $0.wid < $1.wid }) {
            guard seen.insert(Signature(
                ownerName: obstacle.ownerName,
                title: obstacle.title,
                layer: obstacle.layer,
                bounds: obstacle.bounds
            )).inserted else { continue }
            deduplicated.append(obstacle)
        }
        return deduplicated
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
