import QuartzCore
import SwiftUI

/// The island's own colours: it is always black, like the notch it grows from.
enum IslandStyle {
    static let primary = Color(red: 0.949, green: 0.949, blue: 0.937)
    static let secondary = Color(red: 0.604, green: 0.616, blue: 0.639)
    static let tertiary = Color(red: 0.431, green: 0.443, blue: 0.471)
    static let volt = Color(red: 0.714, green: 0.949, blue: 0.227)
    static let amber = Color(red: 0.961, green: 0.647, blue: 0.141)
    static let warning = Color(red: 1.0, green: 0.62, blue: 0.26)
    static let claude = Color(red: 0.851, green: 0.467, blue: 0.341)
    static let card = Color.white.opacity(0.06)
}

/// Per-screen state of one island.
@MainActor
@Observable
final class IslandModel {
    var isExpanded = false
    var tab: IslandModule?
    var isDropTargeted = false
    /// What the shape shows; changed inside an animation so it grows and shrinks smoothly.
    var content: IslandContent = .idle
    /// Each open tab's height as its content measured it, kept for the next time it opens.
    private(set) var tabHeights: [IslandModule: CGFloat] = [:]
    var notch: CGSize
    let hasNotch: Bool

    init(notch: CGSize, hasNotch: Bool) {
        self.notch = notch
        self.hasNotch = hasNotch
    }

    func setMeasuredHeight(_ height: CGFloat, for tab: IslandModule) {
        let height = min(height.rounded(.up), IslandLayout.maximumExpandedHeight)
        guard abs((tabHeights[tab] ?? 0) - height) > 0.5 else { return }
        withAnimation(.spring(duration: 0.3, bounce: 0)) { tabHeights[tab] = height }
    }

    func size(of content: IslandContent) -> CGSize {
        IslandLayout.size(of: content, notch: notch, tabHeights: tabHeights)
    }
}

struct IslandView: View {
    let model: IslandModel
    let services: IslandServices
    let preferences: Preferences
    var onHover: (Bool) -> Void = { _ in }
    var onTap: () -> Void = {}

    private var content: IslandContent { model.content }

    var body: some View {
        let size = model.size(of: content)
        let radius = content.isGrown
            ? (content.isExpandedState ? IslandLayout.expandedCornerRadius : IslandLayout.grownCornerRadius)
            : (model.hasNotch ? 12 : size.height / 2)
        let shape = IslandShape(bottomRadius: radius, topRadius: model.hasNotch ? 0 : radius)
        ZStack(alignment: .top) {
            // The black shape: the only thing whose size animates.
            shape
                .fill(.black)
                .frame(width: size.width, height: size.height)
                .shadow(color: .black.opacity(content.isGrown ? 0.5 : 0), radius: 20, y: 10)
                .contentShape(shape)
                .onHover(perform: onHover)
                .onTapGesture(perform: onTap)

            // Rain, snow or fireflies behind whatever the island shows: in the wings while closed,
            // across the whole shape while it's open, fainter behind content.
            if let kind = services.effects.islandKind, content != .idle {
                Group {
                    if content.isGrown {
                        IslandEffectView(kind: kind, style: services.effects.style, scale: .screen)
                    } else {
                        HStack(spacing: 0) {
                            IslandEffectView(kind: kind, style: services.effects.style)
                            Color.clear.frame(width: model.notch.width)
                            IslandEffectView(kind: kind, style: services.effects.style)
                        }
                    }
                }
                .frame(width: size.width, height: size.height)
                .opacity(content == .effect(kind) ? 1 : content.isGrown ? 0.7 : 0.5)
                .mask(shape)
                .allowsHitTesting(false)
            }

            // Each state's content is laid out once, at its own final size, and the shape reveals it
            // like a mask. Nothing reflows or squeezes while the island grows or shrinks.
            ZStack(alignment: .top) {
                let own = model.size(of: content)
                contentView
                    .frame(width: own.width, height: own.height, alignment: .top)
                    .id(content.kind)
                    .transition(.asymmetric(
                        insertion: .modifier(
                            active: IslandContentTransition(progress: 0),
                            identity: IslandContentTransition(progress: 1)
                        ).animation(.spring(duration: 0.32, bounce: 0).delay(0.04)),
                        removal: .modifier(
                            active: IslandContentTransition(progress: 0),
                            identity: IslandContentTransition(progress: 1)
                        ).animation(.easeIn(duration: 0.1))
                    ))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .mask(alignment: .top) {
                shape.frame(width: size.width, height: size.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    private var monitor: AgentMonitor { services.agents }
    private var music: NowPlayingMonitor { services.music }

    @ViewBuilder
    private var contentView: some View {
        let notch = model.notch
        switch content {
        case .idle:
            Color.clear
        // Yours on the left (a question waiting, or the song and the Pomodoro), the agents on the right.
        case let .agents(row):
            CompactRow(notchWidth: notch.width, height: notch.height) {
                if let waiting = row.waiting {
                    HStack(spacing: 4) {
                        Image(systemName: "hand.raised.fill").font(.system(size: 10))
                        Text("\(waiting.kind.shortName) needs you").font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    }
                    .fixedSize()
                    .foregroundStyle(IslandStyle.amber)
                } else if row.percentOnLeft {
                    if let percent = row.percent { LimitText(percent: percent) }
                } else {
                    HStack(spacing: 8) {
                        if row.withMusic { MusicMini(music: music) }
                        if row.withMusic && row.focus != nil {
                            Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 12)
                        }
                        if let phase = row.focus { FocusMini(timer: services.focus, phase: phase) }
                    }
                    .fixedSize()
                }
            } trailing: {
                HStack(spacing: 8) {
                    if !row.percentOnLeft, row.waiting == nil, let percent = row.percent { LimitText(percent: percent) }
                    HStack(spacing: 4) {
                        ForEach(row.marks, id: \.kind) { mark in
                            AgentMark(kind: mark.kind, ring: mark.needsYou ? IslandStyle.amber : IslandStyle.volt, size: 16)
                        }
                    }
                }
                .fixedSize()
            }
        case let .finished(session):
            FinishedView(session: session, monitor: monitor)
                .padding(.top, notch.height + 6)
                .padding(.horizontal, 14)
        case let .approval(request):
            ApprovalView(request: request, monitor: monitor)
                .padding(.top, notch.height + 6)
                .padding(.horizontal, 14)
        case .music:
            CompactRow(notchWidth: notch.width, height: notch.height) {
                Artwork(image: music.artwork ?? music.app?.icon, size: 20)
            } trailing: {
                PlayingBars(isPlaying: music.track?.isPlaying == true).frame(width: 23, height: 16)
            }
        case .drop:
            DropTargetView()
                .padding(.top, notch.height + 6)
                .padding(.horizontal, 14)
        case let .windowDrop(selection):
            WindowDropPicker(selection: selection)
                .padding(.top, notch.height + 6)
                .padding(.horizontal, 14)
        case let .columnDrop(state):
            ColumnDropBar(state: state)
                .padding(.top, notch.height + 6)
                .padding(.horizontal, 14)
        case let .arrival(item):
            ArrivalView(item: item, count: services.shelf.items.count)
                .padding(.top, notch.height + 6)
                .padding(.horizontal, 14)
        case let .meeting(meeting):
            MeetingView(meeting: meeting, watcher: services.meetings)
                .padding(.top, notch.height + 6)
                .padding(.horizontal, 14)
        case let .moment(moment):
            CompactRow(notchWidth: notch.width, height: notch.height) {
                HStack(spacing: 6) {
                    Image(systemName: moment.symbol).font(.system(size: 13, weight: .semibold))
                    Text(moment.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                }
                .foregroundStyle(moment.tint)
            } trailing: {
                if let value = moment.value {
                    Text(value).font(.system(size: 11, weight: .semibold).monospacedDigit()).fixedSize().foregroundStyle(moment.tint)
                }
            }
        case let .focus(phase):
            let timer = services.focus
            TimelineView(.periodic(from: .now, by: 1)) { context in
                CompactRow(notchWidth: notch.width, height: notch.height) {
                    FocusRing(fraction: timer.fraction(at: context.date), tint: phase.tint, lineWidth: 2.5)
                        .frame(width: 16, height: 16)
                } trailing: {
                    Text((phase == .rest ? "Break " : "") + FocusTimer.clock(timer.remaining(at: context.date)))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .fixedSize()
                        .foregroundStyle(timer.isPaused ? IslandStyle.secondary : phase.tint)
                }
            }
        case let .focusEnded(phase):
            FocusEndedView(timer: services.focus, ended: phase)
                .padding(.top, notch.height + 6)
                .padding(.horizontal, 14)
        case let .expanded(tab):
            ExpandedView(model: model, services: services, preferences: preferences, tab: tab)
        case .effect:
            // The particles sit behind every closed state; see `wings`.
            Color.clear
        }
    }
}

extension IslandContent {
    /// Which view shows it; a new kind fades in, the same kind updates in place.
    var kind: String {
        switch self {
        case .idle: "idle"
        case .agents: "agents"
        case .finished: "finished"
        case .approval(let request): "approval-\(request.id)"
        case .music: "music"
        case .drop: "drop"
        case .windowDrop: "windowDrop"
        case .columnDrop: "columnDrop"
        case .arrival(let item): "arrival-\(item.id)"
        case .meeting: "meeting"
        case .moment(let moment): "moment-\(moment.title)"
        case .focus: "focus"
        case .focusEnded: "focusEnded"
        case .expanded(let tab): "expanded-\(tab.rawValue)"
        case .effect: "effect"
        }
    }

    var isExpandedState: Bool {
        if case .expanded = self { return true }
        return false
    }
}

/// Content appearing (0 → 1): from small, blurred and clear to its place.
struct IslandContentTransition: ViewModifier {
    let progress: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(0.92 + 0.08 * progress, anchor: .top)
            .blur(radius: 6 * (1 - progress))
            .opacity(progress)
    }
}

/// Flat on top (it hangs from the screen edge), rounded at the bottom.
struct IslandShape: Shape {
    var bottomRadius: CGFloat
    var topRadius: CGFloat = 0

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bottomRadius, topRadius) }
        set { bottomRadius = newValue.first; topRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadii: RectangleCornerRadii(
            topLeading: topRadius, bottomLeading: bottomRadius, bottomTrailing: bottomRadius, topTrailing: topRadius
        ), style: .continuous)
    }
}

/// Artwork and bars side by side, for when music shares the closed island with an agent.
private struct MusicMini: View {
    let music: NowPlayingMonitor

    var body: some View {
        HStack(spacing: 8) {
            Artwork(image: music.artwork ?? music.app?.icon, size: 20)
            PlayingBars(isPlaying: music.track?.isPlaying == true).frame(width: 23, height: 16)
        }
    }
}

/// A running Pomodoro beside the song: ring and time left.
private struct FocusMini: View {
    let timer: FocusTimer
    let phase: FocusCycle.Phase

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 5) {
                FocusRing(fraction: timer.fraction(at: context.date), tint: phase.tint, lineWidth: 2.5)
                    .frame(width: 16, height: 16)
                Text((phase == .rest ? "Break " : "") + FocusTimer.clock(timer.remaining(at: context.date)))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .fixedSize()
                    .foregroundStyle(timer.isPaused ? IslandStyle.secondary : phase.tint)
            }
        }
    }
}

/// "62%", orange from 80%.
private struct LimitText: View {
    let percent: Double

    var body: some View {
        Text("\(Int(percent.rounded()))%")
            .font(.system(size: 12, weight: .semibold))
            .fixedSize()
            .foregroundStyle(percent >= 80 ? IslandStyle.warning : IslandStyle.volt)
    }
}

/// Content on both sides of the notch, nothing under it.
struct CompactRow<Leading: View, Trailing: View>: View {
    let notchWidth: CGFloat
    let height: CGFloat
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 0) {
            leading.frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: notchWidth)
            trailing.frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: height)
        // Optically centred: the rounded bottom corners make true centre look low.
        .offset(y: -1)
    }
}

/// The agent's mark, with a turning ring while it works.
struct AgentMark: View {
    let kind: AgentKind
    var ring: Color?
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(kind == .claude ? IslandStyle.claude : IslandStyle.primary)
                .frame(width: size, height: size)
            Image(systemName: kind == .claude ? "sparkles" : "terminal")
                .font(.system(size: size * 0.55, weight: .semibold))
                .foregroundStyle(kind == .claude ? .white : .black)
            if let ring {
                SpinningRing(color: NSColor(ring))
                    .frame(width: size + 8, height: size + 8)
            }
        }
        .frame(width: size + 8, height: size + 8)
    }
}

private struct FinishedView: View {
    let session: AgentSession
    let monitor: AgentMonitor

    var body: some View {
        HStack(spacing: 10) {
            AgentMark(kind: session.kind, size: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(session.kind.name) finished · \(session.project)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(IslandStyle.primary)
                    .lineLimit(1)
                if let detail = session.detail {
                    Text(detail).font(.system(size: 11)).foregroundStyle(IslandStyle.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if session.pid != nil {
                IslandButton(title: "Open", prominent: true) {
                    monitor.open(session)
                    monitor.dismissFinished()
                }
            }
        }
    }
}

private struct ApprovalView: View {
    let request: ApprovalRequest
    let monitor: AgentMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AgentMark(kind: request.kind, size: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(request.project) wants to use \(request.tool)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(IslandStyle.primary)
                        .lineLimit(1)
                    Text(request.kind.name).font(.system(size: 11)).foregroundStyle(IslandStyle.secondary)
                }
            }
            Text(request.summary)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(IslandStyle.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            HStack(spacing: 8) {
                Button("Always allow") { monitor.answer(request, .allowAlways) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(IslandStyle.secondary)
                Spacer()
                IslandButton(title: "Deny", prominent: false) { monitor.answer(request, .deny) }
                IslandButton(title: "Allow", prominent: true) { monitor.answer(request, .allow) }
            }
        }
    }
}

private struct DropTargetView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.to.line")
            Text("Drop to hold").font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(IslandStyle.volt)
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(IslandStyle.volt.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(IslandStyle.volt, lineWidth: 1.5))
    }
}

struct IslandButton: View {
    let title: String
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(prominent ? Color.black : IslandStyle.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(prominent ? IslandStyle.volt : Color.white.opacity(0.12), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// A ring turning while an agent works. Core Animation spins it, so it costs no CPU.
struct SpinningRing: NSViewRepresentable {
    let color: NSColor

    func makeNSView(context: Context) -> RingView { RingView() }

    func updateNSView(_ view: RingView, context: Context) {
        view.color = color
    }

    final class RingView: NSView {
        private let ring = CAShapeLayer()

        var color: NSColor = .white {
            didSet { ring.strokeColor = color.cgColor }
        }

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            ring.fillColor = nil
            ring.lineWidth = 2
            ring.lineCap = .round
            ring.strokeEnd = 0.72
            layer?.addSublayer(ring)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func layout() {
            super.layout()
            ring.frame = bounds
            ring.path = CGPath(ellipseIn: bounds.insetBy(dx: 1, dy: 1), transform: nil)
            if ring.animation(forKey: "spin") == nil {
                let spin = CABasicAnimation(keyPath: "transform.rotation.z")
                spin.fromValue = 0
                spin.toValue = -2 * Double.pi
                spin.duration = 1.6
                spin.repeatCount = .infinity
                ring.add(spin, forKey: "spin")
            }
        }
    }
}

extension Moment {
    var symbol: String {
        switch kind {
        case .headphones: "headphones"
        case .charging: "battery.100percent.bolt"
        case .lowBattery: "battery.25percent"
        }
    }

    var tint: Color {
        switch kind {
        case .headphones: IslandStyle.primary
        case .charging: IslandStyle.volt
        case .lowBattery: IslandStyle.warning
        }
    }
}

private struct WindowDropPicker: View {
    let selection: WindowDropLayout?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(WindowDropLayout.allCases) { layout in
                let isOn = layout == selection
                VStack(spacing: 6) {
                    Image(systemName: layout.symbol).font(.system(size: 18, weight: .medium))
                    Text(layout.title).font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(isOn ? IslandStyle.volt : IslandStyle.primary.opacity(0.8))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isOn ? IslandStyle.volt.opacity(0.14) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(isOn ? IslandStyle.volt : .clear, lineWidth: 1.5))
            }
        }
    }
}

/// With Tiling on: the other columns while a tiled window is held over the island. A Volt bar marks
/// the gap it moves to; a Volt column is the one it stacks into.
private struct ColumnDropBar: View {
    let state: NotchDrop.State

    var body: some View {
        HStack(spacing: NotchDrop.spacing) {
            ForEach(Array(state.columns.enumerated()), id: \.offset) { index, column in
                let isTarget = state.target == .column(index)
                // Into tabs it goes in front; into a stack, at the bottom.
                let apps = !isTarget ? column.apps : column.tabs > 1 ? [state.dragged] : column.apps + [state.dragged]
                tile(apps: apps, number: index + 1, isOn: isTarget)
                    .overlay(alignment: .topTrailing) {
                        if column.tabs > 1 { tabCount(column.tabs + (isTarget ? 1 : 0), isOn: isTarget) }
                    }
                    .overlay(alignment: .leading) { if state.target == .gap(index) { marker.offset(x: -(NotchDrop.spacing + 3) / 2) } }
                    .overlay(alignment: .trailing) {
                        if index == state.columns.count - 1, state.target == .gap(index + 1) { marker.offset(x: (NotchDrop.spacing + 3) / 2) }
                    }
            }
            if state.columns.isEmpty {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(IslandStyle.volt, lineWidth: 1.5)
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
            }
        }
    }

    private func tabCount(_ count: Int, isOn: Bool) -> some View {
        Text("\(count)")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(isOn ? Color.black : IslandStyle.primary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(isOn ? IslandStyle.volt : Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .padding(5)
    }

    private var marker: some View {
        RoundedRectangle(cornerRadius: 1.5).fill(IslandStyle.volt).frame(width: 3, height: 56)
    }

    private func tile(apps: [pid_t], number: Int, isOn: Bool) -> some View {
        let size: CGFloat = apps.count > 2 ? 12 : apps.count > 1 ? 16 : 20
        return VStack(spacing: 5) {
            VStack(spacing: 2) {
                ForEach(Array(apps.enumerated()), id: \.offset) { row, pid in
                    if row > 0 {
                        Rectangle().fill(isOn ? IslandStyle.volt : IslandStyle.secondary.opacity(0.5)).frame(width: size, height: 1.5)
                    }
                    AppIcon(pid: pid).frame(width: size, height: size)
                }
            }
            Text("\(number)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(isOn ? IslandStyle.volt : IslandStyle.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .background(isOn ? IslandStyle.volt.opacity(0.14) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(isOn ? IslandStyle.volt : .clear, lineWidth: 1.5))
    }
}

private struct AppIcon: View {
    let pid: pid_t

    var body: some View {
        if let icon = NSRunningApplication(processIdentifier: pid)?.icon {
            Image(nsImage: icon).resizable().interpolation(.high)
        } else {
            Image(systemName: "macwindow").resizable().scaledToFit().foregroundStyle(IslandStyle.secondary)
        }
    }
}

private struct MeetingView: View {
    let meeting: UpcomingMeeting
    let watcher: MeetingWatcher

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color(red: 0.29, green: 0.49, blue: 1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(IslandStyle.primary).lineLimit(1)
                TimelineView(.everyMinute) { context in
                    Text(Self.when(meeting.start, now: context.date) + (meeting.service.map { " · \($0)" } ?? ""))
                        .font(.system(size: 11))
                        .foregroundStyle(IslandStyle.secondary)
                }
            }
            Spacer(minLength: 8)
            Button { watcher.dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(IslandStyle.secondary)
            }
            .buttonStyle(.plain)
            if meeting.link != nil {
                IslandButton(title: "Join", prominent: true) { watcher.join() }
            }
        }
    }

    static func when(_ start: Date, now: Date) -> String {
        let minutes = Int((start.timeIntervalSince(now) / 60).rounded(.up))
        if minutes > 0 { return "in \(minutes) min" }
        return minutes == 0 ? "now" : "started \(-minutes) min ago"
    }
}
