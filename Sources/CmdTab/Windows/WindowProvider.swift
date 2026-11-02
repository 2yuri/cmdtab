import AppKit
import os

/// Builds the window list on demand, only when the switcher is invoked.
///
/// There is no background work: no polling, no observers, no screenshots. Each invocation costs
/// one WindowServer query plus one Accessibility round trip per app that has a window in scope.
@MainActor
final class WindowProvider {
    /// Upper bound for a single Accessibility call, so a hung app can't freeze the switcher.
    private static let accessibilityTimeout: Float = 0.1
    /// Accessibility subroles that represent windows a user would want to switch to.
    private static let switchableSubroles: Set<String> = [kAXStandardWindowSubrole, kAXDialogSubrole]
    /// Windows on other Spaces have no AX element, so only trust reasonably sized ones.
    private static let minimumSideWithoutAccessibility: CGFloat = 150

    private let ownPID = ProcessInfo.processInfo.processIdentifier
    /// The last desktop (not full-screen app) each display showed, so a full-screen app can list the
    /// desktop it was opened from. Updated only when the Space changes.
    private var lastDesktop: [String: PrivateAPI.SpaceID] = [:]

    init() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), Self.accessibilityTimeout)
        rememberDesktops()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rememberDesktops() }
        }
    }

    private func rememberDesktops() {
        lastDesktop.merge(SwitcherSpaces.desktops(of: PrivateAPI.displaySpaces())) { _, new in new }
    }

    func windows(options: WindowFilterOptions) -> [SwitcherWindow] {
        let scope = options.scope
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular
                && $0.processIdentifier != ownPID
                && (options.includesHiddenApps || !$0.isHidden) // Skips the Accessibility round trip too.
                && !options.excludedBundleIDs.contains($0.bundleIdentifier ?? "")
        }
        let appsByPID = Dictionary(apps.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { first, _ in first })

        guard let rawList = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]]
        else { return [] }

        let currentSpaces = PrivateAPI.currentSpaceIDs()
        // "This desktop" also covers full-screen apps and, from one of them, the desktop it came from.
        let shownSpaces = currentSpaces.isEmpty
            ? currentSpaces
            : SwitcherSpaces.visible(displays: PrivateAPI.displaySpaces(), lastDesktop: lastDesktop).union(currentSpaces)
        var onCurrentSpace = Set<CGWindowID>()
        var spacesByWindow: [CGWindowID: Set<PrivateAPI.SpaceID>] = [:]
        let candidates = WindowOrdering
            .candidates(from: rawList.compactMap(WindowServerEntry.init), eligiblePIDs: Set(appsByPID.keys))
            .filter { entry in
                let spaces = PrivateAPI.spaceIDs(forWindow: entry.windowID)
                spacesByWindow[entry.windowID] = spaces
                if !spaces.isDisjoint(with: currentSpaces) { onCurrentSpace.insert(entry.windowID) }
                return WindowOrdering.isVisible(windowSpaces: spaces, currentSpaces: shownSpaces, scope: scope)
            }

        let onScreenOrder = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []).compactMap { $0[kCGWindowNumber as String] as? CGWindowID }
        let zIndex = WindowOrdering.zIndex(onScreenOrder: onScreenOrder, fullOrder: candidates.map(\.windowID))
        // The on-screen list is the source of truth: `kCGWindowIsOnscreen` can be set on windows it omits.
        let onScreenIDs = Set(onScreenOrder)

        var windows: [SwitcherWindow] = []
        var seenPIDs = Set<pid_t>()
        for entry in candidates where seenPIDs.insert(entry.pid).inserted {
            guard let app = appsByPID[entry.pid] else { continue }
            let appCandidates = candidates.filter { $0.pid == entry.pid }
            windows += Self.windows(of: app, candidates: appCandidates, onCurrentSpace: onCurrentSpace)
                .filter { WindowOrdering.isIncluded(isMinimized: $0.isMinimized, isAppHidden: $0.isAppHidden, options: options) }
                .filter {
                    !WindowOrdering.isOrderedOut(
                        isOnScreen: onScreenIDs.contains($0.windowID),
                        isOnCurrentSpace: onCurrentSpace.contains($0.windowID),
                        isMinimized: $0.isMinimized,
                        isAppHidden: $0.isAppHidden
                    )
                }
        }

        if scope == .allSpaces {
            let numbers = PrivateAPI.desktopNumbers()
            for index in windows.indices where !onCurrentSpace.contains(windows[index].windowID) {
                windows[index].desktopNumber = (spacesByWindow[windows[index].windowID] ?? [])
                    .compactMap { numbers[$0] }
                    .min()
            }
        }

        return WindowOrdering.arranged(
            windows,
            zIndex: { zIndex[$0.windowID] ?? .max },
            isDimmed: \.isDimmed
        )
    }

    private static func windows(
        of app: NSRunningApplication,
        candidates: [WindowServerEntry],
        onCurrentSpace: Set<CGWindowID>
    ) -> [SwitcherWindow] {
        let appName = app.localizedName ?? ""
        let icon = app.icon
        let isHidden = app.isHidden
        let appKey = app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
        let candidateIDs = Set(candidates.map(\.windowID))
        let boundsByID = Dictionary(candidates.map { ($0.windowID, $0.bounds) }, uniquingKeysWith: { first, _ in first })

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let elements: [AXUIElement] = appElement.value(of: kAXWindowsAttribute) ?? []

        var windows: [SwitcherWindow] = []
        var matchedIDs = Set<CGWindowID>()
        for element in elements {
            guard let windowID = PrivateAPI.windowID(of: element), candidateIDs.contains(windowID) else { continue }

            let attributes = element.values(of: [kAXSubroleAttribute, kAXTitleAttribute, kAXMinimizedAttribute])
            guard let subrole = attributes[kAXSubroleAttribute] as? String,
                  switchableSubroles.contains(subrole)
            else { continue }

            let title = (attributes[kAXTitleAttribute] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? appName
            matchedIDs.insert(windowID)
            windows.append(SwitcherWindow(
                windowID: windowID,
                pid: app.processIdentifier,
                appKey: appKey,
                element: element,
                title: title,
                appName: appName,
                icon: icon,
                isMinimized: attributes[kAXMinimizedAttribute] as? Bool ?? false,
                isAppHidden: isHidden,
                frame: boundsByID[windowID] ?? .zero
            ))
        }

        // Windows on other Spaces (full-screen apps, the desktop behind one, other desktops) are left out
        // of kAXWindows. Ask the app for their elements directly; candidates are already limited to the
        // scope. Without an element a window is still listed, by app name.
        let offSpace = candidates.filter {
            !matchedIDs.contains($0.windowID)
                && !onCurrentSpace.contains($0.windowID)
                && $0.size.width >= minimumSideWithoutAccessibility
                && $0.size.height >= minimumSideWithoutAccessibility
        }
        let offSpaceElements = PrivateAPI.windowElements(pid: app.processIdentifier, windowIDs: Set(offSpace.map(\.windowID)))
        for entry in offSpace {
            let element = offSpaceElements[entry.windowID]
            let attributes = element?.values(of: [kAXSubroleAttribute, kAXTitleAttribute, kAXMinimizedAttribute]) ?? [:]
            if element != nil, let subrole = attributes[kAXSubroleAttribute] as? String, !switchableSubroles.contains(subrole) {
                continue
            }
            windows.append(SwitcherWindow(
                windowID: entry.windowID,
                pid: app.processIdentifier,
                appKey: appKey,
                element: element,
                title: (attributes[kAXTitleAttribute] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? appName,
                appName: appName,
                icon: icon,
                isMinimized: attributes[kAXMinimizedAttribute] as? Bool ?? false,
                isAppHidden: isHidden,
                frame: entry.bounds
            ))
        }
        return windows
    }
}
