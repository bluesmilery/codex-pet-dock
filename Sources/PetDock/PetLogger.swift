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
/// `enabled=false`（release 默认）时 `log()` 为 no-op，不创建/写任何文件。
final class PetLogger {
    private let enabled: Bool
    private let queue: DispatchQueue
    private let logURL: URL

    init(enabled: Bool = DebugLog.enabled,
         logURL: URL = URL(fileURLWithPath: "/tmp/petdock.log"),
         queue: DispatchQueue = DispatchQueue(label: "petdock.logger")) {
        self.enabled = enabled
        self.logURL = logURL
        self.queue = queue
    }

    /// 记录一行日志。release 默认 no-op；开启时异步写入后台队列（主线程无文件 IO）。
    func log(_ s: String) {
        guard enabled else { return }
        let line = "[\(s)]\n"
        guard let data = line.data(using: .utf8) else { return }
        let url = logURL
        queue.async {
            if FileManager.default.fileExists(atPath: url.path),
               let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile(); h.write(data); try? h.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}
