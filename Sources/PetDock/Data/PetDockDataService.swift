import Foundation

// MARK: - 数据层顶层服务

/// 数据层顶层服务：组合「官方额度（WEEK LEFT）」+「本机 Token 统计（WEEK TOKENS）」，
/// 统一退避与暂停语义。纯接口——供未来 `main.swift` / 调度器在宠物可见时驱动刷新、
/// 不可见时 `pause()`。本类不做 UI、不自行启动定时器（保持可测、可注入时钟）。
final class PetDockDataService {
    private let rateLimit: RateLimitFetching
    private var tokenLog: TokenLogReading
    private let now: () -> Date

    /// 连续失败计数（两数据源各自独立退避）。
    private(set) var weekLeftFailures = 0
    private(set) var weekTokensFailures = 0

    /// 宠物不可见时由集成层调用 `pause()`；为 true 时刷新直接返回暂停错误。
    private(set) var isPaused = false

    init(rateLimit: RateLimitFetching,
         tokenLog: TokenLogReading,
         now: @escaping () -> Date = Date.init) {
        self.rateLimit = rateLimit
        self.tokenLog = tokenLog
        self.now = now
    }

    // MARK: - WEEK LEFT

    /// 抓取官方周额度。成功重置失败计数；失败累计计数（驱动退避）。
    func fetchWeekLeft() -> DataResult<WeekLeft> {
        guard !isPaused else { return .failure(DataError.msg("已暂停（宠物不可见）")) }
        do {
            let v = try rateLimit.readWeekLeft()
            weekLeftFailures = 0
            return .success(v)
        } catch {
            weekLeftFailures += 1
            return .failure(DataError(message: "WEEK LEFT 获取失败", underlying: error))
        }
    }

    /// WEEK LEFT 下次刷新间隔（依据连续失败次数退避）。
    var weekLeftNextDelay: TimeInterval { Backoff.nextDelay(afterFailures: weekLeftFailures) }

    // MARK: - WEEK TOKENS

    /// 抓取本机周累计 token。weekWindowDays：统计窗口天数（默认 7）。
    func fetchWeekTokens(weekWindowDays: Int = 7) -> DataResult<WeekTokens> {
        guard !isPaused else { return .failure(DataError.msg("已暂停（宠物不可见）")) }
        let to = now()
        let from = to.addingTimeInterval(-Double(weekWindowDays) * 86_400)
        do {
            // 协议要求非 mutating；底层 mutating 实现在 existential 副本上运行，
            // 增量缓存经落盘文件跨次 / 跨进程生效，进程内副本无需写回。
            let window = try tokenLog.readPoints(from: from, to: to)
            let pts = window.points
            weekTokensFailures = 0
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
            weekTokensFailures += 1
            return .failure(DataError(message: "WEEK TOKENS 获取失败", underlying: error))
        }
    }

    /// WEEK TOKENS 下次刷新间隔。
    var weekTokensNextDelay: TimeInterval { Backoff.nextDelay(afterFailures: weekTokensFailures) }

    // MARK: - 暂停（宠物不可见）

    func pause() { isPaused = true }
    func resume() { isPaused = false }
}
