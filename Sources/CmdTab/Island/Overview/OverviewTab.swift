import SwiftUI

/// The first tab, summing up the rest: what's playing, how the Mac is doing, what the agents have
/// left and what's next. Stats are read only while it's open.
struct OverviewTab: View {
    let services: IslandServices
    let preferences: Preferences
    /// Holds which stat's popover is open; the island draws it, floating over everything.
    let model: IslandModel

    var body: some View {
        let detail = model.statDetail
        HStack(alignment: .top, spacing: 18) {
            OverviewSection(title: "NOW PLAYING") { NowPlayingSummary(music: services.music) }
                .frame(width: 230)
                .opacity(detail == nil ? 1 : 0.3)
            Divider().overlay(Color.white.opacity(0.08))
            OverviewSection(title: "THIS MAC") {
                MacSummary(stats: services.stats, detail: detail) { card, inside in
                    model.hoverStat(card: inside ? card : nil, usage: services.appUsage)
                }
            }
            .frame(width: 200)
            Divider().overlay(Color.white.opacity(0.08))
            OverviewSection(title: "AGENTS") { AgentsSummary(monitor: services.agents) }
                .frame(width: 210)
                .opacity(detail == nil ? 1 : 0.3)
            Divider().overlay(Color.white.opacity(0.08))
            OverviewSection(title: "UP NEXT") {
                UpNextSummary(
                    calendar: services.calendar,
                    showsCalendar: preferences.isIslandModuleOn(.calendar) || preferences.isIslandModuleOn(.meetings),
                    focus: services.focus
                )
            }
            .frame(maxWidth: .infinity)
            .opacity(detail == nil ? 1 : 0.3)
        }
        .fixedSize(horizontal: false, vertical: true)
        .onPreferenceChange(StatCardFrames.self) { model.statCards = $0 }
        .onAppear { services.stats.start() }
        .onDisappear {
            services.stats.stop()
            model.closeStat(usage: services.appUsage)
        }
    }
}

/// The open stat's popover, hanging from its card over the island and past its edge.
struct StatPopoverLayer: View {
    let model: IslandModel
    let services: IslandServices

    var body: some View {
        if let detail = model.statDetail, let card = model.statCards[detail] {
            let total = (detail == .cpu ? services.stats.cpu : services.stats.memory).last
            UsagePopover(resource: detail, usage: services.appUsage, total: total) {
                model.closeStat(usage: services.appUsage)
            }
            .onHover { model.hoverStat(card: nil, popover: $0, usage: services.appUsage) }
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(IslandModel.space)) }) { model.popoverRect = $0 }
            .onDisappear { model.popoverRect = nil }
            .padding(.leading, max(card.midX - UsagePopover.arrowX, 0))
            .padding(.top, card.maxY + 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
        }
    }
}

private struct OverviewSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundStyle(IslandStyle.tertiary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Now playing

private struct NowPlayingSummary: View {
    let music: NowPlayingMonitor

    var body: some View {
        let track = music.track
        VStack(alignment: .leading, spacing: 12) {
            TrackHeader(music: music, artworkSize: 64, titleSize: 14)
            HStack(spacing: 16) {
                SmallControl(symbol: "backward.fill") { music.send(.previous) }
                SmallControl(symbol: track?.isPlaying == true ? "pause.fill" : "play.fill") { music.send(.toggle) }
                SmallControl(symbol: "forward.fill") { music.send(.next) }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let duration = track?.duration ?? 0
                    let position = track?.position(at: context.date) ?? 0
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.12))
                            Capsule().fill(IslandStyle.primary)
                                .frame(width: duration > 0 ? proxy.size.width * min(position / duration, 1) : 0)
                        }
                    }
                    .frame(height: 3)
                }
            }
            .padding(.horizontal, 4)
            .opacity(track == nil ? 0.3 : 1)
            .disabled(track == nil)
        }
    }
}

private struct SmallControl: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(IslandStyle.primary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: This Mac

private struct MacSummary: View {
    let stats: SystemStats
    let detail: AppUsage.Resource?
    let hover: (AppUsage.Resource, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                StatCard(resource: .cpu, samples: stats.cpu, isOpen: detail == .cpu) { hover(.cpu, $0) }
                StatCard(resource: .memory, samples: stats.memory, isOpen: detail == .memory) { hover(.memory, $0) }
            }
            .zIndex(1)
            if let battery = stats.battery {
                HStack(spacing: 8) {
                    Image(systemName: battery.isCharging ? "battery.100.bolt" : "battery.75")
                        .font(.system(size: 12))
                        .foregroundStyle(IslandStyle.secondary)
                    Meter(fraction: Double(battery.percent) / 100, tint: battery.percent <= 20 && !battery.isCharging ? IslandStyle.warning : IslandStyle.volt)
                    Text("\(battery.percent)%")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(IslandStyle.secondary)
                    if let minutes = battery.minutesLeft {
                        Text("\(minutes / 60)h \(minutes % 60)m")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(IslandStyle.tertiary)
                            .fixedSize()
                    }
                }
                .opacity(detail == nil ? 1 : 0.3)
            }
        }
    }
}

extension AppUsage.Resource {
    var symbol: String { self == .cpu ? "cpu" : "memorychip" }
    var title: String { self == .cpu ? "CPU" : "Memory" }
    var tint: Color { self == .cpu ? IslandStyle.volt : IslandStyle.primary }
}

/// Where each stat card sits in the Overview, for its popover's arrow.
private struct StatCardFrames: PreferenceKey {
    static let defaultValue: [AppUsage.Resource: CGRect] = [:]
    static func reduce(value: inout [AppUsage.Resource: CGRect], nextValue: () -> [AppUsage.Resource: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct StatCard: View {
    let resource: AppUsage.Resource
    let samples: [Double]
    let isOpen: Bool
    let hover: (Bool) -> Void
    @State private var hovering = false

    var body: some View {
        let tint = resource.tint
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: resource.symbol).font(.system(size: 12)).foregroundStyle(IslandStyle.secondary)
                Spacer(minLength: 0)
                Text(samples.last.map { "\(Int(($0 * 100).rounded()))%" } ?? "–")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(tint)
            }
            Sparkline(samples: samples, tint: tint)
                .frame(height: 40)
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Color.white.opacity(isOpen ? 0.08 : hovering ? 0.11 : 0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isOpen ? tint.opacity(0.6) : Color.white.opacity(hovering ? 0.18 : 0), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover {
            hovering = $0
            hover($0)
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: StatCardFrames.self, value: [resource: proxy.frame(in: .named(IslandModel.space))])
            }
        }
    }
}

/// The apps using the most of a stat, hanging from its card.
struct UsagePopover: View {
    let resource: AppUsage.Resource
    let usage: AppUsage
    let total: Double?
    let close: () -> Void

    /// The arrow's centre, from the popover's leading edge.
    static let arrowX: CGFloat = 70
    static let fill = Color(red: 0.102, green: 0.106, blue: 0.122)

    var body: some View {
        let entries = usage.entries(for: resource)
        let top = entries.first?.value ?? 0
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: resource.symbol).font(.system(size: 12)).foregroundStyle(IslandStyle.secondary)
                Text(resource.title).font(.system(size: 13, weight: .bold)).foregroundStyle(IslandStyle.primary)
                Spacer(minLength: 0)
                Text(total.map { "\(Int(($0 * 100).rounded()))%" } ?? "–")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(resource.tint)
            }
            .padding(.horizontal, 6)
            VStack(spacing: 2) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    ProcessRow(entry: entry, resource: resource, fraction: top > 0 ? entry.value / top : 0, isTop: index == 0) {
                        usage.quit(entry)
                    }
                }
                // Keeps its height while the first reading comes in.
                ForEach(entries.count..<AppUsage.shown, id: \.self) { _ in
                    Color.clear.frame(height: 28)
                }
            }
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                close()
            } label: {
                HStack(spacing: 6) {
                    Text("Activity Monitor").font(.system(size: 12, weight: .medium))
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(IslandStyle.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 12)
        .padding([.horizontal, .bottom], 10)
        .frame(width: 320)
        .background(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Self.fill)
                Rectangle()
                    .fill(Self.fill)
                    .frame(width: 12, height: 12)
                    .rotationEffect(.degrees(45))
                    .offset(x: Self.arrowX - 6, y: -6)
            }
            .shadow(color: .black.opacity(0.7), radius: 16, y: 12)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
    }
}

private struct ProcessRow: View {
    let entry: AppUsage.Entry
    let resource: AppUsage.Resource
    let fraction: Double
    let isTop: Bool
    let quit: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let icon = entry.icon {
                    Image(nsImage: icon).resizable()
                } else {
                    RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.white.opacity(0.1))
                }
            }
            .frame(width: 18, height: 18)
            Text(entry.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(IslandStyle.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(resource.tint).frame(width: proxy.size.width * min(max(fraction, 0), 1))
                }
            }
            .frame(width: 70, height: 3)
            Text(Self.format(entry.value, resource))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(isTop ? resource.tint : IslandStyle.secondary)
                .frame(width: 52, alignment: .trailing)
            Button(action: quit) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(IslandStyle.primary)
                    .frame(width: 18, height: 18)
                    .background(Color.white.opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
            .help("Quit \(entry.name)")
        }
        .padding(.horizontal, 6)
        .frame(height: 28)
        .background(Color.white.opacity(hovering ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering = $0 }
    }

    static func format(_ value: Double, _ resource: AppUsage.Resource) -> String {
        switch resource {
        case .cpu:
            let percent = value * 100
            return percent < 1 ? "<1%" : "\(Int(percent.rounded()))%"
        case .memory:
            let gigabytes = value / 1_073_741_824
            return gigabytes >= 1 ? String(format: "%.1f GB", gigabytes) : "\(Int((value / 1_048_576).rounded())) MB"
        }
    }
}

/// The last samples as a line with a soft fill underneath; empty until two samples are in.
private struct Sparkline: View {
    let samples: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            if samples.count > 1 {
                let points = Self.points(samples, in: proxy.size)
                ZStack {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: proxy.size.height))
                        points.forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: proxy.size.height))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [tint.opacity(0.25), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
                    Path { path in path.addLines(points) }
                        .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    /// Spread over the whole width, newest on the right, so the card is never half empty.
    static func points(_ samples: [Double], in size: CGSize) -> [CGPoint] {
        let slots = max(samples.count - 1, 1)
        return samples.enumerated().map { index, value in
            CGPoint(
                x: size.width * CGFloat(index) / CGFloat(slots),
                y: size.height * (1 - CGFloat(value)) * 0.9 + size.height * 0.05
            )
        }
    }
}

private struct Meter: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule().fill(tint).frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 4)
    }
}

// MARK: Agents

private struct AgentsSummary: View {
    let monitor: AgentMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach([AgentKind.claude, .codex], id: \.self) { kind in
                let sessions = monitor.allSessions.filter { $0.kind == kind }
                let working = sessions.filter { $0.state == .working }.count
                let waiting = sessions.contains { $0.state == .needsYou }
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        AgentMark(kind: kind, size: 14)
                        Text(kind.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(IslandStyle.primary).lineLimit(1)
                        Text(waiting ? "Needs you" : working > 0 ? "\(working) working" : "Idle")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(waiting ? IslandStyle.amber : working > 0 ? IslandStyle.volt : IslandStyle.tertiary)
                            .lineLimit(1)
                    }
                    ForEach(Array((monitor.usage[kind]?.windows ?? []).prefix(2).enumerated()), id: \.offset) { _, window in
                        HStack(spacing: 8) {
                            Text(window.label)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(IslandStyle.tertiary)
                                .lineLimit(1)
                                .frame(width: 48, alignment: .leading)
                            Meter(fraction: window.usedPercent / 100, tint: window.usedPercent >= 80 ? IslandStyle.amber : IslandStyle.volt)
                            Text("\(Int(window.usedPercent.rounded()))%")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(IslandStyle.secondary)
                                .frame(width: 30, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }
}

// MARK: Up next

private struct UpNextSummary: View {
    let calendar: CalendarStore
    let showsCalendar: Bool
    let focus: FocusTimer

    var body: some View {
        VStack(spacing: 8) {
            if showsCalendar && calendar.isAllowed {
                TimelineView(.everyMinute) { context in
                    let _ = calendar.revision
                    let next = calendar.events(on: context.date).first { !$0.isAllDay && $0.end > context.date }
                    UpNextCard {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(next.map { Color(nsColor: $0.color) } ?? Color.white.opacity(0.15))
                            .frame(width: 3, height: 30)
                    } text: {
                        Text(next?.title ?? "Nothing else today")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(next == nil ? IslandStyle.secondary : IslandStyle.primary)
                            .lineLimit(1)
                        if let next {
                            Text(Self.when(next, now: context.date))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(IslandStyle.secondary)
                                .lineLimit(1)
                        }
                    } action: {
                        if let link = next?.link {
                            IslandButton(title: "Join", prominent: true) { NSWorkspace.shared.open(link) }
                        }
                    }
                }
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let phase = focus.cycle.phase
                UpNextCard {
                    if focus.isActive {
                        FocusRing(fraction: focus.fraction(at: context.date), tint: phase.tint, lineWidth: 2.5)
                            .frame(width: 18, height: 18)
                    } else {
                        Image(systemName: "timer").font(.system(size: 15, weight: .medium)).foregroundStyle(IslandStyle.tomato)
                    }
                } text: {
                    Text(phase == .rest ? "Break" : "Focus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(IslandStyle.primary)
                    Text(focus.isActive
                        ? FocusTimer.clock(focus.remaining(at: context.date)) + " · \(focus.cycle.round) of \(FocusCycle.roundsPerSet)"
                        : "\(focus.preset.focus) / \(focus.preset.rest) · \(focus.cycle.round) of \(FocusCycle.roundsPerSet)")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(IslandStyle.secondary)
                        .lineLimit(1)
                } action: {
                    Button { focus.isActive ? focus.toggle() : focus.start() } label: {
                        Text(focus.isRunning ? "Pause" : focus.isPaused ? "Resume" : "Start")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(IslandStyle.tomato)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(IslandStyle.tomato.opacity(0.15), in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    static func when(_ event: CalendarEvent, now: Date) -> String {
        let time = event.start.formatted(date: .omitted, time: .shortened)
        if event.start <= now { return "\(time) · now" }
        let minutes = Int(event.start.timeIntervalSince(now) / 60)
        if minutes < 60 { return "\(time) · in \(max(minutes, 1)) min" }
        return time
    }
}

private struct UpNextCard<Leading: View, TextContent: View, Action: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var text: TextContent
    @ViewBuilder var action: Action

    var body: some View {
        HStack(spacing: 10) {
            leading
            VStack(alignment: .leading, spacing: 2) { text }
                .frame(maxWidth: .infinity, alignment: .leading)
            action
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
