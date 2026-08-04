import Cocoa

/// 宠物窗口识别阈值（候选，与 docs/pet-window-detection.md 对应，待真实数据校准）。
enum PetHeuristics {
    static let mainMinArea: CGFloat = 150_000   // 主聊天窗口面积下限
    static let mainMinSide: CGFloat = 400       // 主窗口最大边下限
    static let petMaxArea: CGFloat = 70_000     // 宠物面积上限
    static let petMaxSide: CGFloat = 300        // 宠物最大边上限
    static let petMinSide: CGFloat = 50         // 宠物最小边下限（排除 18x6 等细长 / 过小辅助控件）
}

/// 一个可观测的窗口候选（来自 CGWindowList）。
struct WinCandidate {
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

    /// R1：通过 bundle id 拿 codex 主进程 PID 集合。
    /// Electron 的 helper 是否纳入，取决于诊断实测（见 docs）。
    static func codexPIDs() -> [Int32] {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        return apps.map { $0.processIdentifier }.filter { $0 != 0 }
    }

    /// R1+R2：按 PID 集合枚举窗口。
    static func enumerate(pids: [Int32]) -> [WinCandidate] {
        let pidSet = Set(pids)
        guard let infos = CGWindowListCopyWindowInfo([], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return infos.compactMap { dict -> WinCandidate? in
            guard let c = parse(dict) else { return nil }
            return pidSet.contains(c.ownerPID) ? c : nil
        }
    }

    /// 扩展通道（诊断用）：按 ownerName 包含关系枚举，用于发现 Electron helper 归属的窗口。
    static func enumerateByOwnerName(_ names: [String]) -> [WinCandidate] {
        guard let infos = CGWindowListCopyWindowInfo([], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return infos.compactMap { dict -> WinCandidate? in
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
    static func unionCandidates() -> [WinCandidate] {
        let byPID = enumerate(pids: codexPIDs())
        let byName = enumerateByOwnerName(["Chat", "GPT", "Codex", "OpenAI"])
        var seen = Set<CGWindowID>()
        var merged: [WinCandidate] = []
        for w in byPID + byName where !seen.contains(w.wid) {
            seen.insert(w.wid); merged.append(w)
        }
        return merged
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
