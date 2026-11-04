import AppKit
import SwiftUI

/// Puts an island on the chosen screens and keeps each one's window the size of what it shows.
@MainActor
final class IslandController {
    private let preferences: Preferences
    let services: IslandServices
    private var islands: [CGDirectDisplayID: IslandWindow] = [:]
    private var screenObserver: NSObjectProtocol?

    init(preferences: Preferences) {
        self.preferences = preferences
        services = IslandServices(preferences: preferences)
    }

    /// Call when the island's settings change.
    func update() {
        let enabled = preferences.islandEnabled
        services.update(preferences)

        guard enabled else {
            islands.values.forEach { $0.close() }
            islands.removeAll()
            if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
            screenObserver = nil
            return
        }
        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.layoutScreens() }
            }
        }
        layoutScreens()
    }

    #if DEBUG
    /// Design review: every island open on `tab`, staying open.
    func previewOpen(tab: IslandModule) {
        islands.values.forEach { $0.pinOpen(tab: tab) }
    }

    /// Shows a made-up state, for screenshots of the closed island.
    func preview(_ content: IslandContent) {
        islands.values.forEach { $0.preview(content) }
    }
    #endif

    private func layoutScreens() {
        let screens = Self.screens(for: preferences.islandScreen)
        let wanted = Set(screens.compactMap(\.displayID))
        for (id, island) in islands where !wanted.contains(id) {
            island.close()
            islands[id] = nil
        }
        for screen in screens {
            guard let id = screen.displayID else { continue }
            if let island = islands[id] {
                island.move(to: screen)
            } else {
                islands[id] = IslandWindow(screen: screen, preferences: preferences, services: services)
            }
        }
    }

    static func screens(for choice: IslandScreen) -> [NSScreen] {
        switch choice {
        case .all: return NSScreen.screens
        case .main: return NSScreen.screens.first.map { [$0] } ?? []
        case .dock: return [dockScreen(NSScreen.screens) ?? NSScreen.screens.first].compactMap { $0 }
        case .builtIn:
            let builtIn = NSScreen.screens.first { screen in
                screen.displayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false
            }
            return [builtIn ?? NSScreen.screens.first].compactMap { $0 }
        }
    }

    /// The screen the Dock is on: the one whose usable area gives up room at the bottom or a side.
    /// A hidden Dock still keeps a few points there, so this finds it either way.
    static func dockScreen(_ screens: [NSScreen]) -> NSScreen? {
        screens.first { dockEdge(frame: $0.frame, visible: $0.visibleFrame) }
    }

    nonisolated static func dockEdge(frame: CGRect, visible: CGRect) -> Bool {
        visible.minY > frame.minY || visible.minX > frame.minX || visible.maxX < frame.maxX
    }

    /// The notch, or on screens without one a notch of our own: the same size, at the top centre,
    /// over the menu bar. The island always grows from there.
    static func islandNotch(of screen: NSScreen) -> CGRect {
        if let notch = notchRect(of: screen) { return notch }
        let frame = screen.frame
        let height = max(frame.maxY - screen.visibleFrame.maxY, IslandLayout.fakeNotch.height)
        let width = IslandLayout.fakeNotch.width
        return CGRect(x: frame.midX - width / 2, y: frame.maxY - height, width: width, height: height)
    }

    static func notchRect(of screen: NSScreen) -> CGRect? {
        guard screen.safeAreaInsets.top > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else { return nil }
        let frame = screen.frame
        let width = frame.width - left.width - right.width
        // As tall as the menu bar, so the closed island never sits shorter than the bar beside it.
        let menuBar = frame.maxY - screen.visibleFrame.maxY
        let height = max(screen.safeAreaInsets.top, menuBar)
        return CGRect(x: frame.minX + left.width, y: frame.maxY - height, width: width, height: height)
    }
}

extension NSScreen {
    /// The screen under `point`, counting its top row: a pointer pushed against the top of the
    /// screen sits exactly on `frame.maxY`, which `contains` leaves out.
    static func under(_ point: CGPoint) -> NSScreen? {
        screens.first { $0.frame.insetBy(dx: 0, dy: -1).contains(point) && point.y >= $0.frame.minY }
    }

    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// The display's UUID, as Mission Control names it.
    var uuidString: String? {
        guard let displayID, let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }
}

/// One island. The black shape lives in a panel that never changes size, so growing and shrinking
/// is pure SwiftUI animation and the shape never leaves the notch. That panel only takes the mouse
/// while the island is open; while closed, a small invisible panel over the shape notices the pointer,
/// clicks and file drags.
@MainActor
final class IslandWindow {
    private let panel = IslandPanel()
    private let hitPanel = IslandPanel()
    private let hitView = IslandHitView()
    private let model: IslandModel
    private let preferences: Preferences
    private let services: IslandServices
    private var monitor: AgentMonitor { services.agents }
    private var screen: NSScreen
    private var hosting: IslandHostingView!
    private var hoverWork: DispatchWorkItem?
    /// Design review only: stays open whatever the pointer does.
    private var pinnedOpen = false
    #if DEBUG
    private var previewContent: IslandContent?

    func preview(_ content: IslandContent) {
        pinnedOpen = true
        previewContent = content
        render(animated: false)
    }
    #endif
    private var closed = false

    /// How long the pointer rests before the island opens, and lingers outside before it closes.
    private static let openDelay: TimeInterval = 0.12
    private static let closeDelay: TimeInterval = 0.35
    /// Room around the biggest shape for its shadow.
    static let shadowMargin: CGFloat = 40

    init(screen: NSScreen, preferences: Preferences, services: IslandServices) {
        self.screen = screen
        self.preferences = preferences
        self.services = services
        model = IslandModel(notch: IslandController.islandNotch(of: screen).size, hasNotch: true)
        hosting = IslandHostingView(rootView: IslandView(
            model: model,
            services: services,
            preferences: preferences,
            onHover: { [weak self] inside in self?.hover(inside) },
            onTap: { [weak self] in self?.tap() }
        ))
        hosting.onFileDrag = { [weak self] targeted in self?.model.isDropTargeted = targeted }
        hosting.onFileDrop = { [weak self] urls in self?.services.shelf.add(urls) }
        // The panel keeps its size and place; content never resizes it (that would push it off centre).
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.allowsKey = true

        hitPanel.backgroundColor = NSColor(white: 0, alpha: 0.002)
        hitPanel.level = NSWindow.Level(rawValue: panel.level.rawValue + 1)
        hitPanel.contentView = hitView
        hitView.onHover = { [weak self] inside in self?.hover(inside) }
        hitView.onClick = { [weak self] in self?.tap() }
        hitView.onFileDrag = { [weak self] targeted in self?.model.isDropTargeted = targeted }
        hitView.onFileDrop = { [weak self] urls in self?.services.shelf.add(urls) }
        hitView.acceptsFiles = { [weak self] in self?.preferences.isIslandModuleOn(.shelf) == true }

        placePanel()
        render(animated: false)
        observeChanges(of: { [weak self] in self?.resolve() }) { [weak self] _ in self?.render(animated: true) }
    }

    func move(to screen: NSScreen) {
        self.screen = screen
        model.notch = IslandController.islandNotch(of: screen).size
        placePanel()
        render(animated: false)
    }

    func pinOpen(tab: IslandModule) {
        pinnedOpen = true
        model.tab = tab
        model.isExpanded = true
    }

    func close() {
        closed = true
        panel.orderOut(nil)
        hitPanel.orderOut(nil)
    }

    private func resolve() -> IslandContent {
        var inputs = IslandContent.Inputs()
        inputs.isExpanded = model.isExpanded
        inputs.tab = model.tab.flatMap { preferences.islandTabs.contains($0) ? $0 : nil } ?? preferences.islandTabs.first
        inputs.isDropTargeted = model.isDropTargeted && preferences.isIslandModuleOn(.shelf)
        inputs.approvals = monitor.approvals
        inputs.finished = monitor.finished
        inputs.sessions = monitor.sessions
        inputs.usage = monitor.usage
        inputs.showsLimit = preferences.islandShowsLimit
        inputs.agentsOn = preferences.isIslandModuleOn(.agents)
        inputs.musicPlaying = preferences.isIslandModuleOn(.music) && services.music.track?.isPlaying == true
        if services.windowDrop.isActive { inputs.windowDrop = .some(services.windowDrop.selection) }
        if preferences.isIslandModuleOn(.windows) { inputs.columnDrop = services.notchDrop?.state }
        if preferences.isIslandModuleOn(.shelf) { inputs.arrival = services.shelf.arrival }
        if preferences.isIslandModuleOn(.meetings) { inputs.meeting = services.meetings.upcoming }
        if preferences.isIslandModuleOn(.moments) { inputs.moment = services.moments.current }
        if preferences.isIslandModuleOn(.focus) {
            let focus = services.focus
            inputs.focusPhase = focus.isActive ? focus.cycle.phase : nil
            inputs.focusEnded = focus.justEnded
        }
        return IslandContent.resolve(inputs)
    }

    private func render(animated: Bool) {
        guard !closed else { return }
        var new = resolve()
        #if DEBUG
        if let previewContent { new = previewContent }
        #endif
        if new != model.content {
            if animated {
                withAnimation(.spring(duration: 0.38, bounce: 0)) { model.content = new }
            } else {
                model.content = new
            }
        }
        // Open: the shape panel takes the mouse. Closed: the hit panel does, over the shape only.
        if !new.isGrown, panel.isKeyWindow {
            // Typing goes back to the app you were in.
            panel.makeFirstResponder(nil)
            panel.orderOut(nil)
        }
        if case .windowDrop = new {
            services.windowDrop.pickerRect = shapeRect(for: new)
        }
        if case .columnDrop = new {
            services.notchDrop?.islandRect = shapeRect(for: new)
            services.notchDrop?.columnsRect = shapeRect(for: new).insetBy(dx: 14, dy: 0)
        }
        // While a file is dragged over it, the stand-in stays and grows with the shape, so the drag
        // never leaves the island mid-way.
        let standInTakesMouse = !new.isGrown || new == .drop
        panel.ignoresMouseEvents = standInTakesMouse
        if standInTakesMouse {
            hitPanel.setFrame(shapeRect(for: new), display: false)
            hitPanel.orderFrontRegardless()
        } else {
            hitPanel.orderOut(nil)
        }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    /// The fixed panel: as big as the open island plus its shadow, hanging from the notch.
    private func placePanel() {
        let width = IslandLayout.maximumWidth + 2 * Self.shadowMargin
        let height = IslandLayout.maximumExpandedHeight + Self.shadowMargin
        let rect = CGRect(x: centerX - width / 2, y: top - height, width: width, height: height)
        panel.setFrame(rect.integral, display: true)
    }

    private var centerX: CGFloat {
        IslandController.islandNotch(of: screen).midX
    }

    private var top: CGFloat {
        screen.frame.maxY
    }

    private func shapeRect(for content: IslandContent) -> CGRect {
        let size = model.size(of: content)
        return CGRect(x: centerX - size.width / 2, y: top - size.height, width: size.width, height: size.height).integral
    }

    /// Hover events only say "look again": whether the island opens or closes depends on where the
    /// pointer really is. Two views report hover (the stand-in while closed, the shape while open) and
    /// they can disagree at the very edge, e.g. the top row of pixels, which made the island flicker
    /// open and shut there.
    private func hover(_ inside: Bool) {
        hoverWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.settleHover() }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (inside ? Self.openDelay : Self.closeDelay), execute: work)
    }

    private func settleHover() {
        guard !pinnedOpen else { return }
        // Mid-drag (a file out of the Shelf, a selection) the island stays as it is until you let go.
        if NSEvent.pressedMouseButtons != 0 && model.isExpanded {
            let work = DispatchWorkItem { [weak self] in self?.settleHover() }
            hoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
            return
        }
        let pointerInside = pointerIsOverIsland
        if pointerInside && !model.isExpanded {
            // Passing over it while dragging something (a window to its columns) never opens it.
            if preferences.islandOpensOnHover && NSEvent.pressedMouseButtons == 0 { expand() }
        } else if !pointerInside && model.isExpanded {
            model.isExpanded = false
        }
        // While open, keep checking until the pointer leaves, in case an exit event was missed.
        if model.isExpanded && pointerInside {
            let work = DispatchWorkItem { [weak self] in self?.settleHover() }
            hoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
    }

    /// The island's shape as it is now, a little larger at the edges, and up to the top of the screen
    /// (the pointer can sit on the very last row).
    private var pointerIsOverIsland: Bool {
        var rect = shapeRect(for: model.content).insetBy(dx: -2, dy: -2)
        rect.size.height += 4
        return rect.contains(NSEvent.mouseLocation)
    }

    private func tap() {
        switch model.content {
        case .finished(let session):
            monitor.open(session)
            monitor.dismissFinished()
        case .agents(let row) where row.waiting != nil:
            monitor.open(row.primary)
        case .expanded:
            break
        default:
            expand(clicked: true)
        }
    }

    /// Opens on the last tab you chose. Only a click on a specific moment (a file that just
    /// arrived, a running timer) opens the tab it belongs to.
    private func expand(clicked: Bool = false) {
        let tabs = preferences.islandTabs
        guard !tabs.isEmpty, !model.isExpanded else { return }
        if clicked {
            switch model.content {
            case .arrival where tabs.contains(.shelf): model.tab = .shelf
            case .focus, .focusEnded: if tabs.contains(.focus) { model.tab = .focus }
            default: break
            }
        }
        model.isExpanded = true
    }
}

/// The invisible stand-in over the closed island: pointer in and out, clicks, file drags.
final class IslandHitView: NSView {
    var onHover: ((Bool) -> Void)?
    var onClick: (() -> Void)?
    var onFileDrag: ((Bool) -> Void)?
    var onFileDrop: (([URL]) -> Void)?
    var acceptsFiles: () -> Bool = { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .assumeInside],
            owner: self
        ))
        super.updateTrackingAreas()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func mouseDown(with event: NSEvent) { onClick?() }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        // A file dragged out of the Shelf passes over the island on its way: not a new arrival.
        guard acceptsFiles(), sender.draggingSource == nil else { return [] }
        onFileDrag?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        acceptsFiles() && sender.draggingSource == nil ? .copy : []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onFileDrag?(false)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        onFileDrag?(false)
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        onFileDrop?(urls)
        return true
    }
}

/// Never takes focus from the app you're in, sits above the menu bar, on every Space.
final class IslandPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
    }

    /// Only so a search field can take typing; nonactivating, so the app you're in stays in front.
    var allowsKey = false
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}

/// Clicks work on the first try (the panel never becomes key), and file drags are reported.
final class IslandHostingView: NSHostingView<IslandView> {
    var onFileDrag: ((Bool) -> Void)?
    var onFileDrop: (([URL]) -> Void)?

    required init(rootView: IslandView) {
        super.init(rootView: rootView)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingSource == nil else { return [] }
        onFileDrag?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        sender.draggingSource == nil ? .copy : []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onFileDrag?(false)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        onFileDrag?(false)
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        onFileDrop?(urls)
        return true
    }
}
