import Foundation

/// 底座/详情的纯展示数据。业务字段可空（缺失时 UI 占位 "—"）。
/// 本阶段不读取真实额度/token，仅承载展示快照。
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

/// 展示数据来源接口。P1 用静态假数据演示；真实额度/token 读取属后续阶段，本阶段严禁实现。
protocol DockModelProvider: AnyObject {
    func currentSnapshot() -> DockSnapshot
}

/// 静态假数据 provider：演示 UI 与跟随，不触碰任何真实数据源。
final class StaticDockProvider: DockModelProvider {
    func currentSnapshot() -> DockSnapshot {
        DockSnapshot(
            weekLeft: "73%",
            weekTokens: "1.2M",
            plan: "Pro（演示）",
            resetAt: "2026-08-10 00:00",
            cacheRatio: "42%",
            inputTokens: "820K",
            outputTokens: "380K",
            sessionCount: 17,
            updatedAt: "—",
            localEstimateNote: "本机估算 · 演示数据（未读取真实额度）"
        )
    }

    /// 全缺失快照：演示「无数据」占位态。
    static func emptyDemo() -> DockSnapshot {
        DockSnapshot(weekLeft: nil, weekTokens: nil, plan: nil, resetAt: nil,
                     cacheRatio: nil, inputTokens: nil, outputTokens: nil,
                     sessionCount: nil, updatedAt: nil,
                     localEstimateNote: "本机估算 · 暂无数据")
    }
}
