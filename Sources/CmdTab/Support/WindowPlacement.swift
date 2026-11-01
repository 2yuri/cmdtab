import CoreGraphics

enum WindowPlacement {
    /// Horizontally centred; vertically a little above the middle (a third of the free space on top),
    /// which reads as centred to the eye, like `NSWindow.center()`. Clamped inside `visibleFrame`.
    static func centeredOrigin(for size: CGSize, in visibleFrame: CGRect) -> CGPoint {
        let x = visibleFrame.midX - size.width / 2
        let freeHeight = max(visibleFrame.height - size.height, 0)
        let y = visibleFrame.minY + freeHeight * 2 / 3
        return CGPoint(
            x: max(visibleFrame.minX, min(x, visibleFrame.maxX - size.width)).rounded(),
            y: max(visibleFrame.minY, y).rounded()
        )
    }
}
