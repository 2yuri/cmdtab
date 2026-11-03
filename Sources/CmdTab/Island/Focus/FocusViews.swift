import SwiftUI

extension IslandStyle {
    static let tomato = Color(red: 1, green: 0.353, blue: 0.31)
}

extension FocusCycle.Phase {
    var tint: Color { self == .focus ? IslandStyle.tomato : IslandStyle.volt }
    var title: String { self == .focus ? "Focus" : "Break" }
}

/// A ring that empties as time runs out.
struct FocusRing: View {
    let fraction: Double
    let tint: Color
    var lineWidth: CGFloat = 8

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.1), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// The open Focus tab: the ring, the rounds, controls and presets.
struct FocusTab: View {
    let timer: FocusTimer
    @State private var custom = false

    var body: some View {
        let phase = timer.cycle.phase
        VStack(spacing: 12) {
            TabHeader(title: "Focus") {
                Text("Round \(timer.cycle.round) of \(FocusCycle.roundsPerSet)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(IslandStyle.secondary)
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                ZStack {
                    FocusRing(fraction: timer.fraction(at: context.date), tint: phase.tint)
                    VStack(spacing: 2) {
                        Text(FocusTimer.clock(timer.remaining(at: context.date)))
                            .font(.system(size: 34, weight: .bold, design: .monospaced))
                            .foregroundStyle(IslandStyle.primary)
                        Text(timer.isPaused ? "Paused" : phase.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(phase.tint)
                    }
                }
                .frame(width: 150, height: 150)
            }
            HStack(spacing: 6) {
                ForEach(1...FocusCycle.roundsPerSet, id: \.self) { round in
                    Circle()
                        .fill(round <= timer.cycle.completed || (round == timer.cycle.round && timer.isActive)
                              ? IslandStyle.tomato : Color.white.opacity(0.15))
                        .frame(width: 8, height: 8)
                }
            }
            HStack(spacing: 18) {
                RoundButton(symbol: "arrow.counterclockwise", size: 34) { timer.reset() }
                    .help("Start over")
                Button { timer.toggle() } label: {
                    Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 46, height: 46)
                        .background(IslandStyle.primary, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                RoundButton(symbol: "forward.end.fill", size: 34) { timer.skip() }
                    .help(phase == .focus ? "Skip to the break" : "Skip the break")
            }
            HStack(spacing: 6) {
                PresetChip(title: "25 / 5", isOn: timer.preset == .short && !custom) { custom = false; timer.choose(.short) }
                PresetChip(title: "50 / 10", isOn: timer.preset == .long && !custom) { custom = false; timer.choose(.long) }
                PresetChip(title: "Custom", isOn: custom || (timer.preset != .short && timer.preset != .long)) { custom = true }
            }
            if custom {
                HStack(spacing: 14) {
                    MinuteStepper(label: "Focus", value: timer.preset.focus, range: FocusPreset.focusRange, step: 5) {
                        timer.choose(FocusPreset(focus: $0, rest: timer.preset.rest))
                    }
                    MinuteStepper(label: "Break", value: timer.preset.rest, range: FocusPreset.restRange, step: 1) {
                        timer.choose(FocusPreset(focus: timer.preset.focus, rest: $0))
                    }
                }
            }
        }
    }
}

private struct RoundButton: View {
    let symbol: String
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(IslandStyle.primary)
                .frame(width: size, height: size)
                .background(Color.white.opacity(0.08), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct PresetChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isOn ? IslandStyle.tomato : IslandStyle.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(isOn ? IslandStyle.tomato.opacity(0.15) : Color.white.opacity(0.08), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct MinuteStepper: View {
    let label: String
    let value: Int
    let range: ClosedRange<Int>
    let step: Int
    let set: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(IslandStyle.secondary)
                .padding(.trailing, 4)
            stepButton("minus", enabled: value > range.lowerBound) { set(max(range.lowerBound, value - step)) }
            Text("\(value)m").font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(IslandStyle.primary)
                .frame(minWidth: 32)
            stepButton("plus", enabled: value < range.upperBound) { set(min(range.upperBound, value + step)) }
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(IslandStyle.primary)
        .padding(.leading, 10)
        .padding(.trailing, 3)
        .padding(.vertical, 3)
        .onScrollStep { steps in set(min(max(value + steps * step, range.lowerBound), range.upperBound)) }
        .background(Color.white.opacity(0.06), in: Capsule())
    }

    /// The whole circle takes the click, not just the glyph.
    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(0.08), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.35)
        .disabled(!enabled)
    }
}

/// "Round 2 done · Take 5 minutes [Start break]", when a phase runs out.
struct FocusEndedView: View {
    let timer: FocusTimer
    let ended: FocusCycle.Phase

    var body: some View {
        let next = timer.cycle
        HStack(spacing: 10) {
            Image(systemName: ended == .focus ? "checkmark" : "cup.and.saucer.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(ended.tint)
                .frame(width: 28, height: 28)
                .background(ended.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(ended == .focus ? "Round \(next.completed) done" : "Break over")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(IslandStyle.primary)
                Text(ended == .focus ? "Take \(timer.preset.rest) minutes" : "Round \(next.round) of \(FocusCycle.roundsPerSet) is next")
                    .font(.system(size: 11))
                    .foregroundStyle(IslandStyle.secondary)
            }
            Spacer(minLength: 8)
            IslandButton(title: ended == .focus ? "Start break" : "Start focus", prominent: true) { timer.start() }
        }
    }
}
