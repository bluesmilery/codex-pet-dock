import Foundation

// MARK: - 本机 Token 日志解析（WEEK TOKENS）

/// 本机会话日志 token 读取接口，便于注入 fixture 目录测试。
protocol TokenLogReading {
    /// 读取 [from, to] 时间窗口内的 token 聚合（事件点 + 唯一会话文件数）。不含正文。
    /// 标记 mutating：实现维护进程内增量缓存（按文件 size 复用解析结果）。
    mutating func readPoints(from: Date, to: Date) throws -> TokenWindow
}

/// 解析 `~/.codex/sessions/YYYY/MM/DD/rollout-<ts>-<uuid>.jsonl`。
///
/// 合规边界：只提取每行**顶层 timestamp** 与 **payload.info.last_token_usage.total_tokens**
/// （单次增量；已验证 Σ last_token_usage.total_tokens = 会话累计，跨会话求和不重复）。
/// **绝不读取 / 记录 / 输出会话正文**；缓存也只持久化 timestamp + tokens。
///
/// 增量缓存：按「文件路径 → {size, points}」缓存整文件解析结果。size 不变则复用，变化则重读全文件
/// （rollout 文件均较小，<5MB）。缓存落盘以跨进程复用。
struct TokenUsageLogReader: TokenLogReading {
    let sessionsRoot: URL
    /// 增量缓存落盘位置（nil=仅进程内）。
    let cacheURL: URL?

    /// 进程内增量缓存（path → {size, points}）。
    private var memCache: [String: CacheEntry]

    /// 仅供测试：累计发生实际文件解析（未命中缓存）的次数，用于验证增量缓存命中。
    private(set) var debugFilesParsed = 0

    private struct CacheEntry: Codable {
        let size: Int64
        let points: [TokenUsagePoint]
    }

    init(sessionsRoot: URL, cacheURL: URL? = nil) {
        self.sessionsRoot = sessionsRoot
        self.cacheURL = cacheURL
        var loaded: [String: CacheEntry] = [:]
        if let cacheURL,
           let data = try? Data(contentsOf: cacheURL),
           let obj = try? JSONDecoder().decode([String: CacheEntry].self, from: data) {
            loaded = obj
        }
        self.memCache = loaded
    }

    mutating func readPoints(from: Date, to: Date) throws -> TokenWindow {
        var all: [TokenUsagePoint] = []
        var filesWithPoints = Set<String>()
        let fm = FileManager.default
        for file in candidateFiles(from: from, to: to) {
            let size = ((try? fm.attributesOfItem(atPath: file.path)[.size]) as? NSNumber)?.int64Value ?? -1
            let points: [TokenUsagePoint]
            if size >= 0, let hit = memCache[file.path], hit.size == size {
                points = hit.points           // size 未变 → 复用缓存
            } else {
                points = parseFile(file)
                debugFilesParsed += 1
                memCache[file.path] = CacheEntry(size: size, points: points)
            }
            // 仅纳入窗口内点；该文件贡献了至少一个窗口内点 → 计入唯一会话文件数。
            let inWindow = points.filter { $0.timestamp >= from && $0.timestamp <= to }
            if !inWindow.isEmpty {
                filesWithPoints.insert(file.path)
                all.append(contentsOf: inWindow)
            }
        }
        persist()
        return TokenWindow(points: all, sessionFileCount: filesWithPoints.count)
    }

    private func persist() {
        guard let cacheURL, let data = try? JSONEncoder().encode(memCache) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    /// 列出覆盖时间窗口的候选 jsonl 文件（按 YYYY/MM/DD 日期桶裁剪）。
    private func candidateFiles(from: Date, to: Date) -> [URL] {
        let cal = Calendar(identifier: .gregorian)
        var files: [URL] = []
        var day = cal.startOfDay(for: from)
        let last = cal.startOfDay(for: to)
        var guardCount = 0
        while day <= last && guardCount < 400 {
            let c = cal.dateComponents([.year, .month, .day], from: day)
            guard let y = c.year, let mo = c.month, let d = c.day else { break }
            let dir = sessionsRoot
                .appendingPathComponent(String(format: "%04d", y))
                .appendingPathComponent(String(format: "%02d", mo))
                .appendingPathComponent(String(format: "%02d", d))
            if let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
                for n in names where n.hasSuffix(".jsonl") {
                    files.append(dir.appendingPathComponent(n))
                }
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
            guardCount += 1
        }
        return files
    }

    private func parseFile(_ url: URL) -> [TokenUsagePoint] {
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { return [] }
        var pts: [TokenUsagePoint] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if let p = Self.parseLine(String(line)) { pts.append(p) }
        }
        return pts
    }

    /// 解析单行，提取 (timestamp, last_token_usage.{total,input,cached,output}_tokens)。
    /// 4 个数值字段缺失一律按 0；忽略无 last_token_usage / 无 timestamp / 损坏的行。**只取数值，不触碰正文**。
    static func parseLine(_ line: String) -> TokenUsagePoint? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let tsStr = obj["timestamp"] as? String,
              let ts = parseISO(tsStr) else { return nil }
        guard let payload = obj["payload"] as? [String: Any],
              let info = payload["info"] as? [String: Any],
              let usage = info["last_token_usage"] as? [String: Any] else { return nil }
        func i64(_ k: String) -> Int64 { (usage[k] as? NSNumber)?.int64Value ?? 0 }
        return TokenUsagePoint(timestamp: ts,
                               tokens: i64("total_tokens"),
                               input: i64("input_tokens"),
                               cached: i64("cached_input_tokens"),
                               output: i64("output_tokens"))
    }

    /// 宽容解析 ISO8601（兼容纳秒精度与无小数秒两种形态）。
    static func parseISO(_ s: String) -> Date? {
        var str = s
        if let dot = str.firstIndex(of: ".") {
            let intPart = String(str[..<dot])
            let rest = String(str[str.index(after: dot)...])
            var i = rest.startIndex
            while i < rest.endIndex, rest[i].isNumber { i = rest.index(after: i) }
            let digits = String(rest[rest.startIndex..<i])
            let suffix = String(rest[i...])
            let millis = String(digits.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
            str = intPart + "." + millis + suffix
        }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: str) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: str)
    }
}
