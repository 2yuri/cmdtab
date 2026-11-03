import Foundation

/// Which screens get an island.
enum IslandScreen: String, CaseIterable {
    /// The display the Dock is on; it follows the Dock when it moves.
    case dock
    /// The built-in display (it has the notch), or the main display when the lid is closed.
    case builtIn
    case main
    case all

    var label: String {
        switch self {
        case .dock: "Display with the Dock"
        case .builtIn: "Built-in display"
        case .main: "Main display"
        case .all: "All"
        }
    }
}

/// One thing the island can show. Most are tabs; Moments only ever show while closed.
enum IslandModule: String, Codable, CaseIterable, Identifiable {
    case overview, agents, music, shelf, windows, calendar, focus, meetings, clock, weather, moments

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .agents: "Agents"
        case .music: "Music"
        case .shelf: "Shelf"
        case .windows: "Windows"
        case .calendar: "Calendar"
        case .focus: "Focus"
        case .meetings: "Meetings"
        case .clock: "World clock"
        case .weather: "Weather"
        case .moments: "Moments"
        }
    }

    var detail: String {
        switch self {
        case .overview: "Music, this Mac, your agents and what's next in one tab. Reads CPU and memory only while it's open."
        case .agents: "Claude Code and Codex: what's left of your limits and what each session is doing."
        case .music: "What's playing, from any app. Controls and AirPlay when it opens."
        case .shelf: "Holds files you drag to the notch for 24 hours, and new downloads and screenshots."
        case .windows: "The windows on this desktop. Click one to switch, or drag one to the notch to arrange it."
        case .calendar: "Your week, month or year from the Calendar app, with Join for calls and quick new events."
        case .focus: "A Pomodoro timer: focus and break rounds, shown beside the notch while it runs."
        case .meetings: "Your next event five minutes before, with Join. Asks for Calendar access."
        case .clock: "Two cities beside the notch when it opens, every city in its tab."
        case .weather: "Your city's weather. Uses the network: one request every 30 minutes."
        case .moments: "AirPods, charger and timers, for a few seconds when they happen."
        }
    }

    /// SF Symbol for Settings and the tab bar.
    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .agents: "sparkles"
        case .music: "music.note"
        case .shelf: "tray"
        case .windows: "macwindow"
        case .calendar: "calendar"
        case .focus: "timer"
        case .meetings: "bell"
        case .clock: "globe"
        case .weather: "cloud.sun"
        case .moments: "sparkle"
        }
    }

    /// Modules built so far; the rest stay out of Settings until they work.
    static let available: [IslandModule] = IslandModule.allCases

    /// Meetings and Moments only appear while closed, so they have no tab.
    var hasTab: Bool { self != .meetings && self != .moments }
}

struct IslandModuleSetting: Codable, Hashable, Identifiable {
    var module: IslandModule
    var isOn: Bool

    var id: IslandModule { module }

    /// The saved order, with modules added in later versions appended (off) and unknown ones dropped.
    static func normalized(_ saved: [IslandModuleSetting]) -> [IslandModuleSetting] {
        var seen = Set<IslandModule>()
        var result = saved.filter { seen.insert($0.module).inserted }
        for module in IslandModule.allCases where !seen.contains(module) {
            // The Overview sums up the rest, so it goes first; anything else new goes last.
            if module == .overview {
                result.insert(IslandModuleSetting(module: module, isOn: false), at: 0)
            } else {
                result.append(IslandModuleSetting(module: module, isOn: false))
            }
        }
        return result
    }
}
