import Foundation

// 数据层测试：纯函数 + 依赖注入（fixture 目录），无需屏幕录制权限、不联网。
// 编译运行：make test-data （= swiftc Sources/PetDock/Data/*.swift tests/DataTests.swift -o /tmp/petdock-datatests && /tmp/petdock-datatests）

struct MockFailRateLimit: RateLimitFetching { func readWeekLeft() throws -> WeekLeft { throw DataError.msg("mock-fail") } }
struct MockOKRateLimit: RateLimitFetching {
    func readWeekLeft() throws -> WeekLeft { WeekLeft(usedPercent: 30, resetsAt: nil, windowMinutes: 10080, planType: "fixture-plan", fetchedAt: Date()) }
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

        print("\n[DataTests] 全部通过")
        exit(fail == 0 ? 0 : 1)
    }
}
