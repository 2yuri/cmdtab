import AppKit
import Observation

/// Focus and break lengths, in minutes.
struct FocusPreset: Codable, Equatable {
    var focus: Int
    var rest: Int

    static let short = FocusPreset(focus: 25, rest: 5)
    static let long = FocusPreset(focus: 50, rest: 10)
    static let focusRange = 5...90
    static let restRange = 1...30
}

/// Where a Pomodoro set is. Pure, so the rules can be tested.
struct FocusCycle: Equatable {
    enum Phase: Equatable { case focus, rest }

    static let roundsPerSet = 4

    var phase: Phase = .focus
    /// 1…4.
    var round = 1
    /// Rounds finished in this set.
    var completed = 0

    /// What comes after the current phase ends (or is skipped).
    mutating func advance() {
        switch phase {
        case .focus:
            completed = min(completed + 1, Self.roundsPerSet)
            phase = .rest
        case .rest:
            phase = .focus
            if round >= Self.roundsPerSet {
                round = 1
                completed = 0
            } else {
                round += 1
            }
        }
    }

    func minutes(in preset: FocusPreset) -> Int {
        phase == .focus ? preset.focus : preset.rest
    }
}

/// The Focus tab's Pomodoro timer. One timer fires when a phase ends; nothing ticks otherwise
/// (the views that show the countdown redraw once a second only while they're on screen).
@MainActor
@Observable
final class FocusTimer {
    private(set) var cycle = FocusCycle()
    /// When the running phase ends.
    private(set) var endsAt: Date?
    /// Time left while paused.
    private(set) var pausedRemaining: TimeInterval?
    /// The phase that just ended, while the island shows it.
    private(set) var justEnded: FocusCycle.Phase?
    var preset: FocusPreset { didSet { save() } }

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var clearEnded: Timer?
    @ObservationIgnored private let defaults: UserDefaults
    private static let presetKey = "islandFocusPreset"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preset = defaults.data(forKey: Self.presetKey).flatMap { try? JSONDecoder().decode(FocusPreset.self, from: $0) } ?? .short
    }

    var isRunning: Bool { endsAt != nil }
    var isPaused: Bool { pausedRemaining != nil }
    var isActive: Bool { isRunning || isPaused }

    var phaseLength: TimeInterval { TimeInterval(cycle.minutes(in: preset) * 60) }

    func remaining(at now: Date) -> TimeInterval {
        if let endsAt { return max(0, endsAt.timeIntervalSince(now)) }
        return pausedRemaining ?? phaseLength
    }

    /// 0…1 of the phase still to go.
    func fraction(at now: Date) -> Double {
        phaseLength > 0 ? remaining(at: now) / phaseLength : 0
    }

    func start() {
        justEnded = nil
        run(for: pausedRemaining ?? phaseLength)
        pausedRemaining = nil
    }

    func pause() {
        guard let endsAt else { return }
        pausedRemaining = max(0, endsAt.timeIntervalSinceNow)
        self.endsAt = nil
        timer?.invalidate()
    }

    func toggle() {
        isRunning ? pause() : start()
    }

    /// Back to the start of round 1.
    func reset() {
        timer?.invalidate()
        endsAt = nil
        pausedRemaining = nil
        justEnded = nil
        cycle = FocusCycle()
    }

    /// Ends the current phase now and starts the next one.
    func skip() {
        timer?.invalidate()
        cycle.advance()
        pausedRemaining = nil
        run(for: phaseLength)
    }

    func choose(_ preset: FocusPreset) {
        self.preset = preset
        if !isRunning {
            pausedRemaining = nil
        }
    }

    private func run(for seconds: TimeInterval) {
        timer?.invalidate()
        endsAt = Date.now.addingTimeInterval(seconds)
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.phaseEnded() }
        }
    }

    /// A phase ran out: a sound, and the next phase waits for you to start it.
    private func phaseEnded() {
        let ended = cycle.phase
        cycle.advance()
        endsAt = nil
        pausedRemaining = nil
        justEnded = ended
        NSSound(named: ended == .focus ? "Glass" : "Hero")?.play()
        clearEnded?.invalidate()
        clearEnded = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.justEnded = nil }
        }
    }

    func dismissEnded() {
        justEnded = nil
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(preset), forKey: Self.presetKey)
    }

    nonisolated static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
