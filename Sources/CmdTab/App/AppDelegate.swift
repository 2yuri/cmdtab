import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = Preferences()
    private let permission = AccessibilityPermission()
    private let screenRecording = ScreenRecordingPermission()
    private let hotKeys = HotKeyCenter()
    private let nativeSwitcher = NativeSwitcherGuard()
    private lazy var tiling = TilingEngine(preferences: preferences, hotKeys: hotKeys)
    private var updater: Updater?
    private lazy var island = IslandController(preferences: preferences)
    private lazy var switcher = SwitcherController(
        preferences: preferences,
        screenRecording: screenRecording,
        hotKeys: hotKeys
    )
    private lazy var statusMenu = StatusMenu(
        preferences: preferences,
        permission: permission,
        onOpenSettings: { [weak self] in self?.openSettings() }
    )
    private lazy var settingsWindow: HostingWindowController<SettingsView> = HostingWindowController(title: "CmdTab Settings") { [preferences, permission, screenRecording, weak self] in
        SettingsView(preferences: preferences, permission: permission, screenRecording: screenRecording, updater: self?.updater)
    }
    private lazy var onboardingWindow: HostingWindowController<OnboardingView> = HostingWindowController(
        title: "Welcome to CmdTab"
    ) { [permission, weak self] in
        OnboardingView(permission: permission, onLater: { self?.onboardingWindow.close() })
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningUnitTests else { return }
        #if DEBUG
        if let preview = DesignPreview.requested {
            showPreview(preview)
            return
        }
        #endif
        // A second copy would fight the first one over ⌘⇥ and restore the native switcher when it quits.
        if let runningCopy = Self.otherRunningInstance {
            NSWorkspace.shared.openApplication(at: runningCopy.bundleURL ?? Bundle.main.bundleURL, configuration: .init())
            NSApp.terminate(nil)
            return
        }

        updater = Updater()
        hotKeys.onAction = { [weak self] action in
            if action.isTiling { self?.tiling.handle(action) } else { self?.switcher.handle(action) }
        }
        DragHandoff.shared.onChange = { [weak self] _ in self?.updateSwitcherActivation() }
        DragHandoff.shared.onAction = { [weak self] action in self?.switcher.handle(action) }
        DragHandoff.shared.start()
        statusMenu.refreshVisibility()
        updateSwitcherActivation()

        observeChanges(of: { [preferences, permission] in
            (permission.isGranted, preferences.replacesNativeSwitcher, preferences.exceptions)
        }) { [weak self] _ in
            self?.updateSwitcherActivation()
        }
        // "Leave ⌘⇥" exceptions depend on which app is in front. Event-driven: fires only on app switches.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateSwitcherActivation() }
        }
        updateTiling()
        observeChanges(of: { [preferences, permission] in
            (permission.isGranted, preferences.scrollLockEnabled, preferences.dimsOtherWindows, preferences.keepsWindowsOffEdges)
        }) { [weak self] _ in
            self?.updateTiling()
        }
        // Layout settings: lay the strip out again as soon as they change.
        observeChanges(of: { [preferences] in
            (preferences.tilingPadding, preferences.tilingGap, preferences.centreMode, preferences.dimAmount,
             preferences.floatsSystemApps, preferences.floatingApps, preferences.hidesFloatingApps)
        }) { [weak self] _ in
            self?.tiling.update()
        }
        island.services.notchDrop = tiling.notchDrop
        island.update()
        observeChanges(of: { [preferences] in
            (preferences.islandEnabled, preferences.islandModules, preferences.islandApprovals,
             preferences.islandNotifies, preferences.islandScreen,
             (preferences.islandWatchesNewFiles, preferences.scrollLockEnabled, preferences.islandEffect,
              preferences.islandEffectPausesOnBattery))
        }) { [weak self] _ in
            self?.island.update()
        }
        observeChanges(of: { [preferences] in preferences.showsMenuBarIcon }) { [weak self] _ in
            self?.statusMenu.refreshVisibility()
        }
        observeChanges(of: { [preferences] in preferences.theme }) { [weak self] theme in
            self?.settingsWindow.setAppearance(theme.appearance)
        }

        if !permission.isGranted {
            onboardingWindow.show(appearance: preferences.theme.appearance)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeys.unregister()
        nativeSwitcher.restoreNativeSwitcher()
    }

    /// Opening the app again (Finder, Spotlight) shows Settings and brings back a hidden menu bar icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        preferences.showsMenuBarIcon = true
        openSettings()
        return false
    }

    private func openSettings() {
        settingsWindow.show(appearance: preferences.theme.appearance)
    }

    /// CmdTab owns ⌘⇥ only when it can list and focus windows and the user wants it to.
    private func updateSwitcherActivation() {
        if permission.isGranted {
            onboardingWindow.close()
        }
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        let frontmostKeepsShortcut = preferences.bundleIDs(for: .leaveShortcut).contains(frontmost)
        // Mid-drag the hot key would only fire after the drop, so DragHandoff catches ⌘⇥ instead.
        if permission.isGranted && preferences.replacesNativeSwitcher && !frontmostKeepsShortcut {
            nativeSwitcher.disableNativeSwitcher()
            if DragHandoff.shared.isDragging { hotKeys.unregister() } else { hotKeys.register() }
        } else {
            hotKeys.unregister()
            nativeSwitcher.restoreNativeSwitcher()
        }
    }

    /// Scroll Lock and dimming need Accessibility; their keys exist only while Scroll Lock is on.
    private func updateTiling() {
        let granted = permission.isGranted
        if granted && preferences.scrollLockEnabled {
            hotKeys.registerTilingKeys()
        } else {
            hotKeys.unregisterTilingKeys()
        }
        if granted {
            tiling.update()
        }
    }

    private static var otherRunningInstance: NSRunningApplication? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first { $0 != NSRunningApplication.current }
    }

    #if DEBUG
    private var previewSwitcher: SwitcherController?

    /// Opens one window without touching ⌘⇥, so designs can be checked next to a running copy.
    private func showPreview(_ preview: DesignPreview) {
        let appearance = preview.appearance
        switch preview.screen {
        case .onboarding: onboardingWindow.show(appearance: appearance)
        case .island:
            island.update()
            if preview.islandOption == "columns" || preview.islandOption == "stack" {
                // Four running apps stand in for the strip's columns.
                let pids = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.map(\.processIdentifier)
                let columns = pids.prefix(4).map { NotchDrop.Column(apps: [$0]) }
                let drop = NotchDrop()
                island.services.notchDrop = drop
                drop.preview(NotchDrop.State(
                    columns: columns, dragged: pids.last ?? 0,
                    target: preview.islandOption == "stack" ? .column(2) : .gap(2)
                ))
            } else if let row = Self.previewRow(preview.islandOption) {
                if row.focus != nil { island.services.focus.start() }
                island.preview(.agents(row))
            } else {
                island.previewOpen(tab: preview.islandTab ?? .agents)
            }
        case .switcher:
            // Throwaway settings, so the preview never changes the real ones.
            let previewDefaults = UserDefaults(suiteName: "CmdTab.DesignPreview") ?? .standard
            let previewPreferences = Preferences(defaults: previewDefaults)
            previewPreferences.theme = preview.theme
            previewPreferences.switcherSize = preview.switcherSize
            let environment = ProcessInfo.processInfo.environment
            previewPreferences.switcherStyle = environment["CMDTAB_PREVIEW_STYLE"].flatMap(SwitcherStyle.init) ?? .previews
            previewPreferences.groupsWindowsByApp = environment["CMDTAB_PREVIEW_GROUPED"] != nil
            previewPreferences.previewsSelectedWindow = environment["CMDTAB_PREVIEW_SELECTED"] != nil
            previewPreferences.opensInSearchMode = environment["CMDTAB_PREVIEW_SEARCH_MODE"] != nil
            previewPreferences.spaceScope = environment["CMDTAB_PREVIEW_ALL_SPACES"] != nil ? .allSpaces : .currentSpace
            previewSwitcher = SwitcherController(
                preferences: previewPreferences,
                screenRecording: screenRecording,
                hotKeys: HotKeyCenter()
            )
            previewSwitcher?.revealForDesignReview(searching: ProcessInfo.processInfo.environment["CMDTAB_PREVIEW_SEARCH"])
        case .settings:
            settingsWindow = HostingWindowController(title: "CmdTab Settings") { [preferences, permission, screenRecording] in
                SettingsView(
                    preferences: preferences,
                    permission: permission,
                    screenRecording: screenRecording,
                    updater: preview.pane == .about ? Updater() : nil,
                    initialPane: preview.pane
                )
            }
            settingsWindow.show(appearance: appearance)
        }
    }
    #endif

    private static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    #if DEBUG
    /// `island:dark:agents|everything|waiting`: the closed island with made-up sessions.
    private static func previewRow(_ option: String) -> AgentsRow? {
        func session(_ kind: AgentKind, _ state: AgentState) -> AgentSession {
            AgentSession(id: kind.rawValue, kind: kind, project: "cmdtab", detail: nil, state: state, since: .now, pid: nil)
        }
        let both: [AgentsRow.Mark] = [.init(kind: .claude, needsYou: false), .init(kind: .codex, needsYou: false)]
        switch option {
        case "agents": return AgentsRow(marks: both, waiting: nil, primary: session(.claude, .working), percent: 62)
        case "everything":
            return AgentsRow(marks: both, waiting: nil, primary: session(.claude, .working), percent: 62, withMusic: true, focus: .focus)
        case "waiting":
            return AgentsRow(
                marks: [.init(kind: .codex, needsYou: true), .init(kind: .claude, needsYou: false)],
                waiting: session(.codex, .needsYou), primary: session(.codex, .needsYou), percent: 62, withMusic: true
            )
        default: return nil
        }
    }
    #endif
}
