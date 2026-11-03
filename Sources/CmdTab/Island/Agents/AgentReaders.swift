import Darwin
import Foundation

/// Where CmdTab keeps the island's own files (the hook socket, Claude Code's last status line).
enum IslandFiles {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("CmdTab", isDirectory: true)
    }

    static var claudeStatus: URL { directory.appendingPathComponent("claude-status.json") }
    static var hookSocket: URL { directory.appendingPathComponent("island.sock") }

    static func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}

/// Claude Code writes one small file per running session (`~/.claude/sessions/<pid>.json`) and
/// rewrites it when the session's status changes: busy, waiting or idle.
enum ClaudeSessionReader {
    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/sessions", isDirectory: true)
    }

    private struct File: Decodable {
        let pid: Int32
        let sessionId: String?
        let cwd: String?
        let name: String?
        let status: String?
        let waitingFor: String?
        let statusUpdatedAt: Double?
        let kind: String?
    }

    static func read() -> [AgentSession] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap(session)
    }

    static func session(at url: URL) -> AgentSession? {
        guard let data = try? Data(contentsOf: url), let file = try? JSONDecoder().decode(File.self, from: data) else {
            return nil
        }
        return session(from: file, isAlive: isAlive(file.pid))
    }

    static func session(fromJSON data: Data, isAlive: Bool) -> AgentSession? {
        guard let file = try? JSONDecoder().decode(File.self, from: data) else { return nil }
        return session(from: file, isAlive: isAlive)
    }

    private static func session(from file: File, isAlive: Bool) -> AgentSession? {
        guard isAlive, file.kind == nil || file.kind == "interactive" else { return nil }
        let state: AgentState = switch file.status {
        case "busy": .working
        case "waiting": .needsYou
        default: .idle
        }
        let project = file.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Claude Code"
        let detail = state == .needsYou ? file.waitingFor.map(Self.describe) : nil
        return AgentSession(
            id: "claude-\(file.sessionId ?? String(file.pid))",
            kind: .claude,
            project: project,
            detail: detail,
            state: state,
            since: file.statusUpdatedAt.map { Date(timeIntervalSince1970: $0 / 1000) } ?? .now,
            pid: file.pid
        )
    }

    private static func describe(_ waitingFor: String) -> String {
        switch waitingFor {
        case "permission prompt": "Wants permission"
        case "input needed": "Asked you something"
        case "dialog open": "Waiting on a dialog"
        default: waitingFor.prefix(1).uppercased() + waitingFor.dropFirst()
        }
    }

    private static func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}

/// Claude Code's limits, from the last status line CmdTab saw (see `ClaudeStatusLine`).
enum ClaudeUsageReader {
    private struct Status: Decodable {
        struct Limits: Decodable {
            struct Window: Decodable {
                let used_percentage: Double?
                let resets_at: Double?
            }
            let five_hour: Window?
            let seven_day: Window?
        }
        let rate_limits: Limits?
    }

    static func read(now: Date = .now) -> AgentUsage? {
        guard let data = try? Data(contentsOf: IslandFiles.claudeStatus) else { return nil }
        return usage(fromJSON: data, now: now)
    }

    static func usage(fromJSON data: Data, now: Date) -> AgentUsage? {
        guard let limits = (try? JSONDecoder().decode(Status.self, from: data))?.rate_limits else { return nil }
        var windows: [UsageWindow] = []
        for (label, window) in [("Session", limits.five_hour), ("This week", limits.seven_day)] {
            guard let window, let used = window.used_percentage else { continue }
            let resets = window.resets_at.map { Date(timeIntervalSince1970: $0) }
            // Past its reset, the window has started over.
            let current = resets.map { $0 > now } ?? true
            windows.append(UsageWindow(label: label, usedPercent: current ? used : 0, resetsAt: current ? resets : nil))
        }
        return windows.isEmpty ? nil : AgentUsage(kind: .claude, windows: windows)
    }
}

/// Codex keeps a log per session (`~/.codex/sessions/YYYY/MM/DD/rollout-….jsonl`). Its last lines say
/// whether a turn is running, and every turn records the account's limits.
enum CodexReader {
    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions", isDirectory: true)
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: directory.deletingLastPathComponent().path)
    }

    /// A turn left running longer than this without writing is assumed dead.
    static let staleAfter: TimeInterval = 15 * 60
    /// Sessions not written to for this long are left out.
    static let recentWithin: TimeInterval = 6 * 60 * 60

    static func read(now: Date = .now) -> (sessions: [AgentSession], usage: AgentUsage?) {
        var sessions: [AgentSession] = []
        var newestUsage: (Date, AgentUsage)?
        for (url, modified) in recentLogs(now: now) {
            let isRecent = now.timeIntervalSince(modified) < recentWithin
            // Older logs are only read until one gives the limits.
            guard isRecent || newestUsage == nil, let summary = summarize(url: url) else { continue }
            if let usage = summary.usage, newestUsage.map({ modified > $0.0 }) ?? true {
                newestUsage = (modified, usage)
            }
            guard summary.isInteractive, isRecent else { continue }
            var state = summary.state
            if state == .working, now.timeIntervalSince(modified) > staleAfter { state = .idle }
            sessions.append(AgentSession(
                id: "codex-\(url.lastPathComponent)",
                kind: .codex,
                project: summary.project,
                detail: nil,
                state: state,
                since: modified,
                pid: nil
            ))
        }
        return (sessions, newestUsage.map { current($0.1, now: now) })
    }

    /// A window past its reset has started over.
    static func current(_ usage: AgentUsage, now: Date) -> AgentUsage {
        var usage = usage
        usage.windows = usage.windows.map { window in
            guard let resets = window.resetsAt, resets <= now else { return window }
            return UsageWindow(label: window.label, usedPercent: 0, resetsAt: nil)
        }
        return usage
    }

    /// Logs from the last 8 days, newest first: sessions only count from the last few hours, but
    /// the limits come from whichever log is newest, even if Codex hasn't run for days.
    private static func recentLogs(now: Date) -> [(URL, Date)] {
        let calendar = Calendar.current
        let fm = FileManager.default
        var logs: [(URL, Date)] = []
        for dayOffset in stride(from: 0, through: -7, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            let folder = directory.appendingPathComponent(String(format: "%04d/%02d/%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0))
            let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for file in files where file.pathExtension == "jsonl" {
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                logs.append((file, modified))
            }
        }
        return logs.sorted { $0.1 > $1.1 }
    }

    struct Summary: Equatable {
        var project: String
        var isInteractive: Bool
        var state: AgentState
        var usage: AgentUsage?
    }

    static func summarize(url: URL) -> Summary? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 8192)) ?? Data()
        let size = (try? handle.seekToEnd()) ?? 0
        let tailLength: UInt64 = 256 * 1024
        try? handle.seek(toOffset: size > tailLength ? size - tailLength : 0)
        let tail = (try? handle.readToEnd()) ?? Data()
        return summarize(head: head, tail: tail)
    }

    static func summarize(head: Data, tail: Data) -> Summary? {
        let headText = String(decoding: head, as: UTF8.self)
        let project = firstMatch(#""cwd":"([^"]*)""#, in: headText).map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Codex"
        // Runs started by other apps (`codex exec`) aren't sessions you're watching.
        let source = firstMatch(#""source":"([^"]*)""#, in: headText)
        var summary = Summary(project: project, isInteractive: source != "exec", state: .idle, usage: nil)
        var stateFound = false
        let lines = String(decoding: tail, as: UTF8.self).split(separator: "\n").reversed()
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = object["payload"] as? [String: Any],
                  let type = payload["type"] as? String else { continue }
            if !stateFound {
                switch type {
                case "task_started": summary.state = .working; stateFound = true
                case "task_complete", "turn_aborted": summary.state = .idle; stateFound = true
                case let other where other.hasSuffix("approval_request"): summary.state = .needsYou; stateFound = true
                default: break
                }
            }
            if summary.usage == nil, type == "token_count", let limits = payload["rate_limits"] as? [String: Any] {
                summary.usage = usage(from: limits)
            }
            if stateFound && summary.usage != nil { break }
        }
        return summary
    }

    private static func usage(from limits: [String: Any]) -> AgentUsage? {
        var windows: [UsageWindow] = []
        for key in ["primary", "secondary"] {
            guard let window = limits[key] as? [String: Any], let used = window["used_percent"] as? Double else { continue }
            let minutes = window["window_minutes"] as? Double ?? 0
            let label = minutes >= 7 * 24 * 60 ? "This week" : minutes > 0 ? "\(Int(minutes / 60)) hours" : "Limit"
            let resets = (window["resets_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
            windows.append(UsageWindow(label: label, usedPercent: used, resetsAt: resets))
        }
        return windows.isEmpty ? nil : AgentUsage(kind: .codex, windows: windows)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}
