import Foundation

/// `UserDefaults` 薄封装：持久化产品外壳偏好（主题选择、显示详情、可见性等）。
///
/// - 依赖注入 `UserDefaults`（默认 `.standard`），测试可传临时 suite 隔离。
/// - `launchAtLogin` **不**在此持久化：真实状态以 `SMAppService` 为准（见 `AutoStart`），
///   避免双源不一致；状态栏开关直接反映 `AutoStart.current()`。
final class Settings {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    enum Key {
        static let themeID = "petdock.theme.id"
        static let showDetails = "petdock.ui.showDetails"
        static let dockVisible = "petdock.ui.dockVisible"
    }

    /// 当前主题 id；未设置时回落到内置默认（`Theme.defaultID`）。
    var themeID: String {
        get { defaults.string(forKey: Key.themeID) ?? Theme.defaultID }
        set { defaults.set(newValue, forKey: Key.themeID) }
    }

    /// 是否在底座上显示详情文字。
    var showDetails: Bool {
        get { defaults.object(forKey: Key.showDetails) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.showDetails) }
    }

    /// 底座可见性（用户主动显示/隐藏，重启后保持）。
    var dockVisible: Bool {
        get { defaults.object(forKey: Key.dockVisible) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.dockVisible) }
    }

    /// 清空本类管理的全部键（测试 / 调试用）。
    func reset() {
        for k in [Key.themeID, Key.showDetails, Key.dockVisible] {
            defaults.removeObject(forKey: k)
        }
    }
}
