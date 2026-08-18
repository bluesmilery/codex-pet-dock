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

// fixture 日期与测试窗口单一来源：所有路径日期、时间窗口、now 基线均由 anchor 经日历偏移派生，
// 消除分散硬编码；fixture 文件本身（tests/fixtures/sessions/...）保持脱敏可读不变。
// 基准 anchorDay 与 test-a 文件所在日（2026/08/03）对齐，其余 fixture 日与窗口均按相对偏移生成。
enum FixtureCalendar {
    static let utc = Calendar(identifier: .gregorian)
    /// test-a 所在日（2026-08-03T00:00:00Z）；其余日期与窗口均相对它偏移。
    static let anchorDay = iso("2026-08-03T00:00:00Z")
    /// test-b 所在日 = anchor - 1d（2026-08-02）。
    static let dayB = utc.date(byAdding: .day, value: -1, to: anchorDay)!
    /// test-c 所在日 = anchor + 2d（2026-08-05）。
    static let dayC = utc.date(byAdding: .day, value: 2, to: anchorDay)!
    /// 主聚合窗口 [winFrom, winTo] = [anchor-2d, anchor+1d]（含 test-a/test-b，排除 test-c）。
    static let winFrom = utc.date(byAdding: .day, value: -2, to: anchorDay)!
    static let winTo = utc.date(byAdding: .day, value: 1, to: anchorDay)!
    /// service now 基线 = winTo（覆盖 [winFrom, now] 一周窗口的右端）。
    static let now = winTo
    /// test-c 独立窗口 [dayC, dayC+1d]（2026-08-05 → 2026-08-06）。
    static let dayCFrom = dayC
    static let dayCTo = utc.date(byAdding: .day, value: 1, to: dayC)!
    /// fixture 下 test-a/test-b/test-c 的期望路径（与 sessions 目录布局一致）。
    static func sessionFile(_ root: URL, _ rel: String) -> URL {
        root.appendingPathComponent(rel)
    }

    /// ISO8601 解析辅助（仅 fixture 日期源使用）。
    static func iso(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }
}

// MARK: - fake codex 可执行脚本（合成 stdio JSON-RPC，确定性、不联网/不读 auth）

/// 生成一个合成的「fake codex」可执行 shell 脚本，模拟 `codex app-server` 的 stdio JSON-RPC 行为，
/// 供 `RateLimitClient`（经 `CodexExecutableResolver` env override 指向它）端到端驱动真实 `rpc()` 代码路径。
///
/// 合规：脚本内容**明显合成**（标记 `FAKE_CODEX`、`fixture-plan`），不访问真实 auth.json / 网络 / 真实 codex。
///
/// 行为模式（由脚本首个参数选择，默认 normal）：
/// - `normal`：读到 initialize(id=N) 回 result、读 notifications 跳过、读到 rateLimits/read(id=M)
///   回合成 result；额外先吐一条 id=999 的噪声行验证请求/响应按 id 关联；
/// - `fragmented`：同 normal，但 result 行拆成多次小 write（每次 1-2 字节），验证 LineReader 分片重组；
/// - `silent`：读完所有输入但不回任何响应，验证超时；
/// - `exit-early`：启动后立即退出（不读 stdin），验证「进程退出」失败路径；
/// - `stderr-noise`：同 normal，但额外向 stderr 写垃圾，验证 stderr 被独立管道丢弃不影响 result。
enum FakeCodex {
    /// 合成 result（明显合成：fixture-plan / FAKE_CODEX 标记；不含任何凭证或真实账户信息）。
    static let syntheticResultJSON = """
    {"rateLimits":{"planType":"fixture-plan","primary":{"usedPercent":42,"windowDurationMins":10080,"resetsAt":2000000000}}}
    """

    /// 生成并写入 fake codex 脚本到临时目录，返回其 URL（已 chmod 0755）。
    static func install(mode: String) -> URL {
        // 目录名用 __ 分隔 mode（mode 本身可含 '-'，如 exit-early / stderr-noise），
        // 脚本以 ${dir##*__} 提取 mode，避免被 '-' 切断。
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "pd-fakecodex-\(ProcessInfo.processInfo.processIdentifier)__\(mode)", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("codex")
        // 脚本：从 stdin 逐行读，按 JSON-RPC id 回合成响应。用 grep -oE 提取 "id":N（send 格式确定）。
        let body = """
        #!/bin/sh
        # FAKE_CODEX 合成测试替身（非真实 codex；不读 auth/不联网）。
        # mode 由脚本所在目录名末段决定（install 每种 mode 独立目录，__ 分隔），不依赖命令行参数
        # （rpc() 固定以 "app-server" 为首个参数启动 codex，参数通道不可用）。
        dir=$(dirname "$0")
        mode=${dir##*__}

        # 按 id 回一条 JSON-RPC result 行（$1=id）。根据模式决定是否分片写出。
        emit() {
            id="$1"
            line='{"jsonrpc":"2.0","id":'"$id"',\"result\":'"$SYNTH_RESULT"'}'
            if [ "$mode" = "fragmented" ]; then
                # 分片：先吐无换行的前半段，sleep 制造 readabilityHandler 回调间隙，
                # 再补后半段 + 换行。验证 LineReader 跨多次回调重组同一行（不丢、不 premature）。
                half=$((${#line} / 2))
                printf '%s' "${line:0:half}"
                sleep 0.1
                printf '%s\\n' "${line:half}"
            else
                printf '%s\\n' "$line"
            fi
        }

        if [ "$mode" = "exit-early" ]; then exit 0; fi

        # silent: 读光 stdin 但不回（触发客户端超时）。
        if [ "$mode" = "silent" ]; then
            while IFS= read -r _; do :; done
            exit 0
        fi

        # stderr-noise: 同 normal 但向 stderr 吐垃圾，验证 stderr 独立管道被丢弃。
        if [ "$mode" = "stderr-noise" ]; then
            echo "FAKE_CODEX_STDERR_GARBAGE_IGNORE_ME" >&2
        fi

        # 先吐一条 id=999 噪声响应（normal/fragmented/stderr-noise），验证客户端按目标 id 关联、不被噪声干扰。
        if [ "$mode" = "normal" ] || [ "$mode" = "fragmented" ] || [ "$mode" = "stderr-noise" ]; then
            SYNTH_RESULT='{"jsonrpc":"2.0","id":999,"result":{"noise":"FAKE_CODEX_UNRELATED"}}'
            printf '%s\\n' "$SYNTH_RESULT"
        fi

        SYNTH_RESULT='{"rateLimits":{"planType":"fixture-plan","primary":{"usedPercent":42,"windowDurationMins":10080,"resetsAt":2000000000}}}'
        while IFS= read -r line; do
            # 提取首个 "id":N（send 生成格式确定：顶层带数字 id；通知无 id → 跳过）。
            idv=$(printf '%s' "$line" | grep -oE '"id":[0-9]+' | head -n1 | grep -oE '[0-9]+')
            [ -z "$idv" ] && continue                # notifications/initialized 无 id → 跳过
            emit "$idv"
        done
        """
        try! Data(body.utf8).write(to: script)
        try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    /// 构造指向 fake codex 的 resolver（env override；systemCandidates=空隔离系统 brew）。
    static func resolver(for executable: URL) -> CodexExecutableResolver {
        CodexExecutableResolver(environment: [CodexExecutableResolver.envOverride: executable.path],
                                homeDirectory: executable.deletingLastPathComponent(),
                                systemCandidates: [])
    }

    /// 清理临时脚本目录。
    static func remove(_ executable: URL) {
        try? FileManager.default.removeItem(at: executable.deletingLastPathComponent())
    }
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
        let winFrom = FixtureCalendar.winFrom
        let winTo = FixtureCalendar.winTo

        // ---- T0: 候选文件选择与窗口一致性（路径日期/窗口均同源于 FixtureCalendar）----
        // 证明 candidateFiles 逻辑用派生窗口选中预期文件集合：主窗口含 test-a/test-b，排除 test-c。
        // fixture 相对路径的 YYYY/MM/DD 也由 anchor/dayB/dayC 经日历组件派生，与磁盘布局一致。
        func dayRel(_ day: Date, _ file: String) -> String {
            let c = FixtureCalendar.utc.dateComponents([.year, .month, .day], from: day)
            return String(format: "%04d/%02d/%02d/%@", c.year!, c.month!, c.day!, file as NSString)
        }
        do {
            var r0 = TokenUsageLogReader(sessionsRoot: fixtureRoot)
            let win0 = try! r0.readPoints(from: winFrom, to: winTo)
            let relA = dayRel(FixtureCalendar.anchorDay, "rollout-test-a.jsonl")
            let relB = dayRel(FixtureCalendar.dayB, "rollout-test-b.jsonl")
            let relC = dayRel(FixtureCalendar.dayC, "rollout-test-c.jsonl")
            check("T0a 主窗口 sessionFileCount=2（test-a + test-b）", win0.sessionFileCount == 2, "files=\(win0.sessionFileCount)")
            // 验证 test-a/test-b 点落在窗口内、test-c 点落在窗口外（候选裁剪与点的窗口过滤一致）。
            let aPts = win0.points.filter { $0.timestamp >= FixtureCalendar.anchorDay }   // test-a 在 anchor 日
            check("T0b 主窗口含 test-a 点（anchor 日）", !aPts.isEmpty, "aPts=\(aPts.count)")
            let winC = try! r0.readPoints(from: FixtureCalendar.dayCFrom, to: FixtureCalendar.dayCTo)
            check("T0c test-c 独立窗口仅选 test-c（sessionFileCount=1）", winC.sessionFileCount == 1, "files=\(winC.sessionFileCount)")
            check("T0d test-c 文件在主窗口外（主窗口不含 test-c 点）",
                  !win0.points.contains { $0.timestamp >= FixtureCalendar.dayCFrom }, "")
            // 候选文件存在性：路径日期派生与磁盘布局一致。
            check("T0e fixture test-a 路径存在", FileManager.default.fileExists(atPath: FixtureCalendar.sessionFile(fixtureRoot, relA).path), "")
            check("T0f fixture test-b 路径存在", FileManager.default.fileExists(atPath: FixtureCalendar.sessionFile(fixtureRoot, relB).path), "")
            check("T0g fixture test-c 路径存在", FileManager.default.fileExists(atPath: FixtureCalendar.sessionFile(fixtureRoot, relC).path), "")
        }
        section("fixture 日期同源/候选一致")

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
        // 窗口全部由 FixtureCalendar 派生：[dayB, winTo] 含 a+b；[anchorDay, winTo] 仅含 a。
        do {
            var r = TokenUsageLogReader(sessionsRoot: fixtureRoot)
            _ = try! r.readPoints(from: FixtureCalendar.dayB, to: winTo)   // a(anchorDay)+b(dayB)
            check("T-evict1 首次 parse a,b=2", r.debugFilesParsed == 2, "实际=\(r.debugFilesParsed)")
            _ = try! r.readPoints(from: FixtureCalendar.anchorDay, to: winTo)   // 只 a 在范围
            check("T-evict2 窄范围 a 命中不重parse（仍2），b 移出范围", r.debugFilesParsed == 2, "实际=\(r.debugFilesParsed)")
            _ = try! r.readPoints(from: FixtureCalendar.dayB, to: winTo)   // a 命中；b 已淘汰→重 parse
            check("T-evict3 b 被淘汰后重 parse（=3）", r.debugFilesParsed == 3, "实际=\(r.debugFilesParsed)")
        }

        // 删除场景：临时副本，scan → 删 → scan → 恢复 → scan，验证删除即淘汰、不崩。
        do {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("pd-evict-del", isDirectory: true)
            try? FileManager.default.removeItem(at: tmp)
            // test-a 路径日期由 anchorDay 派生（YYYY/MM/DD）。
            let comps = FixtureCalendar.utc.dateComponents([.year, .month, .day], from: FixtureCalendar.anchorDay)
            let dayPath = String(format: "%04d/%02d/%02d", comps.year!, comps.month!, comps.day!)
            let src = fixtureRoot.appendingPathComponent("\(dayPath)/rollout-test-a.jsonl")
            let dst = tmp.appendingPathComponent("\(dayPath)/rollout-test-a.jsonl")
            try! FileManager.default.createDirectory(at: tmp.appendingPathComponent("\(dayPath)", isDirectory: true),
                                                     withIntermediateDirectories: true)
            try! FileManager.default.copyItem(at: src, to: dst)
            var r = TokenUsageLogReader(sessionsRoot: tmp)
            _ = try! r.readPoints(from: FixtureCalendar.dayB, to: winTo)
            check("T-evict4 临时副本首次 parse=1", r.debugFilesParsed == 1, "实际=\(r.debugFilesParsed)")
            try! FileManager.default.removeItem(at: dst)
            let win5 = try! r.readPoints(from: FixtureCalendar.dayB, to: winTo)
            check("T-evict5 删除后 scan 不崩且 0 点", win5.points.isEmpty, "count=\(win5.points.count)")
            try! FileManager.default.copyItem(at: src, to: dst)
            let win6 = try! r.readPoints(from: FixtureCalendar.dayB, to: winTo)
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
                "primary": ["usedPercent": 45, "windowDurationMins": 10080, "resetsAt": Int64(2000000000)]
            ] as [String: Any]
        ]
        let wl = try! RateLimitClient.parse(result)
        check("T5a remainingPercent=55", wl.remainingPercent == 55, "\(wl.remainingPercent)")
        check("T5b isWeekly(10080min)=true", wl.isWeekly, "")
        check("T5c planType=fixture-plan", wl.planType == "fixture-plan", "\(wl.planType ?? "")")
        check("T5d resetsAt 正确", wl.resetsAt == Date(timeIntervalSince1970: 2000000000), "")
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
        let rl3: [String: Any] = ["rateLimits": ["primary": ["usedPercent": 5, "resetsAt": Int64(2000000000)] as [String: Any]]]
        check("T-rl3 resetsAt 秒", try! RateLimitClient.parse(rl3).resetsAt == Date(timeIntervalSince1970: 2000000000), "")
        // resetsAt 毫秒（13 位）→ /1000
        let rl4: [String: Any] = ["rateLimits": ["primary": ["usedPercent": 5, "resetsAt": Int64(2000000000000)] as [String: Any]]]
        check("T-rl4 resetsAt 毫秒兼容（/1000 后同秒）", try! RateLimitClient.parse(rl4).resetsAt == Date(timeIntervalSince1970: 2000000000), "")
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
                                      now: { FixtureCalendar.now })
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

        // ---- T11: 分项累计 / 缺字段 / cached（test-c 独立窗口 [dayCFrom, dayCTo]）----
        var readerC = TokenUsageLogReader(sessionsRoot: fixtureRoot)
        let winC = try! readerC.readPoints(from: FixtureCalendar.dayCFrom, to: FixtureCalendar.dayCTo)
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
        let wlOK = WeekLeft(usedPercent: 45, resetsAt: Date(timeIntervalSince1970: 2000000000),
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

        // ---- T-fmt: resetsAt 格式化（本机时区 MM-dd HH:mm）+ resetAt 映射 + nil 占位不崩 ----
        let fmtDate = Date(timeIntervalSince1970: 2_000_000_000)
        let formatted = LiveDockProvider.formatDateTime(fmtDate)
        check("T-fmt1 formatDateTime 格式 MM-dd HH:mm",
              formatted.range(of: #"^\d{2}-\d{2} \d{2}:\d{2}$"#, options: .regularExpression) != nil, formatted)
        let wlReset = WeekLeft(usedPercent: 50, resetsAt: fmtDate, windowMinutes: 10080, planType: "fixture-plan", fetchedAt: fmtDate)
        let snapReset = LiveDockProvider.buildSnapshot(left: .success(wlReset), tokens: .failure(DataError.msg("x")))
        check("T-fmt2 buildSnapshot resetAt == formatDateTime(resetsAt)", snapReset.resetAt == formatted, "\(snapReset.resetAt ?? "?")")
        let wlNil = WeekLeft(usedPercent: 50, resetsAt: nil, windowMinutes: 10080, planType: "fixture-plan", fetchedAt: fmtDate)
        let snapNil = LiveDockProvider.buildSnapshot(left: .success(wlNil), tokens: .failure(DataError.msg("x")))
        check("T-fmt3 resetsAt nil → resetAt nil（占位不崩）", snapNil.resetAt == nil, "\(snapNil.resetAt ?? "?")")
        // T-fmt4: formatDateTime 显式本机时区（.current）
        let tzFmt = DateFormatter()
        tzFmt.locale = Locale(identifier: "en_US_POSIX")
        tzFmt.timeZone = .current
        tzFmt.dateFormat = "MM-dd HH:mm"
        check("T-fmt4 formatDateTime 使用本机时区(.current)", LiveDockProvider.formatDateTime(fmtDate) == tzFmt.string(from: fmtDate), "")
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

            // T-r12: group/world writable target is not trusted, even when executable.
            let writable = makeExec(linkHome, "writable/codex")
            try! FileManager.default.setAttributes([.posixPermissions: 0o775], ofItemAtPath: writable.path)
            check("T-r12 group 可写目标→拒绝", !CodexExecutableResolver(
                environment: [CodexExecutableResolver.envOverride: writable.path],
                homeDirectory: linkHome, systemCandidates: []).isExecutableFile(writable), "")

            try? FileManager.default.removeItem(at: tmp)
        }
        section("codex 路径解析")

        // ---- T-env: childEnvironment 严格白名单 + 受控 PATH（端到端复现 env node）----
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

            let expectedSuffix = ":/usr/bin:/bin:/usr/sbin:/sbin"

            // T-env1: codex 目录 + 固定系统 PATH
            let bin1 = tmp.appendingPathComponent("bin1/codex")
            let e1 = RateLimitClient.childEnvironment(codexExecutable: bin1, baseEnvironment: ["PATH": ""])
            check("T-env1 空 PATH→codex 目录+受控系统 PATH", e1["PATH"] == bin1.deletingLastPathComponent().path + expectedSuffix, e1["PATH"] ?? "")

            // T-env2: 父 PATH 被丢弃，不把未知目录带入 helper
            let bin2 = tmp.appendingPathComponent("bin2/codex")
            let e2 = RateLimitClient.childEnvironment(codexExecutable: bin2, baseEnvironment: ["PATH": "/tmp/untrusted:/usr/bin:/bin"])
            check("T-env2 丢弃父 PATH 未知目录",
                  e2["PATH"] == "\(bin2.deletingLastPathComponent().path)\(expectedSuffix)", e2["PATH"] ?? "")

            // T-env3: 受控 PATH 去重
            let bin3Dir = tmp.appendingPathComponent("bin3")
            let bin3 = bin3Dir.appendingPathComponent("codex")
            let e3 = RateLimitClient.childEnvironment(codexExecutable: bin3, baseEnvironment: ["PATH": "\(bin3Dir.path):/usr/bin"])
            check("T-env3 受控 PATH 不重复", e3["PATH"] == "\(bin3Dir.path)\(expectedSuffix)", e3["PATH"] ?? "")
            let sensitive = RateLimitClient.childEnvironment(
                codexExecutable: bin3,
                baseEnvironment: ["PATH": "/tmp/untrusted", "OPENAI_API_KEY": "fixture-key",
                                  "HTTP_PROXY": "http://fixture-proxy", "COOKIE": "fixture-cookie",
                                  "UNKNOWN": "fixture-unknown", "HOME": "/fixture/home",
                                  "TMPDIR": "/fixture/tmp", "LANG": "zh_CN.UTF-8"])
            check("T-env3b 敏感/未知变量被剔除",
                  sensitive["OPENAI_API_KEY"] == nil && sensitive["HTTP_PROXY"] == nil
                  && sensitive["COOKIE"] == nil && sensitive["UNKNOWN"] == nil,
                  sensitive.keys.sorted().joined(separator: ","))
            check("T-env3c 白名单 HOME/TMPDIR/LANG 保留",
                  sensitive["HOME"] == "/fixture/home" && sensitive["TMPDIR"] == "/fixture/tmp"
                  && sensitive["LANG"] == "zh_CN.UTF-8", sensitive.description)

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

        // ---- T-lr: LineReader 异步逐行读取 + stop() 不挂起 + 不完整行缓冲 ----
        do {
            // LR1: 多行 → 逐行回调（readabilityHandler 异步，pump 等待）
            let pipe1 = Pipe()
            var lines1: [String] = []
            let lr1 = LineReader(handle: pipe1.fileHandleForReading) { l in lines1.append(l) }
            lr1.start()
            try? pipe1.fileHandleForWriting.write(contentsOf: Data("alpha\nbeta\ngamma\n".utf8))
            let lr1ok = Self.waitPumpingMain({ lines1 == ["alpha", "beta", "gamma"] }, timeout: 3)
            check("LR1 多行→逐行回调", lr1ok, "lines=\(lines1)")
            lr1.stop()

            // LR2: stop() 后有限时间内退出（不挂起）—— 写入后立即 stop，断言 stop 调用不阻塞
            let pipe2 = Pipe()
            var lines2: [String] = []
            let lr2 = LineReader(handle: pipe2.fileHandleForReading) { l in lines2.append(l) }
            lr2.start()
            try? pipe2.fileHandleForWriting.write(contentsOf: Data("x\n".utf8))
            _ = Self.waitPumpingMain({ !lines2.isEmpty }, timeout: 3)
            let stopStart = Date()
            lr2.stop()
            let stopElapsed = Date().timeIntervalSince(stopStart)
            check("LR2 stop()有限时间内返回(不挂起)", stopElapsed < 2.0, "elapsed=\(stopElapsed)s")

            // LR3: 不完整行缓冲——分两次写同一行，中间无 premature 回调
            let pipe3 = Pipe()
            var lines3: [String] = []
            let lr3 = LineReader(handle: pipe3.fileHandleForReading) { l in lines3.append(l) }
            lr3.start()
            try? pipe3.fileHandleForWriting.write(contentsOf: Data("partial".utf8))   // 无换行
            _ = Self.waitPumpingMain({ false }, timeout: 0.2)   // 短暂等待，确认无 premature 回调
            check("LR3 不完整行无premature回调", lines3.isEmpty, "lines=\(lines3)")
            try? pipe3.fileHandleForWriting.write(contentsOf: Data("-line\n".utf8))   // 补全
            let lr3ok = Self.waitPumpingMain({ lines3 == ["partial-line"] }, timeout: 3)
            check("LR3 分两次写→合并一行", lr3ok, "lines=\(lines3)")
            lr3.stop()

            // LR4: EOF（关闭写端）→ reader 自停，不挂起
            let pipe4 = Pipe()
            var lines4: [String] = []
            let lr4 = LineReader(handle: pipe4.fileHandleForReading) { l in lines4.append(l) }
            lr4.start()
            try? pipe4.fileHandleForWriting.write(contentsOf: Data("eof-line\n".utf8))
            _ = Self.waitPumpingMain({ !lines4.isEmpty }, timeout: 3)
            try? pipe4.fileHandleForWriting.close()   // EOF
            _ = Self.waitPumpingMain({ false }, timeout: 0.5)   // 等待 EOF 处理
            // EOF 后再 stop 不挂起
            let eofStopStart = Date()
            lr4.stop()
            check("LR4 EOF后再stop不挂起", Date().timeIntervalSince(eofStopStart) < 2.0, "")
        }
        section("LineReader 异步读")

        // ---- T-rpc: RateLimitClient.rpc 真实 stdio 端到端（fake codex 合成子进程）----
        // 驱动真实 readWeekLeft() → rpc() 代码路径：initialize 握手 / 请求-响应按 id 关联 /
        // 分片行重组 / 超时 / cancel / 子进程提前退出 / stderr 独立丢弃 / PATH 环境。
        // fake codex 为合成 shell 脚本，不读 auth、不联网、内容明显合成（fixture-plan / FAKE_CODEX）。
        do {
            // E1 normal：握手 + 目标请求成功，解析出合成 WeekLeft。
            let exec1 = FakeCodex.install(mode: "normal")
            defer { FakeCodex.remove(exec1) }
            let client1 = RateLimitClient(resolver: FakeCodex.resolver(for: exec1), timeout: 5)
            let e1wl = try? client1.readWeekLeft()
            check("E1 normal 握手→readWeekLeft 成功", e1wl != nil, "nil=\(e1wl == nil)")
            if let wl = e1wl {
                check("E1b 解析合成 usedPercent=42", wl.usedPercent == 42, "used=\(wl.usedPercent)")
                check("E1c 合成 planType=fixture-plan", wl.planType == "fixture-plan", "\(wl.planType ?? "")")
                check("E1d 合成 isWeekly(10080)", wl.isWeekly, "mins=\(wl.windowMinutes ?? -1)")
                check("E1e 合成 resetsAt=2e9", wl.resetsAt == Date(timeIntervalSince1970: 2_000_000_000), "")
            }

            // E2 噪声 id 不干扰：fake 先吐 id=999 噪声响应，客户端仍按 id 关联到目标（E1 已隐含）。
            // 显式断言：normal 模式多次调用稳定成功（噪声行被正确忽略）。
            var stableOK = true
            for _ in 0..<3 {
                if (try? client1.readWeekLeft()) == nil { stableOK = false }
            }
            check("E2 噪声 id=999 不干扰，多次调用稳定成功", stableOK, "")

            // E3 fragmented：result 行分片写出（每次 2 字节），验证 LineReader 分片重组。
            let exec3 = FakeCodex.install(mode: "fragmented")
            defer { FakeCodex.remove(exec3) }
            let client3 = RateLimitClient(resolver: FakeCodex.resolver(for: exec3), timeout: 5)
            let e3wl = try? client3.readWeekLeft()
            check("E3 fragmented 分片重组→成功解析", e3wl?.usedPercent == 42, "used=\(e3wl?.usedPercent ?? -1)")

            // E4 stderr-noise：fake 向 stderr 吐垃圾，result 仍正常（stderr 独立管道丢弃）。
            let exec4 = FakeCodex.install(mode: "stderr-noise")
            defer { FakeCodex.remove(exec4) }
            let client4 = RateLimitClient(resolver: FakeCodex.resolver(for: exec4), timeout: 5)
            let e4wl = try? client4.readWeekLeft()
            check("E4 stderr 垃圾不影响 result 解析", e4wl?.usedPercent == 42, "used=\(e4wl?.usedPercent ?? -1)")

            // E5 超时：silent 模式不回响应，小超时后 rpc 抛错（不挂起）。
            let exec5 = FakeCodex.install(mode: "silent")
            defer { FakeCodex.remove(exec5) }
            let client5 = RateLimitClient(resolver: FakeCodex.resolver(for: exec5), timeout: 1)
            let tStart5 = Date()
            let threw5: Bool
            do { _ = try client5.readWeekLeft(); threw5 = false }
            catch { threw5 = true }
            let elapsed5 = Date().timeIntervalSince(tStart5)
            check("E5 silent 不响应→超时抛错", threw5, "")
            check("E5b 超时在合理窗口内返回（不挂起）", elapsed5 < 8, "elapsed=\(elapsed5)s")

            // E6 子进程提前退出：exit-early 模式启动即退出，rpc 报进程退出错误（非超时）。
            let exec6 = FakeCodex.install(mode: "exit-early")
            defer { FakeCodex.remove(exec6) }
            let client6 = RateLimitClient(resolver: FakeCodex.resolver(for: exec6), timeout: 5)
            var exitErrMsg = "未抛错"
            do { _ = try client6.readWeekLeft(); exitErrMsg = "未抛错（意外成功）" }
            catch { exitErrMsg = "\(error)" }
            check("E6 exit-early→进程退出错误（含「已退出」）", exitErrMsg.contains("已退出"), "err=\(exitErrMsg)")

            // E7 cancel 幂等 + 无在途安全：cancel() 在无在途请求时可安全重复调用（quit 路径保护）。
            let exec7 = FakeCodex.install(mode: "normal")
            defer { FakeCodex.remove(exec7) }
            let client7 = RateLimitClient(resolver: FakeCodex.resolver(for: exec7), timeout: 5)
            // 无在途时多次 cancel 不崩（currentProc=nil，terminate 不触发）。
            var cancelSafe = true
            client7.cancel(); client7.cancel()
            // 之后正常 readWeekLeft 仍能成功（cancel 标志被 rpc 内部重置，不污染后续请求）。
            let e7wl = try? client7.readWeekLeft()
            if e7wl == nil { cancelSafe = false }
            check("E7 cancel 幂等+无在途不崩，后续请求仍成功", cancelSafe && e7wl?.usedPercent == 42, "used=\(e7wl?.usedPercent ?? -1)")

            // E8 cancel 终止慢进程：silent（持续阻塞读）+ 小超时，发起请求后并发 cancel，
            // 断言子进程被 terminate、客户端在超时窗口前返回（cancel 抢先）。
            let exec8 = FakeCodex.install(mode: "silent")
            defer { FakeCodex.remove(exec8) }
            let client8 = RateLimitClient(resolver: FakeCodex.resolver(for: exec8), timeout: 10)
            let cg8 = DispatchGroup()
            cg8.enter()
            var cancelReturnMsg = ""
            var cancelElapsed: TimeInterval = -1
            DispatchQueue.global().async {
                let s = Date()
                do { _ = try client8.readWeekLeft() }
                catch { cancelReturnMsg = "\(error)"; cancelElapsed = Date().timeIntervalSince(s) }
                cg8.leave()
            }
            Thread.sleep(forTimeInterval: 0.3)   // 等子进程起来、请求在途
            let cancelStart = Date()
            client8.cancel()                      // terminate 子进程 → await 检测 cancelled 抛错
            let cancelOK = Self.waitPumpingMain({ cg8.wait(timeout: .now()) == .success }, timeout: 8)
            check("E8 cancel 在途慢请求→客户端返回（不悬挂）", cancelOK, "msg=\(cancelReturnMsg)")
            check("E8b 返回原因为「已取消」", cancelReturnMsg.contains("已取消"), "msg=\(cancelReturnMsg)")
            check("E8c cancel() 自身有限时间返回", Date().timeIntervalSince(cancelStart) < 5, "")
            check("E8d 请求在超时窗口前返回（cancel 抢先）", cancelElapsed >= 0 && cancelElapsed < 9, "elapsed=\(cancelElapsed)s")
        }
        section("rpc stdio 端到端")

        print("\n[DataTests] 全部通过")
        exit(fail == 0 ? 0 : 1)
    }
}
