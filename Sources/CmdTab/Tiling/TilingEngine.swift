import AppKit
import QuartzCore
import os

/// Scroll Lock and window dimming (Settings → Tiling, beta).
///
/// Event-driven: it only does work when a window opens, closes, moves or takes focus, or when a
/// Scroll Lock key is pressed. Each desktop keeps its own strip.
@MainActor
final class TilingEngine {
    /// A window Scroll Lock arranges.
    private struct Tiled {
        let id: CGWindowID
        let pid: pid_t
        let element: AXUIElement
        let bundleID: String
        let bundlePath: String?
        let appName: String
        var frame: CGRect
    }

    /// A drag or resize the user is doing with the mouse on a tiled window.
    private struct Interaction {
        let window: CGWindowID
        let startFrame: CGRect
        var resized = false
        var drop: Drop?
    }

    /// What letting go of a dragged window does.
    private enum Drop {
        /// Share the column with `window` (split its height), above or below it.
        case stack(onto: CGWindowID, below: Bool)
        /// Move to its own column right before or after the column holding `window`.
        case move(beside: CGWindowID, after: Bool)
        /// Become a tab of the column holding `window` (let go on its title bar).
        case tab(onto: CGWindowID)
        /// Let go on the island's columns.
        case notch(NotchDrop.Target)
    }

    private static let log = Logger(subsystem: "dev.yuri.CmdTab", category: "Tiling")
    /// Coalesces bursts of notifications (an app opening several windows) into one layout.
    private static let refreshDelay: Duration = .milliseconds(60)
    /// Our own moves echo back as moved/resized notifications for a moment.
    private static let ownMoveEcho: TimeInterval = 0.4
    private static let tileableSubroles: Set<String> = [kAXStandardWindowSubrole]
    /// The top of a column where letting go of a window makes it a tab: about a title bar's height.
    private static let titleBarZone: CGFloat = 44

    private let preferences: Preferences
    private let watcher = AXWindowWatcher()
    private let dimOverlay = DimOverlay()
    private let dropZone = DropZoneOverlay()
    /// A tiled window dragged up to the island.
    let notchDrop = NotchDrop()
    private let stripMap = StripMapHUD()
    private let scrollTap = StripScrollTap()
    /// Desktops whose strip the user scrolled by hand; focus changes hand control back.
    private var manuallyScrolled: Set<PrivateAPI.SpaceID> = []
    private var pendingScroll: CGFloat = 0
    /// The window that just lost focus, for a moment: if it turns out it was closing, focus goes
    /// back to the one before it rather than to whatever macOS picked.
    private var recentlyUnfocused: (id: CGWindowID, until: Date)?
    private var scrollTask: Task<Void, Never>?
    private let animator = WindowAnimator()
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    private var isRunning = false
    private var strips: [PrivateAPI.SpaceID: ScrollLockStrip<CGWindowID>] = [:]
    private var scrolls: [PrivateAPI.SpaceID: CGFloat] = [:]
    private var tiled: [CGWindowID: Tiled] = [:]
    /// The frames we last asked for, so a layout only touches windows that need to move.
    private var applied: [CGWindowID: CGRect] = [:]
    /// Where each window was before Scroll Lock first moved it, to put it back when it is turned off.
    private var originalFrames: [CGWindowID: CGRect] = [:]
    private var lastLayout: (space: PrivateAPI.SpaceID, screen: NSScreen, usable: CGRect, result: ScrollLockLayout<CGWindowID>.Result)?
    private var ignoreMovesUntil = Date.distantPast
    private var refreshTask: Task<Void, Never>?
    private var interaction: Interaction?
    private var mouseMonitor: Any?
    private var workspaceObservers: [NSObjectProtocol] = []

    private let hotKeys: HotKeyCenter
    private let arrangeHUD = ArrangeHUD()
    private let focusOutline = FocusOutline()
    /// S was pressed in Arrange mode: the next ← or → stacks into that side, S again unstacks.
    private var isStackArmed = false
    /// T was pressed in Arrange mode: the next ← or → tabs into that side, T again goes back.
    private var isTabArmed = false
    private let thumbnailer = WindowThumbnailer()
    private var previews: [CGWindowID: NSImage] = [:]
    private var previewTask: Task<Void, Never>?
    /// Arrange mode (⌃⌥A): numbered columns to move, reorder and stack, until ⌃⌥A or esc.
    private(set) var isArranging = false

    init(preferences: Preferences, hotKeys: HotKeyCenter) {
        self.preferences = preferences
        self.hotKeys = hotKeys
        watcher.onEvent = { [weak self] event in self?.handle(event) }
        scrollTap.onScroll = { [weak self] delta in self?.scroll(by: delta) }
        arrangeHUD.onReorder = { [weak self] from, to in self?.reorderColumn(from: from, to: to) }
        arrangeHUD.onSelect = { [weak self] index in self?.handleArrange(focusIndex: index) }
        arrangeHUD.onStack = { [weak self] from, into in self?.stackColumn(from, into: into) }
        arrangeHUD.onKey = { [weak self] action in self?.handle(action) }
        arrangeHUD.onResignKey = { [weak self] in self?.endArrange(focusingSelection: false) }
        animator.onFinish = { [weak self] in
            self?.ignoreMovesUntil = Date().addingTimeInterval(Self.ownMoveEcho)
            // Safety net: read where the windows really are and put any straggler in its place.
            self?.scheduleRefresh()
        }
    }

    private var wantsScrollLock: Bool { preferences.scrollLockEnabled }
    private var isActive: Bool {
        preferences.scrollLockEnabled || preferences.dimsOtherWindows || preferences.keepsWindowsOffEdges
    }

    // MARK: - Lifecycle

    /// Starts or stops watching windows to match the settings.
    func update() {
        if !wantsScrollLock && !strips.isEmpty {
            restoreWindows()
        }
        if isActive {
            start()
            scheduleRefresh()
        } else {
            stop()
        }
        if !wantsScrollLock {
            endArrange()
            strips.removeAll()
            scrolls.removeAll()
            applied.removeAll()
            originalFrames.removeAll()
            stripMap.hide()
        }
    }

    /// Turning Scroll Lock off puts every window back where it was before Scroll Lock moved it.
    /// Windows that opened meanwhile, or would end up mostly off screen (columns parked at an
    /// edge), are centred on their screen instead, so none gets lost.
    private func restoreWindows() {
        var cascade: CGFloat = 0
        for id in strips.values.flatMap(\.windows) {
            bringBack(id, cascade: &cascade)
        }
        ignoreMovesUntil = Date().addingTimeInterval(Self.ownMoveEcho)
        Self.log.debug("restored \(self.strips.values.map(\.windows.count).reduce(0, +)) windows")
    }

    /// Puts a window that leaves the strip back where it was before Scroll Lock, or centred on its
    /// screen when that would be mostly off screen (a parked column), so it never gets lost.
    private func bringBack(_ id: CGWindowID, cascade: inout CGFloat) {
        guard let window = tiled[id], let current = window.element.frame else { return }
        var target = originalFrames[id] ?? current
        guard let screen = ScreenGeometry.screen(containing: target) ?? lastLayout?.screen ?? NSScreen.main else { return }
        let visible = ScreenGeometry.accessibilityRect(fromAppKit: screen.visibleFrame)
        if originalFrames[id] == nil || !Self.isMostlyVisible(target, in: visible) {
            let size = CGSize(width: min(target.width, visible.width), height: min(target.height, visible.height))
            target = CGRect(
                x: visible.midX - size.width / 2 + cascade,
                y: visible.midY - size.height / 2 + cascade,
                width: size.width,
                height: size.height
            ).intersection(visible)
            cascade = (cascade + 24).truncatingRemainder(dividingBy: 24 * 8)
        }
        window.element.setFrame(target)
        originalFrames[id] = nil
        applied[id] = nil
    }

    private static func isMostlyVisible(_ frame: CGRect, in visible: CGRect) -> Bool {
        let shown = frame.intersection(visible)
        guard !shown.isNull, frame.width > 0, frame.height > 0 else { return false }
        return shown.width * shown.height >= 0.6 * frame.width * frame.height
    }

    private func start() {
        if wantsScrollLock { scrollTap.start() } else { scrollTap.stop() }
        guard !isRunning else { return }
        isRunning = true
        for app in NSWorkspace.shared.runningApplications where Self.isEligible(app) {
            watcher.watch(app.processIdentifier)
        }
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
        ]
        workspaceObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let pid = app?.processIdentifier
                let eligible = app.map(Self.isEligible) ?? false
                MainActor.assumeIsolated {
                    self?.workspaceChanged(name, pid: pid, eligible: eligible)
                }
            }
        }
        Self.log.debug("started")
    }

    private func stop() {
        endArrange()
        scrollTap.stop()
        guard isRunning else { return }
        isRunning = false
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        watcher.unwatchAll()
        refreshTask?.cancel()
        animator.stop(finishing: true)
        ignoreMovesUntil = .distantPast
        endInteraction()
        if let mouseUpMonitor { NSEvent.removeMonitor(mouseUpMonitor) }
        mouseUpMonitor = nil
        dimOverlay.hide()
        stripMap.hide()
        tiled.removeAll()
        Self.log.debug("stopped")
    }

    private func workspaceChanged(_ name: Notification.Name, pid: pid_t?, eligible: Bool) {
        if name == NSWorkspace.didLaunchApplicationNotification, let pid, eligible {
            watcher.watch(pid)
        } else if name == NSWorkspace.didTerminateApplicationNotification, let pid {
            watcher.unwatch(pid)
        }
        scheduleRefresh()
    }

    private nonisolated static func isEligible(_ app: NSRunningApplication) -> Bool {
        app.activationPolicy == .regular && app.processIdentifier != ProcessInfo.processInfo.processIdentifier
    }

    // MARK: - Events

    private func handle(_ event: AXWindowWatcher.Event) {
        switch event {
        case .windowsChanged, .focusChanged:
            scheduleRefresh()
        case let .moved(element), let .resized(element):
            guard Date() >= ignoreMovesUntil, wantsScrollLock || preferences.keepsWindowsOffEdges else { return }
            guard NSEvent.pressedMouseButtons & 1 != 0 else {
                // The app moved itself, or the window was maximized or zoomed. Lay out again.
                scheduleRefresh()
                return
            }
            var resized = false
            if case .resized = event { resized = true }
            if wantsScrollLock { beginInteraction(element, resized: resized) }
            // A window the user is dragging is fitted inside the padding once they let go.
            if interaction == nil && preferences.keepsWindowsOffEdges { refreshAfterMouseUp() }
        }
    }

    private var mouseUpMonitor: Any?

    private func refreshAfterMouseUp() {
        guard mouseUpMonitor == nil else { return }
        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let monitor = self.mouseUpMonitor { NSEvent.removeMonitor(monitor) }
                self.mouseUpMonitor = nil
                self.scheduleRefresh()
            }
        }
    }

    private func scheduleRefresh() {
        guard isRunning else { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: Self.refreshDelay)
            guard !Task.isCancelled, self?.interaction == nil else { return }
            self?.refresh()
        }
    }

    // MARK: - Keys

    func handle(_ action: HotKeyCenter.Action) {
        guard wantsScrollLock else { return }
        // In Arrange mode the selection lives in the strip (the bar has the keyboard); a refresh would
        // reset it to whatever app is frontmost.
        if !isArranging { refreshNow() }
        guard let space = lastLayout?.space, var strip = strips[space], let focused = strip.focused else {
            Self.log.debug("""
                \(String(describing: action), privacy: .public) ignored: space=\(String(describing: self.lastLayout?.space)) \
                columns=\(self.lastLayout.flatMap { self.strips[$0.space]?.columns.count } ?? -1) \
                focusedWindow=\(String(describing: self.focusedWindowID()))
                """)
            return
        }
        Self.log.debug("\(String(describing: action), privacy: .public) on window \(focused) in \(strip.columns.count) columns")

        let column = strip.focusedColumnIndex.map { strip.columns[$0] }

        switch action {
        case .focusColumnLeft, .focusColumnRight:
            let left = action == .focusColumnLeft
            let before = strip.focusedColumnIndex
            strip.focusColumn(by: left ? -1 : 1, wrapping: preferences.wrapsAround)
            if strip.focusedColumnIndex == before {
                bounce(dx: left ? 28 : -28) // Already at that end.
                return
            }
        case .focusStackUp: strip.focusInStack(by: -1)
        case .focusStackDown: strip.focusInStack(by: 1)
        case .moveColumnLeft: strip.moveFocusedColumn(by: -1)
        case .moveColumnRight: strip.moveFocusedColumn(by: 1)
        case .cycleWidth:
            guard let column else { return }
            let width = column.width.next
            strip.setWidth(width, ofColumnWith: focused)
            remember(width: width, for: focused)
        case .cycleHeight, .arrangeHeight:
            guard let height = strip.cycleHeight(of: focused) else {
                // Not in a stack: nothing to resize. Show the map so the key visibly did something.
                if let layout = lastLayout {
                    stripMap.flash(Self.map(of: layout.result, strip: strip), on: layout.screen)
                }
                return
            }
            remember(height: height, for: focused)
        case .toggleStack:
            strip.toggleStack(focused, height: stackHeight(for: focused))
        case .arrangeTab:
            isTabArmed.toggle() // T: Tab mode on or off.
            isStackArmed = false
            updateArrangePrompt()
            return
        case .arrangeTabLeft, .arrangeTabRight:
            guard strip.tabIntoNeighbour(focused, toTheRight: action == .arrangeTabRight) else {
                showArrangeNote("Nothing to tab with on that side")
                return
            }
        case .toggleTab:
            guard strip.toggleTab(focused) else {
                let note = column?.isSplit == true ? "A split stack can't hold tabs" : "Nothing on the left to tab with"
                if isArranging {
                    showArrangeNote(note)
                } else if let layout = lastLayout {
                    stripMap.flash(Self.map(of: layout.result, strip: strip), on: layout.screen)
                }
                return
            }
        case .toggleArrange:
            if isArranging { endArrange() } else { beginArrange() }
            return
        case .arrangeDone:
            endArrange()
            return
        case .arrangeStack:
            isStackArmed.toggle() // S: Stack mode on or off.
            isTabArmed = false
            updateArrangePrompt()
            return
        case .arrangeLeft: strip.moveFocusedColumn(by: -1)
        case .arrangeRight: strip.moveFocusedColumn(by: 1)
        case .arrangeToStart: strip.moveFocusedColumnToEnd(false)
        case .arrangeToEnd: strip.moveFocusedColumnToEnd(true)
        case .arrangeWider, .arrangeNarrower:
            guard let column else { return }
            let width = column.width.step(action == .arrangeWider)
            guard width != column.width else {
                showArrangeNote(action == .arrangeWider ? "Already full width" : "Already at 33%")
                return
            }
            strip.setWidth(width, ofColumnWith: focused)
            remember(width: width, for: focused)
        case .arrangeStackLeft, .arrangeStackRight:
            guard strip.stackIntoNeighbour(focused, toTheRight: action == .arrangeStackRight) else {
                showArrangeNote("Nothing to stack with on that side")
                return
            }
        case .arrangeUnstack:
            guard let column, column.windows.count > 1 else {
                showArrangeNote(isTabArmed ? "Not in tabs" : "Not in a stack")
                return
            }
            strip.unstack(focused)
        case .arrangeTaller, .arrangeShorter:
            guard let height = strip.stepHeight(of: focused, taller: action == .arrangeTaller) else {
                showArrangeNote(action == .arrangeTaller ? "As tall as it gets" : "As short as it gets")
                return
            }
            remember(height: height, for: focused)
        case .arrangeWidth:
            guard let column else { return }
            let width = column.width.next
            strip.setWidth(width, ofColumnWith: focused)
            remember(width: width, for: focused)
        default:
            if let index = action.arrangeFocusIndex {
                strip.focusColumn(at: index)
            } else {
                return
            }
        }
        strips[space] = strip
        manuallyScrolled.remove(space)
        hideFloatingApps()
        // Start sliding first, then raise the window, so it comes into view instead of flashing in
        // at the edge it was parked at. In Arrange mode the bar keeps the keyboard, so only raise it;
        // it gets focus when Arrange mode ends.
        layOut(space: space, flashMap: true)
        if let newFocus = strip.focused, newFocus != focused {
            if isArranging { raise(newFocus) } else { focus(newFocus) }
        }
    }

    // MARK: - Refresh

    private func refreshNow() {
        refreshTask?.cancel()
        refresh()
    }

    /// Reads the windows on the focused window's desktop, updates its strip and lays it out.
    private func refresh() {
        guard isRunning else { return }
        let focusedID = focusedWindowID()
        let focusedFrame = focusedID.flatMap { id in tiled[id]?.frame } ?? focusedElement()?.frame
        guard let screen = focusedFrame.flatMap(ScreenGeometry.screen(containing:)) ?? NSScreen.main,
              let space = currentSpace(for: focusedID)
        else { return }

        let screenRect = ScreenGeometry.accessibilityRect(fromAppKit: screen.frame)
        let windows = tileableWindows(on: space, screen: screenRect)
        for window in windows {
            tiled[window.id] = window
            watcher.watch(window: window.element, id: window.id, pid: window.pid)
        }

        if wantsScrollLock {
            var strip = strips[space] ?? ScrollLockStrip()
            var present = Set(windows.map(\.id))
            var cascade: CGFloat = 0
            let existing = Self.existingWindowIDs()
            // Windows that just appeared, by app: one may be taking the place of one that just left.
            var arrivals = Dictionary(grouping: windows.filter { !strip.contains($0.id) }, by: \.pid)
            var replaced = Set<CGWindowID>()
            for id in strip.windows where !present.contains(id) {
                let why = departure(of: id, space: space, existing: existing)
                Self.log.debug("strip: \(self.name(id), privacy: .public) missing → \(String(describing: why), privacy: .public)")
                switch why {
                case .stays:
                    // Missed by this read only (a slow app, a hidden one): it keeps its place.
                    present.insert(id)
                    continue
                case .floats:
                    // Still open, but its app floats now: bring it back on screen.
                    bringBack(id, cascade: &cascade)
                    ignoreMovesUntil = Date().addingTimeInterval(Self.ownMoveEcho)
                case .gone:
                    // The same app opened another window at the same moment (TablePlus swaps its
                    // launcher for a database window and back): the new one takes this column.
                    if let pid = tiled[id]?.pid, var candidates = arrivals[pid], !candidates.isEmpty {
                        let successor = candidates.removeFirst()
                        arrivals[pid] = candidates
                        strip.replace(id, with: successor.id)
                        replaced.insert(successor.id)
                        if originalFrames[successor.id] == nil { originalFrames[successor.id] = successor.frame }
                        Self.log.debug("strip: \(self.name(successor.id), privacy: .public) takes the place of \(self.name(id), privacy: .public)")
                    }
                }
                applied[id] = nil
                if let window = tiled[id] { watcher.forgetWindow(id, pid: window.pid) }
            }
            let focusBefore = strip.focused
            let leaving = Set(strip.windows).subtracting(present)
            strip.retain(present)
            // The focused window closed for good: the strip went back to the one you were on before.
            // Focus it for real, instead of following whichever window macOS picked, unless macOS
            // picked a window that just opened (that one is where you're going). macOS may move
            // focus a moment before the window is gone, so a window that lost focus just now counts.
            let followsNewWindow = focusedID.map { replaced.contains($0) || !strip.contains($0) } ?? false
            var returnTo = !followsNewWindow && focusBefore != nil && focusBefore != strip.focused ? strip.focused : nil
            if returnTo == nil, !followsNewWindow, let recent = recentlyUnfocused, leaving.contains(recent.id),
               Date() < recent.until, let previous = strip.history.last {
                returnTo = previous
                strip.focus(previous)
            }
            let isNewStrip = strip.isEmpty
            // A new strip keeps the left-to-right order windows already had.
            for window in windows.sorted(by: { $0.frame.minX < $1.frame.minX }) where !strip.contains(window.id) {
                let width = preferences.rememberedSize(for: window.bundleID)?.width ?? preferences.defaultColumnWidth
                if originalFrames[window.id] == nil { originalFrames[window.id] = window.frame }
                if isNewStrip { strip.append(window.id, width: width) } else { strip.insert(window.id, width: width) }
                Self.log.debug("strip: new \(self.name(window.id), privacy: .public)")
            }
            let previousFocus = strip.focused
            // In Arrange mode the selection is the strip's own (raising a window must not move it back).
            if let returnTo {
                Self.log.debug("strip: focused window closed, back to \(self.name(returnTo), privacy: .public) (macOS picked \(focusedID.map(self.name) ?? "none", privacy: .public))")
                focus(returnTo)
                recentlyUnfocused = nil
            } else if !isArranging, let focusedID, strip.contains(focusedID) {
                if let before = strip.focused, before != focusedID {
                    recentlyUnfocused = (before, Date().addingTimeInterval(1))
                }
                strip.focus(focusedID)
            }
            if previousFocus != strip.focused { manuallyScrolled.remove(space) }
            if strip.windows != strips[space]?.windows || previousFocus != strip.focused {
                let order = strip.columns.enumerated().map { "\($0.offset + 1):\($0.element.windows.map(self.name).joined(separator: "+"))" }
                Self.log.debug("strip: \(order.joined(separator: "  "), privacy: .public) | focus \(strip.focused.map(self.name) ?? "none", privacy: .public)")
            }
            if let focusedID, strip.contains(focusedID) { hideFloatingApps() }
            strips[space] = strip
            layOut(space: space, on: screen, flashMap: previousFocus != nil && previousFocus != strip.focused)
        }
        rescueLostWindows(on: space)
        if preferences.keepsWindowsOffEdges {
            fitWindowsInsidePadding(skipping: wantsScrollLock ? Set(strips[space]?.windows ?? []) : [])
        }
        updateDim(focusedID: focusedID, screen: screen)
    }

    /// Back on the strip: floating apps with windows on screen step aside (like ⌘H), so they don't sit
    /// on top of the columns as the strip scrolls. ⌘⇥ to one of them unhides it.
    private func hideFloatingApps() {
        guard preferences.hidesFloatingApps else { return }
        // CmdTab's own windows (Settings, the welcome window) float too and would sit on top of the
        // strip. Close just those: hiding the whole app would bring them back every time the switcher
        // panel shows, flashing them on screen.
        if !NSApp.isActive {
            for window in NSApp.windows where window.isVisible && window.level == .normal && !(window is NSPanel) {
                window.orderOut(nil)
            }
        }
        let floatingApps = Set(preferences.floatingApps.map(\.bundleID))
        let onScreen = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let pidsWithWindows = Set(onScreen.compactMap { info -> pid_t? in
            guard info[kCGWindowLayer as String] as? Int == 0 else { return nil }
            return info[kCGWindowOwnerPID as String] as? pid_t
        })
        for app in NSWorkspace.shared.runningApplications
            where !app.isHidden && !app.isActive && pidsWithWindows.contains(app.processIdentifier) && Self.isEligible(app)
            && FloatingRule.floats(
                bundleID: app.bundleIdentifier,
                bundlePath: app.bundleURL?.path,
                floatsSystemApps: preferences.floatsSystemApps,
                floatingApps: floatingApps
            ) {
            app.hide()
        }
    }

    /// Windows left off every screen that Scroll Lock doesn't arrange (say, an app that now floats
    /// still had a window parked at the edge) are brought back, so none gets lost.
    private func rescueLostWindows(on space: PrivateAPI.SpaceID) {
        let arranged = Set(strips.values.flatMap(\.windows))
        var cascade: CGFloat = 0
        for window in candidateWindows(requiresResizable: false)
            where !arranged.contains(window.id) && ScreenGeometry.screen(containing: window.frame) == nil
            && PrivateAPI.spaceIDs(forWindow: window.id).contains(space) {
            tiled[window.id] = window
            bringBack(window.id, cascade: &cascade)
            ignoreMovesUntil = Date().addingTimeInterval(Self.ownMoveEcho)
        }
    }

    /// Screen padding: moves (and if needed shrinks) every window on the visible desktops so it stays
    /// `padding` away from the screen edges. Windows Scroll Lock arranges are already laid out inside it.
    private func fitWindowsInsidePadding(skipping skipped: Set<CGWindowID>) {
        let padding = CGFloat(preferences.screenPadding)
        let current = PrivateAPI.currentSpaceIDs()
        var moved = false
        for window in candidateWindows(requiresResizable: false) where !skipped.contains(window.id) {
            guard !PrivateAPI.spaceIDs(forWindow: window.id).isDisjoint(with: current),
                  let screen = ScreenGeometry.screen(containing: window.frame)
            else { continue }
            let area = ScreenPadding.area(of: screen, padding: padding)
            guard var target = ScreenPadding.fitted(window.frame, inside: area) else { continue }
            if target.size != window.frame.size && !window.element.isSettable(kAXSizeAttribute) {
                // Fixed-size windows can only move; skip those that are larger than the area.
                guard window.frame.width <= area.width, window.frame.height <= area.height else { continue }
                target.size = window.frame.size
            }
            window.element.setFrame(target)
            moved = true
        }
        if moved { ignoreMovesUntil = Date().addingTimeInterval(Self.ownMoveEcho) }
    }

    private func layOut(space: PrivateAPI.SpaceID, on screen: NSScreen? = nil, flashMap: Bool, animated: Bool = true) {
        guard let strip = strips[space],
              let screen = screen ?? lastLayout?.screen ?? NSScreen.main
        else { return }
        // The padded area already includes the menu bar and the Dock, so the layout adds no padding of its own.
        let usable = ScreenPadding.area(of: screen, padding: CGFloat(preferences.screenPadding))
        animator.speed = preferences.animationSpeed
        let layout = ScrollLockLayout<CGWindowID>(options: .init(
            padding: 0,
            gap: CGFloat(preferences.tilingGap),
            centreMode: preferences.centreMode
        ))
        let parking = ScreenGeometry.accessibilityRect(fromAppKit: screen.frame)
        let result = layout.layout(
            strip,
            in: usable,
            previousScroll: scrolls[space] ?? 0,
            followsFocus: !manuallyScrolled.contains(space),
            parkingBounds: parking,
            // Neighbours of a full-width column still peek in through the padding.
            parksBeyondScreen: true
        )
        // Where the strip is on screen right now: mid-scroll if a scroll is running.
        let shownScroll = displayedScroll.flatMap { $0.space == space && animator.isAnimating ? $0.value : nil }
            ?? scrolls[space] ?? result.scroll
        let sameScreen = lastLayout?.space == space
        scrolls[space] = result.scroll
        lastLayout = (space, screen, usable, result)
        if isArranging { updateArrangeOverlays(strip: strip, result: result, screen: screen) }

        if animated, preferences.animatesScrolling, sameScreen, abs(shownScroll - result.scroll) > 1 {
            scrollStrip(strip, from: shownScroll, to: result, layout: layout, usable: usable, parking: parking, space: space, screen: screen)
            for (id, frame) in result.frames { applied[id] = frame }
            if flashMap && !isArranging {
                stripMap.flash(Self.map(of: result, strip: strip), on: screen)
            }
            return
        }

        let targets = result.frames.filter { id, frame in
            tiled[id] != nil && (applied[id] != frame || tiled[id].map { !$0.frame.isClose(to: frame) } == true)
        }
        if !targets.isEmpty {
            if animated && preferences.animatesScrolling {
                animate(to: targets)
            } else {
                animator.stop(finishing: false)
                for (id, frame) in targets { move(id, to: frame) }
                ignoreMovesUntil = Date().addingTimeInterval(Self.ownMoveEcho)
            }
            for (id, frame) in targets { applied[id] = frame }
        }
        if flashMap && !isArranging {
            stripMap.flash(Self.map(of: result, strip: strip), on: screen)
        }
    }

    // MARK: - Animation

    /// Slides windows to their new frames. Only positions are animated: a window that changes size gets
    /// its new size at once, since resizing every frame makes apps redraw and blur.
    private func animate(to targets: [CGWindowID: CGRect]) {
        guard let layout = lastLayout else { return }
        // Windows caught mid-scroll by this change still need to reach their place.
        var targets = targets
        for id in animator.windowsInFlight where targets[id] == nil {
            if let frame = applied[id] ?? layout.result.frames[id] { targets[id] = frame }
        }
        var moves: [WindowAnimator.Move] = []
        for (id, target) in targets {
            guard let window = tiled[id] else { continue }
            var start = window.frame
            if let position = animator.currentPosition(of: id) { start.origin = position }
            if !start.size.isClose(to: target.size) {
                window.element.setFrame(CGRect(origin: start.origin, size: target.size))
            }
            let slide = layout.result.slideFrames[id]
            // A column parked at the right edge that belongs left of the focused one comes back in
            // from the left, the side it really is on, instead of crossing the screen.
            if slide == nil, start.minX >= layout.usable.maxX - 2,
               let strip = strips[layout.space], let column = strip.columnIndex(of: id),
               let focusedColumn = strip.focusedColumnIndex, column < focusedColumn {
                start.origin = CGPoint(x: layout.usable.minX - target.width, y: target.minY)
            }
            moves.append(.init(
                id: id, pid: window.pid, element: window.element, width: target.width,
                from: start.origin, to: slide?.origin ?? target.origin,
                landing: slide == nil ? nil : target.origin
            ))
            tiled[id]?.frame = target
        }
        ignoreMovesUntil = .distantFuture
        animator.animate(moves, on: layout.screen, visibleArea: layout.usable)
    }

    private var displayedScroll: (space: PrivateAPI.SpaceID, value: CGFloat)?

    /// Scrolls the whole strip from one position to another: every frame lays the strip out at the
    /// in-between scroll, so the columns in between pass across the screen like a real scroll.
    private func scrollStrip(
        _ strip: ScrollLockStrip<CGWindowID>,
        from start: CGFloat,
        to result: ScrollLockLayout<CGWindowID>.Result,
        layout: ScrollLockLayout<CGWindowID>,
        usable: CGRect,
        parking: CGRect,
        space: PrivateAPI.SpaceID,
        screen: NSScreen
    ) {
        // Sizes change at once, before the slide (resizing every frame makes apps redraw and blur).
        for (id, target) in result.frames {
            guard let window = tiled[id] else { continue }
            if !window.frame.size.isClose(to: target.size) {
                let origin = animator.currentPosition(of: id) ?? window.frame.origin
                window.element.setFrame(CGRect(origin: origin, size: target.size))
            }
            tiled[id]?.frame = target
        }
        var windows: [CGWindowID: (pid: pid_t, element: AXUIElement)] = [:]
        for id in strip.windows {
            if let window = tiled[id] { windows[id] = (window.pid, window.element) }
        }
        let end = result.scroll
        let finalPositions = result.frames.mapValues(\.origin)
        ignoreMovesUntil = .distantFuture
        let duration = WindowAnimator.scrollDuration(distance: end - start, viewWidth: usable.width)
        animator.scroll(windows: windows, on: screen, duration: duration) { [weak self] progress in
            guard progress < 1 else {
                self?.displayedScroll = nil
                return finalPositions
            }
            let scroll = start + (end - start) * CGFloat(progress)
            self?.displayedScroll = (space, scroll)
            return layout.layout(
                strip, in: usable, previousScroll: 0, parkingBounds: parking,
                fixedScroll: scroll, parksBeyondScreen: true
            ).frames.mapValues(\.origin)
        }
    }

    private var lastBounce = Date.distantPast

    /// A short nudge and spring back when focus or a hand scroll runs into the end of the strip.
    /// - Parameter dx: positive nudges the windows right (the start was hit), negative left (the end).
    private func bounce(dx: CGFloat) {
        guard preferences.animatesScrolling, !animator.isAnimating,
              Date().timeIntervalSince(lastBounce) > WindowAnimator.bounceDuration + 0.15,
              let layout = lastLayout, let strip = strips[layout.space]
        else { return }
        lastBounce = Date()
        let moves = strip.windows.compactMap { id -> WindowAnimator.Move? in
            guard let window = tiled[id], let frame = applied[id] else { return nil }
            return .init(
                id: id, pid: window.pid, element: window.element, width: frame.width,
                from: frame.origin, to: frame.origin, kind: .bounce(dx: dx)
            )
        }
        ignoreMovesUntil = .distantFuture
        animator.animate(moves, on: layout.screen, visibleArea: layout.usable, duration: WindowAnimator.bounceDuration)
        stripMap.flash(Self.map(of: layout.result, strip: strip), on: layout.screen)
    }

    /// Moves one window, touching its size only when it changes.
    private func move(_ id: CGWindowID, to frame: CGRect) {
        guard let window = tiled[id] else { return }
        if window.frame.size.isClose(to: frame.size) {
            window.element.setPosition(frame.origin)
        } else {
            window.element.setFrame(frame)
        }
        tiled[id]?.frame = frame
    }

    /// The strip map in screen widths: a column at 50% is half a screen wide.
    private static func map(of result: ScrollLockLayout<CGWindowID>.Result, strip: ScrollLockStrip<CGWindowID>) -> StripMapHUD.Map {
        let unit = Double(max(result.viewWidth, 1))
        let focused = strip.focusedColumnIndex
        return StripMapHUD.Map(
            columns: result.columnSpans.map { (offset: Double($0.offset) / unit, width: Double($0.width) / unit) },
            focused: focused,
            viewOffset: Double(result.scroll) / unit,
            tabLabels: strip.columns.enumerated().map { index, column in
                guard column.isTabbed else { return nil }
                guard index == focused, let active = column.active, let row = column.windows.firstIndex(of: active) else {
                    return "\(column.windows.count)"
                }
                return "\(row + 1)/\(column.windows.count)"
            },
            splits: strip.columns.map { $0.isSplit ? $0.windows.count : 1 }
        )
    }

    // MARK: - ⌃⌥ + scroll

    /// Slides the strip by hand. Scroll events arrive far faster than windows can move, so they are
    /// added up and applied about once a frame.
    private func scroll(by delta: CGFloat) {
        guard wantsScrollLock else { return }
        pendingScroll += delta
        guard scrollTask == nil else { return }
        scrollTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(16))
            self?.applyPendingScroll()
        }
    }

    private func applyPendingScroll() {
        scrollTask = nil
        let delta = pendingScroll
        pendingScroll = 0
        guard delta != 0, let space = lastLayout?.space, strips[space] != nil else { return }
        manuallyScrolled.insert(space)
        let before = scrolls[space] ?? 0
        scrolls[space] = before + delta
        layOut(space: space, flashMap: true, animated: false) // Follows the fingers directly.
        if abs((scrolls[space] ?? 0) - before) < 0.5 {
            bounce(dx: delta > 0 ? -28 : 28) // Pushed past the first or last column.
        }
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            self?.settleAfterScroll(space: space)
        }
    }

    private var settleTask: Task<Void, Never>?

    /// Once the fingers stop, the column nearest the middle of the screen takes focus and the strip
    /// settles on it, so scrolling to column 2 really moves you to column 2.
    private func settleAfterScroll(space: PrivateAPI.SpaceID) {
        guard let layout = lastLayout, layout.space == space, var strip = strips[space],
              let column = ScrollLockLayout<CGWindowID>.columnNearestToCentre(of: layout.result)
        else { return }
        let previous = strip.focused
        if strip.focusedColumnIndex != column, let window = strip.columns[column].entry {
            strip.focus(window)
        }
        strips[space] = strip
        manuallyScrolled.remove(space)
        hideFloatingApps()
        layOut(space: space, flashMap: true)
        if let focused = strip.focused, focused != previous {
            focus(focused)
        }
    }

    // MARK: - Arrange mode

    private var dragStacks: Bool {
        switch preferences.dragToStack {
        case .always: true
        case .inArrangeMode: isArranging
        case .off: false
        }
    }

    private func beginArrange() {
        guard wantsScrollLock, !isArranging else { return }
        Self.log.debug("arrange mode on")
        isArranging = true
        thumbnailer.resetSession()
        isStackArmed = false
        isTabArmed = false
        // The bar takes the keyboard itself: one path for every key, and Secure Input can't hide them.
        if let layout = lastLayout, let strip = strips[layout.space] {
            updateArrangeOverlays(strip: strip, result: layout.result, screen: layout.screen)
        }
    }

    /// - Parameter focusingSelection: give focus to the window picked in Arrange mode (not when the
    ///   user left by clicking another window).
    func endArrange(focusingSelection: Bool = true) {
        guard isArranging else { return }
        Self.log.debug("arrange mode off")
        isArranging = false
        previewTask?.cancel()
        previewTask = nil
        previews.removeAll() // Snapshots live only while Arrange mode is on.
        isStackArmed = false
        isTabArmed = false
        // Hide the bar before focusing, so losing the keyboard to that window doesn't end Arrange mode twice.
        arrangeHUD.hide()
        focusOutline.hide()
        if focusingSelection, let layout = lastLayout, let selected = strips[layout.space]?.focused {
            focus(selected)
        }
    }

    private func updateArrangeOverlays(
        strip: ScrollLockStrip<CGWindowID>,
        result: ScrollLockLayout<CGWindowID>.Result,
        screen: NSScreen
    ) {
        let showsPreviews = preferences.arrangePreviews && CGPreflightScreenCaptureAccess()
        let tiles = strip.columns.map { column in
            // A column of tabs shows the one in front, and how many there are.
            let shown = column.isTabbed ? column.entry.map { [$0] } ?? [] : column.windows
            return ArrangeHUD.Tile(
                parts: zip(shown, column.isTabbed ? [1] : strip.heightFractions(of: column)).map { id, height in
                    ArrangeHUD.Tile.Part(
                        icon: tiled[id].flatMap { NSRunningApplication(processIdentifier: $0.pid)?.icon },
                        preview: showsPreviews ? previews[id] ?? Self.placeholderPreview : nil,
                        height: height
                    )
                },
                width: column.width.fraction,
                tabs: column.isTabbed ? column.windows.count : 1
            )
        }
        Self.log.debug("arrange bar: \(tiles.count) columns, \(tiles.map { "\($0.parts.count)" }.joined(separator: ","), privacy: .public)")
        if showsPreviews { capturePreviews(of: strip.windows, screen: screen) }
        stripMap.hide()
        arrangeHUD.show(
            tiles, focused: strip.focusedColumnIndex, stackPrompt: isStackArmed, tabPrompt: isTabArmed, showsHeight: true,
            note: arrangeNote, on: screen
        )
        if let focused = strip.focused, let frame = result.frames[focused] {
            focusOutline.show(around: ScreenGeometry.appKitRect(fromAccessibility: frame))
        } else {
            focusOutline.hide()
        }
    }

    /// An empty image so tiles keep their preview layout while snapshots load.
    private static let placeholderPreview = NSImage(size: NSSize(width: 16, height: 10))

    /// Snapshots for the tiles, taken only while Arrange mode is on, missing ones first.
    private func capturePreviews(of windows: [CGWindowID], screen: NSScreen) {
        let missing = windows.filter { previews[$0] == nil }
        guard !missing.isEmpty, previewTask == nil else { return }
        let scale = screen.backingScaleFactor
        previewTask = Task { [weak self] in
            guard let self else { return }
            await thumbnailer.capture(missing, fittingPixelSize: CGSize(width: 340 * scale, height: 220 * scale), backingScale: scale) { id, image in
                self.previews[id] = image
                if self.isArranging, let layout = self.lastLayout, let strip = self.strips[layout.space] {
                    self.updateArrangeOverlays(strip: strip, result: layout.result, screen: layout.screen)
                }
            }
            previewTask = nil
            // Windows that joined while this pass ran (a new stack, say) get their snapshot now.
            updateArrangePrompt()
        }
    }

    /// A short line in the Arrange mode bar when a key can't do anything, so it never looks dead.
    private func showArrangeNote(_ note: String) {
        arrangeNote = note
        updateArrangePrompt()
        noteTask?.cancel()
        noteTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            self?.arrangeNote = nil
            self?.updateArrangePrompt()
        }
    }

    private var arrangeNote: String?
    private var noteTask: Task<Void, Never>?

    private func updateArrangePrompt() {
        guard isArranging, let layout = lastLayout, let strip = strips[layout.space] else { return }
        updateArrangeOverlays(strip: strip, result: layout.result, screen: layout.screen)
    }

    private func reorderColumn(from: Int, to: Int) {
        guard let space = lastLayout?.space, var strip = strips[space] else { return }
        strip.moveColumn(from: from, to: to)
        strips[space] = strip
        manuallyScrolled.remove(space)
        layOut(space: space, flashMap: false)
    }

    private func stackColumn(_ from: Int, into target: Int) {
        guard let space = lastLayout?.space, var strip = strips[space] else { return }
        Self.log.debug("arrange: tile \(from) dropped onto \(target)")
        guard strip.stackColumn(from, into: target) else {
            let tabbed = strip.columns.indices.contains(target) && strip.columns[target].isTabbed
            showArrangeNote(tabbed ? "A column of tabs can't be split" : "That column already holds three windows")
            return
        }
        strips[space] = strip
        manuallyScrolled.remove(space)
        layOut(space: space, flashMap: false)
    }

    private func handleArrange(focusIndex: Int) {
        guard let space = lastLayout?.space, var strip = strips[space] else { return }
        let previous = strip.focused
        strip.focusColumn(at: focusIndex)
        strips[space] = strip
        manuallyScrolled.remove(space)
        layOut(space: space, flashMap: false)
        if let focused = strip.focused, focused != previous { raise(focused) }
    }

    // MARK: - Dimming

    private func updateDim(focusedID: CGWindowID?, screen: NSScreen) {
        guard preferences.dimsOtherWindows, let focusedID else {
            dimOverlay.hide()
            return
        }
        dimOverlay.show(below: focusedID, on: screen, amount: preferences.dimAmount)
    }

    // MARK: - Drag and drop, resizing

    private func beginInteraction(_ element: AXUIElement, resized: Bool) {
        guard let id = PrivateAPI.windowID(of: element), let window = tiled[id],
              let space = lastLayout?.space, strips[space]?.contains(id) == true
        else { return }
        if interaction == nil {
            interaction = Interaction(window: id, startFrame: applied[id] ?? window.frame)
            mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
                let isUp = event.type == .leftMouseUp
                MainActor.assumeIsolated {
                    if isUp { self?.finishInteraction() } else { self?.updateDropZone() }
                }
            }
        }
        if resized { interaction?.resized = true }
    }

    /// While a window is dragged over another column, shows what letting go would do: in the middle of
    /// a column it splits that column's height, on the column's left or right edge it moves there.
    /// Columns out of view are reached at the screen's edges (with full-width columns, the only way).
    private func updateDropZone() {
        if updateNotchDrop() { return }
        guard dragStacks, var interaction, !interaction.resized, let layout = lastLayout,
              let strip = strips[layout.space], let source = strip.columnIndex(of: interaction.window)
        else { return dropZone.hide() }

        let mouse = ScreenGeometry.accessibilityPoint(fromAppKit: NSEvent.mouseLocation)
        interaction.drop = nil
        var zone: CGRect?
        var label = ""
        func name(_ id: CGWindowID) -> String { tiled[id]?.appName ?? "window" }

        // A column under the pointer that is actually on screen.
        for (index, frame) in layout.result.columnFrames.enumerated()
            where index != source && frame.contains(mouse) && frame.minX < layout.usable.maxX && frame.maxX > layout.usable.minX {
            let windows = strip.columns[index].windows
            let edge = min(90, frame.width * 0.22)
            if mouse.y < frame.minY + Self.titleBarZone, let entry = strip.columns[index].entry,
               strip.canTab(interaction.window, onto: entry) {
                interaction.drop = .tab(onto: entry)
                zone = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: Self.titleBarZone)
                label = "Tab with \(name(entry))"
            } else if mouse.x < frame.minX + edge || mouse.x > frame.maxX - edge, let first = windows.first {
                let after = mouse.x > frame.midX
                interaction.drop = .move(beside: first, after: after)
                zone = CGRect(x: after ? frame.maxX - edge : frame.minX, y: frame.minY, width: edge, height: frame.height)
                label = after ? "Move after \(name(first))" : "Move before \(name(first))"
            } else if let target = windows.min(by: { abs((layout.result.frames[$0]?.midY ?? 0) - mouse.y) < abs((layout.result.frames[$1]?.midY ?? 0) - mouse.y) }),
                      strip.canStack(interaction.window, onto: target), let targetFrame = layout.result.frames[target] {
                interaction.drop = .stack(onto: target, below: true)
                zone = targetFrame.insetBy(dx: edge, dy: 0)
                label = "Split height with \(name(target))"
            }
            break
        }

        // The screen's edges stand for the neighbouring columns.
        let screenEdge: CGFloat = 90
        if interaction.drop == nil {
            let side: Int? = mouse.x < layout.usable.minX + screenEdge ? -1 : mouse.x > layout.usable.maxX - screenEdge ? 1 : nil
            if let side, strip.columns.indices.contains(source + side),
               let target = strip.columns[source + side].windows.last, strip.canStack(interaction.window, onto: target) {
                interaction.drop = .stack(onto: target, below: true)
                let width = min(320, layout.usable.width / 3)
                zone = CGRect(
                    x: side < 0 ? layout.usable.minX : layout.usable.maxX - width,
                    y: layout.usable.minY, width: width, height: layout.usable.height
                )
                label = "Split height with \(name(target))"
            }
        }

        if let zone {
            dropZone.show(ScreenGeometry.appKitRect(fromAccessibility: zone), label: label)
        } else {
            dropZone.hide()
        }
        self.interaction = interaction
    }

    /// Pushed up into the menu bar, the dragged window goes to the island's columns instead.
    /// Returns whether it's there.
    private func updateNotchDrop() -> Bool {
        let pointer = NSEvent.mouseLocation
        guard notchDrop.isEnabled, var interaction, !interaction.resized, let layout = lastLayout,
              let strip = strips[layout.space], let window = tiled[interaction.window],
              let screen = NSScreen.under(pointer),
              notchDrop.holds(pointer, screen: screen.frame)
        else {
            notchDrop.end()
            if case .notch = interaction?.drop { interaction?.drop = nil }
            return false
        }
        let columns = strip.without(interaction.window).columns.map { column in
            column.isTabbed
                ? NotchDrop.Column(apps: column.entry.map { [tiled[$0]?.pid ?? 0] } ?? [], tabs: column.windows.count)
                : NotchDrop.Column(apps: column.windows.map { tiled[$0]?.pid ?? 0 })
        }
        notchDrop.show(columns, dragged: window.pid, pointerX: pointer.x)
        interaction.drop = notchDrop.state?.target.map(Drop.notch)
        self.interaction = interaction
        dropZone.hide()
        return true
    }

    private func finishInteraction() {
        guard let interaction, let layout = lastLayout, var strip = strips[layout.space],
              let window = tiled[interaction.window]
        else { return endInteraction() }
        let atNotch = notchDrop.state != nil
        endInteraction()

        let frame = window.element.frame ?? interaction.startFrame
        if interaction.resized {
            let usableWidth = layout.usable.width
            let fraction = ScrollLockLayout<CGWindowID>.fraction(
                ofWidth: frame.width, usableWidth: usableWidth, gap: CGFloat(preferences.tilingGap)
            )
            let width = ColumnWidth.nearest(to: fraction)
            strip.setWidth(width, ofColumnWith: window.id)
            remember(width: width, for: window.id)
            if let index = strip.columnIndex(of: window.id), strip.columns[index].windows.count > 1,
               abs(frame.height - interaction.startFrame.height) > 4 {
                let usableHeight = layout.usable.height
                let height = StackHeight.nearest(to: Double((frame.height + CGFloat(preferences.tilingGap)) / (usableHeight + CGFloat(preferences.tilingGap))))
                strip.setHeight(height, of: window.id)
                remember(height: height, for: window.id)
            }
        } else if let drop = interaction.drop {
            Self.log.debug("window drop: \(String(describing: drop), privacy: .public)")
            switch drop {
            case let .stack(target, below):
                strip.stack(window.id, onto: target, below: below, height: .half) // Splits the height evenly.
            case let .move(target, after):
                strip.move(window.id, besideColumnOf: target, after: after)
            case let .tab(target):
                strip.tab(window.id, onto: target)
            case let .notch(.gap(gap)):
                strip.place(window.id, inGap: gap)
            case let .notch(.column(index)):
                strip.place(window.id, intoColumn: index)
            }
        } else if !atNotch, let index = strip.columnIndex(of: window.id), strip.columns[index].windows.count > 1,
                  let column = layout.result.columnFrames[safe: index],
                  !column.contains(ScreenGeometry.accessibilityPoint(fromAppKit: NSEvent.mouseLocation)) {
            // Dragged out of its stack.
            strip.unstack(window.id)
        }
        strip.focus(window.id)
        strips[layout.space] = strip
        applied[window.id] = nil // Its frame changed under us; always put it back.
        layOut(space: layout.space, flashMap: false)
    }

    private func endInteraction() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        interaction = nil
        dropZone.hide()
        notchDrop.end()
    }

    // MARK: - Windows

    private enum Departure { case stays, floats, gone }

    /// "TablePlus 'Connections'#1234", for the debug log.
    private func name(_ id: CGWindowID) -> String {
        guard let window = tiled[id] else { return "#\(id)" }
        return "\(window.appName)#\(id)"
    }

    /// Why a window on the strip didn't come back in this read. Only proof it left takes it off the
    /// strip; otherwise a slow app or a hidden one would lose its place and come back somewhere
    /// else, renumbering the columns.
    private func departure(of id: CGWindowID, space: PrivateAPI.SpaceID, existing: Set<CGWindowID>) -> Departure {
        guard existing.contains(id), let window = tiled[id],
              let app = NSRunningApplication(processIdentifier: window.pid), !app.isTerminated else { return .gone }
        let floatingApps = Set(preferences.floatingApps.map(\.bundleID))
        if FloatingRule.floats(bundleID: window.bundleID, bundlePath: window.bundlePath,
                               floatsSystemApps: preferences.floatsSystemApps, floatingApps: floatingApps) {
            return .floats
        }
        // Hidden (⌘H): its windows come back where they were.
        if app.isHidden { return .stays }
        // Ask the app for its windows. Some apps keep a closed window around (TablePlus does), so
        // the WindowServer still lists it: only the app knows it's closed. An app too slow to answer
        // keeps its windows in place.
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            AXUIElementCreateApplication(window.pid), kAXWindowsAttribute as CFString, &value
        )
        guard result == .success, let appWindows = value as? [AXUIElement] else { return .stays }
        guard appWindows.contains(where: { PrivateAPI.windowID(of: $0) == id }) else { return .gone }
        let attributes = window.element.values(of: [kAXMinimizedAttribute, "AXFullScreen"])
        if attributes[kAXMinimizedAttribute] as? Bool == true || attributes["AXFullScreen"] as? Bool == true {
            return .gone
        }
        let spaces = PrivateAPI.spaceIDs(forWindow: id)
        if !spaces.isEmpty && !spaces.contains(space) { return .gone }
        return .stays
    }

    /// Every window the WindowServer knows, on any desktop: what isn't here was closed.
    private static func existingWindowIDs() -> Set<CGWindowID> {
        let all = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        return Set(all.compactMap { $0[kCGWindowNumber as String] as? CGWindowID })
    }

    private func tileableWindows(on space: PrivateAPI.SpaceID, screen: CGRect) -> [Tiled] {
        let floatingApps = Set(preferences.floatingApps.map(\.bundleID))
        return candidateWindows(requiresResizable: true).filter { window in
            guard !FloatingRule.floats(
                bundleID: window.bundleID,
                bundlePath: window.bundlePath,
                floatsSystemApps: preferences.floatsSystemApps,
                floatingApps: floatingApps
            ) else { return false }
            guard PrivateAPI.spaceIDs(forWindow: window.id).contains(space) else { return false }
            // Windows we parked at an edge sit outside the screen; keep them. Windows on no screen at all
            // (lost off screen) join this one, so turning Scroll Lock off brings them back.
            let centre = CGPoint(x: window.frame.midX, y: window.frame.midY)
            return strips[space]?.contains(window.id) == true || screen.contains(centre)
                || ScreenGeometry.screen(containing: window.frame) == nil
        }
    }

    /// Standard windows of regular apps that are on screen, not minimized and not full screen.
    /// - Parameter requiresResizable: fixed-size windows (Calculator) float instead of tiling.
    private func candidateWindows(requiresResizable: Bool) -> [Tiled] {
        // Only apps with a normal window on screen need an Accessibility round trip.
        let onScreen = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let pids = Set(onScreen.compactMap { info -> pid_t? in
            guard info[kCGWindowLayer as String] as? Int == 0 else { return nil }
            return info[kCGWindowOwnerPID as String] as? pid_t
        })

        var windows: [Tiled] = []
        for app in NSWorkspace.shared.runningApplications
            where pids.contains(app.processIdentifier) && Self.isEligible(app) && !app.isHidden {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            let appWindows: [AXUIElement] = element.value(of: kAXWindowsAttribute) ?? []
            for window in appWindows {
                let attributes = window.values(of: [kAXSubroleAttribute, kAXMinimizedAttribute, "AXFullScreen", "AXModal"])
                guard let subrole = attributes[kAXSubroleAttribute] as? String, Self.tileableSubroles.contains(subrole),
                      attributes[kAXMinimizedAttribute] as? Bool != true,
                      attributes["AXFullScreen"] as? Bool != true,
                      !Self.looksLikeDialog(window, modal: attributes["AXModal"] as? Bool),
                      !requiresResizable || window.isSettable(kAXSizeAttribute),
                      let id = PrivateAPI.windowID(of: window),
                      let frame = window.frame
                else { continue }
                windows.append(Tiled(
                    id: id,
                    pid: app.processIdentifier,
                    element: window,
                    bundleID: app.bundleIdentifier ?? "pid:\(app.processIdentifier)",
                    bundlePath: app.bundleURL?.path,
                    appName: app.localizedName ?? "",
                    frame: frame
                ))
            }
        }
        return windows
    }

    /// Some apps (Java ones like DBeaver, among others) give their dialogs the standard window
    /// subrole. A modal window, or one that can neither be minimized nor zoomed, is a dialog: it
    /// floats instead of becoming a column.
    static func looksLikeDialog(_ window: AXUIElement, modal: Bool?) -> Bool {
        if modal == true { return true }
        func canUse(_ button: String) -> Bool {
            guard let element: AXUIElement = window.value(of: button) else { return false }
            return element.value(of: kAXEnabledAttribute) as Bool? ?? true
        }
        let canMinimize = canUse(kAXMinimizeButtonAttribute)
        let canZoom = canUse(kAXZoomButtonAttribute) || canUse(kAXFullScreenButtonAttribute)
        let dialog = WindowKind.isDialog(modal: modal ?? false, canMinimize: canMinimize, canZoom: canZoom)
        let title: String = window.value(of: kAXTitleAttribute) ?? ""
        let identifier: String = window.value(of: kAXIdentifierAttribute) ?? "-"
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        let app = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "?"
        let size = window.frame.map { "\(Int($0.width))x\(Int($0.height))" } ?? "?"
        let buttons = [kAXCloseButtonAttribute, kAXMinimizeButtonAttribute, kAXZoomButtonAttribute, kAXFullScreenButtonAttribute]
            .map { canUse($0) ? "1" : "0" }.joined()
        Self.log.debug("window \(app, privacy: .public) id=\(identifier, privacy: .public) size=\(size, privacy: .public) resizable=\(window.isSettable(kAXSizeAttribute)) buttons(c,m,z,f)=\(buttons, privacy: .public) modal=\(modal ?? false) → \(dialog ? "floats" : "tiles", privacy: .public)")
        return dialog
    }

    private func focusedElement() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ownPID else { return nil }
        return AXUIElementCreateApplication(app.processIdentifier).value(of: kAXFocusedWindowAttribute)
    }

    private func focusedWindowID() -> CGWindowID? {
        focusedElement().flatMap(PrivateAPI.windowID(of:))
    }

    /// The desktop the focused window is on, or the one shown on the main display.
    private func currentSpace(for focusedID: CGWindowID?) -> PrivateAPI.SpaceID? {
        let current = PrivateAPI.currentSpaceIDs()
        if let focusedID, let space = PrivateAPI.spaceIDs(forWindow: focusedID).first(where: current.contains) {
            return space
        }
        return lastLayout.map(\.space).flatMap { current.contains($0) ? $0 : nil } ?? current.first
    }

    private func focus(_ id: CGWindowID) {
        guard let window = tiled[id] else { return }
        PrivateAPI.focusWindow(id, pid: window.pid)
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
    }

    /// Brings a window to the front without taking the keyboard from the Arrange mode bar.
    private func raise(_ id: CGWindowID) {
        guard let window = tiled[id] else { return }
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
    }

    private func stackHeight(for id: CGWindowID) -> StackHeight {
        tiled[id].flatMap { preferences.rememberedSize(for: $0.bundleID)?.height } ?? preferences.defaultStackHeight
    }

    private func remember(width: ColumnWidth? = nil, height: StackHeight? = nil, for id: CGWindowID) {
        guard let window = tiled[id] else { return }
        preferences.remember(width: width, height: height, bundleID: window.bundleID, name: window.appName)
    }
}

private extension CGSize {
    func isClose(to other: CGSize, tolerance: CGFloat = 2) -> Bool {
        abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}

private extension CGRect {
    func isClose(to other: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
