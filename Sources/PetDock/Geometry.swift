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

    /// 水平 clamp 纯函数：将居中后的 dock x 限制在 `[visibleMinX, visibleMaxX - dockWidth]`。
    /// - 屏可见宽 < dock 宽 → nil（无法放下）。
    /// - 正常居中不超界 → 原值不变。
    /// - 右超界 → clamp 到 visibleMaxX - dockWidth。
    /// - 左超界 → clamp 到 visibleMinX。
    /// Quartz x 与 AppKit x 同轴，参数用同一坐标系。
    static func clampDockX(centeredX: CGFloat, dockWidth: CGFloat,
                           visibleMinX: CGFloat, visibleMaxX: CGFloat) -> CGFloat? {
        guard dockWidth <= visibleMaxX - visibleMinX else { return nil }   // 屏宽不足
        return min(max(centeredX, visibleMinX), visibleMaxX - dockWidth)
    }

    /// 计算 pet（Quartz）正下方的底座 frame，避开 `obstacles`（Quartz rects）。
    /// - x 默认按 pet 中心固定 `dockSize.width`；若水平超出 `screen.visibleFrame`，经 `clampDockX` 贴边展示；
    /// - y 从 `pet.maxY + gap` 起，对与当前 dock 矩形相交的障碍迭代下移到 `obstacle.maxY + gap`，直到不相交（多障碍链式）；
    /// - 限定同一 `screen` 的 visibleFrame：水平 clamp 后仍越界（屏宽 < dock 宽）或垂直越界返回 nil（隐藏）。
    static func safeDockFrame(pet: CGRect, avoiding obstacles: [CGRect],
                              dockSize: CGSize, gap: CGFloat, screen: NSScreen?) -> (frame: CGRect?, reason: String) {
        let dw = dockSize.width, dh = dockSize.height
        var dx = pet.origin.x + (pet.width - dw) / 2   // 默认按 pet 中心
        var dy = pet.origin.y + pet.height + gap

        // 水平 clamp：若 screen 有 visibleFrame，经纯函数 clampDockX 限制。
        if let screen {
            let v = screen.visibleFrame
            guard let clamped = clampDockX(centeredX: dx, dockWidth: dw,
                                           visibleMinX: v.minX, visibleMaxX: v.maxX) else {
                return (nil, "dock 宽度(\(Int(dw)))超过屏可见宽度(\(Int(v.width)))")
            }
            dx = clamped
        }

        let dockX = dx..<(dx + dw)
        var changed = true, iterations = 0
        while changed && iterations < 8 {           // 链式避让，n 小，8 次足够收敛
            changed = false; iterations += 1
            for obs in obstacles {
                let ox = obs.origin.x..<(obs.origin.x + obs.width)
                let oy = obs.origin.y..<(obs.origin.y + obs.height)
                if dockX.overlaps(ox) && (dy..<(dy + dh)).overlaps(oy) {
                    dy = max(dy, obs.origin.y + obs.height + gap)
                    changed = true
                }
            }
        }
        let quartz = CGRect(x: dx, y: dy, width: dw, height: dh)
        if let screen {                              // 垂直 visible 判断（AppKit，转一次）
            let appKit = appKitRectFromQuartz(quartz)
            let v = screen.visibleFrame
            let vInside = appKit.minY >= v.minY && appKit.maxY <= v.maxY
            if !vInside { return (nil, "避让后底座垂直越出 screen visibleFrame") }
        }
        return (quartz, "ok")
    }
}
