import AppKit
import QuartzCore

/// Slides other apps' windows smoothly through Accessibility.
///
/// Each move is a round trip to the window's app, and a busy app answers late. So:
/// - frames are paced by the display (`CADisplayLink`), not a timer;
/// - every app gets its own serial queue, so a slow app never holds the others back, and while an
///   app is still busy with one frame its next frames are skipped rather than queued up;
/// - apps with "enhanced user interface" on animate frame changes themselves, which fights ours,
///   so it is switched off for the length of the slide and restored afterwards;
/// - windows that start and end off screen just jump to the end.
@MainActor
final class WindowAnimator {
    struct Move {
        enum Kind {
            /// Slides from `from` to `to`.
            case slide
            /// Nudges `dx` points away from `from` and springs back: "you've hit the end".
            case bounce(dx: CGFloat)
        }

        let id: CGWindowID
        let pid: pid_t
        let element: AXUIElement
        let width: CGFloat
        let from: CGPoint
        let to: CGPoint
        var kind: Kind = .slide
        /// Where the window goes once the slide ends, if not `to`: a column slid out to the left is
        /// then parked at the right edge.
        var landing: CGPoint?

        var destination: CGPoint { landing ?? to }

        func position(at progress: Double) -> CGPoint {
            switch kind {
            case .slide:
                let eased = WindowAnimator.easeOut(progress)
                return CGPoint(
                    x: (from.x + (to.x - from.x) * eased).rounded(),
                    y: (from.y + (to.y - from.y) * eased).rounded()
                )
            case let .bounce(dx):
                return CGPoint(x: (from.x + dx * sin(.pi * progress)).rounded(), y: from.y)
            }
        }
    }

    static let duration: CFTimeInterval = 0.45
    static let bounceDuration: CFTimeInterval = 0.22

    var onFinish: (() -> Void)?
    /// Animation speed from Settings: 2 halves every duration, 0.5 doubles it.
    var speed: Double = 1

    private let ticker = DisplayTicker()
    private var link: CADisplayLink?
    private var moves: [Move] = []
    /// A strip scroll: every window's position at a given progress, worked out by the caller.
    private var scrollFrames: ((Double) -> [CGWindowID: CGPoint])?
    private var scrollWindows: [CGWindowID: (pid: pid_t, element: AXUIElement)] = [:]
    private var lastSent: [CGWindowID: CGPoint] = [:]
    private var began: CFTimeInterval = 0
    private var duration: CFTimeInterval = WindowAnimator.duration
    private var current: [CGWindowID: CGPoint] = [:]
    private var busy: Set<pid_t> = []
    private var queues: [pid_t: DispatchQueue] = [:]
    private var enhancedUIPIDs: Set<pid_t> = []

    var isAnimating: Bool { link != nil }

    /// Where a window is mid-slide, so a new slide can start from there.
    func currentPosition(of id: CGWindowID) -> CGPoint? {
        isAnimating ? current[id] : nil
    }

    /// Windows that are partway through an animation.
    var windowsInFlight: [CGWindowID] {
        isAnimating ? Array(current.keys) : []
    }

    func animate(_ moves: [Move], on screen: NSScreen, visibleArea: CGRect, duration: CFTimeInterval = WindowAnimator.duration) {
        // Windows still on their way from an interrupted slide keep going to where they were headed,
        // from wherever they are now. Dropping them would leave them stranded mid-screen.
        var moves = moves
        if isAnimating {
            let newIDs = Set(moves.map(\.id))
            for move in self.moves where !newIDs.contains(move.id) {
                moves.append(Move(
                    id: move.id, pid: move.pid, element: move.element, width: move.width,
                    from: current[move.id] ?? move.from, to: move.to, landing: move.landing
                ))
            }
        }
        stop(finishing: false)
        current = [:]
        self.duration = duration / min(max(speed, 0.25), 4)
        var animated: [Move] = []
        for move in moves {
            if !Self.isVisible(move.from, width: move.width, area: visibleArea)
                && !Self.isVisible(move.to, width: move.width, area: visibleArea) {
                send([(move.element, move.destination)], pid: move.pid, force: true)
            } else {
                animated.append(move)
            }
        }
        guard !animated.isEmpty else {
            onFinish?()
            return
        }
        self.moves = animated
        for move in animated { current[move.id] = move.from }
        for pid in Set(animated.map(\.pid)) { disableEnhancedUI(pid) }

        began = CACurrentMediaTime()
        start(on: screen)
    }

    /// Scrolls the whole strip: each frame asks `positions` where every window is at that point of the
    /// (eased) scroll, so columns in between pass across the screen like a real scroll.
    func scroll(
        windows: [CGWindowID: (pid: pid_t, element: AXUIElement)],
        on screen: NSScreen,
        duration: CFTimeInterval = WindowAnimator.duration,
        positions: @escaping (Double) -> [CGWindowID: CGPoint]
    ) {
        stop(finishing: false)
        current = [:]
        self.duration = duration / min(max(speed, 0.25), 4)
        scrollWindows = windows
        scrollFrames = positions
        lastSent = [:]
        for pid in Set(windows.values.map(\.pid)) { disableEnhancedUI(pid) }
        began = CACurrentMediaTime()
        start(on: screen)
    }

    private func start(on screen: NSScreen) {
        ticker.onTick = { [weak self] in self?.step() }
        let link = screen.displayLink(target: ticker, selector: #selector(DisplayTicker.tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    /// Ends the slide. `finishing` puts every window at its destination first.
    func stop(finishing: Bool) {
        guard let link else { return }
        link.invalidate()
        self.link = nil
        if finishing {
            for (pid, group) in Dictionary(grouping: moves, by: \.pid) {
                send(group.map { ($0.element, $0.destination) }, pid: pid, force: true)
            }
            if let scrollFrames { sendScroll(scrollFrames(1), force: true) }
        }
        restoreEnhancedUI()
        moves = []
        scrollFrames = nil
    }

    private func step() {
        let progress = min((CACurrentMediaTime() - began) / duration, 1)
        let done = progress >= 1
        if let scrollFrames {
            sendScroll(scrollFrames(done ? 1 : Self.easeOut(progress)), force: done)
        }

        for (pid, group) in Dictionary(grouping: moves, by: \.pid) {
            let positions = group.map { move -> (AXUIElement, CGPoint) in
                let point = done ? move.destination : move.position(at: progress)
                current[move.id] = point
                return (move.element, point)
            }
            send(positions, pid: pid, force: done)
        }

        if done {
            link?.invalidate()
            link = nil
            restoreEnhancedUI()
            moves = []
            scrollFrames = nil
            onFinish?()
        }
    }

    /// Sends only the windows whose position changed since the last frame (parked ones stay put).
    private func sendScroll(_ positions: [CGWindowID: CGPoint], force: Bool) {
        var byApp: [pid_t: [(AXUIElement, CGPoint)]] = [:]
        for (id, point) in positions {
            guard let window = scrollWindows[id], force || lastSent[id] != point else { continue }
            if force || !busy.contains(window.pid) {
                byApp[window.pid, default: []].append((window.element, point))
                lastSent[id] = point
                current[id] = point
            }
        }
        for (pid, list) in byApp { send(list, pid: pid, force: force) }
    }

    /// Moves windows of one app on that app's queue. Unless `force`, skips the frame while the app is
    /// still busy with the previous one.
    private func send(_ positions: [(AXUIElement, CGPoint)], pid: pid_t, force: Bool) {
        guard force || !busy.contains(pid) else { return }
        busy.insert(pid)
        let queue = queues[pid] ?? DispatchQueue(label: "dev.yuri.CmdTab.move.\(pid)", qos: .userInteractive)
        queues[pid] = queue
        let payload = Unchecked(positions)
        queue.async { [weak self] in
            for (element, point) in payload.value {
                element.setPosition(point)
            }
            Task { @MainActor in self?.busy.remove(pid) }
        }
    }

    private func disableEnhancedUI(_ pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        guard app.value(of: "AXEnhancedUserInterface") as Bool? == true else { return }
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
        enhancedUIPIDs.insert(pid)
    }

    private func restoreEnhancedUI() {
        for pid in enhancedUIPIDs {
            let queue = queues[pid] ?? .main
            queue.async {
                AXUIElementSetAttributeValue(
                    AXUIElementCreateApplication(pid), "AXEnhancedUserInterface" as CFString, kCFBooleanTrue
                )
            }
        }
        enhancedUIPIDs.removeAll()
    }

    /// Whether a window would show on screen. One parked at an edge keeps only a sliver; that counts as hidden.
    private static func isVisible(_ origin: CGPoint, width: CGFloat, area: CGRect) -> Bool {
        origin.x + width > area.minX + 4 && origin.x < area.maxX - 4
    }

    /// Longer scrolls take a little longer, so the eye can follow the columns going past.
    nonisolated static func scrollDuration(distance: CGFloat, viewWidth: CGFloat) -> CFTimeInterval {
        let screens = Double(abs(distance) / max(viewWidth, 1))
        return min(max(0.42 + 0.12 * screens, 0.42), 0.8)
    }

    /// Ease-in-out cubic: starts gently, glides through the middle and lands softly. (An ease-out
    /// curve covers most of the distance in the first few frames, which reads as a jump.)
    nonisolated static func easeOut(_ t: Double) -> Double {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }
}

@MainActor
private final class DisplayTicker: NSObject {
    var onTick: (() -> Void)?

    @objc func tick(_ link: CADisplayLink) {
        onTick?()
    }
}

/// Hands main-thread values to a background queue that uses them alone (AX elements are thread-safe).
private struct Unchecked<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
