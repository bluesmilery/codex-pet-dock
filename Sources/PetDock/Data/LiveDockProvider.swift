import Foundation

// MARK: - 真实数据 Provider：把 PetDockDataService 接到 DockModelProvider

/// 真实数据 Provider：桥接 `PetDockDataService`（WEEK LEFT / WEEK TOKENS）与展示层 `DockSnapshot`。
///
/// **主线程安全**：`currentSnapshot()` 同步返回**主线程缓存**（O(1)，不触发 IO）；真实抓取在
/// `refresh()` 内以全局队列异步进行（`RateLimitClient` 经 stdio JSON-RPC 可能阻塞数秒乃至超时，
/// 绝不在主线程调用），完成后切回主线程更新缓存并回调 `onUpdated`，由集成层重渲染 AppKit UI。
///
/// **占位策略**：单源失败时，该源对应字段为 nil（渲染为 `DockSnapshot.placeholder`「—」），
/// 另一源若成功仍正常展示；两源全失败亦仅全占位，绝不崩溃。
///
/// **退避 / 暂停**：刷新间隔与暂停语义直接转发 `PetDockDataService`（两源各自独立计数 / pause-resume）。
final class LiveDockProvider: DockModelProvider {
    private let service: PetDockDataService
    /// 仅在主线程读写的缓存快照（`currentSnapshot()` 直接返回它）。
    private var cached: DockSnapshot
    /// 主线程回调：缓存更新后通知集成层重渲染（由调用方管理生命周期）。
    var onUpdated: ((DockSnapshot) -> Void)?

    init(service: PetDockDataService) {
        self.service = service
        self.cached = LiveDockProvider.emptySnapshot
    }

    /// 同步返回缓存（主线程，O(1)，不阻塞）。
    func currentSnapshot() -> DockSnapshot { cached }

    /// 后台抓取两源 → 切回主线程更新缓存 + 回调。`completion` 恒在主线程调用一次。
    func refresh(completion: @escaping () -> Void = {}) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { DispatchQueue.main.async { completion() }; return }
            let left = self.service.fetchWeekLeft()
            let tokens = self.service.fetchWeekTokens()
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { completion(); return }
                self.cached = LiveDockProvider.buildSnapshot(left: left, tokens: tokens)
                self.onUpdated?(self.cached)
                completion()
            }
        }
    }

    // MARK: - 退避 / 暂停（转发 service）

    var weekLeftNextDelay: TimeInterval { service.weekLeftNextDelay }
    var weekTokensNextDelay: TimeInterval { service.weekTokensNextDelay }
    func pause() { service.pause() }
    func resume() { service.resume() }

    // MARK: - token 缓存落盘位置（Application Support，跨进程复用；失败兜底 nil）

    static func tokenCacheURL() -> URL? {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true) else { return nil }
        let dir = support.appendingPathComponent("PetDock", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("token-cache.json")
    }

    // MARK: - 映射（纯函数，可测）

    /// 把两源结果映射为展示快照。任一 `.failure` → 对应字段占位 nil；互不影响。
    /// 详情字段：非缓存输入=max(input-cached,0)；缓存比例=cached/input（分母 0 占位）；
    /// 输出=output；真实会话数=唯一会话文件数（非事件点数）。
    static func buildSnapshot(left: DataResult<WeekLeft>, tokens: DataResult<WeekTokens>) -> DockSnapshot {
        var wl: WeekLeft?
        if case .success(let v) = left { wl = v }
        var wt: WeekTokens?
        if case .success(let v) = tokens { wt = v }

        return DockSnapshot(
            weekLeft: wl.map { "\($0.remainingPercent)%" },
            weekTokens: wt.map { formatTokens($0.totalTokens) },
            plan: wl?.planType,
            resetAt: wl?.resetsAt.map { formatDateTime($0) },
            cacheRatio: wt.flatMap { w in
                // 缓存比例 = cached / input；分母 0 → nil（占位「—」）。
                w.inputTokens > 0 ? formatPercent(w.cachedInputTokens, of: w.inputTokens) : nil
            },
            inputTokens: wt.map { formatTokens(max($0.inputTokens - $0.cachedInputTokens, 0)) },
            outputTokens: wt.map { formatTokens($0.outputTokens) },
            sessionCount: wt?.sessionFileCount,
            updatedAt: (wl?.fetchedAt ?? wt?.fetchedAt).map { formatTime($0) },
            localEstimateNote: noteText(leftOk: wl != nil, tokensOk: wt != nil)
        )
    }

    /// 初始 / 全失败占位快照。
    static let emptySnapshot = DockSnapshot(
        weekLeft: nil, weekTokens: nil, plan: nil, resetAt: nil,
        cacheRatio: nil, inputTokens: nil, outputTokens: nil,
        sessionCount: nil, updatedAt: nil,
        localEstimateNote: "本机估算 · 暂无数据")

    private static func noteText(leftOk: Bool, tokensOk: Bool) -> String {
        // 始终说明数据性质：WEEK TOKENS 仅本机会话日志，非官方额度。
        switch (leftOk, tokensOk) {
        case (true, true):   return "LEFT 官方额度 · TOKENS 本机日志"
        case (true, false):  return "LEFT 官方额度 · TOKENS 暂不可用"
        case (false, true):  return "TOKENS 本机日志 · 官方额度暂不可用"
        case (false, false): return emptySnapshot.localEstimateNote
        }
    }

    // MARK: - 格式化（纯函数，可测）

    /// Token 数缩写：≥1e9→"X.XXB"，≥1e6→"X.XXM"，≥1e3→"X.XXK"，否则原值。
    static func formatTokens(_ n: Int64) -> String {
        let d = Double(n)
        if n >= 1_000_000_000 { return String(format: "%.2fB", d / 1e9) }
        if n >= 1_000_000 { return String(format: "%.2fM", d / 1e6) }
        if n >= 1_000 { return String(format: "%.1fK", d / 1e3) }
        return String(n)
    }

    /// 百分比（四舍五入到整数）：cached / whole。调用方保证 whole > 0。
    static func formatPercent(_ part: Int64, of whole: Int64) -> String {
        let p = Int((Double(part) / Double(whole) * 100).rounded())
        return "\(p)%"
    }

    /// 日期 + 时间（如 "08-10 00:00"）。
    static func formatDateTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: d)
    }

    /// 仅时间（如 "12:34"）。
    static func formatTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}
