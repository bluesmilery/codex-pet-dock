import Foundation

/// 一次跟随 tick 的纯决策层：把「该执行什么编排动作」从AppDelegate.tick 的副作用中剥离，
/// 使核心编排（数据 pause/resume、UI show/hide、候选为空、dockVisible）可纯函数测试。
/// 输入为只读快照，输出为互斥的动作信号；不触碰 UI / 数据 / timer。
///
/// 与 `Follower.decide`（决定频率与 setFrame）互补：
/// - Follower.decide：宠物几何 → 跟随状态机（hidden/moving/stable）。
/// - FollowTickPlan：跟随结果 → 编排动作（数据探测、UI 可见性）。
struct FollowTickInput {
    /// 本 tick 宠物是否可见（来自 Follower.showDock）。
    let petVisible: Bool
    /// 上一 tick 的宠物可见性（边沿触发用）。
    let wasPetVisible: Bool
    /// 用户「显示/隐藏底座」开关（settings.dockVisible）。用户隐藏只关 UI，不影响数据探测。
    let dockVisible: Bool
}

/// 纯决策输出（互斥动作信号）。执行层（AppDelegate.tick）只消费这些信号。
struct FollowTickPlan: Equatable {
    /// 数据探测 resume（petVisible false→true 边沿）：触发 provider.resume + refreshData。
    let resumeData: Bool
    /// 数据探测 pause（petVisible true→false 边沿）：触发 provider.pause + stopDataRefresh。
    let pauseData: Bool
    /// UI 可见 = 宠物可见 && 用户可见。执行层据此渲染 + 显示底座/详情。
    let showUI: Bool
    /// UI 需隐藏（宠物不可见 或 用户隐藏）。执行层据此隐藏底座 + 关详情。
    let hideUI: Bool
    /// 宠物消失（petVisible==false）：执行层据此清 lastPet/lastWID/bubbleProbe。
    let petDisappeared: Bool
}

/// 跟随 tick 编排纯决策。
enum FollowTickPlanner {
    /// 纯函数：根据快照决策编排动作。
    /// - 数据探测仅跟随宠物可见性（与用户是否隐藏 UI 解耦）。
    /// - UI 可见 = 宠物可见 && 用户可见；用户隐藏只关 UI，仍跟踪宠物。
    static func decide(input: FollowTickInput) -> FollowTickPlan {
        let resumeData = input.petVisible && !input.wasPetVisible     // false→true
        let pauseData = !input.petVisible && input.wasPetVisible      // true→false
        let showUI = input.petVisible && input.dockVisible
        return FollowTickPlan(
            resumeData: resumeData,
            pauseData: pauseData,
            showUI: showUI,
            hideUI: !showUI,
            petDisappeared: !input.petVisible
        )
    }
}
