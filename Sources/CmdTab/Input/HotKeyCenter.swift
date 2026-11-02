import Carbon.HIToolbox

/// Registers ⌘⇥ and ⌘⇧⇥ as Carbon global hot keys, plus the in-switcher keys while it is open
/// and the Scroll Lock keys while it is on.
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
        // Scroll Lock (⌃⌥…), registered only while it is on.
        case focusColumnLeft = 20, focusColumnRight, moveColumnLeft, moveColumnRight
        case focusStackUp, focusStackDown, cycleWidth, cycleHeight, toggleStack
        case toggleArrange
        // Arrange mode keys, typed into its bar (see `ArrangeHUD`).
        case arrangeLeft = 40, arrangeRight, arrangeToStart, arrangeToEnd, arrangeWidth, arrangeStack, arrangeDone
        case arrangeHeight, arrangeStackLeft, arrangeStackRight
        case arrangeWider = 70, arrangeNarrower, arrangeTaller, arrangeShorter, arrangeUnstack
        case arrangeFocus1 = 51, arrangeFocus2, arrangeFocus3, arrangeFocus4, arrangeFocus5
        case arrangeFocus6, arrangeFocus7, arrangeFocus8, arrangeFocus9

        /// 0-based column for 1–9 in Arrange mode.
        var arrangeFocusIndex: Int? {
            (Action.arrangeFocus1.rawValue...Action.arrangeFocus9.rawValue).contains(rawValue)
                ? Int(rawValue - Action.arrangeFocus1.rawValue) : nil
        }

        var isTiling: Bool { rawValue >= Action.focusColumnLeft.rawValue }
    }

    var onAction: ((Action) -> Void)?

    private static let signature: OSType = 0x434D_5442 // "CMTB"
    private var eventHandler: EventHandlerRef?
    private var hotKeys: [EventHotKeyRef] = []
    private var sessionHotKeys: [EventHotKeyRef] = []
    private var tilingHotKeys: [EventHotKeyRef] = []

    /// Keys handled while the switcher is open. ⌘ is still held, and ⇧ may be too after ⌘⇧⇥.
    private static let sessionKeys: [(Action, Int)] = [
        (.left, kVK_LeftArrow), (.right, kVK_RightArrow), (.up, kVK_UpArrow), (.down, kVK_DownArrow),
        (.confirm, kVK_Return), (.confirm, kVK_ANSI_KeypadEnter), (.cancel, kVK_Escape),
        (.search, kVK_ANSI_F),
        (.closeWindow, kVK_ANSI_W), (.minimizeWindow, kVK_ANSI_M), (.quitApp, kVK_ANSI_Q),
    ]

    /// Scroll Lock keys: ⌃⌥ plus arrows, R and S.
    private static let tilingKeys: [(Action, Int, Int)] = [
        (.focusColumnLeft, kVK_LeftArrow, controlKey | optionKey),
        (.focusColumnRight, kVK_RightArrow, controlKey | optionKey),
        (.moveColumnLeft, kVK_LeftArrow, controlKey | optionKey | shiftKey),
        (.moveColumnRight, kVK_RightArrow, controlKey | optionKey | shiftKey),
        (.focusStackUp, kVK_UpArrow, controlKey | optionKey),
        (.focusStackDown, kVK_DownArrow, controlKey | optionKey),
        (.cycleWidth, kVK_ANSI_R, controlKey | optionKey),
        (.cycleHeight, kVK_ANSI_R, controlKey | optionKey | shiftKey),
        (.toggleStack, kVK_ANSI_S, controlKey | optionKey),
        (.toggleArrange, kVK_ANSI_A, controlKey | optionKey),
    ]

    var isRegistered: Bool { !hotKeys.isEmpty }

    func register() {
        installHandlerIfNeeded()
        guard hotKeys.isEmpty else { return }
        registerHotKey(.forward, keyCode: kVK_Tab, modifiers: cmdKey, into: &hotKeys)
        registerHotKey(.backward, keyCode: kVK_Tab, modifiers: cmdKey | shiftKey, into: &hotKeys)
    }

    func unregister() {
        unregisterSessionKeys()
        hotKeys.forEach { UnregisterEventHotKey($0) }
        hotKeys.removeAll()
        removeHandlerIfUnused()
    }

    func registerTilingKeys() {
        installHandlerIfNeeded()
        guard tilingHotKeys.isEmpty else { return }
        for (action, keyCode, modifiers) in Self.tilingKeys {
            registerHotKey(action, keyCode: keyCode, modifiers: modifiers, into: &tilingHotKeys)
        }
    }

    func unregisterTilingKeys() {
        tilingHotKeys.forEach { UnregisterEventHotKey($0) }
        tilingHotKeys.removeAll()
        removeHandlerIfUnused()
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventDispatcherTarget(), hotKeyHandler, 1, &eventType, context, &eventHandler)
    }

    private func removeHandlerIfUnused() {
        guard hotKeys.isEmpty, sessionHotKeys.isEmpty, tilingHotKeys.isEmpty, let eventHandler else { return }
        RemoveEventHandler(eventHandler)
        self.eventHandler = nil
    }

    /// Claims ⌘+arrows, ⌘↩, ⌘⎋, ⌘F, ⌘W, ⌘M and ⌘Q only for as long as the switcher is open.
    func registerSessionKeys() {
        guard !hotKeys.isEmpty, sessionHotKeys.isEmpty else { return }
        for (action, keyCode) in Self.sessionKeys {
            registerHotKey(action, keyCode: keyCode, modifiers: cmdKey, into: &sessionHotKeys)
            registerHotKey(action, keyCode: keyCode, modifiers: cmdKey | shiftKey, into: &sessionHotKeys)
        }
    }

    func unregisterSessionKeys() {
        sessionHotKeys.forEach { UnregisterEventHotKey($0) }
        sessionHotKeys.removeAll()
        removeHandlerIfUnused()
    }

    fileprivate func handleHotKey(id: UInt32) {
        guard let action = Action(rawValue: id) else { return }
        if action.isTiling { Log.activation.debug("tiling key \(String(describing: action), privacy: .public)") }
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
        } else {
            // Usually another app (a launcher or window manager) already owns this shortcut.
            Log.activation.error("hot key \(String(describing: action), privacy: .public) not registered: \(status)")
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
