import Foundation

// MARK: - codex 可执行文件路径解析（不依赖交互式 shell）

/// 解析 codex 可执行文件绝对路径，**不依赖交互式 shell**。
///
/// 背景：.app 由 launchd 启动，进程环境 PATH 为 launchd 默认（不含 nvm），且非交互式 shell
/// 不读 `~/.zshrc`（nvm 通常配在此）。故 `/bin/sh -lc "exec codex"` 在 .app 内找不到 codex。
/// 本类型用文件系统查找替代 shell PATH 解析。
///
/// 顺序：
/// 1. 环境覆盖 `CODEX_PET_DOCK_CODEX_PATH`（必须是可执行普通文件，否则报错**不回退**）；
/// 2. 当前 `PATH` 各目录；
/// 3. 用户目录常见位置（`~/.local/bin`、`~/.nvm/versions/node/*/bin`、`~/.volta/bin`）
///    及 brew（`/opt/homebrew/bin`、`/usr/local/bin`）；nvm 多版本按语义版本降序取最新。
///
/// 仅返回文件系统路径（**非凭证**）；不读取 auth.json / 正文。
struct CodexExecutableResolver {
    /// 用户可用此环境变量显式指定 codex 绝对路径（最高优先级）。
    static let envOverride = "CODEX_PET_DOCK_CODEX_PATH"

    let environment: [String: String]
    let homeDirectory: URL
    let fileManager: FileManager

    init(environment: [String: String] = ProcessInfo.processInfo.environment,
         homeDirectory: URL? = nil,
         fileManager: FileManager = .default) {
        self.environment = environment
        self.homeDirectory = homeDirectory ?? FileManager.default.homeDirectoryForCurrentUser
        self.fileManager = fileManager
    }

    /// 解析 codex 可执行文件路径。
    func resolve() -> Result<URL, CodexResolveError> {
        // 1) 环境覆盖：显式指定则必须可用，不回退（避免错误路径被静默忽略）。
        if let raw = environment[Self.envOverride]?.trimmingCharacters(in: .whitespaces), !raw.isEmpty {
            let url = URL(fileURLWithPath: raw)
            if isExecutableFile(url) { return .success(url) }
            return .failure(.overrideNotExecutable(path: raw))
        }
        // 2) 当前 PATH 各目录。
        if let path = environment["PATH"] {
            for dir in path.split(separator: ":") {
                let cand = URL(fileURLWithPath: String(dir)).appendingPathComponent("codex")
                if isExecutableFile(cand) { return .success(cand) }
            }
        }
        // 3) 常见位置（nvm 多版本降序优先最新）。
        for cand in candidateLocations() where isExecutableFile(cand) {
            return .success(cand)
        }
        return .failure(.notFound)
    }

    /// 候选位置（顺序即优先级；nvm 展开多版本并按语义版本降序）。
    func candidateLocations() -> [URL] {
        var locs: [URL] = [homeDirectory.appendingPathComponent(".local/bin/codex")]
        let nvmRoot = homeDirectory.appendingPathComponent(".nvm/versions/node")
        if let versions = try? fileManager.contentsOfDirectory(atPath: nvmRoot.path) {
            for v in versions.sorted(by: { Self.compareVersion($0, $1) > 0 }) {
                locs.append(nvmRoot.appendingPathComponent("\(v)/bin/codex"))
            }
        }
        locs.append(homeDirectory.appendingPathComponent(".volta/bin/codex"))
        locs.append(URL(fileURLWithPath: "/opt/homebrew/bin/codex"))
        locs.append(URL(fileURLWithPath: "/usr/local/bin/codex"))
        return locs
    }

    /// 是否为可执行普通文件（存在、非目录、有可执行权限）。
    func isExecutableFile(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { return false }
        return fileManager.isExecutableFile(atPath: url.path)
    }

    /// 语义版本键（"v22.21.1" / "22.21.1" → [22,21,1]）。
    static func versionKey(_ s: String) -> [Int] {
        s.split(separator: ".").compactMap { Int($0.drop(while: { !$0.isNumber })) }
    }

    /// 版本降序比较（>0 表示 a 更新）；按数字段字典序，nvm 多版本稳定排序。
    static func compareVersion(_ a: String, _ b: String) -> Int {
        let ka = versionKey(a), kb = versionKey(b)
        for i in 0..<min(ka.count, kb.count) {
            if ka[i] != kb[i] { return ka[i] - kb[i] }
        }
        return ka.count - kb.count
    }
}

/// codex 路径解析失败（可解释错误，不含凭证）。
enum CodexResolveError: Error, CustomStringConvertible {
    case overrideNotExecutable(path: String)
    case notFound
    var description: String {
        switch self {
        case .overrideNotExecutable(let p):
            return "环境变量 \(CodexExecutableResolver.envOverride) 指定的路径不是可执行普通文件：\(p)"
        case .notFound:
            return "PATH 与常见位置（~/.local/bin、~/.nvm/versions/node/*/bin、~/.volta/bin、/opt/homebrew/bin、/usr/local/bin）均未找到 codex"
        }
    }
}
