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
    let lastMaterialChangeAt: TimeInterval?
}

/// 可解释自适应跟随：纯函数 decide 驱动状态转换。
/// - 静止：低频，且不重复 setFrame
/// - 移动：升频，setFrame
/// - 稳定后：降频
/// - 隐藏：底座 + 详情隐藏，低频检测重现
/// - 重现：重捕，回到 moving
enum Follower {
    static let stableInterval: TimeInterval = 0.1       // 静止降频且 0.1s 内探测移动
    static let hiddenInterval: TimeInterval = 1.0       // 隐藏检测重现
    static let stationaryDuration: TimeInterval = 4.0 / 60.0

    /// 纯函数：`now` 与 `lastMaterialChangeAt` 均为同一单调时钟的秒数。
    /// stable 以连续静止时长判定，不受 60/120Hz 或可变刷新 callback 次数影响。
    static func decide(
        pet: CGRect?,
        lastPet: CGRect?,
        lastMaterialChangeAt: TimeInterval?,
        now: TimeInterval
    ) -> FollowDecision {
        // 无宠物 → 隐藏，低频检测重现
        guard let pet = pet else {
            return FollowDecision(state: .hidden, showDock: false, shouldSetFrame: false,
                                  lastMaterialChangeAt: nil)
        }
        // 实质变化（含首次捕获 / 重现）→ moving，升频，setFrame。
        // 位置变化用容差比较（吸收亚像素抖动）；尺寸变化不耐受，直接判变。
        if lastPet == nil || hasMaterialChange(pet, lastPet!) {
            return FollowDecision(state: .moving, showDock: true, shouldSetFrame: true,
                                  lastMaterialChangeAt: now)
        }
        // 位置不变：沿用最近一次实质变化时刻，按 elapsed time 判定稳定。
        let changedAt = lastMaterialChangeAt ?? now
        if now - changedAt >= stationaryDuration {
            // 已稳定 → 降频，不重复 setFrame
            return FollowDecision(state: .stable, showDock: true, shouldSetFrame: false,
                                  lastMaterialChangeAt: changedAt)
        }
        // 过渡期：仍 moving，但不 setFrame
        return FollowDecision(state: .moving, showDock: true, shouldSetFrame: false,
                              lastMaterialChangeAt: changedAt)
    }

    /// 是否发生实质变化：尺寸不同，或 origin 位移超过 `PetHeuristics.positionTolerance`。
    /// 位移用欧氏距离比较，吸收 Electron 渲染亚像素抖动（< 容差视为静止）。
    private static func hasMaterialChange(_ pet: CGRect, _ last: CGRect) -> Bool {
        if pet.width != last.width || pet.height != last.height { return true }
        let dx = pet.origin.x - last.origin.x, dy = pet.origin.y - last.origin.y
        return (dx * dx + dy * dy).squareRoot() > PetHeuristics.positionTolerance
    }
}
