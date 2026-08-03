import Foundation

// MARK: - 数据层顶层服务

/// 数据层顶层服务：组合「官方额度（WEEK LEFT）」+「本机 Token 统计（WEEK TOKENS）」，
/// 统一退避与暂停语义。纯接口——供集成层在宠物可见时驱动刷新、不可见时 `pause()`。
/// 本类不做 UI、不自行启动定时器（保持可测、可注入时钟）。
///
/// **线程安全**：所有可变状态（`isPaused` / 失败计数 / `tokenLog` 增量缓存）经同一 private
/// serial `queue` 序列化，且该队列由 `LiveDockProvider` 共用（保护 refreshInFlight / pending 等）。
/// - `fetchWeekLeft` 的官方额度 IO（codex app-server stdio，可能阻塞数秒）在 queue **外**执行，
///   避免阻塞 pause/resume/delay/currentSnapshot；
/// - `fetchWeekTokens` 的 `tokenLog`（维护 memCache）在 queue **内**执行以保护增量缓存。
final class PetDockDataService {
    private let rateLimit: RateLimitFetching
    private var tokenLog: TokenLogReading
    private let now: () -> Date

    /// 单一序列化队列：保护本类状态，并供 `LiveDockProvider` 共用。
    let queue = DispatchQueue(label: "petdock.data", qos: .utility)

    /// 受 queue 保护的状态（外部经计算属性同步读取）。
    private var weekLeftFailuresStorage = 0
    private var weekTokensFailuresStorage = 0
    private var isPausedStorage = false

    /// 连续失败计数（两数据源各自独立退避）。只读视图，经 queue 同步。
    var weekLeftFailures: Int { queue.sync { weekLeftFailuresStorage } }
    var weekTokensFailures: Int { queue.sync { weekTokensFailuresStorage } }
    /// 是否暂停（宠物不可见）。只读视图，经 queue 同步。
    var isPaused: Bool { queue.sync { isPausedStorage } }

    init(rateLimit: RateLimitFetching,
         tokenLog: TokenLogReading,
         now: @escaping () -> Date = Date.init) {
        self.rateLimit = rateLimit
        self.tokenLog = tokenLog
        self.now = now
    }

    // MARK: - WEEK LEFT

    /// 抓取官方周额度。成功重置失败计数；失败累计计数（驱动退避）。
    /// RateLimitClient 的 stdio IO 在 queue 外（数秒级），不阻塞队列上的 pause/delay。
    func fetchWeekLeft() -> DataResult<WeekLeft> {
        let paused = queue.sync { isPausedStorage }          // queue 内读（快）
        if paused { return .failure(DataError.msg("已暂停（宠物不可见）")) }
        do {
            let v = try rateLimit.readWeekLeft()             // queue 外：stdio JSON-RPC（数秒）
            queue.sync { weekLeftFailuresStorage = 0 }
            return .success(v)
        } catch {
            queue.sync { weekLeftFailuresStorage += 1 }
            return .failure(DataError(message: "WEEK LEFT 获取失败", underlying: error))
        }
    }

    /// WEEK LEFT 下次刷新间隔（依据连续失败次数退避）。
    var weekLeftNextDelay: TimeInterval { Backoff.nextDelay(afterFailures: weekLeftFailures) }

    // MARK: - WEEK TOKENS

    /// 抓取本机周累计 token。weekWindowDays：统计窗口天数（默认 7）。
    /// tokenLog 维护 memCache → 读取与计数更新在同一 queue 内（保护增量缓存）。
    func fetchWeekTokens(weekWindowDays: Int = 7) -> DataResult<WeekTokens> {
        let to = now()
        let from = to.addingTimeInterval(-Double(weekWindowDays) * 86_400)
        return queue.sync {
            if isPausedStorage { return DataResult<WeekTokens>.failure(DataError.msg("已暂停（宠物不可见）")) }
            do {
                let window = try tokenLog.readPoints(from: from, to: to)
                let pts = window.points
                weekTokensFailuresStorage = 0
                return .success(WeekTokens(
                    totalTokens: pts.reduce(Int64(0)) { $0 + $1.tokens },
                    inputTokens: pts.reduce(Int64(0)) { $0 + $1.input },
                    cachedInputTokens: pts.reduce(Int64(0)) { $0 + $1.cached },
                    outputTokens: pts.reduce(Int64(0)) { $0 + $1.output },
                    windowStart: from, windowEnd: to,
                    sampleCount: pts.count,
                    sessionFileCount: window.sessionFileCount,
                    fetchedAt: to))
            } catch {
                weekTokensFailuresStorage += 1
                return .failure(DataError(message: "WEEK TOKENS 获取失败", underlying: error))
            }
        }
    }

    /// WEEK TOKENS 下次刷新间隔。
    var weekTokensNextDelay: TimeInterval { Backoff.nextDelay(afterFailures: weekTokensFailures) }

    // MARK: - 暂停（宠物不可见）

    func pause() { queue.sync { isPausedStorage = true } }
    func resume() { queue.sync { isPausedStorage = false } }
}
