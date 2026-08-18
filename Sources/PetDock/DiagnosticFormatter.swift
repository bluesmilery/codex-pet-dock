import Foundation

/// Privacy-preserving diagnostic projections.  Window titles, owner names,
/// WID/PID values and exact coordinates remain in-memory for recognition but
/// are never emitted by the default diagnostic path.
enum DiagnosticFormatter {
    static func candidateSummary(_ candidate: WinCandidate) -> String {
        let shape: String
        if candidate.isLikelyMainWindow {
            shape = "main"
        } else if candidate.isReasonablePet {
            shape = "pet-shaped"
        } else if candidate.isPetShaped {
            shape = "small-window"
        } else {
            shape = "other"
        }
        let size = sizeClass(candidate.bounds.size)
        return "shape=\(shape) size=\(size) layer=\(candidate.layer) "
            + "alpha=\(String(format: "%.2f", candidate.alpha)) "
            + "onscreen=\(candidate.isOnscreen) sharing=\(candidate.sharingState)"
    }

    static func selectionSummary(_ selection: SelectionResult) -> String {
        let selected = selection.selected.map { candidateSummary($0) } ?? "none"
        return "selected=\(selected) reason=\(sanitizeReason(selection.reason)) "
            + "hits=\(selection.hitFlags.map(sanitizeFlag).joined(separator: ",")) "
            + "candidateCount=\(selection.allCandidates.count)"
    }

    static func sizeClass(_ size: CGSize) -> String {
        let maxSide = max(size.width, size.height)
        if maxSide <= 64 { return "tiny" }
        if maxSide <= 320 { return "small" }
        if maxSide <= 800 { return "medium" }
        return "large"
    }

    private static func sanitizeReason(_ reason: String) -> String {
        var value = reason
        for pattern in [#"(?i)\bwid\s*=\s*\d+"#, #"\b\d+\s*x\s*\d+\b"#] {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(value.startIndex..<value.endIndex, in: value)
                value = regex.stringByReplacingMatches(in: value, options: [], range: range,
                                                        withTemplate: "<redacted>")
            }
        }
        return value
    }

    private static func sanitizeFlag(_ flag: String) -> String {
        if flag.lowercased().contains("wid") { return "hysteresis" }
        if flag.lowercased().hasPrefix("area=") { return "shape" }
        if flag.lowercased().hasPrefix("layer=") { return "floating-layer" }
        return flag.replacingOccurrences(of: "=", with: "~")
            .replacingOccurrences(of: " ", with: "-")
    }
}
