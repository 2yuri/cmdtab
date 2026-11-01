import CoreGraphics

enum ModifierState {
    /// Live hardware state, independent of which app is frontmost.
    static var isCommandPressed: Bool {
        CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand)
    }
}
