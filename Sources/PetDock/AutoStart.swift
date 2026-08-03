import Foundation
import ServiceManagement

/// 登录自启动：用**公开** `SMAppService.mainApp`（macOS 13+）注册 / 注销。
///
/// 设计原则：**失败可解释、绝不崩溃**。
/// - 命令行裸跑（非 `.app` bundle）时 `mainApp` 通常 `notFound`/`notRegistered`，属预期，
///   映射为「不可用」并给出可读原因；
/// - `SMAppService.Status` 是非 frozen 枚举，未来可能新增状态，`@unknown default` 兜底解释。
final class AutoStart {
    /// 对外状态：可用（开 / 关）或不可用（带可读原因）。
    enum Status: Equatable {
        case enabled
        case disabled
        case unavailable(String)
    }

    /// 把系统 `SMAppService.Status` 映射为对外可读状态（纯函数，便于测试）。
    static func explain(_ s: SMAppService.Status) -> Status {
        switch s {
        case .enabled:
            return .enabled
        case .notRegistered:
            return .disabled
        case .requiresApproval:
            return .unavailable("已注册，请在「系统设置 › 通用 › 登录项」中批准 PetDock")
        case .notFound:
            return .unavailable("找不到主应用 bundle（需作为 .app 运行，命令行裸跑不支持）")
        @unknown default:
            return .unavailable("登录启动当前不可用（未知的系统状态：\(s.rawValue)）")
        }
    }

    /// 查询当前状态。
    static func current() -> Status {
        explain(SMAppService.mainApp.status)
    }

    /// 开启 / 关闭登录启动。`register()`/`unregister()` 抛错时映射为「不可用」，不崩溃。
    /// 返回操作后的真实状态（而非请求的意图），供 UI 据实更新。
    static func set(enabled: Bool) -> Status {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            return .unavailable("登录启动操作失败：\(error.localizedDescription)")
        }
        return explain(service.status)
    }

    private init() {}
}
