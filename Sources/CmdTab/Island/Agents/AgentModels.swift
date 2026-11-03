import Foundation

enum AgentKind: String, Sendable {
    case claude, codex

    var name: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }

    var shortName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }
}

enum AgentState: Equatable, Sendable {
    case working
    case needsYou
    /// Finished its turn while you were away; cleared when it starts working again.
    case done
    case idle
}

/// One running agent session, as read from the tool's own files.
struct AgentSession: Identifiable, Equatable, Sendable {
    let id: String
    let kind: AgentKind
    /// The folder it runs in.
    let project: String
    /// The session's name, or what it's waiting for.
    var detail: String?
    var state: AgentState
    /// When the state last changed.
    var since: Date
    /// The terminal process, to bring its window forward.
    var pid: pid_t?
}

/// One limit window: "Session 62% · resets 2h 14m".
struct UsageWindow: Equatable, Sendable {
    let label: String
    /// 0…100.
    let usedPercent: Double
    let resetsAt: Date?
}

struct AgentUsage: Equatable, Sendable {
    let kind: AgentKind
    var windows: [UsageWindow]

    /// The short window (5 hours), what the closed island shows.
    var session: UsageWindow? { windows.first }
}

/// Claude Code is waiting to run a tool; the island can answer for you.
struct ApprovalRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    let kind: AgentKind
    let project: String
    let tool: String
    /// The command, file or URL it wants to use.
    let summary: String
    let receivedAt: Date
}

enum ApprovalDecision: Sendable {
    case allow, deny
    /// Allow, and add the rule Claude Code suggested so it stops asking.
    case allowAlways
}

/// A session that just finished, shown briefly by the closed island.
struct FinishedEvent: Equatable, Sendable {
    let session: AgentSession
    let at: Date
}

/// Turns raw states read on each change into what the island shows: "Done" for a session that went
/// from working to idle, and a finished event for the moment it happened. Pure, so it can be tested.
struct AgentTransitions {
    private(set) var previous: [String: AgentSession] = [:]

    /// `sessions` are as read now (working, needsYou or idle). Returns them with `.done` applied and
    /// the sessions that finished since the last call.
    mutating func apply(_ sessions: [AgentSession], now: Date) -> (sessions: [AgentSession], finished: [AgentSession]) {
        var finished: [AgentSession] = []
        var result: [AgentSession] = []
        for var session in sessions {
            let before = previous[session.id]
            if session.state == .idle, let before {
                switch before.state {
                case .working:
                    session.state = .done
                    session.since = now
                    finished.append(session)
                case .done:
                    session.state = .done
                    session.since = before.since
                default:
                    break
                }
            }
            if let before, before.state == session.state {
                session.since = before.since
            }
            result.append(session)
        }
        previous = Dictionary(result.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        return (result, finished)
    }
}
