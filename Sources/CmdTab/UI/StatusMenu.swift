import AppKit

/// The optional menu bar icon and its menu.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let preferences: Preferences
    private let permission: AccessibilityPermission
    private let onOpenSettings: () -> Void
    private var statusItem: NSStatusItem?

    init(preferences: Preferences, permission: AccessibilityPermission, onOpenSettings: @escaping () -> Void) {
        self.preferences = preferences
        self.permission = permission
        self.onOpenSettings = onOpenSettings
        super.init()
    }

    /// Shows or hides the icon according to preferences.
    func refreshVisibility() {
        if preferences.showsMenuBarIcon {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            let image = NSImage(named: "MenuBarIcon")
            image?.isTemplate = true
            image?.accessibilityDescription = "CmdTab"
            item.button?.image = image
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            statusItem = item
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    // Rebuilt on every open so checkmarks always reflect the current state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        permission.refresh()

        let header = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        if !permission.isGranted {
            menu.addItem(item("Grant Accessibility Access…", action: #selector(grantAccess)))
        }
        menu.addItem(.separator())

        let currentSpaceOnly = item("Only Windows on Current Desktop", action: #selector(toggleSpaceScope))
        currentSpaceOnly.state = preferences.spaceScope == .currentSpace ? .on : .off
        menu.addItem(currentSpaceOnly)

        let launchAtLogin = item("Launch at Login", action: #selector(toggleLaunchAtLogin))
        launchAtLogin.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(launchAtLogin)

        menu.addItem(.separator())
        menu.addItem(item("Settings…", action: #selector(openSettings), key: ","))
        let hideIcon = item("Hide Menu Bar Icon", action: #selector(hideIcon))
        hideIcon.toolTip = "Open CmdTab again from Finder or Spotlight to bring it back."
        menu.addItem(hideIcon)
        menu.addItem(.separator())
        menu.addItem(item("Quit CmdTab", action: #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
    }

    private var statusTitle: String {
        if !permission.isGranted { return "CmdTab needs Accessibility access" }
        return preferences.replacesNativeSwitcher ? "CmdTab is active" : "CmdTab is paused"
    }

    private func item(_ title: String, action: Selector, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? self
        return item
    }

    @objc private func grantAccess() {
        permission.requestAccess()
    }

    @objc private func toggleSpaceScope() {
        preferences.spaceScope = preferences.spaceScope == .currentSpace ? .allSpaces : .currentSpace
    }

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLogin.setEnabled(!LaunchAtLogin.isEnabled)
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func hideIcon() {
        preferences.showsMenuBarIcon = false
    }
}
