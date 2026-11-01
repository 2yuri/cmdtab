import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = Preferences()
    private let permission = AccessibilityPermission()
    private let screenRecording = ScreenRecordingPermission()
    private let hotKeys = HotKeyCenter()
    private let nativeSwitcher = NativeSwitcherGuard()
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
    private lazy var settingsWindow: HostingWindowController<SettingsView> = HostingWindowController(title: "CmdTab Settings") { [preferences, permission, screenRecording] in
        SettingsView(preferences: preferences, permission: permission, screenRecording: screenRecording)
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

        hotKeys.onAction = { [weak self] action in self?.switcher.handle(action) }
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
        if permission.isGranted && preferences.replacesNativeSwitcher && !frontmostKeepsShortcut {
            nativeSwitcher.disableNativeSwitcher()
            hotKeys.register()
        } else {
            hotKeys.unregister()
            nativeSwitcher.restoreNativeSwitcher()
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
}
