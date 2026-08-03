import Foundation

// 数据层测试：纯函数 + 依赖注入（fixture 目录），无需屏幕录制权限、不联网。
// 编译运行：make test-data （= swiftc Sources/PetDock/Data/*.swift tests/DataTests.swift -o /tmp/petdock-datatests && /tmp/petdock-datatests）

struct MockFailRateLimit: RateLimitFetching {
    func readWeekLeft() throws -> WeekLeft { throw DataError.msg("mock-fail") }
    func cancel() {}
}
struct MockOKRateLimit: RateLimitFetching {
    func readWeekLeft() throws -> WeekLeft { WeekLeft(usedPercent: 30, resetsAt: nil, windowMinutes: 10080, planType: "fixture-plan", fetchedAt: Date()) }
    func cancel() {}
}
/// 记录 cancel 调用次数的 mock，用于断言 service.cancelInFlight 转发。
final class MockCancelRateLimit: RateLimitFetching {
    private(set) var cancelCount = 0
    func readWeekLeft() throws -> WeekLeft { WeekLeft(usedPercent: 1, resetsAt: nil, windowMinutes: 10080, planType: "fixture-plan", fetchedAt: Date()) }
    func cancel() { cancelCount += 1 }
}

/// 可控慢源：阻塞指定时长，记录并发抓取峰值（maxActive）与总调用次数，用于断言 refreshInFlight 合并。
final class SlowRateLimit: RateLimitFetching {
    let delay: TimeInterval
    private let lock = NSLock()
    private var active = 0
    private(set) var maxActive = 0
    private(set) var callCount = 0
    init(delay: TimeInterval) { self.delay = delay }
    func readWeekLeft() throws -> WeekLeft {
        lock.lock(); active += 1; callCount += 1
        if active > maxActive { maxActive = active }
        lock.unlock()
        Thread.sleep(forTimeInterval: delay)
        lock.lock(); active -= 1; lock.unlock()
        return WeekLeft(usedPercent: 40, resetsAt: nil, windowMinutes: 10080, planType: "fixture-plan", fetchedAt: Date())
    }
    func cancel() {}
}

@main
struct DataTestRunner {
    static var pass = 0
    static var fail = 0

    static func check(_ desc: String, _ cond: Bool, _ extra: String = "") {
        print((cond ? "PASS" : "FAIL") + ": " + desc + (extra.isEmpty ? "" : "  | " + extra))
        if cond { pass += 1 } else { fail += 1 }
    }
    static func section(_ name: String) {
        print("\n[\(name)] \(pass) passed, \(fail) failed")
        pass = 0; fail = 0
    }

    /// 在主线程 pump RunLoop 的同时轮询 pred（completion 经 main 派发，避免死锁）。超时返回 pred()。
    static func waitPumpingMain(_ pred: () -> Bool, timeout: TimeInterval = 10) -> Bool {
        let end = Date(timeIntervalSinceNow: timeout)
        while Date() < end {
            if pred() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
        return pred()
    }

    static func main() {
        func D(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }
        let fixtureRoot = URL(fileURLWithPath: "tests/fixtures/sessions")
        let winFrom = D("2026-08-01T00:00:00Z")
        let winTo = D("2026-08-04T00:00:00Z")

        // ---- T1/T2/T10: 周窗口聚合 + 只用 last_token_usage + 脱敏 + 分项 ----
        var reader = TokenUsageLogReader(sessionsRoot: fixtureRoot)
        let win = try! reader.readPoints(from: winFrom, to: winTo)
        let pts = win.points
        let sum = pts.reduce(Int64(0)) { $0 + $1.tokens }
        check("T1 周窗口聚合 Σ=710", sum == 710, "实际=\(sum) count=\(pts.count)")
        check("T2 只用 last_token_usage（999/777 不计入）", pts.count == 5, "实际=\(pts.count)")
        let input = pts.reduce(Int64(0)) { $0 + $1.input }
        let cached = pts.reduce(Int64(0)) { $0 + $1.cached }
        let output = pts.reduce(Int64(0)) { $0 + $1.output }
        check("T1b input Σ=60（仅 11:00 那条带 input）", input == 60, "input=\(input)")
        check("T1c cached Σ=0（fixture 无 cached_input_tokens）", cached == 0, "cached=\(cached)")
        check("T1d output Σ=40", output == 40, "output=\(output)")
        check("T1e 唯一会话文件数=2（test-a/test-b）", win.sessionFileCount == 2, "files=\(win.sessionFileCount)")
        let described = pts.map { "\($0.timestamp) \($0.tokens)" }.joined()
        check("T10 脱敏：结果不含正文诱饵", !described.contains("SECRET_BODY"), "")
        section("Token 聚合/脱敏/分项")

        // ---- T3: 增量缓存（未变文件命中缓存不重解析）----
        let cacheURL = URL(fileURLWithPath: "/tmp/petdock-test-cache.json")
        try? FileManager.default.removeItem(at: cacheURL)
        var r1 = TokenUsageLogReader(sessionsRoot: fixtureRoot, cacheURL: cacheURL)
        _ = try! r1.readPoints(from: winFrom, to: winTo)
        check("T3a 首次解析 2 个文件", r1.debugFilesParsed == 2, "实际=\(r1.debugFilesParsed)")
        var r2 = TokenUsageLogReader(sessionsRoot: fixtureRoot, cacheURL: cacheURL)
        let win2 = try! r2.readPoints(from: winFrom, to: winTo)
        let pts2 = win2.points
        check("T3b 跨实例命中缓存不重解析", r2.debugFilesParsed == 0, "实际=\(r2.debugFilesParsed)")
        check("T3c 缓存往返聚合一致", pts2.reduce(Int64(0)) { $0 + $1.tokens } == 710, "")
        section("增量缓存")

        // ---- T-evict: 缓存淘汰（范围外 / 已删除 / 过期）----
        do {
            var r = TokenUsageLogReader(sessionsRoot: fixtureRoot)
            _ = try! r.readPoints(from: D("2026-08-02T00:00:00Z"), to: D("2026-08-04T00:00:00Z"))   // a(08-03)+b(08-02)
            check("T-evict1 首次 parse a,b=2", r.debugFilesParsed == 2, "实际=\(r.debugFilesParsed)")
            _ = try! r.readPoints(from: D("2026-08-03T00:00:00Z"), to: D("2026-08-04T00:00:00Z"))   // 只 a 在范围
            check("T-evict2 窄范围 a 命中不重parse（仍2），b 移出范围", r.debugFilesParsed == 2, "实际=\(r.debugFilesParsed)")
            _ = try! r.readPoints(from: D("2026-08-02T00:00:00Z"), to: D("2026-08-04T00:00:00Z"))   // a 命中；b 已淘汰→重 parse
            check("T-evict3 b 被淘汰后重 parse（=3）", r.debugFilesParsed == 3, "实际=\(r.debugFilesParsed)")
        }

        // 删除场景：临时副本，scan → 删 → scan → 恢复 → scan，验证删除即淘汰、不崩。
        do {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("pd-evict-del", isDirectory: true)
            try? FileManager.default.removeItem(at: tmp)
            let src = fixtureRoot.appendingPathComponent("2026/08/03/rollout-test-a.jsonl")
            let dst = tmp.appendingPathComponent("2026/08/03/rollout-test-a.jsonl")
            try! FileManager.default.createDirectory(at: tmp.appendingPathComponent("2026/08/03", isDirectory: true),
                                                     withIntermediateDirectories: true)
            try! FileManager.default.copyItem(at: src, to: dst)
            var r = TokenUsageLogReader(sessionsRoot: tmp)
            _ = try! r.readPoints(from: D("2026-08-02T00:00:00Z"), to: D("2026-08-04T00:00:00Z"))
            check("T-evict4 临时副本首次 parse=1", r.debugFilesParsed == 1, "实际=\(r.debugFilesParsed)")
            try! FileManager.default.removeItem(at: dst)
            let win5 = try! r.readPoints(from: D("2026-08-02T00:00:00Z"), to: D("2026-08-04T00:00:00Z"))
            check("T-evict5 删除后 scan 不崩且 0 点", win5.points.isEmpty, "count=\(win5.points.count)")
            try! FileManager.default.copyItem(at: src, to: dst)
            let win6 = try! r.readPoints(from: D("2026-08-02T00:00:00Z"), to: D("2026-08-04T00:00:00Z"))
            check("T-evict6 删除时淘汰→恢复后重 parse（=2）且非空",
                  r.debugFilesParsed == 2 && !win6.points.isEmpty, "parsed=\(r.debugFilesParsed)")
            try? FileManager.default.removeItem(at: tmp)
        }
        section("缓存淘汰")

        // ---- T4: parseLine 纯函数鲁棒性 ----
        check("T4a 损坏行→nil", TokenUsageLogReader.parseLine("{bad") == nil)
        check("T4b 无 token 行→nil", TokenUsageLogReader.parseLine("{\"type\":\"response_item\",\"timestamp\":\"2026-08-03T11:00:00.000Z\",\"payload\":{}}") == nil)
        check("T4c 无 timestamp→nil", TokenUsageLogReader.parseLine("{\"type\":\"event_msg\",\"payload\":{\"info\":{\"last_token_usage\":{\"total_tokens\":1}}}}") == nil)
        let good = TokenUsageLogReader.parseLine("{\"type\":\"event_msg\",\"timestamp\":\"2026-08-03T11:00:00.000Z\",\"payload\":{\"info\":{\"last_token_usage\":{\"total_tokens\":123}}}}")
        check("T4d 正常行→点 tokens=123", good?.tokens == 123, "\(good?.tokens ?? -1)")
        section("parseLine")

        // ---- T5: WeekLeft 解析（fixture 响应）----
        let result: [String: Any] = [
            "rateLimits": [
                "planType": "fixture-plan",
                "primary": ["usedPercent": 45, "windowDurationMins": 10080, "resetsAt": Int64(1723104120)]
            ] as [String: Any]
        ]
        let wl = try! RateLimitClient.parse(result)
        check("T5a remainingPercent=55", wl.remainingPercent == 55, "\(wl.remainingPercent)")
        check("T5b isWeekly(10080min)=true", wl.isWeekly, "")
        check("T5c planType=fixture-plan", wl.planType == "fixture-plan", "\(wl.planType ?? "")")
        check("T5d resetsAt 正确", wl.resetsAt == Date(timeIntervalSince1970: 1723104120), "")
        let r2res: [String: Any] = ["rateLimits": ["primary": ["usedPercent": 10, "windowDurationMins": 1440]]]
        check("T5e windowMins=1440(日)→非周", try! RateLimitClient.parse(r2res).isWeekly == false, "")
        section("WeekLeft 解析")

        // ---- T-rl: weekly 窗口选择 / resetsAt 秒-毫秒 / cancel 转发 ----
        // weekly closest 10080：primary(日1440)+secondary(周10080) → 选 secondary
        let rl1: [String: Any] = ["rateLimits": [
            "primary": ["usedPercent": 10, "windowDurationMins": 1440] as [String: Any],
            "secondary": ["usedPercent": 45, "windowDurationMins": 10080] as [String: Any]]]
        let wl1 = try! RateLimitClient.parse(rl1)
        check("T-rl1 weekly 选 closest10080（secondary）", wl1.usedPercent == 45 && wl1.windowMinutes == 10080 && wl1.isWeekly,
              "used=\(wl1.usedPercent) mins=\(wl1.windowMinutes ?? -1)")
        // 单窗兜底：只 primary 且无 windowDurationMins → 兜底 primary
        let rl2: [String: Any] = ["rateLimits": ["primary": ["usedPercent": 30] as [String: Any]]]
        let wl2 = try! RateLimitClient.parse(rl2)
        check("T-rl2 单窗兜底 primary（无 windowMins）", wl2.usedPercent == 30 && wl2.windowMinutes == nil, "")
        // resetsAt 秒
        let rl3: [String: Any] = ["rateLimits": ["primary": ["usedPercent": 5, "resetsAt": Int64(1723104120)] as [String: Any]]]
        check("T-rl3 resetsAt 秒", try! RateLimitClient.parse(rl3).resetsAt == Date(timeIntervalSince1970: 1723104120), "")
        // resetsAt 毫秒（13 位）→ /1000
        let rl4: [String: Any] = ["rateLimits": ["primary": ["usedPercent": 5, "resetsAt": Int64(1723104120000)] as [String: Any]]]
        check("T-rl4 resetsAt 毫秒兼容（/1000 后同秒）", try! RateLimitClient.parse(rl4).resetsAt == Date(timeIntervalSince1970: 1723104120), "")
        // 多桶 rateLimitsByLimitId：选桶内 weekly primary
        let rl5: [String: Any] = ["rateLimits": [
            "primary": ["usedPercent": 10, "windowDurationMins": 1440] as [String: Any],
            "rateLimitsByLimitId": ["codex": ["primary": ["usedPercent": 55, "windowDurationMins": 10080] as [String: Any]] as [String: Any]]] as [String: Any]]
        let wl5 = try! RateLimitClient.parse(rl5)
        check("T-rl5 多桶选 weekly primary", wl5.usedPercent == 55 && wl5.isWeekly, "used=\(wl5.usedPercent)")
        // cancel 转发：service.cancelInFlight → rateLimit.cancel
        let mc = MockCancelRateLimit()
        let svcRl = PetDockDataService(rateLimit: mc, tokenLog: TokenUsageLogReader(sessionsRoot: fixtureRoot))
        svcRl.cancelInFlight()
        check("T-rl6 cancelInFlight 转发→cancelCount=1", mc.cancelCount == 1, "count=\(mc.cancelCount)")
        section("WeekLeft 窗口/重置/cancel")

        // ---- T6: 退避 ----
        check("T6a 0失败→300", Backoff.nextDelay(afterFailures: 0) == 300, "")
        check("T6b 1失败→900", Backoff.nextDelay(afterFailures: 1) == 900, "")
        check("T6c 2失败→1800", Backoff.nextDelay(afterFailures: 2) == 1800, "")
        check("T6d 3失败→3600", Backoff.nextDelay(afterFailures: 3) == 3600, "")
        check("T6e 9失败→3600", Backoff.nextDelay(afterFailures: 9) == 3600, "")
        section("退避")

        // ---- T7: service pause ----
        let svc7 = PetDockDataService(rateLimit: MockOKRateLimit(), tokenLog: TokenUsageLogReader(sessionsRoot: fixtureRoot))
        if case .success = svc7.fetchWeekLeft() { check("T7-pre pause 前 fetchWeekLeft 成功", true) } else { check("T7-pre pause 前 fetchWeekLeft 成功", false) }
        svc7.pause()
        if case .failure = svc7.fetchWeekLeft() { check("T7a pause→fetchWeekLeft 失败", true) } else { check("T7a pause→fetchWeekLeft 失败", false) }
        if case .failure = svc7.fetchWeekTokens() { check("T7b pause→fetchWeekTokens 失败", true) } else { check("T7b pause→fetchWeekTokens 失败", false) }
        section("暂停")

        // ---- T8: service fetchWeekTokens（真实 reader + 注入时钟）----
        let svc8 = PetDockDataService(rateLimit: MockOKRateLimit(),
                                      tokenLog: TokenUsageLogReader(sessionsRoot: fixtureRoot),
                                      now: { D("2026-08-04T00:00:00Z") })
        if case .success(let wt) = svc8.fetchWeekTokens() {
            check("T8 Σ=710 sampleCount=5", wt.totalTokens == 710 && wt.sampleCount == 5,
                  "tokens=\(wt.totalTokens) count=\(wt.sampleCount)")
            check("T8b input=60 cached=0 output=40",
                  wt.inputTokens == 60 && wt.cachedInputTokens == 0 && wt.outputTokens == 40,
                  "in=\(wt.inputTokens) cached=\(wt.cachedInputTokens) out=\(wt.outputTokens)")
            check("T8c sessionFileCount=2（非 sampleCount=5）", wt.sessionFileCount == 2, "files=\(wt.sessionFileCount)")
        } else { check("T8 fetchWeekTokens", false) }
        section("service WeekTokens")

        // ---- T9: service 退避计数 ----
        let svc9 = PetDockDataService(rateLimit: MockFailRateLimit(), tokenLog: TokenUsageLogReader(sessionsRoot: fixtureRoot))
        _ = svc9.fetchWeekLeft(); _ = svc9.fetchWeekLeft(); _ = svc9.fetchWeekLeft()
        check("T9a 3 次失败→failures=3", svc9.weekLeftFailures == 3, "\(svc9.weekLeftFailures)")
        check("T9b nextDelay=3600", svc9.weekLeftNextDelay == 3600, "\(svc9.weekLeftNextDelay)")
        section("service 退避")

        // ---- T11: 分项累计 / 缺字段 / cached（test-c 独立窗口 [08-05,08-06]）----
        var readerC = TokenUsageLogReader(sessionsRoot: fixtureRoot)
        let winC = try! readerC.readPoints(from: D("2026-08-05T00:00:00Z"), to: D("2026-08-06T00:00:00Z"))
        let ptsC = winC.points
        check("T11a test-c 3 个点", ptsC.count == 3, "count=\(ptsC.count)")
        check("T11b total=1500（含无 total→0 的点）", ptsC.reduce(Int64(0)) { $0 + $1.tokens } == 1500, "")
        check("T11c input=1000（600+300+100）", ptsC.reduce(Int64(0)) { $0 + $1.input } == 1000, "")
        check("T11d cached=250（200+缺0+50）", ptsC.reduce(Int64(0)) { $0 + $1.cached } == 250, "")
        check("T11e output=650（400+200+50）", ptsC.reduce(Int64(0)) { $0 + $1.output } == 650, "")
        check("T11f 缺字段：点2 无 cached→0", ptsC.count > 1 && ptsC[1].cached == 0, "")
        check("T11g 缺字段：点3 无 total→0", ptsC.count > 2 && ptsC[2].tokens == 0, "")
        check("T11h 单文件 sessionFileCount=1", winC.sessionFileCount == 1, "files=\(winC.sessionFileCount)")
        section("分项累计/缺字段")

        // ---- T12: LiveDockProvider 字段映射 / 占位 / 单源失败（纯函数 buildSnapshot）----
        let wlOK = WeekLeft(usedPercent: 45, resetsAt: Date(timeIntervalSince1970: 1723104120),
                            windowMinutes: 10080, planType: "fixture-plan", fetchedAt: D("2026-08-03T12:00:00Z"))
        let wtOK = WeekTokens(totalTokens: 1_590_000_000, inputTokens: 1000, cachedInputTokens: 250,
                              outputTokens: 650, windowStart: D("2026-08-05T00:00:00Z"),
                              windowEnd: D("2026-08-06T00:00:00Z"), sampleCount: 3, sessionFileCount: 2,
                              fetchedAt: D("2026-08-05T12:00:00Z"))
        let both = LiveDockProvider.buildSnapshot(left: .success(wlOK), tokens: .success(wtOK))
        check("T12a weekLeft=55%", both.weekLeft == "55%", both.weekLeft ?? "nil")
        check("T12b weekTokens=1.59B", both.weekTokens == "1.59B", both.weekTokens ?? "nil")
        check("T12c plan=fixture-plan", both.plan == "fixture-plan", both.plan ?? "nil")
        check("T12d 非缓存输入=max(1000-250,0)=750", both.inputTokens == "750", both.inputTokens ?? "nil")
        check("T12e 输出=650", both.outputTokens == "650", both.outputTokens ?? "nil")
        check("T12f 缓存比例=250/1000=25%", both.cacheRatio == "25%", both.cacheRatio ?? "nil")
        check("T12g 真实会话数=sessionFileCount=2（非 sampleCount=3）", both.sessionCount == 2, "\(both.sessionCount ?? -1)")
        check("T12h updatedAt 取自 fetchedAt", both.updatedAt != nil, both.updatedAt ?? "nil")

        let leftOnly = LiveDockProvider.buildSnapshot(left: .success(wlOK), tokens: .failure(DataError.msg("x")))
        check("T12i tokens 失败→weekTokens 占位 nil", leftOnly.weekTokens == nil, "")
        check("T12j tokens 失败→weekLeft 仍展示 55%", leftOnly.weekLeft == "55%", "")
        check("T12k tokens 失败→sessionCount 占位 nil", leftOnly.sessionCount == nil, "")

        let tokOnly = LiveDockProvider.buildSnapshot(left: .failure(DataError.msg("x")), tokens: .success(wtOK))
        check("T12l left 失败→weekLeft 占位 nil", tokOnly.weekLeft == nil, "")
        check("T12m left 失败→weekTokens 仍展示", tokOnly.weekTokens == "1.59B", "")

        let none = LiveDockProvider.buildSnapshot(left: .failure(DataError.msg("x")), tokens: .failure(DataError.msg("y")))
        check("T12n 双失败→全占位不崩", none.weekLeft == nil && none.weekTokens == nil && none.sessionCount == nil, "")

        let wtNoInput = WeekTokens(totalTokens: 100, inputTokens: 0, cachedInputTokens: 0, outputTokens: 50,
                                   windowStart: D("2026-08-02T00:00:00Z"), windowEnd: D("2026-08-03T00:00:00Z"),
                                   sampleCount: 2, sessionFileCount: 1, fetchedAt: D("2026-08-02T12:00:00Z"))
        let noInput = LiveDockProvider.buildSnapshot(left: .success(wlOK), tokens: .success(wtNoInput))
        check("T12o input=0→缓存比例占位 nil（分母 0）", noInput.cacheRatio == nil, noInput.cacheRatio ?? "nil")
        check("T12p input=0→非缓存输入=0", noInput.inputTokens == "0", noInput.inputTokens ?? "nil")

        check("T12q formatTokens 各档",
              LiveDockProvider.formatTokens(0) == "0" && LiveDockProvider.formatTokens(999) == "999"
              && LiveDockProvider.formatTokens(1500) == "1.5K" && LiveDockProvider.formatTokens(1_590_000) == "1.59M"
              && LiveDockProvider.formatTokens(1_590_000_000) == "1.59B", "")
        check("T12r formatPercent=25%", LiveDockProvider.formatPercent(250, of: 1000) == "25%", "")
        section("LiveDockProvider 映射")

        // ---- C: 并发（refreshInFlight 合并 / maxConcurrent=1 / pending 最终刷新 / pause-resume 安全）----
        // completion 经 main 派发，故用 waitPumpingMain 在主线程 pump RunLoop 等待，避免死锁。
        let slow = SlowRateLimit(delay: 0.15)
        let svcC = PetDockDataService(rateLimit: slow, tokenLog: TokenUsageLogReader(sessionsRoot: fixtureRoot))
        let prov = LiveDockProvider(service: svcC)
        let cg = DispatchGroup()
        for _ in 0..<3 {
            cg.enter()
            prov.refresh { cg.leave() }   // 三连 refresh：首次在途，后两次合并 pending
        }
        let cok = Self.waitPumpingMain({ cg.wait(timeout: .now()) == .success }, timeout: 10)
        check("C1 三连 refresh completion 全部到达（无悬挂）", cok, "")
        check("C2 maxConcurrent==1（refreshInFlight 合并）", slow.maxActive == 1, "maxActive=\(slow.maxActive)")
        // C3: pending 最终刷新是异步的（C1 完成后才启动 startFetch#2），轮询等待其 readWeekLeft 发生。
        let c3ok = Self.waitPumpingMain({ slow.callCount >= 2 }, timeout: 10)
        check("C3 pending 最终刷新 callCount>=2", c3ok, "callCount=\(slow.callCount)")

        // C4: refresh 在途期间 pause/resume（经同一 queue，不阻塞慢 IO、不死锁），最终仍完成。
        let slow2 = SlowRateLimit(delay: 0.2)
        let svcP = PetDockDataService(rateLimit: slow2, tokenLog: TokenUsageLogReader(sessionsRoot: fixtureRoot))
        let provP = LiveDockProvider(service: svcP)
        var pDone = false
        provP.refresh { pDone = true }
        provP.pause()
        provP.resume()
        let pok = Self.waitPumpingMain({ pDone }, timeout: 10)
        check("C4 refresh 在途 pause/resume 不死锁（最终完成）", pok, "")
        section("并发")

        // ---- T-resolver: CodexExecutableResolver（env优先/PATH/nvm多版本/不可执行/缺失）----
        do {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(
                "pd-resolver-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
            try? FileManager.default.removeItem(at: tmp)
            try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            // 在指定 home 下造可执行 / 不可执行文件
            func makeExec(_ home: URL, _ rel: String) -> URL {
                let u = home.appendingPathComponent(rel)
                try! FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: u.path, contents: Data("#!/bin/sh\n".utf8))
                try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: u.path)
                return u
            }
            func makeNoExec(_ home: URL, _ rel: String) -> URL {
                let u = home.appendingPathComponent(rel)
                try! FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: u.path, contents: Data())   // 0644 无 +x
                return u
            }
            func home(_ name: String) -> URL {
                let h = tmp.appendingPathComponent(name)
                try! FileManager.default.createDirectory(at: h, withIntermediateDirectories: true)
                return h
            }

            // T-r1: env 优先（候选也存在仍选 env）
            let envHome = home("env")
            let envExec = makeExec(envHome, "custom/codex")
            _ = makeExec(envHome, ".local/bin/codex")
            let r1 = CodexExecutableResolver(environment: [CodexExecutableResolver.envOverride: envExec.path], homeDirectory: envHome, systemCandidates: [])
            if case .success(let u) = r1.resolve() { check("T-r1 env 优先", u == envExec, "") } else { check("T-r1 env 优先", false) }

            // T-r2: env 不可执行 → overrideNotExecutable（不回退）
            let noExec = makeNoExec(envHome, "noexec/codex")
            let r2 = CodexExecutableResolver(environment: [CodexExecutableResolver.envOverride: noExec.path], homeDirectory: envHome, systemCandidates: [])
            if case .failure(let e) = r2.resolve(), case .overrideNotExecutable = e { check("T-r2 env 不可执行→overrideNotExecutable", true) } else { check("T-r2", false) }

            // T-r3: PATH 命中（home 无候选）
            let pathHome = home("path")
            let pathExec = makeExec(pathHome, "pathdir/codex")
            let r3 = CodexExecutableResolver(environment: ["PATH": pathHome.appendingPathComponent("pathdir").path], homeDirectory: home("empty1"), systemCandidates: [])
            if case .success(let u) = r3.resolve() { check("T-r3 PATH 命中", u == pathExec, "") } else { check("T-r3 PATH 命中", false) }

            // T-r4: nvm 多版本选最新（语义版本降序；home 无 .local/bin）
            let nvmHome = home("nvm")
            _ = makeExec(nvmHome, ".nvm/versions/node/v20.10.0/bin/codex")
            let newV = makeExec(nvmHome, ".nvm/versions/node/v22.21.1/bin/codex")
            let r4 = CodexExecutableResolver(environment: [:], homeDirectory: nvmHome, systemCandidates: [])
            if case .success(let u) = r4.resolve() { check("T-r4 nvm 选最新 v22.21.1", u == newV, u.path) } else { check("T-r4", false) }

            // T-r5: 均缺失 → notFound（systemCandidates=[] 隔离系统 brew，不依赖本机环境）
            let r5 = CodexExecutableResolver(environment: [:], homeDirectory: home("empty2"), systemCandidates: [])
            if case .failure(let e) = r5.resolve(), case .notFound = e { check("T-r5 均缺失→notFound", true) } else { check("T-r5", false) }

            // T-r6: 不可执行文件不被选中（isExecutableFile=false）
            let badHome = home("bad")
            let badLocal = makeNoExec(badHome, ".local/bin/codex")
            check("T-r6 不可执行 isExecutableFile=false",
                  !CodexExecutableResolver(environment: [:], homeDirectory: badHome, systemCandidates: []).isExecutableFile(badLocal), "")

            // T-r7: compareVersion / versionKey 纯函数
            check("T-r7a compareVersion v22.21.1>v20.10.0", CodexExecutableResolver.compareVersion("v22.21.1", "v20.10.0") > 0, "")
            check("T-r7b versionKey v22.21.1=[22,21,1]", CodexExecutableResolver.versionKey("v22.21.1") == [22, 21, 1], "")

            // T-r8: PATH 跳过空 / 相对元素，命中绝对目录
            let safeHome = home("safe")
            let safeExec = makeExec(safeHome, "codex")
            let r8 = CodexExecutableResolver(environment: ["PATH": "::relative:\(safeHome.path)"], homeDirectory: home("empty3"), systemCandidates: [])
            if case .success(let u) = r8.resolve() { check("T-r8 PATH 跳过空/相对命中绝对", u == safeExec, u.path) } else { check("T-r8", false) }

            // T-r9: env ~ 展开 → 绝对命中
            let tildeHome = home("tilde")
            let tildeExec = makeExec(tildeHome, "custom/codex")
            let r9 = CodexExecutableResolver(environment: [CodexExecutableResolver.envOverride: "~/custom/codex"], homeDirectory: tildeHome, systemCandidates: [])
            if case .success(let u) = r9.resolve() { check("T-r9 env ~ 展开命中", u == tildeExec, u.path) } else { check("T-r9", false) }

            // T-r10: env 相对路径 → overrideNotAbsolute（不允许相对 CWD）
            let r10 = CodexExecutableResolver(environment: [CodexExecutableResolver.envOverride: "custom/codex"], homeDirectory: home("rel"), systemCandidates: [])
            if case .failure(let e) = r10.resolve(), case .overrideNotAbsolute = e { check("T-r10 env 相对→overrideNotAbsolute", true) } else { check("T-r10", false) }

            // T-r11: 符号链接到可执行目标 → 命中（isExecutableFile 跟随 symlink）
            let linkHome = home("link")
            let realExec = makeExec(linkHome, "real/codex")
            let linkPath = linkHome.appendingPathComponent("link/codex")
            try! FileManager.default.createDirectory(at: linkPath.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: linkPath)
            try! FileManager.default.createSymbolicLink(at: linkPath, withDestinationURL: realExec)
            let r11 = CodexExecutableResolver(environment: [CodexExecutableResolver.envOverride: linkPath.path], homeDirectory: linkHome, systemCandidates: [])
            if case .success(let u) = r11.resolve() { check("T-r11 symlink→可执行目标命中", u.path == linkPath.path, u.path) } else { check("T-r11", false) }

            try? FileManager.default.removeItem(at: tmp)
        }
        section("codex 路径解析")

        // ---- T-env: RateLimitClient.childEnvironment（prepend codex 父目录到 PATH，去重；端到端复现 env node）----
        do {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(
                "pd-env-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
            try? FileManager.default.removeItem(at: tmp)
            try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            func writeExec(_ url: URL, _ content: String) {
                try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: url.path, contents: Data(content.utf8))
                try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            }
            // 用给定环境运行 exec，返回 stdout（同步等待退出）。
            func runWithEnv(_ exec: URL, _ env: [String: String]) -> String {
                let p = Process()
                p.executableURL = exec
                p.environment = env
                let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
                try? p.run(); p.waitUntilExit()
                return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            }

            // T-env1: prepend 到空 PATH
            let bin1 = tmp.appendingPathComponent("bin1/codex")
            let e1 = RateLimitClient.childEnvironment(codexExecutable: bin1, baseEnvironment: ["PATH": ""])
            check("T-env1 空 PATH→prepend codex 父目录", e1["PATH"] == bin1.deletingLastPathComponent().path, e1["PATH"] ?? "")

            // T-env2: prepend 到已有 PATH（不含 codex 父目录）
            let bin2 = tmp.appendingPathComponent("bin2/codex")
            let e2 = RateLimitClient.childEnvironment(codexExecutable: bin2, baseEnvironment: ["PATH": "/usr/bin:/bin"])
            check("T-env2 prepend 到已有 PATH（去重）",
                  e2["PATH"] == "\(bin2.deletingLastPathComponent().path):/usr/bin:/bin", e2["PATH"] ?? "")

            // T-env3: 已含 codex 父目录 → 不重复
            let bin3Dir = tmp.appendingPathComponent("bin3")
            let bin3 = bin3Dir.appendingPathComponent("codex")
            let e3 = RateLimitClient.childEnvironment(codexExecutable: bin3, baseEnvironment: ["PATH": "\(bin3Dir.path):/usr/bin"])
            check("T-env3 已含 codex 父目录→不重复", e3["PATH"] == "\(bin3Dir.path):/usr/bin", e3["PATH"] ?? "")

            // T-env4: 端到端复现 — 假 codex shebang #!/usr/bin/env fake-node + 同目录 fake-node
            let fakeBin = tmp.appendingPathComponent("fakebin")
            let fakeCodex = fakeBin.appendingPathComponent("codex")
            writeExec(fakeCodex, "#!/usr/bin/env fake-node\n")                       // shebang 找 fake-node
            writeExec(fakeBin.appendingPathComponent("fake-node"), "#!/bin/sh\necho FAKE_NODE_OK\n")
            // 基线 PATH 不含 fakeBin → env fake-node 找不到 → 失败
            let baselineOut = runWithEnv(fakeCodex, ["PATH": "/usr/bin:/bin"])
            check("T-env4b 基线PATH不含→env fake-node 失败", !baselineOut.contains("FAKE_NODE_OK"), baselineOut)
            // childEnvironment prepend fakeBin → env fake-node 找到同目录 fake-node
            let childEnv = RateLimitClient.childEnvironment(codexExecutable: fakeCodex, baseEnvironment: ["PATH": "/usr/bin:/bin"])
            let childOut = runWithEnv(fakeCodex, childEnv)
            check("T-env4 prepend后 env 找到同目录 fake-node", childOut.contains("FAKE_NODE_OK"), childOut)

            try? FileManager.default.removeItem(at: tmp)
        }
        section("子进程环境 prepend")

        print("\n[DataTests] 全部通过")
        exit(fail == 0 ? 0 : 1)
    }
}
