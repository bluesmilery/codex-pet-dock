import Foundation

// MARK: - 官方额度获取（WEEK LEFT）

/// 官方额度获取接口，便于注入 mock 测试。
protocol RateLimitFetching {
    func readWeekLeft() throws -> WeekLeft
    /// 取消当前在途请求（quit 时调用），终止 codex 子进程避免孤儿。mock 可空实现。
    func cancel()
}

/// 通过 `codex app-server`（stdio JSON-RPC）调用 `account/rateLimits/read` 获取官方周额度。
///
/// 合规边界：本类型**不读取 / 复制 auth.json、token、邮箱**；鉴权完全由 `codex` 进程在其
/// 可信环境内完成。本进程仅经 stdio 收发 JSON-RPC 文本，且只解析状态 / 比例 / 重置时间字段。
///
/// 健壮性：
/// - `cancel()` 经内部锁置取消标志并 `terminate` 当前 codex 子进程，`rpc` 的等待循环检测到后
///   立即抛错，quit 时不留孤儿进程；
/// - `proc.run()` 启动失败抛 Swift error（由上层 catch）；`stdin` 写入用 `try?` 忽略管道破裂，
///   进程提前退出时快速失败，**不崩**；
/// - 结束时仅 `isRunning` 才 `terminate` + `waitUntilExit`，回收子进程。
final class RateLimitClient: RateLimitFetching {
    /// 启动 codex app-server 的命令。默认经 login shell 以继承用户 PATH（nvm / homebrew 等）。
    let launchCommand: [String]
    /// 单次请求超时（秒）。
    let timeout: TimeInterval

    private let lock = NSLock()
    private var currentProc: Process?
    private var cancelled = false

    init(launchCommand: [String]? = nil, timeout: TimeInterval = 20) {
        self.launchCommand = launchCommand ?? ["/bin/sh", "-lc", "exec codex app-server"]
        self.timeout = timeout
    }

    func readWeekLeft() throws -> WeekLeft {
        let result = try rpc(method: "account/rateLimits/read", params: [:], id: 2)
        return try Self.parse(result)
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let p = currentProc
        lock.unlock()
        if let p = p, p.isRunning { p.terminate() }
    }

    // MARK: - 解析（纯函数，便于 fixture 测试）

    /// 解析 `account/rateLimits/read` 的 result，提取脱敏字段。
    /// 窗口选择：从所有 snapshot 的 primary/secondary 中取 `windowDurationMins` 最接近 10080（周）者；
    /// 均无 `windowDurationMins` 时兜底 primary。`resetsAt` 兼容秒（10 位）与毫秒（13 位）。
    static func parse(_ result: Any) throws -> WeekLeft {
        guard let dict = result as? [String: Any],
              let rateLimits = dict["rateLimits"] as? [String: Any] else {
            throw DataError.msg("rateLimits 字段缺失")
        }
        let window = pickWeeklyWindow(rateLimits)
        let usedPercent = asInt(window?["usedPercent"]) ?? 0
        let windowMinutes = asInt(window?["windowDurationMins"])
        let resetsAt: Date? = {
            guard let raw = asInt64(window?["resetsAt"]) else { return nil }
            var secs = raw
            if secs > 1_000_000_000_000 { secs /= 1000 }   // 毫秒（13 位）→ 秒
            return Date(timeIntervalSince1970: TimeInterval(secs))
        }()
        let planType = rateLimits["planType"] as? String
        return WeekLeft(usedPercent: usedPercent, resetsAt: resetsAt,
                        windowMinutes: windowMinutes, planType: planType, fetchedAt: Date())
    }

    /// 从顶层 primary/secondary 及 `rateLimitsByLimitId` 各桶的 primary/secondary 中，
    /// 选 `windowDurationMins` 最接近 10080（一周）的窗口；若无该字段则兜底顶层 primary。
    static func pickWeeklyWindow(_ rateLimits: [String: Any]) -> [String: Any]? {
        var candidates: [[String: Any]] = []
        if let p = rateLimits["primary"] as? [String: Any] { candidates.append(p) }
        if let s = rateLimits["secondary"] as? [String: Any] { candidates.append(s) }
        if let byId = rateLimits["rateLimitsByLimitId"] as? [String: Any] {
            for v in byId.values {
                guard let snap = v as? [String: Any] else { continue }
                if let p = snap["primary"] as? [String: Any] { candidates.append(p) }
                if let s = snap["secondary"] as? [String: Any] { candidates.append(s) }
            }
        }
        let withMins = candidates.filter { asInt($0["windowDurationMins"]) != nil }
        if withMins.isEmpty { return rateLimits["primary"] as? [String: Any] }   // 单窗兜底
        return withMins.min { lhs, rhs in
            abs((asInt(lhs["windowDurationMins"]) ?? 0) - 10080)
                < abs((asInt(rhs["windowDurationMins"]) ?? 0) - 10080)
        }
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

        let bagLock = NSLock()
        var responses: [Int: Any] = [:]
        let reader = LineReader(handle: stdout.fileHandleForReading) { line in
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rid = obj["id"] as? Int else { return }
            if let r = obj["result"] { bagLock.lock(); responses[rid] = r; bagLock.unlock() }
            else if let e = obj["error"] { bagLock.lock(); responses[rid] = e; bagLock.unlock() }
        }
        reader.start()

        lock.lock(); cancelled = false; currentProc = proc; lock.unlock()

        try proc.run()   // 启动失败抛 Swift error，由上层 catch，不崩
        defer {
            reader.stop()
            if proc.isRunning { proc.terminate(); proc.waitUntilExit() }   // 仅在运行时回收
            lock.lock(); if currentProc === proc { currentProc = nil }; lock.unlock()
        }

        // 1) 握手（experimentalApi=true：rate limits 属实验 API）
        send(["id": 1, "method": "initialize",
              "params": ["clientInfo": ["name": "PetDock", "version": "0.1"],
                         "capabilities": ["experimentalApi": true]]], into: stdin)
        guard Self.await(id: 1, bag: &responses, bagLock: bagLock, proc: proc,
                         cancelled: { self.lock.lock(); let c = self.cancelled; self.lock.unlock(); return c },
                         timeout: timeout) != nil else {
            throw awaitFailure(proc: proc)
        }
        send(["method": "notifications/initialized"], into: stdin)

        // 2) 目标请求
        send(["id": id, "method": method, "params": params], into: stdin)
        guard let res = Self.await(id: id, bag: &responses, bagLock: bagLock, proc: proc,
                                   cancelled: { self.lock.lock(); let c = self.cancelled; self.lock.unlock(); return c },
                                   timeout: timeout) else {
            throw awaitFailure(proc: proc)
        }
        if let err = res as? [String: Any], err["code"] != nil || err["message"] != nil {
            throw DataError.msg("app-server 错误：\(err["message"] ?? "?")")
        }
        return res
    }

    /// 写入失败（管道破裂等）忽略；靠 await 的「进程退出 / 超时」失败，不崩。
    private func send(_ obj: [String: Any], into stdin: Pipe) {
        var d = obj
        if d["jsonrpc"] == nil { d["jsonrpc"] = "2.0" }
        guard let data = try? JSONSerialization.data(withJSONObject: d) else { return }
        try? stdin.fileHandleForWriting.write(contentsOf: data)
        try? stdin.fileHandleForWriting.write(contentsOf: Data("\n".utf8))
    }

    /// 根据取消 / 进程退出 / 超时返回对应错误。
    private func awaitFailure(proc: Process) -> DataError {
        lock.lock(); let c = cancelled; lock.unlock()
        if c { return DataError.msg("已取消（quit）") }
        if !proc.isRunning { return DataError.msg("codex app-server 进程已退出（未安装 / 启动失败）") }
        return DataError.msg("app-server 无响应（超时 \(Int(timeout))s）")
    }

    private static func await(id: Int, bag: inout [Int: Any], bagLock: NSLock, proc: Process,
                              cancelled: () -> Bool, timeout: TimeInterval) -> Any? {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            if cancelled() { return nil }
            bagLock.lock(); let v = bag[id]; bagLock.unlock()
            if let v = v { return v }
            if !proc.isRunning {
                Thread.sleep(forTimeInterval: 0.1)   // 进程提前退出：稍等残留输出
                bagLock.lock(); let v2 = bag[id]; bagLock.unlock()
                return v2
            }
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
