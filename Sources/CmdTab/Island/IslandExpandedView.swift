import SwiftUI

/// The open island, the same frame for every tab: the notch row (first city on the left, the
/// temperature on the right), the tabs centred under the notch, then the tab. The tab sets the
/// width (from the design) and its content the height, measured, so there's never empty space.
struct ExpandedView: View {
    let model: IslandModel
    let services: IslandServices
    let preferences: Preferences
    let tab: IslandModule

    var body: some View {
        VStack(spacing: 12) {
            NotchRow(model: model, preferences: preferences, weather: services.weather, wide: IslandLayout.width(of: tab) >= 600)
            TabBar(tabs: preferences.islandTabs, selection: tab) { model.tab = $0 }
            Group {
                switch tab {
                case .overview: OverviewTab(services: services, preferences: preferences)
                case .agents: AgentsTab(monitor: services.agents)
                case .music: MusicTab(music: services.music)
                case .shelf: ShelfTab(shelf: services.shelf, isTargeted: model.isDropTargeted)
                case .windows: WindowsTab(source: services.windows)
                case .calendar: CalendarTab(calendar: services.calendar)
                case .focus: FocusTab(timer: services.focus)
                case .clock: ClockTab(preferences: preferences)
                case .weather: WeatherTab(preferences: preferences, weather: services.weather)
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
            model.setMeasuredHeight(height, for: tab)
        }
    }
}

/// Beside the notch: the first city's time on the left and the second's on the right. The
/// temperature joins them when the island is wide enough.
private struct NotchRow: View {
    let model: IslandModel
    let preferences: Preferences
    let weather: WeatherService
    let wide: Bool

    var body: some View {
        let cities = preferences.isIslandModuleOn(.clock) ? Array(preferences.islandCities.prefix(2)) : []
        let report = preferences.isIslandModuleOn(.weather) ? weather.report : nil
        TimelineView(.everyMinute) { context in
            HStack(spacing: 0) {
                HStack(spacing: 10) {
                    if let first = cities.first { CityTime(city: first, date: context.date, labelled: cities.count > 1) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: model.hasNotch ? model.notch.width : 0)
                HStack(spacing: 10) {
                    if cities.count > 1 { CityTime(city: cities[1], date: context.date, labelled: true) }
                    if let report, wide || cities.count < 2 {
                        HStack(spacing: 4) {
                            Image(systemName: WeatherService.symbol(report.code, isDay: report.isDay))
                            Text("\(Int(report.temperature.rounded()))°")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(IslandStyle.secondary)
        .padding(.horizontal, 4)
        .frame(height: model.notch.height - 4)
        .offset(y: -1)
        .onAppear {
            if preferences.isIslandModuleOn(.weather) { weather.refreshIfNeeded(place: preferences.islandWeatherPlace) }
        }
    }
}

/// "SAO 6:12": the city's three letters dimmer than its time.
private struct CityTime: View {
    let city: WorldCity
    let date: Date
    let labelled: Bool

    var body: some View {
        HStack(spacing: 4) {
            if labelled { Text(city.short).foregroundStyle(IslandStyle.tertiary) }
            Text(city.time(at: date)).monospacedDigit().foregroundStyle(IslandStyle.primary.opacity(0.85))
        }
        .lineLimit(1)
        .fixedSize()
    }
}

private struct TabBar: View {
    let tabs: [IslandModule]
    let selection: IslandModule
    let select: (IslandModule) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs) { tab in
                let isOn = tab == selection
                Button { select(tab) } label: {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isOn ? IslandStyle.primary : IslandStyle.tertiary)
                        .frame(width: 32, height: 26)
                        .background(isOn ? Color.white.opacity(0.13) : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(tab.title)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// "Shelf" on the left, a detail or action on the right: every tab starts with one.
struct TabHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Text(title).font(.system(size: 15, weight: .bold)).foregroundStyle(IslandStyle.primary)
            Spacer()
            trailing
        }
    }
}

// MARK: Agents

private struct AgentsTab: View {
    let monitor: AgentMonitor
    @State private var query = ""

    private var shown: [AgentSession] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return monitor.sessions }
        return monitor.allSessions.filter { session in
            [session.project, session.detail ?? "", session.kind.name].contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .medium))
                    TextField("Search sessions", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .foregroundStyle(IslandStyle.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                let sessions = shown
                if sessions.isEmpty {
                    Text(query.isEmpty ? "No agents running" : "No sessions match")
                        .font(.system(size: 13))
                        .foregroundStyle(IslandStyle.secondary)
                        .padding(.top, 6)
                } else {
                    let rows = VStack(spacing: 2) {
                        ForEach(sessions) { session in
                            SessionRow(session: session) { monitor.open(session) }
                        }
                    }
                    if sessions.count > 6 {
                        ScrollView { rows }.scrollIndicators(.never).frame(height: 6 * 42)
                    } else {
                        rows
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            let usages = [AgentKind.claude, .codex].compactMap { monitor.usage[$0] }
            if !usages.isEmpty {
                VStack(spacing: 10) {
                    ForEach(usages, id: \.kind) { UsageCard(usage: $0) }
                }
                .frame(width: 270)
            }
        }
    }
}

private struct SessionRow: View {
    let session: AgentSession
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                AgentMark(kind: session.kind, size: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.project)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(IslandStyle.primary)
                        .lineLimit(1)
                    if let detail = session.detail {
                        Text(detail).font(.system(size: 12)).foregroundStyle(IslandStyle.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                StatePill(state: session.state)
                Text(session.since, format: .relativeShort)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(IslandStyle.tertiary)
                    .frame(width: 28, alignment: .trailing)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct StatePill: View {
    let state: AgentState

    var body: some View {
        let (title, symbol, tint): (String, String, Color) = switch state {
        case .working: ("Working", "rays", IslandStyle.volt)
        case .needsYou: ("Needs you", "hand.raised.fill", IslandStyle.amber)
        case .done: ("Done", "checkmark", IslandStyle.secondary)
        case .idle: ("Idle", "moon.zzz", IslandStyle.tertiary)
        }
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold))
            Text(title).font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(state == .done ? 0.12 : 0.15), in: Capsule())
    }
}

private struct UsageCard: View {
    let usage: AgentUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                AgentMark(kind: usage.kind, size: 20)
                Text(usage.kind.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(IslandStyle.primary)
            }
            ForEach(usage.windows, id: \.label) { window in
                VStack(spacing: 5) {
                    HStack {
                        Text(window.label).font(.system(size: 12)).foregroundStyle(IslandStyle.primary)
                        Spacer()
                        Text(UsageText.value(window))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(IslandStyle.secondary)
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.1))
                            Capsule()
                                .fill(window.usedPercent >= 80 ? IslandStyle.warning : IslandStyle.volt)
                                .frame(width: proxy.size.width * min(max(window.usedPercent, 0), 100) / 100)
                        }
                    }
                    .frame(height: 5)
                }
            }
        }
        .padding(12)
        .background(IslandStyle.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// "62% · resets 2h 14m", "38% · resets Thu".
enum UsageText {
    static func value(_ window: UsageWindow, now: Date = .now) -> String {
        let percent = "\(Int(window.usedPercent.rounded()))%"
        guard let resets = window.resetsAt, resets > now else { return percent }
        return "\(percent) · resets \(resetText(resets, now: now))"
    }

    static func resetText(_ date: Date, now: Date) -> String {
        let seconds = Int(date.timeIntervalSince(now))
        if seconds < 24 * 3600 {
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            return hours > 0 ? "\(hours)h \(minutes)m" : "\(max(minutes, 1))m"
        }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }
}

extension FormatStyle where Self == RelativeShortDateStyle {
    static var relativeShort: RelativeShortDateStyle { RelativeShortDateStyle() }
}

/// "3m", "1h", "2d".
struct RelativeShortDateStyle: FormatStyle {
    func format(_ value: Date) -> String {
        let seconds = max(0, Int(Date.now.timeIntervalSince(value)))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86400 { return "\(seconds / 3600)h" }
        return "\(seconds / 86400)d"
    }
}
