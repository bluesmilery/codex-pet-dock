import Cocoa

/// 坐标转换：Quartz 全局坐标（主屏左上原点，y 向下，跨屏可负）
/// ↔ AppKit 全局坐标（主屏左下原点，y 向上，即 NSScreen.frame 用的坐标系）。
/// NSWindow/NSPanel.setFrame 接收的就是 AppKit 全局坐标。
enum Geometry {

    /// Quartz 全局矩形 → AppKit 全局矩形。统一公式，适用于多显示器 / 负坐标。
    /// 推导：两坐标系共享 x 轴与全局宽度，仅 y 轴方向相反、原点在主屏对边。
    ///   appKitOriginY = mainScreenHeight - quartzOriginY - height
    static func appKitRectFromQuartz(_ q: CGRect) -> NSRect {
        guard let main = NSScreen.screens.first else {
            return NSRect(origin: q.origin, size: q.size)
        }
        let mainH = main.frame.height
        return NSRect(
            x: q.origin.x,
            y: mainH - q.origin.y - q.height,
            width: q.width,
            height: q.height
        )
    }

    /// 给定 Quartz 全局坐标下的中心点，返回它所在的 NSScreen（用于诊断 / 边界判断）。
    static func screenContaining(quartzCenterX cx: CGFloat, _ cy: CGFloat) -> NSScreen? {
        guard let main = NSScreen.screens.first else { return nil }
        let ay = main.frame.height - cy // 该中心点在 AppKit 全局系下的 y
        for s in NSScreen.screens where s.frame.contains(NSPoint(x: cx, y: ay)) {
            return s
        }
        // fallback：最近的屏幕
        var best: NSScreen?
        var bestDist: CGFloat = .greatestFiniteMagnitude
        for s in NSScreen.screens {
            let f = s.frame
            let dx = max(f.minX - cx, 0, cx - f.maxX)
            let dy = max(f.minY - ay, 0, ay - f.maxY)
            let d = dx * dx + dy * dy
            if d < bestDist { bestDist = d; best = s }
        }
        return best
    }
}
