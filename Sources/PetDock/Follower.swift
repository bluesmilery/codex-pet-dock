import Foundation

/// 跟随状态：决定轮询频率与是否 setFrame。
enum FollowState: String, Equatable {
    case hidden   // 无宠物窗口：低频检测重现
    case moving   // 宠物移动中：高频，需要 setFrame
    case stable   // 宠物静止：低频，不重复 setFrame
}

/// 一次跟随决策（纯函数输出，可测试、可记录）。
struct FollowDecision: Equatable {
    let state: FollowState
    let showDock: Bool          // 底座可见
    let shouldSetFrame: Bool    // 仅位置变化时 true，避免重复 setFrame
    let nextInterval: TimeInterval
    let stableCount: Int
}

/// 可解释自适应跟随：纯函数 decide 驱动状态转换。
/// - 静止：低频，且不重复 setFrame
/// - 移动：升频，setFrame
/// - 稳定后：降频
/// - 隐藏：底座 + 详情隐藏，低频检测重现
/// - 重现：重捕，回到 moving
enum Follower {
    static let movingInterval: TimeInterval = 0.05   // 移动升频
    static let stableInterval: TimeInterval = 0.5    // 静止降频
    static let hiddenInterval: TimeInterval = 1.0    // 隐藏检测重现
    static let stableThreshold: Int = 4              // 连续 N 次位置不变 → stable

    /// 纯函数：根据当前宠物窗口（Quartz 全局 rect，nil=不可见）、上次位置、状态、稳定计数，决策下一步。
    static func decide(pet: CGRect?, lastPet: CGRect?, state: FollowState, stableCount: Int) -> FollowDecision {
        // 无宠物 → 隐藏，低频检测重现
        guard let pet = pet else {
            return FollowDecision(state: .hidden, showDock: false, shouldSetFrame: false,
                                  nextInterval: hiddenInterval, stableCount: 0)
        }
        // 位置变化（含首次捕获 / 重现）→ moving，升频，setFrame
        if lastPet == nil || pet != lastPet! {
            return FollowDecision(state: .moving, showDock: true, shouldSetFrame: true,
                                  nextInterval: movingInterval, stableCount: 0)
        }
        // 位置不变：累加稳定计数
        let count = stableCount + 1
        if count >= stableThreshold {
            // 已稳定 → 降频，不重复 setFrame
            return FollowDecision(state: .stable, showDock: true, shouldSetFrame: false,
                                  nextInterval: stableInterval, stableCount: count)
        }
        // 过渡期：仍 moving，但不 setFrame
        return FollowDecision(state: .moving, showDock: true, shouldSetFrame: false,
                              nextInterval: movingInterval, stableCount: count)
    }
}
