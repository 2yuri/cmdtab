import AppKit
import Observation

/// Claude Code and Codex sessions, their limits and pending approvals. Reads the tools' files when
/// they change (FSEvents), never on a timer.
@MainActor
@Observable
final class AgentMonitor {
    /// Sessions doing something or just done, most urgent first.
    private(set) var sessions: [AgentSession] = []
    /// Every running session, idle ones too, for search.
    private(set) var allSessions: [AgentSession] = []
    private(set) var usage: [AgentKind: AgentUsage] = [:]
    private(set) var approvals: [ApprovalRequest] = []
    /// The last session to finish, while the island shows it.
    private(set) var finished: FinishedEvent?

    @ObservationIgnored var notifies = true
    @ObservationIgnored private var transitions = AgentTransitions()
    @ObservationIgnored private var watchers: [FileWatcher] = []
    @ObservationIgnored private var hookServer: ClaudeHookServer?
    @ObservationIgnored private var finishedTimer: Timer?
    @ObservationIgnored private var refreshing = false

    static let finishedDuration: TimeInterval = 4

    var isRunning: Bool { !watchers.isEmpty }

    func start() {
        guard watchers.isEmpty else { return }
        IslandFiles.ensureDirectory()
        let paths = [ClaudeSessionReader.directory.path, CodexReader.directory.path, IslandFiles.directory.path]
        if let watcher = FileWatcher(paths: paths, onChange: { [weak self] in self?.refresh() }) {
            watchers.append(watcher)
        }
        refresh()
    }

    func stop() {
        watchers.forEach { $0.stop() }
        watchers.removeAll()
        sessions = []
        allSessions = []
        usage = [:]
        finished = nil
        transitions = AgentTransitions()
    }

    // MARK: Approvals

    func setApprovals(_ on: Bool) {
        if on {
            guard hookServer == nil else { return }
            let server = ClaudeHookServer()
            server.onRequest = { [weak self] request in self?.approvals.append(request.approval) }
            server.onCancel = { [weak self] id in self?.approvals.removeAll { $0.id == id } }
            server.start()
            hookServer = server
        } else {
            hookServer?.stop()
            hookServer = nil
            approvals.removeAll()
        }
    }

    func answer(_ request: ApprovalRequest, _ decision: ApprovalDecision) {
        hookServer?.answer(request.id, with: decision)
        approvals.removeAll { $0.id == request.id }
    }

    func dismissFinished() {
        finished = nil
        finishedTimer?.invalidate()
    }

    // MARK: Reading

    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        Task.detached(priority: .utility) {
            let claude = ClaudeSessionReader.read()
            let claudeUsage = ClaudeUsageReader.read()
            let codex = CodexReader.read()
            await MainActor.run { [weak self] in
                self?.apply(claude + codex.sessions, claudeUsage: claudeUsage, codexUsage: codex.usage)
            }
        }
    }

    private func apply(_ raw: [AgentSession], claudeUsage: AgentUsage?, codexUsage: AgentUsage?) {
        refreshing = false
        let now = Date.now
        let (current, justFinished) = transitions.apply(raw, now: now)
        let all = current.sorted { lhs, rhs in
            if lhs.state.rank != rhs.state.rank { return lhs.state.rank < rhs.state.rank }
            return lhs.since > rhs.since
        }
        let ordered = all.filter { $0.state != .idle }
        if ordered != sessions { sessions = ordered }
        if all != allSessions { allSessions = all }
        var newUsage: [AgentKind: AgentUsage] = [:]
        newUsage[.claude] = claudeUsage
        newUsage[.codex] = codexUsage
        if newUsage != usage { usage = newUsage }
        if notifies, let last = justFinished.last {
            finished = FinishedEvent(session: last, at: now)
            finishedTimer?.invalidate()
            finishedTimer = Timer.scheduledTimer(withTimeInterval: Self.finishedDuration, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.finished = nil }
            }
        }
    }

    /// Brings the session's terminal forward.
    func open(_ session: AgentSession) {
        guard let pid = session.pid, let app = Self.owningApp(of: pid) else { return }
        app.activate()
    }

    /// The app (terminal, editor) whose process tree contains `pid`.
    private static func owningApp(of pid: pid_t) -> NSRunningApplication? {
        var current = pid
        for _ in 0..<12 {
            if let app = NSRunningApplication(processIdentifier: current), app.activationPolicy == .regular {
                return app
            }
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.size
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, current]
            guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return nil }
            let parent = info.kp_eproc.e_ppid
            guard parent > 1 else { return nil }
            current = parent
        }
        return nil
    }
}

extension AgentState {
    /// Needs you first, then working, then done.
    var rank: Int {
        switch self {
        case .needsYou: 0
        case .working: 1
        case .done: 2
        case .idle: 3
        }
    }
}
