import Carbon.HIToolbox

/// Registers ⌘⇥ and ⌘⇧⇥ as Carbon global hot keys, plus the in-switcher keys while it is open.
///
/// Hot keys are matched by the WindowServer, so CmdTab receives nothing — and costs nothing —
/// for any other keystroke. This is what keeps idle CPU (and battery) usage at zero, unlike an
/// always-on keyboard event tap. Hot keys also keep working under Secure Input (password fields,
/// or macOS leaving it stuck on), which hides ordinary key presses from event taps.
@MainActor
final class HotKeyCenter {
    enum Action: UInt32 {
        case forward = 1
        case backward = 2
        case left, right, up, down
        case confirm, cancel
        case search
        case closeWindow, minimizeWindow, quitApp
    }

    var onAction: ((Action) -> Void)?

    private static let signature: OSType = 0x434D_5442 // "CMTB"
    private var eventHandler: EventHandlerRef?
    private var hotKeys: [EventHotKeyRef] = []
    private var sessionHotKeys: [EventHotKeyRef] = []

    /// Keys handled while the switcher is open. ⌘ is still held, and ⇧ may be too after ⌘⇧⇥.
    private static let sessionKeys: [(Action, Int)] = [
        (.left, kVK_LeftArrow), (.right, kVK_RightArrow), (.up, kVK_UpArrow), (.down, kVK_DownArrow),
        (.confirm, kVK_Return), (.confirm, kVK_ANSI_KeypadEnter), (.cancel, kVK_Escape),
        (.search, kVK_ANSI_F),
        (.closeWindow, kVK_ANSI_W), (.minimizeWindow, kVK_ANSI_M), (.quitApp, kVK_ANSI_Q),
    ]

    func register() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventDispatcherTarget(), hotKeyHandler, 1, &eventType, context, &eventHandler)

        registerHotKey(.forward, keyCode: kVK_Tab, modifiers: cmdKey, into: &hotKeys)
        registerHotKey(.backward, keyCode: kVK_Tab, modifiers: cmdKey | shiftKey, into: &hotKeys)
    }

    func unregister() {
        unregisterSessionKeys()
        hotKeys.forEach { UnregisterEventHotKey($0) }
        hotKeys.removeAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    /// Claims ⌘+arrows, ⌘↩, ⌘⎋, ⌘F, ⌘W, ⌘M and ⌘Q only for as long as the switcher is open.
    func registerSessionKeys() {
        guard eventHandler != nil, sessionHotKeys.isEmpty else { return }
        for (action, keyCode) in Self.sessionKeys {
            registerHotKey(action, keyCode: keyCode, modifiers: cmdKey, into: &sessionHotKeys)
            registerHotKey(action, keyCode: keyCode, modifiers: cmdKey | shiftKey, into: &sessionHotKeys)
        }
    }

    func unregisterSessionKeys() {
        sessionHotKeys.forEach { UnregisterEventHotKey($0) }
        sessionHotKeys.removeAll()
    }

    fileprivate func handleHotKey(id: UInt32) {
        guard let action = Action(rawValue: id) else { return }
        onAction?(action)
    }

    private func registerHotKey(_ action: Action, keyCode: Int, modifiers: Int, into refs: inout [EventHotKeyRef]) {
        var hotKey: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: action.rawValue)
        let status = RegisterEventHotKey(
            UInt32(keyCode), UInt32(modifiers), id, GetEventDispatcherTarget(), 0, &hotKey
        )
        if status == noErr, let hotKey {
            refs.append(hotKey)
        }
    }
}

/// Carbon delivers hot key events on the main thread.
private func hotKeyHandler(
    _: EventHandlerCallRef?,
    _ event: EventRef?,
    _ context: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let context else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    let id = hotKeyID.id
    let center = Unmanaged<HotKeyCenter>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated {
        center.handleHotKey(id: id)
    }
    return noErr
}
