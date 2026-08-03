import Cocoa

// MARK: - 颜色（数值契约，而非字符串）

/// 主题颜色：0~1 浮点分量。刻意用数值而非 CSS/十六进制字符串，
/// 从源头杜绝 `url(...)` / `expression(...)` 等可执行面。
struct ThemeColor: Equatable {
    let r: Double
    let g: Double
    let b: Double
    let a: Double

    init(r: Double, g: Double, b: Double, a: Double) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    var nsColor: NSColor {
        NSColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
    }

    /// 仅校验分量范围 ∈ [0,1]（纯函数，解析时复用）。
    static func valid(_ r: Double, _ g: Double, _ b: Double, _ a: Double) -> Bool {
        for v in [r, g, b, a] where v < 0 || v > 1 { return false }
        return true
    }
}

// MARK: - 字体白名单 token

/// 字体仅允许系统 token 白名单，拒绝任意字体名（防 shell / 路径注入）。
/// 具体渲染由集成层按 token 选择系统字体，主题层只保留语义。
enum ThemeFont: String, Equatable, CaseIterable {
    case system
    case rounded
    case monospace
}

// MARK: - 指标契约（同一语义 + 共享几何槽位）

/// 所有主题共享同一套「指标语义与几何槽位」：颜色随主题变化，几何尺寸一致。
/// 几何常量与 `DockPanel` 对齐——主题只换皮，不改变布局/尺寸。
struct ThemeMetrics: Equatable {
    let background: ThemeColor
    let accent: ThemeColor
    let label: ThemeColor
    let cornerRadius: Double
    let borderWidth: Double
    let font: ThemeFont

    /// 共享几何槽位（与 DockPanel 常量一致）。主题不得改变它。
    static let dockWidth: Double = 180
    static let dockHeight: Double = 30
    static let gap: Double = 2
}

/// 一个完整主题（内置程序化产物 / 外部 JSON 解析产物）。
struct ThemeSpec: Equatable {
    let id: String
    let displayName: String
    let metrics: ThemeMetrics
    let badge: NSImage?        // 可选徽标 PNG（与 JSON 同目录加载）
    let isBuiltin: Bool

    // NSImage 用 identity（===）比较，避免逐像素比较。
    static func == (lhs: ThemeSpec, rhs: ThemeSpec) -> Bool {
        lhs.id == rhs.id
            && lhs.displayName == rhs.displayName
            && lhs.metrics == rhs.metrics
            && lhs.isBuiltin == rhs.isBuiltin
            && lhs.badge === rhs.badge
    }
}

// MARK: - 内置程序化主题

/// 主题命名空间：3 款内置程序化主题，共享同一指标语义与几何槽位。
enum Theme {
    static let holographic = ThemeSpec(
        id: "builtin.holographic",
        displayName: "Holographic",
        metrics: ThemeMetrics(
            background: ThemeColor(r: 0.05, g: 0.15, b: 0.25, a: 0.55),
            accent: ThemeColor(r: 0.70, g: 0.30, b: 0.90, a: 1.0),
            label: ThemeColor(r: 0.70, g: 0.95, b: 1.00, a: 1.0),
            cornerRadius: 10, borderWidth: 1, font: .system),
        badge: nil, isBuiltin: true)

    static let warmGold = ThemeSpec(
        id: "builtin.warmGold",
        displayName: "Warm Gold",
        metrics: ThemeMetrics(
            background: ThemeColor(r: 0.12, g: 0.08, b: 0.04, a: 0.55),
            accent: ThemeColor(r: 0.95, g: 0.75, b: 0.25, a: 1.0),
            label: ThemeColor(r: 0.98, g: 0.90, b: 0.75, a: 1.0),
            cornerRadius: 8, borderWidth: 1, font: .rounded),
        badge: nil, isBuiltin: true)

    static let circuit = ThemeSpec(
        id: "builtin.circuit",
        displayName: "Circuit",
        metrics: ThemeMetrics(
            background: ThemeColor(r: 0.03, g: 0.06, b: 0.04, a: 0.55),
            accent: ThemeColor(r: 0.20, g: 0.90, b: 0.40, a: 1.0),
            label: ThemeColor(r: 0.60, g: 0.95, b: 0.70, a: 1.0),
            cornerRadius: 4, borderWidth: 1, font: .monospace),
        badge: nil, isBuiltin: true)

    /// 菜单展示顺序。
    static let builtins: [ThemeSpec] = [holographic, warmGold, circuit]

    /// 默认主题 id（首次运行 / 未设置时）。
    static let defaultID = holographic.id
}

// MARK: - 安全白名单契约

/// 把外部 JSON 主题安全地解析为 `ThemeSpec`。
///
/// **威胁模型**：主题来自 Application Support 的本地 JSON（用户/第三方可写）。
/// 本解析器在「字符串值」层全面收口，拒绝脚本 / CSS / JS / URL / 绝对路径 / 路径穿越 / 外部依赖：
/// - 颜色只接受 `[r,g,b,a]` 四个 0~1 数值，拒绝任何颜色字符串（`#hex` / `rgb()` / `url()`）；
/// - 字体只接受白名单 token（`system` / `rounded` / `monospace`）；
/// - 字符串 token 长度受限、不含 `/ \ : < > ( ) ' "` 与控制字符（: 挡住 URL scheme，/ \ 挡住路径，
///   < > 挡住标记，() 挡住函数调用）；
/// - 兜底扫描：任何 key / value 含 `http(s)://` `file://` `ftp://` `<script` `javascript:` `url(`
///   `import` `eval` `expression` → 整体拒绝；
/// - schema 扁平，拒绝嵌套对象（减少注入面）；
/// - 徽标文件名仅允许 `[A-Za-z0-9._-]+.png`，且不以 `.` 开头、不含 `..`（防路径穿越）。
///
/// 解析为纯函数（不读文件）：文件读取交给 `ThemeStore`，便于 fixture 测试。
enum ThemeManifest {
    static let maxNameLength = 32
    static let maxTokenLength = 64

    enum Error: Swift.Error, Equatable, CustomStringConvertible {
        case topShapeNotObject
        case dangerousKey(String)
        case dangerousValue(String)
        case nestedObjectForbidden(String)
        case nameInvalid
        case colorInvalid(String)
        case fontNotWhitelisted(String)
        case badgeInvalidName

        var description: String {
            switch self {
            case .topShapeNotObject: return "主题 JSON 顶层必须是对象"
            case .dangerousKey(let k): return "禁止的 key：\(k)"
            case .dangerousValue(let v): return "禁止的 value：\(v)"
            case .nestedObjectForbidden(let k): return "禁止嵌套对象：\(k)"
            case .nameInvalid: return "name 非法或过长"
            case .colorInvalid(let f): return "颜色字段非法（须 [r,g,b,a]∈[0,1]）：\(f)"
            case .fontNotWhitelisted(let f): return "字体不在白名单：\(f)"
            case .badgeInvalidName: return "徽标文件名非法（仅允许纯文件名 *.png）"
            }
        }
    }

    /// 单 token 安全校验（纯函数）。
    /// 拒绝：空 / 过长 / 含路径或 scheme 分隔符 / 含标记 / 含函数调用括号 / 含控制字符 / 命中危险关键字。
    static func isSafeToken(_ s: String) -> Bool {
        guard !s.isEmpty, s.count <= maxTokenLength else { return false }
        let banned: Set<Character> = ["/", "\\", ":", "<", ">", "(", ")", "\"", "'"]
        if s.contains(where: { banned.contains($0) }) { return false }
        if s.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) { return false }
        let lower = s.lowercased()
        let danger = ["http://", "https://", "file://", "ftp://",
                      "<script", "javascript:", "url(", "import ", "eval(", "expression("]
        if danger.contains(where: { lower.contains($0) }) { return false }
        return true
    }

    /// 徽标文件名校验：纯文件名 `*.png`，字符集受限，防 `.`/`..`/穿越。
    static func isSafeBadgeName(_ s: String) -> Bool {
        guard s.count <= maxTokenLength, s.lowercased().hasSuffix(".png") else { return false }
        let base = String(s.dropLast(4))
        guard !base.isEmpty, base != ".", base != ".." else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        return base.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// 解析 `[r,g,b,a]` → `ThemeColor`，分量必须 ∈ [0,1]（纯函数）。
    static func parseColor(_ raw: Any?) -> ThemeColor? {
        guard let arr = raw as? [Any], arr.count == 4 else { return nil }
        let nums = arr.compactMap { ($0 as? NSNumber)?.doubleValue }
        guard nums.count == 4 else { return nil }
        let (r, g, b, a) = (nums[0], nums[1], nums[2], nums[3])
        guard ThemeColor.valid(r, g, b, a) else { return nil }
        return ThemeColor(r: r, g: g, b: b, a: a)
    }

    /// 解析有界数值（纯函数）。
    static func parseNumber(_ raw: Any?, min lo: Double, max hi: Double) -> Double? {
        guard let n = (raw as? NSNumber)?.doubleValue else { return nil }
        return (n >= lo && n <= hi) ? n : nil
    }

    /// 深度扫描扁平字典的所有 key 与标量 value；命中危险模式返回首个错误。
    static func firstDangerous(in dict: [String: Any]) -> Error? {
        for (k, v) in dict {
            if !isSafeToken(k) { return .dangerousKey(k) }
            if let s = v as? String {
                if !isSafeToken(s) { return .dangerousValue("\(k)=\(s)") }
            } else if let arr = v as? [Any] {
                for (i, el) in arr.enumerated() {
                    if let nested = el as? [String: Any] { _ = nested; return .nestedObjectForbidden("\(k)[\(i)]") }
                    if let s = el as? String, !isSafeToken(s) { return .dangerousValue("\(k)[\(i)]=\(s)") }
                }
            } else if v is [String: Any] {
                return .nestedObjectForbidden(k)
            }
        }
        return nil
    }

    /// 解析主题 JSON。`badgeLoader` 注入：测试传 mock，运行时 `ThemeStore` 传真实文件加载。
    static func parse(jsonData data: Data,
                      id: String,
                      badgeLoader: (String) -> NSImage?) -> Result<ThemeSpec, Error> {
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: []),
              let dict = obj as? [String: Any] else {
            return .failure(.topShapeNotObject)
        }
        if let bad = firstDangerous(in: dict) { return .failure(bad) }

        guard let name = dict["name"] as? String,
              isSafeToken(name), name.count <= maxNameLength else {
            return .failure(.nameInvalid)
        }
        guard let bg = parseColor(dict["background"]) else { return .failure(.colorInvalid("background")) }
        guard let ac = parseColor(dict["accent"]) else { return .failure(.colorInvalid("accent")) }
        guard let lb = parseColor(dict["label"]) else { return .failure(.colorInvalid("label")) }

        let radius = parseNumber(dict["cornerRadius"], min: 0, max: 40) ?? 8
        let border = parseNumber(dict["borderWidth"], min: 0, max: 10) ?? 0

        let font: ThemeFont
        if let raw = dict["font"] as? String {
            guard isSafeToken(raw), let f = ThemeFont(rawValue: raw.lowercased()) else {
                return .failure(.fontNotWhitelisted(raw))
            }
            font = f
        } else {
            font = .system
        }

        var badge: NSImage?
        if let badgeName = dict["badge"] as? String {
            guard isSafeBadgeName(badgeName) else { return .failure(.badgeInvalidName) }
            badge = badgeLoader(badgeName)   // 缺失 PNG 不算错误（可选资源）
        }

        let metrics = ThemeMetrics(background: bg, accent: ac, label: lb,
                                   cornerRadius: radius, borderWidth: border, font: font)
        return .success(ThemeSpec(id: id, displayName: name, metrics: metrics,
                                  badge: badge, isBuiltin: false))
    }
}

// MARK: - Application Support 读取 + 热加载

/// 从 Application Support 读取外部主题 JSON（+ 同名 PNG），并在文件变化时热加载。
/// 主题目录：`~/Library/Application Support/PetDock/themes/*.json`。
///
/// 解析失败的条目被跳过（不中断整体）；目录监视失败时静默忽略——热加载是增强而非必需，
/// 不得让文件系统异常影响主流程。
final class ThemeStore {
    let directory: URL
    private var source: DispatchSourceFileSystemObject?
    private var fd: CInt = -1

    init(directory: URL? = nil) throws {
        if let dir = directory {
            self.directory = dir
        } else {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true)
            self.directory = support.appendingPathComponent("PetDock/themes", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    /// 扫描目录下所有 `*.json` 并解析（同名 `*.png` 作为徽标）。单条失败跳过。
    func loadAll() -> [ThemeSpec] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension.lowercased() == "json" }) else { return [] }
        return urls.compactMap { url -> ThemeSpec? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            let id = "user." + url.deletingPathExtension().lastPathComponent
            // 徽标只能来自 JSON 同目录、且文件名经 manifest 白名单校验。
            let badgeLoader: (String) -> NSImage? = { name in
                let png = url.deletingLastPathComponent().appendingPathComponent(name)
                return NSImage(contentsOf: png)
            }
            let result = ThemeManifest.parse(jsonData: data, id: id, badgeLoader: badgeLoader)
            return try? result.get()
        }
    }

    /// 热加载：监视目录的写入/删除/改名，回调最新主题列表（主线程）。
    /// 无法取得目录 fd 时静默跳过（不抛出）。
    func start(onChange: @escaping ([ThemeSpec]) -> Void) {
        stop()
        fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.delete, .write, .extend, .rename], queue: .main)
        src.setEventHandler { [weak self] in
            guard let self = self else { return }
            onChange(self.loadAll())
        }
        src.setCancelHandler { [fd = self.fd] in close(fd) }
        src.resume()
        source = src
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    deinit { stop() }
}
