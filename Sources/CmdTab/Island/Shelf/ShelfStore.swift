import AppKit
import Observation

/// A file held on the Shelf. The Shelf keeps a link to the file where it is, never a copy.
struct ShelfItem: Codable, Identifiable, Equatable {
    var id = UUID()
    let path: String
    let addedAt: Date

    var url: URL { URL(fileURLWithPath: path) }
    var name: String { url.lastPathComponent }
}

/// Files held for 24 hours: dropped on the island, or new downloads and screenshots.
@MainActor
@Observable
final class ShelfStore {
    private(set) var items: [ShelfItem] = []
    /// The file that just arrived on its own (a download, a screenshot), while the island shows it.
    private(set) var arrival: ShelfItem?

    static let keepFor: TimeInterval = 24 * 60 * 60
    static let arrivalDuration: TimeInterval = 3

    @ObservationIgnored private var expiryTimer: Timer?
    @ObservationIgnored private var arrivalTimer: Timer?
    @ObservationIgnored private var watcher: FileWatcher?
    @ObservationIgnored private var seen: Set<String> = []

    private static var file: URL { IslandFiles.directory.appendingPathComponent("shelf.json") }

    init() {
        let saved = (try? Data(contentsOf: Self.file)).flatMap { try? JSONDecoder().decode([ShelfItem].self, from: $0) } ?? []
        items = Self.current(saved, now: .now)
        scheduleExpiry()
    }

    /// Items still within 24 hours whose files still exist, newest first.
    static func current(_ items: [ShelfItem], now: Date) -> [ShelfItem] {
        items
            .filter { now.timeIntervalSince($0.addedAt) < keepFor && FileManager.default.fileExists(atPath: $0.path) }
            .sorted { $0.addedAt > $1.addedAt }
    }

    /// Adds files to the top. A file already on the Shelf moves back to the top with a fresh 24 hours.
    func add(_ urls: [URL]) {
        let now = Date.now
        let paths = urls.filter(\.isFileURL).map(\.path)
        guard !paths.isEmpty else { return }
        items = Self.adding(paths, to: items, at: now)
        save()
    }

    static func adding(_ paths: [String], to items: [ShelfItem], at now: Date) -> [ShelfItem] {
        let unique = paths.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let kept = items.filter { !unique.contains($0.path) }
        return unique.map { ShelfItem(path: $0, addedAt: now) } + kept
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    func copyAll() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(items.map { $0.url as NSURL })
    }

    /// The file itself (paste in Finder), and for images the picture too (paste in a chat or a doc).
    static func copyToClipboard(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
        if let image = NSImage(contentsOf: url), let tiff = image.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
    }

    func airDrop() {
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: items.map(\.url))
    }

    // MARK: Downloads and screenshots

    /// Watches the Downloads folder and where screenshots are saved; new files land on the Shelf.
    func setWatchesNewFiles(_ on: Bool) {
        watcher?.stop()
        watcher = nil
        guard on else { return }
        let folders = Self.watchedFolders
        seen = Set(folders.flatMap { Self.files(in: $0) }.map(\.path))
        watcher = FileWatcher(paths: folders.map(\.path), latency: 1) { [weak self] in self?.scanForNewFiles() }
    }

    static var watchedFolders: [URL] {
        let fm = FileManager.default
        var folders = fm.urls(for: .downloadsDirectory, in: .userDomainMask)
        let screenshots = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location")
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            ?? fm.urls(for: .desktopDirectory, in: .userDomainMask).first
        if let screenshots { folders.append(screenshots) }
        return Array(Set(folders))
    }

    private static func files(in folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles]
        )) ?? []
    }

    /// Partial downloads end in these until they finish.
    static func isFinished(_ url: URL) -> Bool {
        !["download", "crdownload", "part", "partial", "tmp"].contains(url.pathExtension.lowercased())
    }

    private func scanForNewFiles() {
        let now = Date.now
        var arrived: [URL] = []
        for folder in Self.watchedFolders {
            for url in Self.files(in: folder) where !seen.contains(url.path) && Self.isFinished(url) {
                seen.insert(url.path)
                let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                if now.timeIntervalSince(created) < 120 { arrived.append(url) }
            }
        }
        guard !arrived.isEmpty else { return }
        add(arrived)
        arrival = items.first { $0.path == arrived.last?.path }
        arrivalTimer?.invalidate()
        arrivalTimer = Timer.scheduledTimer(withTimeInterval: Self.arrivalDuration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.arrival = nil }
        }
    }

    // MARK: Saving and expiry

    private func save() {
        IslandFiles.ensureDirectory()
        try? JSONEncoder().encode(items).write(to: Self.file, options: .atomic)
        scheduleExpiry()
    }

    /// One timer, for the next item to turn 24 hours old.
    private func scheduleExpiry() {
        expiryTimer?.invalidate()
        guard let oldest = items.map(\.addedAt).min() else { return }
        let due = oldest.addingTimeInterval(Self.keepFor)
        expiryTimer = Timer.scheduledTimer(withTimeInterval: max(1, due.timeIntervalSinceNow), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.items = Self.current(self.items, now: .now)
                self.save()
            }
        }
    }
}
