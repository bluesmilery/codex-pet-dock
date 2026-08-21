import Foundation
import os

// MARK: - Runtime evidence（默认关闭、QA 显式启用的匿名聚合诊断）
//
// Fifth break-loop runtime trigger contract：第一候选只采集白名单内的
// 枚举/计数与匿名 bucket，用于区分真实 full-hide 的触发分支。
// 不携带窗口/进程标识、标题、属主、显示器、精确坐标、原始像素比例、颜色、文字、
// 图像或可关联到单个窗口的事件序列；本文件也不新建任何捕获或计时来源。

/// 实际 dock frame 相对本 tick 无障碍基础 frame 的垂直差 bucket（不输出坐标）。
enum DockDyBucket: String, CaseIterable, Sendable {
    case base      // dy 在像素对齐容差内（视为基础位）
    case upTo32    // (0, 32]
    case upTo64    // (32, 64]
    case above64   // > 64

    /// 像素对齐容差与既有 frame 断言一致（< 1.0）；仅在分类边界使用，不输出数值。
    static func bucket(dy: CGFloat) -> DockDyBucket {
        if dy < 1.0 { return .base }
        if dy <= 32 { return .upTo32 }
        if dy <= 64 { return .upTo64 }
        return .above64
    }
}

/// 捕获结果的最小枚举镜像（不携带统计原始值）。
enum RuntimeCaptureOutcomeKind: String, Sendable {
    case stats
    case targetMissing
    case unavailable
}

/// 诊断启用参数：`--runtime-evidence=<candidate-sha>`。
/// 缺省或格式非法 → nil（保持关闭：不创建诊断文件、不增加捕获或计时开销）。
enum RuntimeEvidenceFlag {
    static let name = "--runtime-evidence"

    static func parseCandidateSHA(_ arguments: [String]) -> String? {
        for argument in arguments {
            guard argument.hasPrefix("\(name)=") else { continue }
            let sha = String(argument.dropFirst(name.count + 1))
            return isCandidateSHA(sha) ? sha : nil
        }
        return nil
    }

    /// 精确候选 provenance 合同：恰好 40 个小写十六进制字符（Git SHA-1 完整对象 SHA）。
    /// 7 位缩写、39/41/64 位、大写或非 hex 一律拒绝并保持诊断关闭。
    static func isCandidateSHA(_ value: String) -> Bool {
        value.count == 40
            && value.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }
}

/// 匿名 runtime 聚合证据收集器。
/// - 默认不存在实例（启动参数未提供时生产链全部传 nil，零 IO、零额外调用）。
/// - record 系列只在既有生产 tick / 捕获路径内递增计数，不新建计时器、不触发捕获。
/// - flush 把当前时间窗聚合计数原子写入 PetDock 私有 Diagnostics
///   （目录 0700、文件 0600、no-follow，全部由 PrivateStorage 保证）；
///   任何失败只放弃本次输出（fail-closed，不另找落盘位置）。
final class RuntimeEvidenceCollector: Sendable {
    static let outputFileName = "runtime-evidence.json"
    static let schemaVersion = "petdock-runtime-evidence/1"

    internal struct State: Sendable {
        var tickCount = 0
        var bubbleObstacleTotal = 0
        var controlObstacleTotal = 0
        var visibleObstacleTotal = 0
        var lastBubbleObstacleCount = 0
        var lastControlObstacleCount = 0
        var lastVisibleObstacleCount = 0
        var captureStatsCount = 0
        var captureTargetMissingCount = 0
        var captureUnavailableCount = 0
        var visibilityVisibleCount = 0
        var visibilityHiddenCount = 0
        var identityChangeCount = 0
        var wakeCallbackCount = 0
        var dockDyBaseCount = 0
        var dockDyUpTo32Count = 0
        var dockDyUpTo64Count = 0
        var dockDyAbove64Count = 0
        var lastDockDyBucket: DockDyBucket?
        /// 上次实际尝试写盘的单调时刻（用于 flush 节流；成功与失败都推进）。
        var lastFlushAt: TimeInterval?
        /// 自上次成功落盘后是否出现新的有意义聚合证据（accepted capture/identity/wake/
        /// layout 状态变化/dy bucket 变化）。tickCount 等单调增长本身不算新证据，
        /// 避免高频无变化 display tick 产生持续写 IO。
        var dirty = false
    }

    internal let lock = OSAllocatedUnfairLock<State>(initialState: State())
    let candidateSHA: String
    private let outputURL: URL
    /// flush 节流时钟（由调用方注入的单调时钟；本文件不读取任何系统时间源）。
    private let flushNow: @Sendable () -> TimeInterval

    /// 连续聚合证据（如每 tick identity 抖动）在窗口内合并写盘的最小间隔。
    static let minimumFlushInterval: TimeInterval = 0.5

    init(
        candidateSHA: String,
        outputURL: URL,
        flushNow: @escaping @Sendable () -> TimeInterval
    ) {
        self.candidateSHA = candidateSHA
        self.outputURL = outputURL
        self.flushNow = flushNow
    }

    // MARK: - 生产 fact owner 调用点（全部为计数，无 IO、无副作用）

    /// FollowLayoutPass：本 tick 的 bubble/control 障碍数与最终可见障碍数。
    /// 只有首个样本或三元组状态变化才标记 dirty；相同状态的重复 tick 不触发写盘。
    func recordLayoutTick(bubbleObstacles: Int, controlObstacles: Int, visibleObstacles: Int) {
        lock.withLock {
            let firstLayoutSample = $0.tickCount == 0
            let layoutStateChanged = $0.lastBubbleObstacleCount != bubbleObstacles
                || $0.lastControlObstacleCount != controlObstacles
                || $0.lastVisibleObstacleCount != visibleObstacles
            $0.tickCount += 1
            $0.bubbleObstacleTotal += bubbleObstacles
            $0.controlObstacleTotal += controlObstacles
            $0.visibleObstacleTotal += visibleObstacles
            $0.lastBubbleObstacleCount = bubbleObstacles
            $0.lastControlObstacleCount = controlObstacles
            $0.lastVisibleObstacleCount = visibleObstacles
            if firstLayoutSample || layoutStateChanged { $0.dirty = true }
        }
    }

    /// BubbleVisibilityProbe：被当前 generation+identity 接受并写入 cache 的
    /// outcome 与分类结果（枚举计数）；stale/过期结果绝不进入该方法。
    func recordCapture(kind: RuntimeCaptureOutcomeKind, visibility: BubbleVisibility) {
        lock.withLock {
            switch kind {
            case .stats: $0.captureStatsCount += 1
            case .targetMissing: $0.captureTargetMissingCount += 1
            case .unavailable: $0.captureUnavailableCount += 1
            }
            switch visibility {
            case .visible: $0.visibilityVisibleCount += 1
            case .hidden: $0.visibilityHiddenCount += 1
            }
            $0.dirty = true
        }
    }

    /// BubbleVisibilityProbe：候选集合/identity 变化导致的 generation 重建次数。
    func recordIdentityChange() {
        lock.withLock {
            $0.identityChangeCount += 1
            $0.dirty = true
        }
    }

    /// BubbleVisibilityProbe：实际发出的 visibility-change wake callback 次数。
    func recordWakeCallback() {
        lock.withLock {
            $0.wakeCallbackCount += 1
            $0.dirty = true
        }
    }

    /// DockPanel：实际写入 frame 相对本 tick 无障碍基础 frame 的匿名 dy bucket。
    /// 仅 bucket 值变化时标记 dirty（同值重复写回不算新证据）。
    func recordDockDyBucket(_ bucket: DockDyBucket) {
        lock.withLock {
            let dyBucketChanged = $0.lastDockDyBucket != bucket
            switch bucket {
            case .base: $0.dockDyBaseCount += 1
            case .upTo32: $0.dockDyUpTo32Count += 1
            case .upTo64: $0.dockDyUpTo64Count += 1
            case .above64: $0.dockDyAbove64Count += 1
            }
            $0.lastDockDyBucket = bucket
            if dyBucketChanged { $0.dirty = true }
        }
    }

    // MARK: - 序列化与落盘

    /// 白名单字段快照（固定 key 集合；新增字段必须同步 privacy 测试）。
    func snapshot() -> [String: Any] {
        lock.withLock { s in
            [
                "schema": Self.schemaVersion,
                "candidateSHA": candidateSHA,
                "tickCount": s.tickCount,
                "bubbleObstacleCount": s.bubbleObstacleTotal,
                "controlObstacleCount": s.controlObstacleTotal,
                "visibleObstacleCount": s.visibleObstacleTotal,
                "lastBubbleObstacleCount": s.lastBubbleObstacleCount,
                "lastControlObstacleCount": s.lastControlObstacleCount,
                "lastVisibleObstacleCount": s.lastVisibleObstacleCount,
                "captureStatsCount": s.captureStatsCount,
                "captureTargetMissingCount": s.captureTargetMissingCount,
                "captureUnavailableCount": s.captureUnavailableCount,
                "visibilityVisibleCount": s.visibilityVisibleCount,
                "visibilityHiddenCount": s.visibilityHiddenCount,
                "identityChangeCount": s.identityChangeCount,
                "wakeCallbackCount": s.wakeCallbackCount,
                "dockDyBaseCount": s.dockDyBaseCount,
                "dockDyUpTo32Count": s.dockDyUpTo32Count,
                "dockDyUpTo64Count": s.dockDyUpTo64Count,
                "dockDyAbove64Count": s.dockDyAbove64Count,
                "lastDockDyBucket": s.lastDockDyBucket?.rawValue ?? NSNull(),
            ]
        }
    }

    /// 原子写入私有 Diagnostics；仅在存在未落盘的新聚合证据且距上次尝试 ≥ 0.5s 时执行。
    /// 被节流的 dirty 向后携带；到期后由既有 tick 的下一次调用最终写出。
    /// 返回是否真正写盘；失败（含 symlink 拒绝）恢复 dirty，但重试同样受节流。
    @discardableResult
    func flush() -> Bool {
        let now = flushNow()
        let shouldWrite = lock.withLock { s -> Bool in
            guard s.dirty else { return false }
            if let lastFlushAt = s.lastFlushAt, now - lastFlushAt < Self.minimumFlushInterval {
                return false
            }
            s.lastFlushAt = now
            s.dirty = false
            return true
        }
        guard shouldWrite else { return false }
        let payload = snapshot()
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
            return false
        }
        do {
            try PrivateStorage.atomicWrite(data, to: outputURL)
            return true
        } catch {
            lock.withLock { $0.dirty = true }
            return false
        }
    }
}
