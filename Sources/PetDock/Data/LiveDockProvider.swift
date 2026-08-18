import Foundation

// MARK: - 真实数据 Provider：把 PetDockDataService 接到 DockModelProvider

/// 真实数据 Provider：桥接 `PetDockDataService`（WEEK LEFT / WEEK TOKENS）与展示层 `DockSnapshot`。
///
/// **线程安全（单一 serial queue）**：所有共享状态——`cached` 快照、`refreshInFlight`、
/// `hasPending` / `pendingCompletions`、`isStopped`——与 `PetDockDataService` 共用**同一** private
/// serial queue（`service.queue`）。慢 IO（RateLimitClient stdio）在 queue 外执行，不阻塞主线程的
/// `currentSnapshot()` / pause / delay 读取。
///
/// **refresh 合并**：刷新在途（`refreshInFlight`）时，新请求仅置 `hasPending` 并缓存其 completion，
/// 不再发起并发抓取（`maxConcurrent == 1`）；在途完成后若有 pending，则发起一次「最终刷新」并补发
/// 所有 pending 的 completion。`stop()`（quit）后拒绝任何新刷新，在途任务完成时不再有 UI 副作用。
///
/// **占位策略**：单源失败时该源字段为 nil（渲染为 `DockSnapshot.placeholder`「—」），另一源仍正常展示。
final class LiveDockProvider: DockModelProvider {
    private let service: PetDockDataService
    /// 经 queue 保护的缓存快照。
    private var cached: DockSnapshot
    /// 经 queue 保护的刷新控制状态。
    private var refreshInFlight = false
    private var hasPending = false
    private var pendingCompletions: [() -> Void] = []
    private var isStopped = false
    /// 主线程回调：缓存更新后通知集成层重渲染（由调用方管理生命周期）。
    var onUpdated: ((DockSnapshot) -> Void)?

    init(service: PetDockDataService) {
        self.service = service
        self.cached = LiveDockProvider.emptySnapshot
    }

    /// 与 service 共用的单一 serial queue。
    private var queue: DispatchQueue { service.queue }

    /// 同步返回缓存（经 queue，O(1)；不触发 IO，不阻塞于慢额度抓取）。
    func currentSnapshot() -> DockSnapshot { queue.sync { cached } }

    /// 后台抓取两源 → 经 queue 提交缓存 → 切回主线程回调。`completion` 恒在主线程调用一次。
    /// 在途时合并为 pending（保证 maxConcurrent==1）。
    func refresh(completion: @escaping () -> Void = {}) {
        queue.async { [weak self] in
            guard let self else { return }
            if self.isStopped { self.onMain(completion); return }
            if self.refreshInFlight {
                self.hasPending = true
                self.pendingCompletions.append(completion)
                return
            }
            self.refreshInFlight = true
            self.startFetch(completion: completion)
        }
    }

    /// 停止：拒绝后续刷新；在途任务完成时不再有 UI 副作用；终止在途 codex 子进程不留孤儿。供 quit 调用。
    func stop() {
        queue.sync { isStopped = true }
        service.cancelInFlight()
    }

    /// 执行一次抓取（慢 IO 在 queue 外）并在 queue 内提交结果 / 处理 pending。
    private func startFetch(completion: @escaping () -> Void) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            // service.fetch* 各自内部 queue.sync（本线程为 global，非 queue 线程 → 不嵌套死锁）。
            let left = self.service.fetchWeekLeft()
            let tokens = self.service.fetchWeekTokens()
            self.queue.async { [weak self] in
                guard let self else { return }
                let stopped = self.isStopped
                self.cached = LiveDockProvider.buildSnapshot(left: left, tokens: tokens)
                let snap = self.cached
                let pending = self.hasPending
                let pendings = self.pendingCompletions
                self.hasPending = false
                self.pendingCompletions.removeAll()
                self.refreshInFlight = false
                self.onMain {
                    if !stopped { self.onUpdated?(snap) }
                    completion()
                    pendings.forEach { $0() }   // 补发所有 pending 的 completion
                }
                // pending 最终刷新（在途期间数据可能已变）；仍在 queue 线程，refresh 内为 async 不嵌套。
                if pending && !stopped { self.refresh(completion: {}) }
            }
        }
    }

    /// 在主线程执行 block（已是主线程则直执）。
    private func onMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
    }

    // MARK: - 退避 / 暂停（转发 service）

    var weekLeftNextDelay: TimeInterval { service.weekLeftNextDelay }
    var weekTokensNextDelay: TimeInterval { service.weekTokensNextDelay }
    func pause() { service.pause() }
    func resume() { service.resume() }

    // MARK: - token 缓存落盘位置（Application Support，跨进程复用；失败兜底 nil）

    static func tokenCacheURL() -> URL? {
        guard (try? PrivateStorage.ensureLayout()) != nil else { return nil }
        return PrivateStorage.tokenCacheURL
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

    /// 日期 + 时间（如 "08-10 00:00"）。显式本机时区（.current）。
    static func formatDateTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: d)
    }

    /// 仅时间（如 "12:34"）。显式本机时区（.current）。
    static func formatTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}
