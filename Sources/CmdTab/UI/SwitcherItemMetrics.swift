import CoreGraphics

enum SwitcherStyle: String, CaseIterable {
    /// App icon and title, like the native switcher. Needs no Screen Recording.
    case icons
    /// A snapshot of each window, with a small icon and title underneath. Needs Screen Recording.
    case previews
    /// A compact list: small icon, window title and app name. Needs no Screen Recording.
    case titles
}

/// Tile geometry for each switcher size and style.
struct SwitcherItemMetrics: Equatable {
    let itemSize: CGSize
    /// App icon side: the large centred icon in `.icons`, the small badge next to the title in `.previews`.
    let iconSide: CGFloat
    let fontSize: CGFloat
    /// The snapshot area in `.previews`; zero in `.icons`.
    let previewSize: CGSize

    static func forSize(_ size: SwitcherSize, style: SwitcherStyle = .icons) -> SwitcherItemMetrics {
        switch (style, size) {
        case (.icons, .small):
            SwitcherItemMetrics(itemSize: CGSize(width: 96, height: 92), iconSide: 48, fontSize: 10, previewSize: .zero)
        case (.icons, .medium):
            SwitcherItemMetrics(itemSize: CGSize(width: 116, height: 112), iconSide: 64, fontSize: 11, previewSize: .zero)
        case (.icons, .large):
            SwitcherItemMetrics(itemSize: CGSize(width: 144, height: 138), iconSide: 88, fontSize: 12, previewSize: .zero)
        case (.previews, .small):
            SwitcherItemMetrics(itemSize: CGSize(width: 180, height: 140), iconSide: 14, fontSize: 10, previewSize: CGSize(width: 164, height: 100))
        case (.previews, .medium):
            SwitcherItemMetrics(itemSize: CGSize(width: 230, height: 174), iconSide: 16, fontSize: 11, previewSize: CGSize(width: 214, height: 132))
        case (.previews, .large):
            SwitcherItemMetrics(itemSize: CGSize(width: 300, height: 220), iconSide: 18, fontSize: 12, previewSize: CGSize(width: 284, height: 176))
        case (.titles, .small):
            SwitcherItemMetrics(itemSize: CGSize(width: 440, height: 30), iconSide: 18, fontSize: 12, previewSize: .zero)
        case (.titles, .medium):
            SwitcherItemMetrics(itemSize: CGSize(width: 540, height: 36), iconSide: 22, fontSize: 13, previewSize: .zero)
        case (.titles, .large):
            SwitcherItemMetrics(itemSize: CGSize(width: 660, height: 44), iconSide: 28, fontSize: 15, previewSize: .zero)
        }
    }

    /// Room for two lines of title under a large icon.
    var titleHeight: CGFloat { (fontSize * 2.7).rounded(.up) }
}
