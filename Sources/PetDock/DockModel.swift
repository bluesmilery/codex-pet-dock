import Foundation

/// 底座/详情的纯展示数据。业务字段可空（缺失时 UI 占位 "—"）。
/// 本结构仅承载展示快照，不直接读取数据源（由 LiveDockProvider 填充真实官方额度 / 本机 token）。
struct DockSnapshot {
    let weekLeft: String?        // 剩余额度，如 "73%"
    let weekTokens: String?      // 本周 token，如 "1.2M"
    let plan: String?            // 套餐
    let resetAt: String?         // 重置时间
    let cacheRatio: String?      // 缓存比例
    let inputTokens: String?     // 输入 token
    let outputTokens: String?    // 输出 token
    let sessionCount: Int?       // 会话数
    let updatedAt: String?       // 更新时间
    let localEstimateNote: String // 本机估算提示（说明数据性质，默认总有）

    /// 字段缺失时的统一占位符。
    static let placeholder = "—"

    /// 把可空字段渲染为「值或占位」。
    func rendered(_ s: String?) -> String { s ?? DockSnapshot.placeholder }

    /// 会话数渲染（Int? → String）。
    var sessionString: String {
        sessionCount.map { String($0) } ?? DockSnapshot.placeholder
    }
}

/// 展示数据来源接口。LiveDockProvider 提供真实数据（官方额度 + 本机 token）。
protocol DockModelProvider: AnyObject {
    func currentSnapshot() -> DockSnapshot
}
