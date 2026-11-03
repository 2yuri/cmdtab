import CoreServices
import Foundation

/// Calls `onChange` on the main actor when anything under `paths` changes, at most once per
/// `latency`. FSEvents does the watching, so nothing runs while the files are quiet.
@MainActor
final class FileWatcher {
    // Only touched on the main actor, and by deinit once nothing else holds the watcher.
    nonisolated(unsafe) private var stream: FSEventStreamRef?
    private let onChange: @MainActor () -> Void

    init?(paths: [String], latency: TimeInterval = 0.3, onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        let existing = paths.filter { FileManager.default.fileExists(atPath: $0) }
        guard !existing.isEmpty else { return nil }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            MainActor.assumeIsolated { watcher.onChange() }
        }
        guard let stream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            existing as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        ) else { return nil }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        Self.tearDown(stream)
        self.stream = nil
    }

    deinit {
        if let stream { Self.tearDown(stream) }
    }

    private nonisolated static func tearDown(_ stream: FSEventStreamRef) {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
