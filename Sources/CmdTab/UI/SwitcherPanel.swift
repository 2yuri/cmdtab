import AppKit

/// The floating switcher. One panel is created once and reused. It never activates CmdTab, so the
/// frontmost app keeps focus until a window is picked; while typing a search it becomes key (like
/// Spotlight) to receive the keys, still without activating CmdTab.
@MainActor
final class SwitcherPanel: NSObject, NSTextFieldDelegate {
    private enum Metrics {
        static let padding: CGFloat = 14
        static let spacing: CGFloat = 6
        static let cornerRadius: CGFloat = 20
        static let minimumSearchWidth: CGFloat = 568
        /// Fraction of the screen the panel may use before wrapping into more rows / columns.
        static let maximumScreenRatio: CGFloat = 0.9
    }

    enum SearchCommand {
        case up, down, next, previous, confirm, cancel
    }

    var onHover: ((Int) -> Void)?
    var onClick: ((Int) -> Void)?
    var onSearchChange: ((String) -> Void)?
    var onSearchCommand: ((SearchCommand) -> Void)?
    /// ⌘W / ⌘M / ⌘Q typed while the search field has the keyboard (hot keys are off then).
    var onCommandKey: ((HotKeyCenter.Action) -> Void)?

    private let panel: KeyablePanel
    private let background = NSVisualEffectView()
    /// Deepens the system material to the design's panel colour (#26272B at 85% in dark mode),
    /// so the panel doesn't wash out to grey over bright windows.
    private let tint = NSView()
    private let searchBar = SearchBarView()
    private let keyHints = KeyHintsView()
    private let emptyLabel = NSTextField(labelWithString: "No windows match")
    private var itemViews: [SwitcherTileView] = []
    private var indexByWindowID: [CGWindowID: Int] = [:]
    /// Tiles per row in the current layout; arrow keys move across this grid.
    private(set) var columns = 1
    /// The search bar is showing (from the start in search mode, or after ⌘F).
    private(set) var isSearching = false
    /// The search field has the keyboard (⌘ has been released).
    private(set) var isTyping = false
    /// While searching the panel keeps its top edge and width, so it doesn't jump as results change.
    private var searchFrame: NSRect?
    private var lastResultCount = 0

    override init() {
        panel = KeyablePanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        super.init()
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.onEscape = { [weak self] in self?.onSearchCommand?(.cancel) }
        panel.onCommandKey = { [weak self] action in self?.onCommandKey?(action) }

        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = Metrics.cornerRadius
        background.layer?.cornerCurve = .continuous
        background.layer?.masksToBounds = true
        panel.contentView = background
        tint.wantsLayer = true
        tint.autoresizingMask = [.width, .height]
        background.addSubview(tint)

        searchBar.field.delegate = self
        searchBar.isHidden = true
        background.addSubview(searchBar)
        keyHints.isHidden = true
        background.addSubview(keyHints)

        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true
        background.addSubview(emptyLabel)
    }

    /// Screen pixels per point where the panel appears; used to size snapshots.
    var backingScale: CGFloat { (NSScreen.main ?? NSScreen.screens.first)?.backingScaleFactor ?? 2 }

    var isVisible: Bool { panel.isVisible }

    func show(
        _ items: [SwitcherItem],
        selectedIndex: Int,
        size: SwitcherSize,
        style: SwitcherStyle,
        theme: AppTheme,
        highlight: String,
        cachedThumbnail: (CGWindowID) -> NSImage?
    ) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let metrics = SwitcherItemMetrics.forSize(size, style: style)
        let itemSize = metrics.itemSize
        applyTheme(theme)

        let grid = Self.grid(count: items.count, itemSize: itemSize, available: screen.visibleFrame.size, style: style)
        columns = grid.columns
        let header = isSearching ? SearchBarView.height : 0
        let footer = isSearching ? KeyHintsView.height : 0
        let gridHeight = items.isEmpty && isSearching
            ? itemSize.height
            : CGFloat(grid.rows) * itemSize.height + CGFloat(max(grid.rows - 1, 0)) * Metrics.spacing

        var contentSize = NSSize(
            width: CGFloat(grid.columns) * itemSize.width + CGFloat(grid.columns - 1) * Metrics.spacing
                + 2 * Metrics.padding,
            height: header + gridHeight + 2 * Metrics.padding + footer
        )
        if isSearching {
            contentSize.width = max(contentSize.width, Metrics.minimumSearchWidth, searchFrame?.width ?? 0)
        }

        itemViews.forEach { $0.removeFromSuperview() }
        itemViews = items.enumerated().map { index, item in
            let (row, column) = (index / grid.columns, index % grid.columns)
            let origin = NSPoint(
                x: Metrics.padding + CGFloat(column) * (itemSize.width + Metrics.spacing),
                y: contentSize.height - header - Metrics.padding - CGFloat(row + 1) * itemSize.height
                    - CGFloat(row) * Metrics.spacing
            )
            let view: SwitcherTileView = switch style {
            case .icons:
                IconTileView(item: item, origin: origin, metrics: metrics, highlight: highlight)
            case .previews:
                PreviewTileView(
                    item: item,
                    origin: origin,
                    metrics: metrics,
                    thumbnail: cachedThumbnail(item.primary.windowID),
                    highlight: highlight
                )
            case .titles:
                TitleTileView(item: item, origin: origin, metrics: metrics, highlight: highlight)
            }
            view.onHover = { [weak self] in self?.onHover?(index) }
            view.onClick = { [weak self] in self?.onClick?(index) }
            background.addSubview(view)
            return view
        }
        // A group's tile shows its primary window's snapshot.
        indexByWindowID = Dictionary(
            items.enumerated().map { ($1.primary.windowID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        select(selectedIndex)

        layoutSearchChrome(contentSize: contentSize, items: items)

        let frame: NSRect
        if isSearching, let searchFrame {
            frame = NSRect(
                x: searchFrame.midX - contentSize.width / 2,
                y: searchFrame.maxY - contentSize.height,
                width: contentSize.width,
                height: contentSize.height
            )
        } else {
            let screenFrame = screen.visibleFrame
            frame = NSRect(
                x: screenFrame.midX - contentSize.width / 2,
                y: screenFrame.midY - contentSize.height / 2,
                width: contentSize.width,
                height: contentSize.height
            )
        }
        if isSearching { searchFrame = frame }
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    func select(_ index: Int) {
        for (itemIndex, view) in itemViews.enumerated() {
            view.isSelected = itemIndex == index
        }
    }

    func setThumbnail(_ image: NSImage, for windowID: CGWindowID) {
        guard let index = indexByWindowID[windowID], itemViews.indices.contains(index) else { return }
        itemViews[index].setThumbnail(image)
    }

    /// Shows the search bar. Call `startTyping()` to give it the keyboard.
    func showSearchBar() {
        guard !isSearching else { return }
        isSearching = true
        searchFrame = nil
        searchBar.field.stringValue = ""
        searchBar.isHidden = false
        keyHints.isHidden = false
    }

    /// Gives the search field the keyboard, without activating CmdTab.
    func startTyping() {
        showSearchBar()
        isTyping = true
        searchBar.update(placeholder: "Search windows", resultCount: lastResultCount)
        panel.makeKey()
        panel.makeFirstResponder(searchBar.field)
    }

    #if DEBUG
    func fillSearchForDesignReview(_ text: String) {
        searchBar.field.stringValue = text
    }
    #endif

    func hide() {
        isSearching = false
        isTyping = false
        searchFrame = nil
        searchBar.isHidden = true
        keyHints.isHidden = true
        emptyLabel.isHidden = true
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        itemViews.forEach { $0.removeFromSuperview() }
        itemViews.removeAll()
        indexByWindowID.removeAll()
    }

    /// Fires when the panel stops being key while typing (a click elsewhere).
    var onSearchResignKey: (() -> Void)? {
        get { panel.onResignKey }
        set { panel.onResignKey = newValue }
    }

    // MARK: - Layout

    struct Grid: Equatable {
        let columns: Int
        let rows: Int
    }

    /// Icons and previews fill rows across the screen; titles form a column and only add columns
    /// when the list would be taller than the screen.
    static func grid(count: Int, itemSize: CGSize, available: CGSize, style: SwitcherStyle) -> Grid {
        guard count > 0 else { return Grid(columns: 1, rows: 0) }
        switch style {
        case .titles:
            let usableHeight = available.height * Metrics.maximumScreenRatio - 2 * Metrics.padding
            let maxRows = max(1, Int((usableHeight + Metrics.spacing) / (itemSize.height + Metrics.spacing)))
            let columns = (count + maxRows - 1) / maxRows
            return Grid(columns: columns, rows: (count + columns - 1) / columns)
        case .icons, .previews:
            let usableWidth = available.width * Metrics.maximumScreenRatio - 2 * Metrics.padding
            let maxColumns = max(1, Int((usableWidth + Metrics.spacing) / (itemSize.width + Metrics.spacing)))
            let columns = min(count, maxColumns)
            return Grid(columns: columns, rows: (count + columns - 1) / columns)
        }
    }

    private func layoutSearchChrome(contentSize: NSSize, items: [SwitcherItem]) {
        guard isSearching else { return }
        searchBar.frame = NSRect(
            x: 0,
            y: contentSize.height - SearchBarView.height,
            width: contentSize.width,
            height: SearchBarView.height
        )
        lastResultCount = items.reduce(0) { $0 + $1.windowCount }
        searchBar.update(
            placeholder: isTyping ? "Search windows" : "Let go of ⌘ to search",
            resultCount: lastResultCount
        )
        keyHints.frame = NSRect(x: 0, y: 0, width: contentSize.width, height: KeyHintsView.height)

        emptyLabel.isHidden = !items.isEmpty
        emptyLabel.sizeToFit()
        emptyLabel.frame = NSRect(
            x: 0,
            y: (contentSize.height - emptyLabel.frame.height) / 2 - (SearchBarView.height - KeyHintsView.height) / 2,
            width: contentSize.width,
            height: emptyLabel.frame.height
        )
    }

    private func applyTheme(_ theme: AppTheme) {
        panel.appearance = theme.appearance
        let isDark = (theme.appearance ?? NSApp.effectiveAppearance).isDark
        // The HUD material is always dark; use the adaptive popover material for light mode.
        background.material = isDark ? .hudWindow : .popover
        tint.frame = background.bounds
        // Accessibility → Display → Reduce transparency: a solid panel, no blur showing through.
        let isSolid = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        tint.layer?.backgroundColor = isDark
            ? NSColor(srgbRed: 0x26 / 255, green: 0x27 / 255, blue: 0x2B / 255, alpha: isSolid ? 1 : 0.85).cgColor
            : NSColor(srgbRed: 0xF7 / 255, green: 0xF7 / 255, blue: 0xF5 / 255, alpha: isSolid ? 1 : 0.75).cgColor
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ notification: Notification) {
        onSearchChange?(searchBar.field.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        let command: SearchCommand? = switch selector {
        case #selector(NSResponder.moveUp(_:)): .up
        case #selector(NSResponder.moveDown(_:)): .down
        case #selector(NSResponder.insertTab(_:)): .next
        case #selector(NSResponder.insertBacktab(_:)): .previous
        case #selector(NSResponder.insertNewline(_:)): .confirm
        case #selector(NSResponder.cancelOperation(_:)): .cancel
        default: nil
        }
        guard let command else { return false }
        onSearchCommand?(command)
        return true
    }
}

/// A non-activating panel that can still become key, so the search field receives typing while
/// the app the user came from stays active.
private final class KeyablePanel: NSPanel {
    var onResignKey: (() -> Void)?
    var onEscape: (() -> Void)?
    var onCommandKey: ((HotKeyCenter.Action) -> Void)?

    private static let commandKeys: [String: HotKeyCenter.Action] = [
        "w": .closeWindow, "m": .minimizeWindow, "q": .quitApp,
    ]

    override var canBecomeKey: Bool { true }

    /// Esc always closes the switcher, whichever view has focus.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53, let onEscape {
            onEscape()
            return
        }
        if event.type == .keyDown,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           let action = event.charactersIgnoringModifiers.flatMap({ Self.commandKeys[$0.lowercased()] }),
           let onCommandKey {
            onCommandKey(action)
            return
        }
        super.sendEvent(event)
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}
