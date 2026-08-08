import Cocoa
import ServiceManagement
import Foundation

// 产品外壳模块（Theme/Settings/ThemeStore/AutoStart）的纯函数 + fixture 测试。
// 文件名必须为 main.swift：Swift 仅允许 main.swift 含顶层可执行表达式（程序入口）。
// 编译：
//   swiftc tests/shell/main.swift \
//     Sources/PetDock/Theme.swift Sources/PetDock/Settings.swift Sources/PetDock/AutoStart.swift \
//     -framework Cocoa -framework ServiceManagement
// 无需屏幕录制权限、不启动 GUI；与 tests/main.swift 互不干扰（独立 main，分目录）。

var pass = 0, fail = 0
func check(_ desc: String, _ cond: Bool, _ extra: String = "") {
    print((cond ? "PASS" : "FAIL") + ": " + desc + (extra.isEmpty ? "" : "  | " + extra))
    if cond { pass += 1 } else { fail += 1 }
}
func mark(_ s: String) { print("\n--- \(s) ---") }

// ============ 内置主题 ============
mark("内置主题")
check("内置主题恰好 3 款", Theme.builtins.count == 3, "count=\(Theme.builtins.count)")
let ids = Set(Theme.builtins.map { $0.id })
check("内置主题 id 唯一", ids.count == Theme.builtins.count, "\(ids)")
check("含 holographic/warmGold/circuit",
      ids == ["builtin.holographic", "builtin.warmGold", "builtin.circuit"], "\(ids)")
check("全部 isBuiltin", Theme.builtins.allSatisfy { $0.isBuiltin })
check("defaultID 指向 holographic", Theme.defaultID == "builtin.holographic")
check("共享 dockWidth=200（与 DockPanel 一致）", ThemeMetrics.dockWidth == 200)
check("共享 dockHeight=48（与 DockPanel 一致）", ThemeMetrics.dockHeight == 48)
check("共享 gap=2", ThemeMetrics.gap == 2)
check("3 款背景 alpha 一致(0.55)", Theme.builtins.allSatisfy { abs($0.metrics.background.a - 0.55) < 1e-9 })
check("3 款颜色分量均 ∈[0,1]", Theme.builtins.allSatisfy {
    [$0.metrics.background, $0.metrics.accent, $0.metrics.label]
        .allSatisfy { ThemeColor.valid($0.r, $0.g, $0.b, $0.a) }
})
check("3 款 accent 与 background 不同色", Theme.builtins.allSatisfy {
    $0.metrics.accent != $0.metrics.background
})

// ============ ThemeColor.valid ============
mark("ThemeColor.valid")
check("0/1 边界合法", ThemeColor.valid(0, 0, 0, 0) && ThemeColor.valid(1, 1, 1, 1))
check("超出范围非法", !ThemeColor.valid(-0.1, 0, 0, 0) && !ThemeColor.valid(0, 0, 0, 1.1))

// ============ parseColor ============
mark("parseColor")
check("合法 4 数组→颜色", ThemeManifest.parseColor([0.1, 0.2, 0.3, 0.4]) != nil)
check("长度不足→nil", ThemeManifest.parseColor([0.1, 0.2, 0.3]) == nil)
check("超范围→nil", ThemeManifest.parseColor([0.1, 0.2, 0.3, 1.5]) == nil)
check("值正确", ThemeManifest.parseColor([0.1, 0.2, 0.3, 0.4]) == ThemeColor(r: 0.1, g: 0.2, b: 0.3, a: 0.4))

// ============ isSafeToken（安全白名单核心）============
mark("isSafeToken 白名单")
for t in ["Warm Gold", "system", "Circuit", "builtin.holographic", "主题", "a-b_1.2"] {
    check("合法 token: \(t)", ThemeManifest.isSafeToken(t))
}
let badTokens = ["http://x", "https://x", "file:///etc", "ftp://x",   // URL/外部依赖
                 "a/b", "a\\b",                                       // 路径分隔
                 "javascript:alert", "a:b",                           // scheme
                 "<script>", "a<b",                                   // 标记
                 "url(", "eval(", "expression(", "import x", "a(b)",  // 脚本/函数调用
                 "\"q\"", "'q'",                                      // 引号
                 "", String(repeating: "a", count: 65)]               // 空/超长
for t in badTokens { check("拒绝 token: \(t)", !ThemeManifest.isSafeToken(t)) }

// ============ isSafeBadgeName ============
mark("isSafeBadgeName")
for n in ["logo.png", "a-b_1.png", "Logo.PNG", "pet.dock.png"] {
    check("合法徽标名: \(n)", ThemeManifest.isSafeBadgeName(n))
}
let badBadges = ["logo.jpg", ".png", "..png",
                 "../x.png", "/abs/x.png", "C:\\x.png",
                 "a b.png", String(repeating: "a", count: 61) + ".png"]
for n in badBadges { check("拒绝徽标名: \(n)", !ThemeManifest.isSafeBadgeName(n)) }

// ============ ThemeManifest.parse 合法 ============
mark("parse 合法")
let okJSON = """
{"name":"My Theme","background":[0.1,0.2,0.3,0.4],"accent":[0.9,0.8,0.7,1.0],
 "label":[1.0,1.0,1.0,1.0],"cornerRadius":12,"borderWidth":2,"font":"rounded"}
""".data(using: .utf8)!
let okResult = ThemeManifest.parse(jsonData: okJSON, id: "user.test", badgeLoader: { _ in nil })
if case .success(let spec) = okResult {
    check("解析成功", true)
    check("id 透传", spec.id == "user.test")
    check("displayName 正确", spec.displayName == "My Theme")
    check("非内置", !spec.isBuiltin)
    check("cornerRadius 正确", spec.metrics.cornerRadius == 12)
    check("borderWidth 正确", spec.metrics.borderWidth == 2)
    check("font=rounded", spec.metrics.font == .rounded)
    check("颜色正确", spec.metrics.background == ThemeColor(r: 0.1, g: 0.2, b: 0.3, a: 0.4))
} else {
    check("解析成功（应成功却失败）", false, "\(okResult)")
}
let minimalJSON = "{\"name\":\"X\",\"background\":[0,0,0,0],\"accent\":[0,0,0,0],\"label\":[0,0,0,0]}".data(using: .utf8)!
if case .success(let spec) = ThemeManifest.parse(jsonData: minimalJSON, id: "u", badgeLoader: { _ in nil }) {
    check("cornerRadius 缺省→8", spec.metrics.cornerRadius == 8)
    check("borderWidth 缺省→0", spec.metrics.borderWidth == 0)
    check("font 缺省→system", spec.metrics.font == .system)
}

// ============ ThemeManifest.parse 拒绝 ============
mark("parse 拒绝")
func failCase(_ desc: String, json: String, expected: ThemeManifest.Error) {
    let res = ThemeManifest.parse(jsonData: json.data(using: .utf8)!, id: "u", badgeLoader: { _ in nil })
    if case .failure(let e) = res {
        check("\(desc) → \(expected)", e == expected, "got \(e)")
    } else {
        check("\(desc) → \(expected)（应失败却成功）", false)
    }
}
failCase("缺 name",
         json: "{\"background\":[0,0,0,0],\"accent\":[0,0,0,0],\"label\":[0,0,0,0]}",
         expected: .nameInvalid)
failCase("缺 background",
         json: "{\"name\":\"x\",\"accent\":[0,0,0,0],\"label\":[0,0,0,0]}",
         expected: .colorInvalid("background"))
failCase("name 含 http URL",
         json: "{\"name\":\"http://evil\",\"background\":[0,0,0,0],\"accent\":[0,0,0,0],\"label\":[0,0,0,0]}",
         expected: .dangerousValue("name=http://evil"))
failCase("嵌套对象",
         json: "{\"name\":\"x\",\"style\":{\"a\":1},\"background\":[0,0,0,0],\"accent\":[0,0,0,0],\"label\":[0,0,0,0]}",
         expected: .nestedObjectForbidden("style"))
failCase("font 非白名单",
         json: "{\"name\":\"x\",\"background\":[0,0,0,0],\"accent\":[0,0,0,0],\"label\":[0,0,0,0],\"font\":\"ComicSans\"}",
         expected: .fontNotWhitelisted("ComicSans"))
failCase("badge 非后缀",
         json: "{\"name\":\"x\",\"background\":[0,0,0,0],\"accent\":[0,0,0,0],\"label\":[0,0,0,0],\"badge\":\"x.jpg\"}",
         expected: .badgeInvalidName)
failCase("顶层非对象",
         json: "[1,2,3]",
         expected: .topShapeNotObject)

// ============ Settings 持久化 ============
mark("Settings 持久化")
let suite = "petdock.test.\(ProcessInfo.processInfo.processIdentifier)"
let ud = UserDefaults(suiteName: suite)!
let s = Settings(defaults: ud)
s.reset()
check("默认 themeID=内置默认", s.themeID == Theme.defaultID, s.themeID)
s.themeID = "builtin.circuit"
check("set/get themeID", s.themeID == "builtin.circuit")
ud.synchronize()
let ud2 = UserDefaults(suiteName: suite)!
check("持久化跨实例", Settings(defaults: ud2).themeID == "builtin.circuit")
check("默认 dockVisible=true", s.dockVisible == true)
s.dockVisible = false
check("set dockVisible=false", s.dockVisible == false)
s.reset()
check("reset→themeID 回落默认", s.themeID == Theme.defaultID)
UserDefaults().removePersistentDomain(forName: suite)

// ============ ThemeStore fixture 加载 ============
mark("ThemeStore fixture")
let tmp = FileManager.default.temporaryDirectory
    .appendingPathComponent("petdock-theme-test-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
try? FileManager.default.removeItem(at: tmp)
let store = try! ThemeStore(directory: tmp)
let jsonA = "{\"name\":\"User A\",\"background\":[0.1,0.1,0.1,0.5],\"accent\":[0.2,0.2,0.2,1],\"label\":[1,1,1,1]}"
let jsonB = "{\"name\":\"User B\",\"background\":[0,0,0,0.5],\"accent\":[1,0,0,1],\"label\":[1,1,1,1],\"badge\":\"mark.png\"}"
try! jsonA.data(using: .utf8)!.write(to: tmp.appendingPathComponent("a.json"))
try! jsonB.data(using: .utf8)!.write(to: tmp.appendingPathComponent("b.json"))
try! "{\"name\":\"Bad\"}".data(using: .utf8)!.write(to: tmp.appendingPathComponent("c.json"))

let pngOK: Bool = {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 4, bitsPerPixel: 32) else { return false }
    rep.setColor(NSColor(red: 1, green: 0, blue: 0, alpha: 1), atX: 0, y: 0)
    guard let data = rep.representation(using: .png, properties: [:]) else { return false }
    do { try data.write(to: tmp.appendingPathComponent("mark.png")); return true } catch { return false }
}()
check("生成并写入 mark.png", pngOK, pngOK ? "" : "PNG 生成失败（后续走缺失分支）")

let loaded = store.loadAll()
check("加载 2 个合法主题(非法跳过)", loaded.count == 2, "count=\(loaded.count)")
check("id 带 user. 前缀",
      loaded.contains { $0.id == "user.a" } && loaded.contains { $0.id == "user.b" })
let aSpec = loaded.first { $0.id == "user.a" }
check("主题 a 无 badge 字段→badge nil", aSpec?.badge == nil)
let bSpec = loaded.first { $0.id == "user.b" }
if pngOK {
    check("主题 b 的 badge PNG 已加载", bSpec?.badge != nil)
} else {
    check("主题 b 缺 PNG 时不报错且 badge nil", bSpec?.badge == nil)
}
try? FileManager.default.removeItem(at: tmp)

// ============ AutoStart 状态映射（纯函数）+ 不崩 ============
mark("AutoStart")
check("enabled → enabled", AutoStart.explain(.enabled) == .enabled)
check("notRegistered → disabled", AutoStart.explain(.notRegistered) == .disabled)
if case .unavailable(let msg) = AutoStart.explain(.requiresApproval) {
    check("requiresApproval → unavailable(含'批准')", msg.contains("批准"), msg)
} else {
    check("requiresApproval → unavailable", false)
}
if case .unavailable(let msg) = AutoStart.explain(.notFound) {
    check("notFound → unavailable(含'bundle')", msg.contains("bundle"), msg)
} else {
    check("notFound → unavailable", false)
}
let cur = AutoStart.current()
check("current() 返回状态且不崩", true, "\(cur)")
_ = AutoStart.set(enabled: true)
_ = AutoStart.set(enabled: false)
check("set(true)/set(false) 均不崩", true)

// ============ StatusBar TCC 权限降级提示 ============
mark("StatusBar TCC 提示")
let _ = NSApplication.shared   // NSStatusBar 需 NSApp
let sb = StatusBar(
    themes: Theme.builtins,
    currentThemeID: Theme.defaultID,
    dockVisible: true,
    launchAtLogin: false,
    actions: StatusBar.Actions(
        onSelectTheme: { _ in }, onToggleVisible: { _ in },
        onToggleLaunchAtLogin: { _ in }, onQuit: {}))
// 默认无权限提示
check("SB1 默认无 TCC 提示项", !sb.menuItemTitlesForTesting.contains { $0.contains("屏幕录制权限") },
      "items=\(sb.menuItemTitlesForTesting)")
// 开启提示 → 菜单顶部出现提示项
sb.updatePermissionWarning(true)
check("SB2 开启→菜单含 TCC 提示项", sb.menuItemTitlesForTesting.contains { $0.contains("屏幕录制权限") },
      "items=\(sb.menuItemTitlesForTesting)")
// 提示项在顶部（第一项）
check("SB3 TCC 提示项在菜单顶部", sb.menuItemTitlesForTesting.first?.contains("屏幕录制权限") ?? false,
      "first=\(sb.menuItemTitlesForTesting.first ?? "nil")")
// 关闭提示 → 消失
sb.updatePermissionWarning(false)
check("SB4 关闭→TCC 提示项消失", !sb.menuItemTitlesForTesting.contains { $0.contains("屏幕录制权限") },
      "items=\(sb.menuItemTitlesForTesting)")

print("\n[Shell: Theme/Settings/Store/AutoStart/StatusBar] \(pass) passed, \(fail) failed")
exit(fail == 0 ? 0 : 1)
