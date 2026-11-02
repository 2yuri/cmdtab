import Foundation

/// The Spaces of one display, as Mission Control has them.
struct DisplaySpaces: Equatable {
    let displayID: String
    /// The Space shown on the display right now.
    let current: UInt64
    let currentIsFullScreen: Bool
    /// Every full-screen app Space on the display.
    let fullScreen: [UInt64]
}

/// Which Spaces "this desktop" covers.
///
/// A full-screen app gets a Space of its own, so taken literally "this desktop" would be just that
/// one window. Instead a full-screen app counts as part of the desktop you came from: from it you see
/// that desktop's windows, and from the desktop you see your full-screen apps, so you can ⌘⇥ both ways.
enum SwitcherSpaces {
    static func visible(displays: [DisplaySpaces], lastDesktop: [String: UInt64]) -> Set<UInt64> {
        var spaces = Set<UInt64>()
        for display in displays {
            spaces.insert(display.current)
            spaces.formUnion(display.fullScreen)
            if display.currentIsFullScreen, let desktop = lastDesktop[display.displayID] {
                spaces.insert(desktop)
            }
        }
        return spaces
    }

    /// The desktop to remember for each display: the one it shows now, unless that is a full-screen app.
    static func desktops(of displays: [DisplaySpaces]) -> [String: UInt64] {
        Dictionary(
            displays.filter { !$0.currentIsFullScreen }.map { ($0.displayID, $0.current) },
            uniquingKeysWith: { _, last in last }
        )
    }
}
