import Foundation

/// 运行时日志开关：DEBUG 构建默认开启文件日志，release 构建默认关闭（避免主线程高频同步 IO）。
/// `--verbose` 命令行参数可在 release 下显式开启（诊断用）。
enum DebugLog {
    static var enabled: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    /// 进程启动时按命令行参数覆盖（`--verbose` 强制开启）。仅调用一次。
    static func applyOverrides(arguments: [String]) {
        if arguments.contains("--verbose") { enabled = true }
    }
}

/// 后台异步文件日志：所有 IO 派发到串行后台队列，不阻塞主线程（tick 在 moving 态 20Hz 调用）。
/// 关闭时（release 默认）`log()` 为 no-op，不创建/写任何文件。
///
/// 句柄复用：文件句柄 lazy 打开后常驻于串行队列，不再每次写入都 open/close（accepted-deferred）。
/// 大小上限 / 轮转：累计写入超过 `maxBytes` 时，主文件滚动为 `.1` 轮转副本（单份，覆盖式），
/// 主文件重开为空继续写入，避免日志无限增长。
final class PetLogger {
    /// `nil` = 实时跟随共享开关 `DebugLog.enabled`（默认构造的行为，使 `--verbose`
    /// 能在 logger 创建后才 `applyOverrides` 生效）；显式传入 `true`/`false` 时固定。
    private let enabled: Bool?
    private let queue: DispatchQueue
    private let logURL: URL
    /// 轮转副本路径（主文件同目录 + `.1` 后缀）。单份轮转，每次滚动覆盖旧副本。
    private let rollURL: URL
    /// 日志大小上限（字节）。写入后若超过则触发一次轮转。0 表示不限制（仅句柄复用）。
    private let maxBytes: Int

    /// 队列私有状态：常驻文件句柄与已写字节数。仅在串行队列内访问，无需额外锁。
    private var handle: FileHandle?
    private var writtenBytes: Int64 = 0

    /// - parameter enabled: 传 `nil`（默认）让 `log()` 实时读取 `DebugLog.enabled`；
    ///   传固定值用于测试隔离。默认构造的 logger 须在 `applyOverrides` 之后生效，
    ///   故不在此快照 `DebugLog.enabled`。
    /// - parameter maxBytes: 日志大小上限（字节），超出后滚动一份 `.1` 副本；0 表示不限。
    init(enabled: Bool? = nil,
         logURL: URL? = nil,
         maxBytes: Int = 1_048_576,   // 1 MiB 默认上限
         queue: DispatchQueue = DispatchQueue(label: "petdock.logger")) {
        self.enabled = enabled
        let resolvedURL = logURL ?? PrivateStorage.logsURL.appendingPathComponent("petdock.log")
        self.logURL = resolvedURL
        self.rollURL = URL(fileURLWithPath: resolvedURL.path + ".1")
        self.maxBytes = maxBytes
        self.queue = queue
    }

    /// 记录一行日志。release 默认 no-op；开启时异步写入后台队列（主线程无文件 IO）。
    func log(_ s: String) {
        guard enabled ?? DebugLog.enabled else { return }
        let line = "[\(Self.redact(s))]\n"
        guard let data = line.data(using: .utf8) else { return }
        queue.async { [weak self] in
            self?.append(data)
        }
    }

    /// 同步落盘：等待所有已派发的日志写入磁盘并返回。测试隔离与确定性验证用；
    /// 运行模式不显式调用（进程退出由 deinit 关闭句柄，OS 保证已写数据落盘）。
    func flush() {
        queue.sync { /* barrier：等待队列中所有先前 async 完成 */ }
    }

    deinit {
        // 句柄所有权属于本 logger；析构时在串行队列上同步关闭，避免泄露句柄。
        // queue 闭包不捕获 self（仅引用属性快照），故 deinit 安全。
        let h = handle
        queue.sync {
            try? h?.close()
        }
    }

    // MARK: - 队列私有（仅在 self.queue 上调用）

    /// 追加并按需轮转。仅在串行队列内执行，故 handle/writtenBytes 无数据竞争。
    private func append(_ data: Data) {
        ensureHandle()
        handle?.write(data)
        writtenBytes &+= Int64(data.count)
        if maxBytes > 0 && writtenBytes >= Int64(maxBytes) {
            rotate()
        }
    }

    /// lazy 打开（或重新打开）常驻句柄。文件不存在时先创建空文件。
    private func ensureHandle() {
        if handle != nil { return }
        guard !PrivateStorage.isSymlink(logURL) else { return }
        // Read the existing size before the secure no-follow open.  A
        // symlink or non-regular file is rejected by the storage primitive.
        if FileManager.default.fileExists(atPath: logURL.path) {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: logURL.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else { return }
            writtenBytes = (try? FileManager.default.attributesOfItem(atPath: logURL.path)[.size] as? Int64) ?? 0
        }
        handle = try? PrivateStorage.openAppendFile(at: logURL)
    }

    /// 轮转：关闭当前句柄 → 旧主文件覆盖式重命名为 `.1` → 重置计数并重开空主文件。
    private func rotate() {
        try? handle?.synchronize()
        try? handle?.close()
        handle = nil
        // 覆盖旧副本（若存在）：先删再换，且只操作日志目录中的路径。
        try? FileManager.default.removeItem(at: rollURL)
        _ = try? FileManager.default.moveItem(at: logURL, to: rollURL)
        writtenBytes = 0
        ensureHandle()
    }

    /// Remove identifiers that can correlate a log line with a real window.
    /// The logger does not need to retain WID/PID values for operation.
    private static func redact(_ input: String) -> String {
        var value = input
        for pattern in [#"(?i)\bwid\s*=\s*\d+"#, #"(?i)\bpid\s*=\s*\d+"#] {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(value.startIndex..<value.endIndex, in: value)
                value = regex.stringByReplacingMatches(in: value, options: [], range: range,
                                                        withTemplate: "<redacted>")
            }
        }
        return value
    }
}
