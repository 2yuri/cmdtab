import AppKit
import ScreenCaptureKit

/// Takes window snapshots for previews — **only while the switcher is on screen**.
///
/// Nothing runs in the background: a capture pass starts when the panel appears and is cancelled when
/// it closes. The last snapshot of each listed window is kept in memory so the next opening can show it
/// instantly while a fresh one is taken. Snapshots are never written to disk.
@MainActor
final class WindowThumbnailer {
    private var cache: [CGWindowID: NSImage] = [:]
    /// Capturable windows from the latest lookup, reused within a switcher session.
    private var shareableWindows: [CGWindowID: SCWindow] = [:]

    /// Starts a session: the next capture looks the windows up again.
    func resetSession() {
        shareableWindows = [:]
    }

    func cachedThumbnail(for windowID: CGWindowID) -> NSImage? {
        cache[windowID]
    }

    /// Captures `windowIDs` in order, handing each snapshot to `deliver` as soon as it lands.
    /// Cancel the calling task to stop early.
    func capture(
        _ windowIDs: [CGWindowID],
        fittingPixelSize box: CGSize,
        backingScale: CGFloat,
        deliver: (CGWindowID, NSImage) -> Void
    ) async {
        guard CGPreflightScreenCaptureAccess() else { return }

        let listed = Set(windowIDs)
        cache = cache.filter { listed.contains($0.key) } // Forget windows that are gone.

        for windowID in windowIDs {
            guard !Task.isCancelled else { return }
            guard let thumbnail = await snapshot(of: windowID, fittingPixelSize: box, backingScale: backingScale)
            else { continue }
            cache[windowID] = thumbnail
            deliver(windowID, thumbnail)
        }
    }

    /// One snapshot, not cached (used at full size for the selected-window preview).
    func snapshot(of windowID: CGWindowID, fittingPixelSize box: CGSize, backingScale: CGFloat) async -> NSImage? {
        guard CGPreflightScreenCaptureAccess(), let window = await shareableWindow(windowID) else { return nil }

        let pixelSize = ThumbnailGeometry.fittedPixelSize(window: window.frame.size, box: box)
        guard pixelSize.width >= 1, pixelSize.height >= 1 else { return nil }

        let configuration = SCStreamConfiguration()
        configuration.width = Int(pixelSize.width)
        configuration.height = Int(pixelSize.height)
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true

        guard let image = try? await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: window),
            configuration: configuration
        ), !Task.isCancelled else { return nil }

        return NSImage(
            cgImage: image,
            size: NSSize(width: pixelSize.width / backingScale, height: pixelSize.height / backingScale)
        )
    }

    private func shareableWindow(_ windowID: CGWindowID) async -> SCWindow? {
        if let window = shareableWindows[windowID] { return window }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        else { return nil }
        shareableWindows = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
        return shareableWindows[windowID]
    }
}

enum ThumbnailGeometry {
    /// The largest size with the window's aspect ratio that fits in `box`, never upscaled.
    static func fittedPixelSize(window: CGSize, box: CGSize) -> CGSize {
        guard window.width > 0, window.height > 0 else { return .zero }
        let scale = min(box.width / window.width, box.height / window.height, 1)
        return CGSize(width: (window.width * scale).rounded(), height: (window.height * scale).rounded())
    }
}
