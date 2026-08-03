import Foundation

// MARK: - 官方额度获取（WEEK LEFT）

/// 官方额度获取接口，便于注入 mock 测试。
protocol RateLimitFetching {
    func readWeekLeft() throws -> WeekLeft
}

/// 通过 `codex app-server`（stdio JSON-RPC）调用 `account/rateLimits/read` 获取官方周额度。
///
/// 合规边界：本类型**不读取 / 复制 auth.json、token、邮箱**；鉴权完全由 `codex` 进程在其
/// 可信环境内完成。本进程仅经 stdio 收发 JSON-RPC 文本，且只解析状态 / 比例 / 重置时间字段。
struct RateLimitClient: RateLimitFetching {
    /// 启动 codex app-server 的命令。默认经 login shell 以继承用户 PATH（nvm / homebrew 等）。
    let launchCommand: [String]
    /// 单次请求超时（秒）。
    let timeout: TimeInterval

    init(launchCommand: [String]? = nil, timeout: TimeInterval = 20) {
        self.launchCommand = launchCommand ?? ["/bin/sh", "-lc", "exec codex app-server"]
        self.timeout = timeout
    }

    func readWeekLeft() throws -> WeekLeft {
        let result = try rpc(method: "account/rateLimits/read", params: [:], id: 2)
        return try Self.parse(result)
    }

    /// 解析 `account/rateLimits/read` 的 result，提取脱敏字段。纯函数，便于用 fixture 测试。
    static func parse(_ result: Any) throws -> WeekLeft {
        guard let dict = result as? [String: Any],
              let rateLimits = dict["rateLimits"] as? [String: Any] else {
            throw DataError.msg("rateLimits 字段缺失")
        }
        let primary = rateLimits["primary"] as? [String: Any]
        let usedPercent = Self.asInt(primary?["usedPercent"]) ?? 0
        let windowMinutes = Self.asInt(primary?["windowDurationMins"])
        let resetsAt: Date? = {
            guard let s = Self.asInt64(primary?["resetsAt"]) else { return nil }
            return Date(timeIntervalSince1970: TimeInterval(s))
        }()
        let planType = rateLimits["planType"] as? String
        return WeekLeft(usedPercent: usedPercent, resetsAt: resetsAt,
                        windowMinutes: windowMinutes, planType: planType, fetchedAt: Date())
    }

    /// 兼容 JSON 反序列化的 NSNumber 与原生 Int/Int64。
    private static func asInt(_ x: Any?) -> Int? {
        if let n = x as? NSNumber { return n.intValue }
        return x as? Int
    }
    private static func asInt64(_ x: Any?) -> Int64? {
        if let n = x as? NSNumber { return n.int64Value }
        if let i = x as? Int { return Int64(i) }
        return x as? Int64
    }

    // MARK: - stdio JSON-RPC

    /// 发起一次「initialize 握手 → 目标请求」的 JSON-RPC 会话并返回目标 result。
    private func rpc(method: String, params: Any, id: Int) throws -> Any {
        guard launchCommand.count >= 1 else { throw DataError.msg("launchCommand 为空") }
        let proc = Process()
        proc.launchPath = launchCommand[0]
        proc.arguments = Array(launchCommand.dropFirst())
        let stdin = Pipe(), stdout = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = Pipe()   // 丢弃 app-server 自身日志

        let lock = NSLock()
        var responses: [Int: Any] = [:]
        let reader = LineReader(handle: stdout.fileHandleForReading) { line in
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rid = obj["id"] as? Int else { return }
            if let r = obj["result"] { lock.lock(); responses[rid] = r; lock.unlock() }
            else if let e = obj["error"] { lock.lock(); responses[rid] = e; lock.unlock() }
        }
        reader.start()

        try proc.run()
        defer {
            proc.terminate()
            reader.stop()
        }

        func send(_ obj: [String: Any]) throws {
            var d = obj
            if d["jsonrpc"] == nil { d["jsonrpc"] = "2.0" }
            let data = try JSONSerialization.data(withJSONObject: d)
            stdin.fileHandleForWriting.write(data)
            stdin.fileHandleForWriting.write(Data("\n".utf8))
        }

        // 1) 握手（experimentalApi=true：rate limits 属实验 API）
        try send(["id": 1, "method": "initialize",
                  "params": ["clientInfo": ["name": "PetDock", "version": "0.1"],
                             "capabilities": ["experimentalApi": true]]])
        guard Self.await(id: 1, in: &responses, lock: lock, timeout: timeout) != nil else {
            throw DataError.msg("app-server 握手超时")
        }
        try send(["method": "notifications/initialized"])

        // 2) 目标请求
        try send(["id": id, "method": method, "params": params])
        guard let res = Self.await(id: id, in: &responses, lock: lock, timeout: timeout) else {
            throw DataError.msg("app-server 无响应（超时 \(Int(timeout))s）")
        }
        if let err = res as? [String: Any], err["code"] != nil || err["message"] != nil {
            throw DataError.msg("app-server 错误：\(err["message"] ?? "?")")
        }
        return res
    }

    private static func await(id: Int, in bag: inout [Int: Any], lock: NSLock, timeout: TimeInterval) -> Any? {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            lock.lock(); let v = bag[id]; lock.unlock()
            if let v = v { return v }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return nil
    }
}

// MARK: - 管道逐行读取

/// 后台线程读取 FileHandle 并按换行切分回调，避免阻塞主流程。
final class LineReader {
    private let handle: FileHandle
    private let onLine: (String) -> Void
    private var thread: Thread?
    private var stopped = false

    init(handle: FileHandle, onLine: @escaping (String) -> Void) {
        self.handle = handle
        self.onLine = onLine
    }

    func start() {
        let t = Thread { [weak self] in self?.loop() }
        t.start()
        thread = t
    }

    private func loop() {
        var buffer = Data()
        while !stopped {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer[buffer.startIndex..<nl]
                buffer.removeSubrange(buffer.startIndex...nl)
                if let s = String(data: Data(lineData), encoding: .utf8), !s.isEmpty {
                    onLine(s)
                }
            }
        }
    }

    func stop() {
        stopped = true
        try? handle.close()
    }
}
