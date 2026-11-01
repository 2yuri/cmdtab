import AppKit
import SwiftUI

/// Owns one lazily created window that hosts a SwiftUI view, and brings it forward on demand.
@MainActor
final class HostingWindowController<Content: View> {
    private let makeContent: () -> Content
    private let title: String
    private var window: NSWindow?

    init(title: String, content: @escaping () -> Content) {
        self.title = title
        self.makeContent = content
    }

    var isVisible: Bool { window?.isVisible ?? false }

    func show(appearance: NSAppearance?) {
        let window = window ?? makeWindow()
        self.window = window
        window.appearance = appearance
        if !window.isVisible {
            center(window)
        }
        // CmdTab is a menu bar app: it must activate itself for the window to take focus.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func setAppearance(_ appearance: NSAppearance?) {
        window?.appearance = appearance
    }

    func close() {
        window?.close()
    }

    private func makeWindow() -> NSWindow {
        let controller = NSHostingController(rootView: makeContent())
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        // Size the window from its SwiftUI content now. Centring before this would centre an empty
        // window, which then grows from that point and ends up off to the side.
        window.setContentSize(controller.view.fittingSize)
        return window
    }

    /// Centres on the screen the user is working on (the one under the pointer), slightly above the
    /// middle like system windows.
    private func center(_ window: NSWindow) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else {
            window.center()
            return
        }
        window.setFrameOrigin(WindowPlacement.centeredOrigin(for: window.frame.size, in: screen.visibleFrame))
    }
}
