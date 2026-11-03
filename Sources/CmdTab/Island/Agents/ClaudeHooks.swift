import Darwin
import Foundation

/// Claude Code's PermissionRequest hook connects here and waits: CmdTab shows the request in the
/// island and writes back Allow or Deny. If CmdTab isn't running the hook gets nothing and Claude
/// Code shows its own prompt as usual.
final class ClaudeHookServer: @unchecked Sendable {
    struct Request: Sendable {
        let approval: ApprovalRequest
        let suggestions: Data?
    }

    /// Called on the main actor for each request.
    var onRequest: (@MainActor @Sendable (Request) -> Void)?
    /// Called on the main actor when a request goes away without an answer (Claude Code gave up).
    var onCancel: (@MainActor @Sendable (UUID) -> Void)?

    private let queue = DispatchQueue(label: "dev.yuri.CmdTab.hooks")
    private var listener: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var clients: [UUID: Client] = [:]

    private final class Client {
        let fd: Int32
        var buffer = Data()
        var source: DispatchSourceRead?
        var suggestions: Data?
        var answered = false
        init(fd: Int32) { self.fd = fd }
    }

    func start() {
        queue.async { self.listen() }
    }

    func stop() {
        queue.async {
            self.acceptSource?.cancel()
            self.acceptSource = nil
            for client in self.clients.values { client.source?.cancel() }
            self.clients.removeAll()
            unlink(IslandFiles.hookSocket.path)
        }
    }

    func answer(_ id: UUID, with decision: ApprovalDecision) {
        queue.async {
            guard let client = self.clients[id], !client.answered else { return }
            client.answered = true
            let reply = Self.reply(decision, suggestions: client.suggestions)
            reply.withUnsafeBytes { _ = write(client.fd, $0.baseAddress, $0.count) }
            client.source?.cancel()
            self.clients[id] = nil
        }
    }

    private func listen() {
        IslandFiles.ensureDirectory()
        let path = IslandFiles.hookSocket.path
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { close(fd); return }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
            buffer[bytes.count] = 0
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, Darwin.listen(fd, 8) == 0 else { close(fd); return }
        // Only this user may connect.
        chmod(path, 0o600)
        listener = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptClient() }
        source.setCancelHandler { close(fd) }
        source.resume()
        acceptSource = source
    }

    private func acceptClient() {
        let fd = accept(listener, nil, nil)
        guard fd >= 0 else { return }
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        let id = UUID()
        let client = Client(fd: fd)
        clients[id] = client
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.read(id) }
        source.setCancelHandler { close(fd) }
        client.source = source
        source.resume()
    }

    private func read(_ id: UUID) {
        guard let client = clients[id] else { return }
        var chunk = [UInt8](repeating: 0, count: 16 * 1024)
        let count = Darwin.read(client.fd, &chunk, chunk.count)
        if count <= 0 {
            // The hook went away (Claude Code timed out or the prompt was answered in the terminal).
            client.source?.cancel()
            clients[id] = nil
            let onCancel = onCancel
            Task { @MainActor in onCancel?(id) }
            return
        }
        client.buffer.append(contentsOf: chunk[0..<count])
        // The hook sends one JSON object and keeps the connection open for the reply.
        guard client.suggestions == nil, !client.answered,
              let object = try? JSONSerialization.jsonObject(with: client.buffer) as? [String: Any] else { return }
        guard let request = Self.request(id: id, from: object) else {
            // Not something the island handles: say nothing, Claude Code carries on as usual.
            client.source?.cancel()
            clients[id] = nil
            return
        }
        client.suggestions = request.suggestions ?? Data("[]".utf8)
        let onRequest = onRequest
        Task { @MainActor in onRequest?(request) }
    }

    static func request(id: UUID, from object: [String: Any]) -> Request? {
        guard object["hook_event_name"] as? String == "PermissionRequest",
              let tool = object["tool_name"] as? String else { return nil }
        let input = object["tool_input"] as? [String: Any] ?? [:]
        let summary = ["command", "file_path", "url", "pattern", "path", "description", "prompt"]
            .lazy.compactMap { input[$0] as? String }.first ?? tool
        let project = (object["cwd"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Claude Code"
        let suggestions = (object["permission_suggestions"] as? [Any]).flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        return Request(
            approval: ApprovalRequest(id: id, kind: .claude, project: project, tool: tool, summary: summary, receivedAt: .now),
            suggestions: suggestions
        )
    }

    static func reply(_ decision: ApprovalDecision, suggestions: Data?) -> Data {
        var verdict: [String: Any]
        switch decision {
        case .allow:
            verdict = ["behavior": "allow"]
        case .allowAlways:
            verdict = ["behavior": "allow"]
            if let suggestions, let rules = try? JSONSerialization.jsonObject(with: suggestions) as? [Any], !rules.isEmpty {
                verdict["updatedPermissions"] = rules
            }
        case .deny:
            verdict = ["behavior": "deny", "message": "Denied from the CmdTab island."]
        }
        let reply: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": verdict]]
        return (try? JSONSerialization.data(withJSONObject: reply)) ?? Data()
    }
}

/// Adds and removes CmdTab's entries in `~/.claude/settings.json`: the PermissionRequest hook, and a
/// status line wrapper that saves Claude Code's limits for the island before running your own status
/// line. Everything else in the file is left alone, and a copy is kept the first time it's changed.
enum ClaudeSettings {
    static var settingsFile: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    static var hookScript: URL { IslandFiles.directory.appendingPathComponent("claude-hook.sh") }
    static var statusScript: URL { IslandFiles.directory.appendingPathComponent("claude-statusline.sh") }
    /// The status line command that was there before, run by the wrapper.
    static var originalStatusCommand: URL { IslandFiles.directory.appendingPathComponent("claude-statusline-command") }

    private static let marker = "CmdTab/claude-"

    static var isClaudeInstalled: Bool {
        FileManager.default.fileExists(atPath: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude").path)
    }

    static var hasApprovalHook: Bool {
        guard let settings = load(), let hooks = settings["hooks"] as? [String: Any] else { return false }
        return containsOurs(hooks["PermissionRequest"])
    }

    static var hasStatusLine: Bool {
        guard let settings = load(), let line = settings["statusLine"] as? [String: Any] else { return false }
        return (line["command"] as? String)?.contains(marker) == true
    }

    static func setApprovalHook(_ on: Bool) {
        guard var settings = load() ?? (on ? [:] : nil) else { return }
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        var entries = (hooks["PermissionRequest"] as? [Any] ?? []).filter { !containsOurs([$0]) }
        if on {
            let binary = Bundle.main.executableURL?.path ?? "/Applications/CmdTab.app/Contents/MacOS/CmdTab"
            writeScript(hookScript, """
            #!/bin/sh
            # CmdTab island: lets you answer Claude Code's permission prompts from the notch.
            # Without CmdTab it does nothing and Claude Code asks as usual.
            APP='\(binary)'
            [ -x "$APP" ] && exec "$APP" \(ClaudeHookClient.argument)
            cat >/dev/null
            """)
            entries.append(["matcher": "*", "hooks": [["type": "command", "command": quoted(hookScript.path), "timeout": 600]]])
        }
        hooks["PermissionRequest"] = entries.isEmpty ? nil : entries
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        save(settings)
    }

    static func setStatusLine(_ on: Bool) {
        guard var settings = load() ?? (on ? [:] : nil) else { return }
        let current = settings["statusLine"] as? [String: Any]
        let currentCommand = current?["command"] as? String
        if on {
            guard currentCommand?.contains(marker) != true else { return }
            try? (currentCommand ?? "").write(to: originalStatusCommand, atomically: true, encoding: .utf8)
            writeScript(statusScript, """
            #!/bin/sh
            # CmdTab island: keeps Claude Code's latest limits for the notch, then runs your status line.
            DIR="$HOME/Library/Application Support/CmdTab"
            input=$(cat)
            printf '%s' "$input" > "$DIR/claude-status.json.tmp" && mv -f "$DIR/claude-status.json.tmp" "$DIR/claude-status.json"
            if [ -s "$DIR/claude-statusline-command" ]; then
              printf '%s' "$input" | sh -c "$(cat "$DIR/claude-statusline-command")"
            fi
            """)
            var line = current ?? [:]
            line["type"] = "command"
            line["command"] = quoted(statusScript.path)
            settings["statusLine"] = line
        } else {
            guard currentCommand?.contains(marker) == true else { return }
            let original = (try? String(contentsOf: originalStatusCommand, encoding: .utf8)) ?? ""
            if original.isEmpty {
                settings["statusLine"] = nil
            } else {
                var line = current ?? [:]
                line["command"] = original
                settings["statusLine"] = line
            }
            try? FileManager.default.removeItem(at: originalStatusCommand)
            try? FileManager.default.removeItem(at: IslandFiles.claudeStatus)
        }
        save(settings)
    }

    private static func containsOurs(_ entries: Any?) -> Bool {
        guard let entries = entries as? [Any] else { return false }
        return entries.contains { entry in
            let hooks = (entry as? [String: Any])?["hooks"] as? [[String: Any]] ?? []
            return hooks.contains { ($0["command"] as? String)?.contains(marker) == true }
        }
    }

    private static func quoted(_ path: String) -> String { "\"\(path)\"" }

    private static func writeScript(_ url: URL, _ text: String) {
        IslandFiles.ensureDirectory()
        try? (text + "\n").write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private static func load() -> [String: Any]? {
        guard let data = try? Data(contentsOf: settingsFile) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func save(_ settings: [String: Any]) {
        let fm = FileManager.default
        let backup = settingsFile.appendingPathExtension("cmdtab-backup")
        if fm.fileExists(atPath: settingsFile.path), !fm.fileExists(atPath: backup.path) {
            try? fm.copyItem(at: settingsFile, to: backup)
        }
        try? fm.createDirectory(at: settingsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .withoutEscapingSlashes]) else { return }
        try? data.write(to: settingsFile, options: .atomic)
    }
}
