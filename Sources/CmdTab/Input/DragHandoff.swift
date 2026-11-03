import AppKit
import Carbon.HIToolbox

/// ⌘⇥ in the middle of a drag.
///
/// While a file is being dragged, a registered hot key is only delivered once the drag ends (a
/// burst of switches after the drop). So for the length of a drag the hot key is set aside and a
/// keyboard event tap (Accessibility, which CmdTab already has) catches ⌘⇥ and drives the
/// switcher. The tap exists only while the drag lasts.
///
/// Under Secure Input (a password field, or macOS leaving it stuck on) no tap sees key presses, so
/// mid-drag ⌘⇥ waits until you let go; outside drags the hot key keeps working.
///
/// A drag is noticed from mouse-drag events (only while a button is held) plus the drag pasteboard
/// changing, which is how every app starts a file drag; drags out of the Shelf also say so directly.
@MainActor
final class DragHandoff {
    static let shared = DragHandoff()

    /// Called when a drag starts and ends.
    var onChange: ((Bool) -> Void)?
    /// ⌘⇥ / ⌘⇧⇥ caught mid-drag.
    var onAction: ((HotKeyCenter.Action) -> Void)?
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?


    private(set) var isDragging = false

    private var monitors: [Any] = []
    private var changeCountAtMouseDown = 0
    private var lastCheck = Date.distantPast
    /// The end of a drag isn't always reported (the drop may swallow the mouse-up), so while one is
    /// on, this checks the mouse button a few times a second and stops with the drag.
    private var releaseCheck: Timer?

    func start() {
        guard monitors.isEmpty else { return }
        let down: NSEvent.EventTypeMask = .leftMouseDown
        let dragged: NSEvent.EventTypeMask = .leftMouseDragged
        let up: NSEvent.EventTypeMask = .leftMouseUp
        for (mask, handler) in [(down, mouseDown), (dragged, mouseDragged), (up, mouseUp)] as [(NSEvent.EventTypeMask, @MainActor () -> Void)] {
            if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { _ in MainActor.assumeIsolated { handler() } }) {
                monitors.append(global)
            }
            if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
                MainActor.assumeIsolated { handler() }
                return event
            }) {
                monitors.append(local)
            }
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        if isDragging { set(false) }
    }

    /// A drag out of the Shelf (CmdTab is the source, so it knows exactly).
    func shelfDragBegan() {
        fromShelf = true
        set(true)
    }

    func shelfDragEnded() {
        set(false)
        fromShelf = false
    }

    /// The Shelf says exactly when its drags end; the mouse button reads as up during them.
    private var fromShelf = false

    /// Tab going down while ⌘ is held: one step of the switcher, like the hot key would.
    private func installTap() {
        guard tap == nil, let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: dragKeyCallback,
            userInfo: nil
        ) else { return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        tapSource = source
    }

    private func removeTap() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        tapSource = nil
    }

    /// ⌘⇥ / ⌘⇧⇥: one step of the switcher, and the key goes no further.
    fileprivate func keyDown(keyCode: Int64, flags: CGEventFlags) -> Bool {
        guard keyCode == Int64(kVK_Tab), flags.contains(.maskCommand),
              !flags.contains(.maskControl), !flags.contains(.maskAlternate) else { return false }
        Log.island.debug("⌘⇥ mid-drag")
        onAction?(flags.contains(.maskShift) ? .backward : .forward)
        return true
    }

    fileprivate func reenableTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    private func mouseDown() {
        changeCountAtMouseDown = NSPasteboard(name: .drag).changeCount
    }

    private func mouseDragged() {
        guard !isDragging, Date.now.timeIntervalSince(lastCheck) > 0.1 else { return }
        lastCheck = .now
        if NSPasteboard(name: .drag).changeCount != changeCountAtMouseDown {
            Log.island.debug("drag noticed from the drag pasteboard")
            set(true)
        }
    }

    private func mouseUp() {
        if isDragging && !fromShelf { set(false) }
    }

    private func set(_ dragging: Bool) {
        guard dragging != isDragging else { return }
        isDragging = dragging
        removeTap()
        if dragging {
            installTap()
            Log.island.debug("drag: secure input \(IsSecureEventInputEnabled() ? "on, keys hidden" : "off", privacy: .public)")
        }
        releaseCheck?.invalidate()
        releaseCheck = nil
        if dragging {
            let timer = Timer(timeInterval: 0.25, repeats: true) { _ in
                MainActor.assumeIsolated {
                    let handoff = DragHandoff.shared
                    if !handoff.fromShelf, NSEvent.pressedMouseButtons & 1 == 0 { handoff.set(false) }
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            releaseCheck = timer
        }
        Log.island.debug("drag \(dragging ? "began" : "ended", privacy: .public): ⌘⇥ \(dragging ? "to macOS" : "back to CmdTab", privacy: .public)")
        onChange?(dragging)
    }
}


private func dragKeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { DragHandoff.shared.reenableTap() }
        return Unmanaged.passUnretained(event)
    }
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags
    let handled = MainActor.assumeIsolated { DragHandoff.shared.keyDown(keyCode: keyCode, flags: flags) }
    return handled ? nil : Unmanaged.passUnretained(event)
}
