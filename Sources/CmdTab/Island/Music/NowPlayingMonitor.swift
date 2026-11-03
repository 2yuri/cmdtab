import AppKit
import Observation

/// The track macOS lists as playing, from any app.
struct NowPlaying: Equatable {
    var title: String
    var artist: String?
    var album: String?
    var duration: TimeInterval?
    /// Elapsed time at `timestamp`, while playing at `rate`.
    var elapsed: TimeInterval?
    var rate: Double
    var timestamp: Date?
    var isPlaying: Bool
    var pid: pid_t?

    /// Where playback is now, moving on from the last report while it plays.
    func position(at now: Date) -> TimeInterval? {
        guard let elapsed else { return nil }
        guard isPlaying, let timestamp else { return elapsed }
        let position = elapsed + now.timeIntervalSince(timestamp) * (rate == 0 ? 1 : rate)
        return duration.map { min(position, $0) } ?? position
    }

    /// macOS reported playback but no track details (some web players do): show the app instead.
    var hasDetails: Bool { !title.isEmpty }

    /// One line of the bridge's output; `nil` when nothing is playing.
    static func parse(_ object: [String: Any]) -> NowPlaying? {
        let title = (object["title"] as? String) ?? ""
        let playing = object["playing"] as? Bool ?? false
        guard !title.isEmpty || playing else { return nil }
        return NowPlaying(
            title: title,
            artist: (object["artist"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            album: object["album"] as? String,
            duration: object["duration"] as? Double,
            elapsed: object["elapsed"] as? Double,
            rate: object["rate"] as? Double ?? 0,
            timestamp: (object["timestamp"] as? Double).map { Date(timeIntervalSince1970: $0) },
            isPlaying: object["playing"] as? Bool ?? false,
            pid: (object["pid"] as? Int).flatMap { $0 > 0 ? pid_t($0) : nil }
        )
    }
}

/// Runs the Now Playing bridge (see NowPlayingBridge.m) while the Music module is on. The bridge
/// sleeps until macOS reports a change, so this costs nothing while the music doesn't change.
@MainActor
@Observable
final class NowPlayingMonitor {
    private(set) var track: NowPlaying?
    private(set) var artwork: NSImage?
    /// The app playing it, for its name and icon.
    private(set) var app: NSRunningApplication?

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var input: FileHandle?
    @ObservationIgnored private var buffer = Data()

    enum Command: String {
        case toggle, next, previous, shuffle
    }

    static var bridgePath: String? {
        Bundle.main.privateFrameworksURL?.appendingPathComponent("libCmdTabNowPlaying.dylib").path
    }

    func start() {
        guard process == nil, let path = Self.bridgePath, FileManager.default.fileExists(atPath: path) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [
            "-e",
            "use DynaLoader; my $l = DynaLoader::dl_load_file($ARGV[0], 0) or exit 1; "
                + "my $s = DynaLoader::dl_find_symbol($l, 'cmdtab_now_playing_stream') or exit 1; "
                + "DynaLoader::dl_install_xsub('main::stream', $s); stream();",
            path,
        ]
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor in self?.receive(data) }
        }
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.processEnded() }
        }
        do {
            try process.run()
            self.process = process
            input = stdin.fileHandleForWriting
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
        }
    }

    func stop() {
        guard let process else { return }
        self.process = nil
        try? input?.close()
        input = nil
        process.terminate()
        track = nil
        artwork = nil
        app = nil
    }

    func send(_ command: Command) {
        write(command.rawValue)
    }

    func seek(to seconds: TimeInterval) {
        write("seek \(seconds)")
    }

    /// Brings the playing app forward.
    func openApp() {
        app?.activate()
    }

    private func write(_ line: String) {
        try? input?.write(contentsOf: Data((line + "\n").utf8))
    }

    private func receive(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            apply(object)
        }
    }

    private func apply(_ object: [String: Any]) {
        let new = NowPlaying.parse(object)
        if new != track { track = new }
        if let encoded = object["artwork"] as? String {
            artwork = encoded.isEmpty ? nil : Data(base64Encoded: encoded).flatMap(NSImage.init(data:))
        }
        if new == nil { artwork = nil }
        let pid = new?.pid
        if app?.processIdentifier != pid {
            app = pid.flatMap { NSRunningApplication(processIdentifier: $0) }
        }
    }

    private func processEnded() {
        guard process != nil else { return }
        // It ended on its own (a macOS update, a crash): try again later, never in a tight loop.
        process = nil
        input = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in self?.start() }
    }
}
