import AppKit

/// The switcher's lifecycle: ⌘⇥ opens a session, Tab/arrows move, releasing ⌘ commits. ⌘F searches;
/// with "Open in search mode" the search bar is there from the start and releasing ⌘ starts typing.
@MainActor
final class SwitcherController {
    /// With Quick Switch on, a ⌘⇥ tap shorter than this switches without flashing the panel,
    /// like the native switcher.
    private static let quickSwitchRevealDelay: Duration = .milliseconds(120)
    /// Fast Tab presses don't trigger a snapshot for every window passed over.
    private static let selectedPreviewDelay: Duration = .milliseconds(60)
    /// Upper bound for the selected-window snapshot, in pixels.
    private static let selectedPreviewMaxPixels = CGSize(width: 2560, height: 1600)

    private let preferences: Preferences
    private let screenRecording: ScreenRecordingPermission
    private let hotKeys: HotKeyCenter
    private let provider = WindowProvider()
    private let thumbnailer = WindowThumbnailer()
    private let panel = SwitcherPanel()
    private let overlay = SelectedWindowOverlay()
    private let keyTap = SwitcherKeyTap()
    private var session: SwitcherSession?
    private var revealTask: Task<Void, Never>?
    private var thumbnailTask: Task<Void, Never>?
    private var selectedPreviewTask: Task<Void, Never>?

    init(preferences: Preferences, screenRecording: ScreenRecordingPermission, hotKeys: HotKeyCenter) {
        self.preferences = preferences
        self.screenRecording = screenRecording
        self.hotKeys = hotKeys

        keyTap.onCommandReleased = { [weak self] in self?.commandReleased() }
        panel.onHover = { [weak self] index in self?.select(index) }
        panel.onClick = { [weak self] index in
            self?.select(index)
            self?.commit()
        }
        panel.onSearchChange = { [weak self] query in self?.search(query) }
        panel.onSearchCommand = { [weak self] command in self?.handle(command) }
        panel.onCommandKey = { [weak self] action in self?.handle(action) }
        panel.onSearchResignKey = { [weak self] in
            guard self?.panel.isTyping == true else { return }
            self?.end()
        }
    }

    func handle(_ action: HotKeyCenter.Action) {
        Log.switcher.debug("hot key \(String(describing: action), privacy: .public)")
        guard session != nil else {
            if action == .forward || action == .backward { begin(backward: action == .backward) }
            return
        }
        switch action {
        case .forward: move(backward: false)
        case .backward: move(backward: true)
        case .left: move(.left)
        case .right: move(.right)
        case .up: move(.up)
        case .down: move(.down)
        case .confirm: commit()
        case .cancel: end()
        case .search: startTyping()
        case .closeWindow: act(.closeWindow)
        case .minimizeWindow: act(.minimizeWindow)
        case .quitApp: act(.quitApp)
        default:
            break // Tiling keys are handled by the tiling engine.
        }
    }

    // MARK: - Session

    private func begin(backward: Bool) {
        var session = newSession()
        let items = session.items
        Log.switcher.debug("begin: \(items.count) items: \(items.map { "\($0.primary.appName)#\($0.primary.windowID)×\($0.windowCount)" }.joined(separator: ", "), privacy: .public)")
        guard !items.isEmpty else { return }

        // Index 0 is the window already in front, so the first press targets the next one.
        backward ? session.selection.moveBackward() : session.selection.moveForward()
        self.session = session
        thumbnailer.resetSession()
        keyTap.start()
        hotKeys.registerSessionKeys()

        // ⌘ may already be up if the shortcut was tapped very quickly.
        guard ModifierState.isCommandPressed else {
            commandReleased()
            return
        }

        guard preferences.quickSwitch else {
            reveal()
            return
        }
        revealTask = Task { [weak self] in
            try? await Task.sleep(for: Self.quickSwitchRevealDelay)
            guard !Task.isCancelled else { return }
            self?.reveal()
        }
    }

    private func newSession() -> SwitcherSession {
        SwitcherSession(
            windows: provider.windows(options: preferences.windowFilter),
            groupedByApp: preferences.groupsWindowsByApp
        )
    }

    /// The configured style, falling back to icons when previews lack Screen Recording.
    private var effectiveStyle: SwitcherStyle {
        let style = preferences.switcherStyle
        return style == .previews && !screenRecording.isGranted ? .icons : style
    }

    private func reveal() {
        guard let session else { return }
        revealTask?.cancel()
        revealTask = nil
        screenRecording.refresh()
        if preferences.opensInSearchMode {
            panel.showSearchBar()
        }
        let style = effectiveStyle
        panel.show(
            session.items,
            selectedIndex: session.selection.index,
            size: preferences.switcherSize,
            style: style,
            theme: preferences.theme,
            highlight: session.query,
            cachedThumbnail: thumbnailer.cachedThumbnail(for:)
        )
        if style == .previews {
            capturePreviews(for: session)
        }
        selectionDidChange()
    }

    /// Snapshots start only once the panel is visible, selected window first, and stop when it closes.
    private func capturePreviews(for session: SwitcherSession) {
        thumbnailTask?.cancel()
        let ids = session.items.map(\.primary.windowID)
        guard !ids.isEmpty else { return }
        let start = min(session.selection.index, ids.count - 1)
        let ordered = Array(ids[start...] + ids[..<start])
        let preview = SwitcherItemMetrics.forSize(preferences.switcherSize, style: .previews).previewSize
        let scale = panel.backingScale
        let box = CGSize(width: preview.width * scale, height: preview.height * scale)

        thumbnailTask = Task { [weak self] in
            guard let self else { return }
            await thumbnailer.capture(ordered, fittingPixelSize: box, backingScale: scale) { windowID, image in
                self.panel.setThumbnail(image, for: windowID)
            }
        }
    }

    private func commandReleased() {
        guard session != nil, !panel.isTyping else { return }
        if preferences.opensInSearchMode || panel.isSearching {
            startTyping()
        } else {
            commit()
        }
    }

    // MARK: - Selection

    private func move(backward: Bool) {
        guard var session else { return }
        backward ? session.selection.moveBackward() : session.selection.moveForward()
        self.session = session
        panel.select(session.selection.index)
        selectionDidChange()
    }

    private func move(_ direction: GridNavigation.Direction) {
        guard let session else { return }
        select(GridNavigation.move(
            from: session.selection.index,
            direction,
            count: session.items.count,
            columns: panel.columns
        ))
    }

    private func select(_ index: Int) {
        guard var session, session.selection.index != index else { return }
        session.selection.select(index)
        self.session = session
        panel.select(session.selection.index)
        selectionDidChange()
    }

    /// Updates the on-screen preview of the selected window, if enabled and the panel is showing.
    private func selectionDidChange() {
        selectedPreviewTask?.cancel()
        guard preferences.previewsSelectedWindow, panel.isVisible, let window = session?.selectedItem?.primary,
              window.element != nil, !window.isDimmed
        else {
            overlay.hide()
            return
        }

        let scale = panel.backingScale
        let box = CGSize(
            width: min(window.frame.width * scale, Self.selectedPreviewMaxPixels.width),
            height: min(window.frame.height * scale, Self.selectedPreviewMaxPixels.height)
        )
        selectedPreviewTask = Task { [weak self] in
            try? await Task.sleep(for: Self.selectedPreviewDelay)
            guard !Task.isCancelled, let self else { return }
            let snapshot = await thumbnailer.snapshot(of: window.windowID, fittingPixelSize: box, backingScale: scale)
            guard !Task.isCancelled, panel.isVisible else { return }
            overlay.show(frame: window.frame, snapshot: snapshot)
        }
    }

    // MARK: - Search

    /// Hands the keyboard to the search field. ⌘-arrows etc. go back to the text field, and ⌘ is
    /// no longer watched: from here ↩ opens and esc closes.
    private func startTyping() {
        guard session != nil, !panel.isTyping else { return }
        hotKeys.unregisterSessionKeys()
        keyTap.stop()
        panel.showSearchBar()
        reveal()
        panel.startTyping()
    }

    private func search(_ query: String) {
        guard var session else { return }
        session.search(query)
        self.session = session
        reveal()
    }

    // MARK: - Acting on the selected window

    private enum WindowAction {
        case closeWindow, minimizeWindow, quitApp
    }

    /// ⌘W / ⌘M / ⌘Q: act on the selected window and keep the switcher open on the updated list.
    private func act(_ action: WindowAction) {
        guard var session, let window = session.selectedItem?.primary else { return }
        let succeeded: Bool
        switch action {
        case .closeWindow:
            succeeded = WindowActions.close(window)
            if succeeded { session.removeWindow(window.windowID) }
        case .minimizeWindow:
            succeeded = WindowActions.minimize(window)
            if succeeded { session.markMinimized(window.windowID) }
        case .quitApp:
            succeeded = WindowActions.quit(window)
            if succeeded { session.removeApp(window.appKey) }
        }
        Log.switcher.debug("\(String(describing: action), privacy: .public) \(window.appName, privacy: .public): \(succeeded)")
        guard succeeded else {
            NSSound.beep()
            return
        }
        guard !session.items.isEmpty else {
            end()
            return
        }
        self.session = session
        if panel.isVisible { reveal() }
    }

    private func handle(_ command: SwitcherPanel.SearchCommand) {
        switch command {
        case .up: move(.up)
        case .down: move(.down)
        case .next: move(backward: false)
        case .previous: move(backward: true)
        case .confirm: commit()
        case .cancel: end()
        }
    }

    // MARK: - End

    private func commit() {
        guard let session, let item = session.selectedItem else {
            end()
            return
        }
        Log.switcher.debug("commit index \(session.selection.index) of \(session.items.count)")
        end()
        WindowActivator.activate(item)
    }

    #if DEBUG
    /// Shows the panel with the current windows, without hot keys or ⌘ tracking.
    func revealForDesignReview(searching query: String?) {
        var session = newSession()
        guard !session.items.isEmpty else { return }
        session.selection.moveForward()
        self.session = session
        reveal()
        if let query {
            panel.startTyping()
            panel.fillSearchForDesignReview(query)
            search(query)
        }
    }
    #endif

    private func end() {
        revealTask?.cancel()
        revealTask = nil
        thumbnailTask?.cancel()
        thumbnailTask = nil
        selectedPreviewTask?.cancel()
        selectedPreviewTask = nil
        keyTap.stop()
        hotKeys.unregisterSessionKeys()
        session = nil
        overlay.hide()
        panel.hide()
    }
}
