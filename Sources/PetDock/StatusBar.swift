import Cocoa

/// 状态栏控制器：构建 `NSStatusItem` 菜单（主题选择 / 显示隐藏 / 登录启动 / 退出），
/// 通过 `Actions`（closure）把用户动作外发。自身**不**耦合 `DockPanel` / `Settings` / `AutoStart`——
/// 具体行为由集成层注入闭包实现，便于隔离与测试。
final class StatusBar: NSObject {
    /// 菜单动作外发契约。
    struct Actions {
        var onSelectTheme: (String) -> Void           // themeID
        var onToggleVisible: (Bool) -> Void           // true=显示, false=隐藏
        var onToggleLaunchAtLogin: (Bool) -> Void     // true=开启自启
        var onQuit: () -> Void
    }

    private let statusItem: NSStatusItem
    private var actions: Actions
    private(set) var themes: [ThemeSpec]
    private var currentThemeID: String
    private var dockVisible: Bool
    private var launchAtLogin: Bool

    init(themes: [ThemeSpec],
         currentThemeID: String,
         dockVisible: Bool,
         launchAtLogin: Bool,
         actions: Actions) {
        self.themes = themes
        self.currentThemeID = currentThemeID
        self.dockVisible = dockVisible
        self.launchAtLogin = launchAtLogin
        self.actions = actions
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        rebuildMenu()
    }

    /// 外部状态变化时，同步菜单勾选 / 标题。
    func updateThemes(_ themes: [ThemeSpec]) { self.themes = themes; rebuildMenu() }
    func updateThemeSelection(_ id: String) { currentThemeID = id; rebuildMenu() }
    func updateDockVisible(_ v: Bool) { dockVisible = v; rebuildMenu() }
    func updateLaunchAtLogin(_ v: Bool) { launchAtLogin = v; rebuildMenu() }

    // MARK: - 菜单动作（target/action）

    @objc private func selectTheme(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String else { return }
        actions.onSelectTheme(id)
    }
    @objc private func toggleVisible(_ item: NSMenuItem) {
        dockVisible.toggle()
        actions.onToggleVisible(dockVisible)
        rebuildMenu()
    }
    @objc private func toggleLaunchAtLogin(_ item: NSMenuItem) {
        launchAtLogin.toggle()
        actions.onToggleLaunchAtLogin(launchAtLogin)
        rebuildMenu()
    }
    @objc private func quit() { actions.onQuit() }

    // MARK: - 菜单构建

    func rebuildMenu() {
        let menu = NSMenu()

        // 主题选择（子菜单，当前主题打勾）
        let themeItem = NSMenuItem(title: "主题", action: nil, keyEquivalent: "")
        let themeMenu = NSMenu()
        for t in themes {
            let mi = NSMenuItem(title: t.displayName, action: #selector(selectTheme(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = t.id
            mi.state = (t.id == currentThemeID) ? .on : .off
            themeMenu.addItem(mi)
        }
        themeItem.submenu = themeMenu
        menu.addItem(themeItem)

        menu.addItem(.separator())

        // 显示 / 隐藏底座（标题随状态切换）
        let visItem = NSMenuItem(title: dockVisible ? "隐藏底座" : "显示底座",
                                 action: #selector(toggleVisible(_:)), keyEquivalent: "")
        visItem.target = self
        menu.addItem(visItem)

        // 登录时启动（带勾选）
        let lauItem = NSMenuItem(title: "登录时启动",
                                 action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        lauItem.target = self
        lauItem.state = launchAtLogin ? .on : .off
        menu.addItem(lauItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 PetDock", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.image = NSImage(systemSymbolName: "pawprint", accessibilityDescription: "PetDock")
    }
}
