import Foundation

// MARK: - 通用结果

/// 数据层错误（仅承载可读信息，绝不包含凭证或正文）。
struct DataError: Error, CustomStringConvertible {
    let message: String
    let underlying: Error?
    var description: String {
        if let u = underlying { return "\(message) (\(u))" }
        return message
    }
    static func msg(_ s: String) -> DataError { DataError(message: s, underlying: nil) }
}

/// 数据获取结果。
enum DataResult<T> {
    case success(T)
    case failure(DataError)
}

// MARK: - WEEK LEFT（官方周额度，脱敏）

/// WEEK LEFT：官方周额度。来自 codex app-server `account/rateLimits/read` 的 `primary` 窗口。
/// 仅承载状态 / 比例 / 重置时间，**不含任何凭证**。探测实证：primary 窗口 windowDurationMins=10080（7 天）。
struct WeekLeft {
    /// 周窗口已用百分比（primary.usedPercent，0-100）。
    let usedPercent: Int
    /// 剩余百分比 = 100 - usedPercent。
    var remainingPercent: Int { max(0, 100 - usedPercent) }
    /// 周窗口重置时间（primary.resetsAt，Unix 秒）。
    let resetsAt: Date?
    /// 窗口时长（分钟）；10080 = 7 天 = 周窗口。
    let windowMinutes: Int?
    /// 是否为周窗口。
    var isWeekly: Bool { (windowMinutes ?? 0) >= 10080 }
    /// 账户计划类型（free/go/plus/pro/prolite/team/...）。
    let planType: String?
    /// 抓取时间。
    let fetchedAt: Date
}

// MARK: - WEEK TOKENS（本机周统计）

/// WEEK TOKENS：本机本周累计 token。来自会话日志 Σ `last_token_usage.total_tokens`
/// （单次增量，已验证 Σ last = 会话累计，跨会话求和不重复）。**不含任何会话正文**。
struct WeekTokens {
    /// 窗口内累计 token。
    let totalTokens: Int64
    /// 统计窗口起（now - weekWindowDays）。
    let windowStart: Date
    /// 统计窗口止（now）。
    let windowEnd: Date
    /// 纳入统计的 event_msg 条数。
    let sampleCount: Int
    let fetchedAt: Date
}

/// 单条 token 增量：仅 timestamp + last_token_usage.total_tokens。不含正文，可安全缓存。
struct TokenUsagePoint: Codable, Equatable {
    let timestamp: Date
    let tokens: Int64
}

// MARK: - 退避（纯函数，便于测试）

/// 退避策略：成功→5min；连续失败 1/2/3+ → 15/30/60min。
enum Backoff {
    static let normalInterval: TimeInterval = 5 * 60

    static func nextDelay(afterFailures failures: Int) -> TimeInterval {
        switch failures {
        case 0:  return 5 * 60     // 正常 5 分钟
        case 1:  return 15 * 60    // 失败退避 15 分钟
        case 2:  return 30 * 60    // 失败退避 30 分钟
        default: return 60 * 60    // 持续失败 60 分钟
        }
    }
}
