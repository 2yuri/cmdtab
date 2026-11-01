import CoreGraphics

/// Detects the release of ⌘ **only while the switcher is open**; disabled the rest of the time,
/// so it costs nothing. Modifier changes reach event taps even under Secure Input. Every other key
/// is a hot key (`HotKeyCenter`), and this tap never swallows an event.
@MainActor
final class SwitcherKeyTap {
    var onCommandReleased: (() -> Void)?

    private var tap: CFMachPort?

    /// Returns `false` if the tap can't be created (Accessibility permission missing).
    @discardableResult
    func start() -> Bool {
        if tap == nil { install() }
        guard let tap else { return false }
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
    }

    private func install() {
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.flagsChanged.rawValue),
            callback: keyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: false)
        self.tap = tap
    }

    fileprivate func handle(type: CGEventType, flags: CGEventFlags) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .flagsChanged where !flags.contains(.maskCommand):
            onCommandReleased?()
        default:
            break
        }
    }
}

/// Event taps on the main run loop are called back on the main thread.
private func keyTapCallback(
    _: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let userInfo {
        let flags = event.flags
        let keyTap = Unmanaged<SwitcherKeyTap>.fromOpaque(userInfo).takeUnretainedValue()
        MainActor.assumeIsolated { keyTap.handle(type: type, flags: flags) }
    }
    return Unmanaged.passUnretained(event)
}
