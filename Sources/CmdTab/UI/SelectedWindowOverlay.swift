import AppKit

/// Shows the selected window where it really is on screen, above every other window but below the
/// switcher: its snapshot when Screen Recording is allowed, otherwise an accent outline of its frame.
@MainActor
final class SelectedWindowOverlay {
    private let panel: NSPanel
    private let imageView = NSImageView()
    private let outline = NSView()

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        // Just below the switcher (`.popUpMenu`) so it never covers it.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        let content = NSView()
        content.wantsLayer = true
        imageView.imageScaling = .scaleAxesIndependently
        imageView.autoresizingMask = [.width, .height]
        outline.wantsLayer = true
        outline.autoresizingMask = [.width, .height]
        outline.layer?.cornerRadius = 10
        outline.layer?.borderWidth = 3
        content.addSubview(imageView)
        content.addSubview(outline)
        panel.contentView = content
    }

    /// `frame` uses window-list coordinates (top-left origin of the main display).
    func show(frame: CGRect, snapshot: NSImage?) {
        guard let cocoaFrame = Self.cocoaFrame(fromWindowListFrame: frame) else {
            hide()
            return
        }
        let accent = NSColor(named: "AccentColor") ?? .controlAccentColor
        imageView.image = snapshot
        imageView.isHidden = snapshot == nil
        outline.layer?.borderColor = accent.cgColor
        outline.layer?.backgroundColor = snapshot == nil ? accent.withAlphaComponent(0.12).cgColor : nil
        panel.setFrame(cocoaFrame, display: true)
        imageView.frame = panel.contentView?.bounds ?? .zero
        outline.frame = panel.contentView?.bounds ?? .zero
        panel.orderFrontRegardless()
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        imageView.image = nil
    }

    /// The window list measures from the top of the main display; AppKit from its bottom.
    static func cocoaFrame(fromWindowListFrame frame: CGRect) -> CGRect? {
        guard frame.width > 1, frame.height > 1, let mainHeight = NSScreen.screens.first?.frame.height else {
            return nil
        }
        return CGRect(x: frame.minX, y: mainHeight - frame.maxY, width: frame.width, height: frame.height)
    }
}
