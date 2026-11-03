import AppKit
import SwiftUI

/// Makes a view draggable as a file, with AppKit's drag so CmdTab knows when the drag starts and
/// ends (⌘⇥ goes to macOS meanwhile, see `DragHandoff`). A double click opens the file.
struct FileDragSource: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> SourceView { SourceView(url: url) }

    func updateNSView(_ view: SourceView, context: Context) {
        view.url = url
    }

    final class SourceView: NSView, NSDraggingSource {
        var url: URL
        private var mouseDownEvent: NSEvent?

        init(url: URL) {
            self.url = url
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        /// SwiftUI may otherwise give the press to a view underneath.
        override func hitTest(_ point: NSPoint) -> NSView? {
            frame.contains(point) ? self : nil
        }

        override func mouseDown(with event: NSEvent) {
            Log.island.debug("shelf mouse down \(event.clickCount)")
            mouseDownEvent = event
            if event.clickCount == 2 { NSWorkspace.shared.open(url) }
        }

        override func mouseDragged(with event: NSEvent) {
            guard let start = mouseDownEvent else { return }
            let distance = hypot(event.locationInWindow.x - start.locationInWindow.x, event.locationInWindow.y - start.locationInWindow.y)
            guard distance > 3 else { return }
            mouseDownEvent = nil
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 48, height: 48)
            let point = convert(event.locationInWindow, from: nil)
            item.setDraggingFrame(NSRect(x: point.x - 24, y: point.y - 24, width: 48, height: 48), contents: icon)
            Log.island.debug("shelf drag begins")
            beginDraggingSession(with: [item], event: event, source: self)
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            // Never empty: a drag that starts over the island itself would be cancelled on the spot.
            // The island ignores its own drags (it checks the dragging source).
            [.copy, .generic]
        }

        func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
            MainActor.assumeIsolated { DragHandoff.shared.shelfDragBegan() }
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            Log.island.debug("shelf drag ended, operation \(operation.rawValue)")
            MainActor.assumeIsolated { DragHandoff.shared.shelfDragEnded() }
        }
    }
}
