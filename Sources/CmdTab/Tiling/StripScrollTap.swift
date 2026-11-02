import CoreGraphics

/// ⌃⌥ + scroll slides the Scroll Lock strip.
///
/// Two taps keep this light: one sees only modifier changes (a handful of events while typing), and
/// the scroll tap is switched on only while ⌃ and ⌥ are held. Scrolls with ⌃⌥ are swallowed so the
/// app under the pointer doesn't scroll too; every other scroll passes through untouched.
@MainActor
final class StripScrollTap {
    /// Horizontal distance in points; positive moves the view to the right along the strip.
    var onScroll: ((CGFloat) -> Void)?

    private var modifierTap: CFMachPort?
    private var scrollTap: CFMachPort?

    func start() {
        if modifierTap == nil {
            modifierTap = makeTap(listenOnly: true, events: 1 << CGEventType.flagsChanged.rawValue)
        }
        if scrollTap == nil {
            scrollTap = makeTap(listenOnly: false, events: 1 << CGEventType.scrollWheel.rawValue)
        }
        if let modifierTap { CGEvent.tapEnable(tap: modifierTap, enable: true) }
        if let scrollTap { CGEvent.tapEnable(tap: scrollTap, enable: false) }
    }

    func stop() {
        if let modifierTap { CGEvent.tapEnable(tap: modifierTap, enable: false) }
        if let scrollTap { CGEvent.tapEnable(tap: scrollTap, enable: false) }
    }

    private func makeTap(listenOnly: Bool, events: Int) -> CFMachPort? {
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: listenOnly ? .listenOnly : .defaultTap,
            eventsOfInterest: CGEventMask(events),
            callback: stripScrollCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return nil }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: false)
        return tap
    }

    static func isScrollChord(_ flags: CGEventFlags) -> Bool {
        flags.contains(.maskControl) && flags.contains(.maskAlternate) && !flags.contains(.maskCommand)
    }

    /// Returns whether the event should be swallowed.
    fileprivate func handle(type: CGEventType, flags: CGEventFlags, horizontal: Double, vertical: Double) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let modifierTap { CGEvent.tapEnable(tap: modifierTap, enable: true) }
            return false
        case .flagsChanged:
            if let scrollTap { CGEvent.tapEnable(tap: scrollTap, enable: Self.isScrollChord(flags)) }
            return false
        case .scrollWheel:
            guard Self.isScrollChord(flags) else { return false }
            // A trackpad swipe sideways, or a plain mouse wheel (vertical) used to go sideways.
            let delta = horizontal != 0 ? horizontal : vertical
            onScroll?(CGFloat(-delta))
            return true
        default:
            return false
        }
    }
}

/// Event taps on the main run loop are called back on the main thread.
private func stripScrollCallback(
    _: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let flags = event.flags
    let horizontal = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
    let vertical = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
    let tap = Unmanaged<StripScrollTap>.fromOpaque(userInfo).takeUnretainedValue()
    let swallow = MainActor.assumeIsolated {
        tap.handle(type: type, flags: flags, horizontal: horizontal, vertical: vertical)
    }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
