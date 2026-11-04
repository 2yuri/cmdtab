import CoreGraphics
import Foundation

/// What the island shows right now. Pure, so the priorities can be tested.
enum IslandContent: Equatable {
    /// Nothing live: just the notch (hidden on screens without one).
    case idle
    /// Agents working or waiting for you, with whatever else is going on.
    case agents(AgentsRow)
    case finished(AgentSession)
    case approval(ApprovalRequest)
    /// Music playing, nothing else going on.
    case music
    /// A file is being dragged over the island.
    case drop
    /// A window is being dragged to the island: pick a layout.
    case windowDrop(WindowDropLayout?)
    /// With Tiling on: a tiled window held over the island, and the other columns.
    case columnDrop(NotchDrop.State)
    /// A download or screenshot just landed on the Shelf.
    case arrival(ShelfItem)
    case meeting(UpcomingMeeting)
    case moment(Moment)
    /// A Pomodoro phase running or paused.
    case focus(FocusCycle.Phase)
    /// A Pomodoro phase just ran out: what's next.
    case focusEnded(FocusCycle.Phase)
    case expanded(IslandModule)

    /// Grown states get a taller shape with content under the notch.
    var isGrown: Bool {
        switch self {
        case .finished, .approval, .drop, .windowDrop, .columnDrop, .arrival, .meeting, .focusEnded, .expanded: true
        default: false
        }
    }

    struct Inputs {
        var isExpanded = false
        var tab: IslandModule?
        var isDropTargeted = false
        var approvals: [ApprovalRequest] = []
        var finished: FinishedEvent?
        var sessions: [AgentSession] = []
        var usage: [AgentKind: AgentUsage] = [:]
        var showsLimit = true
        var agentsOn = true
        var musicPlaying = false
        var windowDrop: WindowDropLayout??
        var columnDrop: NotchDrop.State?
        var arrival: ShelfItem?
        var meeting: UpcomingMeeting?
        var moment: Moment?
        var focusPhase: FocusCycle.Phase?
        var focusEnded: FocusCycle.Phase?
        var now = Date.now
    }

    /// A session left waiting this long (a dialog nobody answered days ago) no longer takes over the
    /// closed island. It still shows in the list.
    static let staleWaiting: TimeInterval = 12 * 60 * 60

    /// Dragging wins (you're mid-gesture), then a question waiting for you, then what you opened,
    /// then news, then ongoing work.
    static func resolve(_ inputs: Inputs) -> IslandContent {
        // With the Shelf already open, files land on its own drop zone: no switch to another view.
        if inputs.isDropTargeted, !(inputs.isExpanded && inputs.tab == .shelf) { return .drop }
        if let layout = inputs.windowDrop { return .windowDrop(layout) }
        if let columns = inputs.columnDrop { return .columnDrop(columns) }
        if inputs.agentsOn, let request = inputs.approvals.first { return .approval(request) }
        if inputs.isExpanded, let tab = inputs.tab { return .expanded(tab) }
        if let meeting = inputs.meeting { return .meeting(meeting) }
        if inputs.agentsOn, let finished = inputs.finished { return .finished(finished.session) }
        if let arrival = inputs.arrival { return .arrival(arrival) }
        if let ended = inputs.focusEnded { return .focusEnded(ended) }
        if let moment = inputs.moment { return .moment(moment) }
        if inputs.agentsOn, let row = AgentsRow(inputs) { return .agents(row) }
        if let phase = inputs.focusPhase { return .focus(phase) }
        if inputs.musicPlaying { return .music }
        return .idle
    }
}

/// Sizes of the island shape in each state. The notch's own size is the starting point, so the shape
/// always covers it exactly.
enum IslandLayout {
    /// How far the closed island reaches past each side of the notch.
    static let wing: CGFloat = 84
    static let grownCornerRadius: CGFloat = 24
    static let expandedCornerRadius: CGFloat = 30

    /// The open island never grows past this; longer lists scroll.
    static let maximumExpandedHeight: CGFloat = 460
    /// The widest the island ever gets (any tab), so its fixed panel always holds it, centred.
    static var maximumWidth: CGFloat { IslandModule.allCases.map(width(of:)).max() ?? 680 }

    /// Widths from the design: wide for Agents' two columns, narrow for single-column tabs.
    static func width(of tab: IslandModule) -> CGFloat {
        switch tab {
        case .overview: 980
        case .agents: 680
        case .music, .windows: 520
        default: 420
        }
    }

    static func size(of content: IslandContent, notch: CGSize, tabHeights: [IslandModule: CGFloat] = [:]) -> CGSize {
        switch content {
        case .idle: notch
        case .music, .focus: CGSize(width: notch.width + 2 * wing, height: notch.height)
        case let .agents(row): CGSize(width: notch.width + 2 * max(wing, row.wing), height: notch.height)
        case .moment: CGSize(width: notch.width + 2 * (wing + 30), height: notch.height)
        case .finished, .arrival, .meeting, .focusEnded: CGSize(width: max(420, notch.width + 2 * wing), height: notch.height + 64)
        case .windowDrop: CGSize(width: max(440, notch.width + 2 * wing), height: notch.height + 92)
        case let .columnDrop(state):
            CGSize(width: min(max(440, notch.width + 2 * wing, columnsWidth(state.columns.count) + 28), 720), height: notch.height + 84)
        case .approval: CGSize(width: max(460, notch.width + 2 * wing), height: notch.height + 136)
        case .drop: CGSize(width: max(380, notch.width + 2 * wing), height: notch.height + 96)
        case let .expanded(tab):
            CGSize(width: max(width(of: tab), notch.width + 2 * wing), height: tabHeights[tab] ?? notch.height + 260)
        }
    }

    /// Room for `count` column tiles at a comfortable size.
    static func columnsWidth(_ count: Int) -> CGFloat {
        CGFloat(count) * 64 + CGFloat(max(count - 1, 0)) * NotchDrop.spacing
    }

    /// The notch drawn on screens without one: about the size of a MacBook's.
    static let fakeNotch = CGSize(width: 190, height: 24)
}

/// The closed island while agents are busy. Yours on the left (a question waiting, or the song and
/// the Pomodoro), the agents on the right: one mark per tool, waiting ones first.
struct AgentsRow: Equatable {
    struct Mark: Equatable {
        var kind: AgentKind
        var needsYou: Bool
    }

    var marks: [Mark]
    /// The first session waiting for you; it takes the left side.
    var waiting: AgentSession?
    /// The session a click brings forward.
    var primary: AgentSession
    /// The busiest tool's session limit.
    var percent: Double?
    var withMusic = false
    var focus: FocusCycle.Phase?

    init(marks: [Mark], waiting: AgentSession?, primary: AgentSession, percent: Double?,
         withMusic: Bool = false, focus: FocusCycle.Phase? = nil) {
        self.marks = marks
        self.waiting = waiting
        self.primary = primary
        self.percent = percent
        self.withMusic = withMusic
        self.focus = focus
    }

    init?(_ inputs: IslandContent.Inputs) {
        let waiting = inputs.sessions.filter {
            $0.state == .needsYou && inputs.now.timeIntervalSince($0.since) < IslandContent.staleWaiting
        }
        let working = inputs.sessions.filter { $0.state == .working }
        guard let primary = waiting.first ?? working.first else { return nil }
        var kinds: [AgentKind] = []
        for session in waiting + working where !kinds.contains(session.kind) { kinds.append(session.kind) }
        self.init(
            marks: kinds.map { kind in Mark(kind: kind, needsYou: waiting.contains { $0.kind == kind }) },
            waiting: waiting.first,
            primary: primary,
            percent: inputs.showsLimit ? kinds.compactMap { inputs.usage[$0]?.session?.usedPercent }.max() : nil,
            withMusic: inputs.musicPlaying,
            focus: inputs.focusPhase
        )
    }

    /// The limit shows on the left when nothing else is there, else beside the marks.
    var percentOnLeft: Bool { waiting == nil && !withMusic && focus == nil }

    /// How far past each side of the notch the content needs (both sides match, the notch is centred).
    var wing: CGFloat {
        let padding: CGFloat = 14 + 10
        var left: CGFloat = 0
        if let waiting {
            left = 18 + CGFloat("\(waiting.kind.shortName) needs you".count) * 6.6
        } else {
            if withMusic { left += 51 }
            if withMusic && focus != nil { left += 17 }
            if let focus { left += focus == .rest ? 100 : 66 }
            if percentOnLeft, percent != nil { left = 34 }
        }
        var right = CGFloat(marks.count) * 24 + CGFloat(max(marks.count - 1, 0)) * 4
        if !percentOnLeft, waiting == nil, percent != nil { right += 34 + 8 }
        return max(left, right) + padding
    }
}
