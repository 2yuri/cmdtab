import AppKit
import EventKit
import Observation

/// An event with a call link, starting soon.
struct UpcomingMeeting: Equatable {
    let title: String
    let start: Date
    let link: URL?
    let service: String?
}

/// Your next meeting, five minutes before it starts. Reads the Calendar app's events (with
/// permission) only when they change, and wakes once for the next one; no polling.
@MainActor
@Observable
final class MeetingWatcher {
    private(set) var upcoming: UpcomingMeeting?

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var dismissedStart: Date?

    static let leadTime: TimeInterval = 5 * 60
    /// The island keeps showing it this long after it starts, in case you're late.
    static let graceAfterStart: TimeInterval = 5 * 60

    func start() {
        guard observer == nil else { return }
        store.requestFullAccessToEvents { [weak self] granted, _ in
            Task { @MainActor in
                guard granted, let self else { return }
                self.observer = NotificationCenter.default.addObserver(
                    forName: .EKEventStoreChanged, object: self.store, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.schedule() }
                }
                self.schedule()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        upcoming = nil
    }

    func join() {
        if let link = upcoming?.link { NSWorkspace.shared.open(link) }
        dismiss()
    }

    func dismiss() {
        dismissedStart = upcoming?.start
        upcoming = nil
    }

    private func schedule() {
        timer?.invalidate()
        let now = Date.now
        let calendars = store.calendars(for: .event)
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-Self.graceAfterStart), end: now.addingTimeInterval(24 * 3600), calendars: calendars)
        let events = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.status != .canceled && $0.startDate.addingTimeInterval(Self.graceAfterStart) > now }
            .sorted { $0.startDate < $1.startDate }
        guard let next = events.first else { upcoming = nil; return }
        let showAt = next.startDate.addingTimeInterval(-Self.leadTime)
        let hideAt = next.startDate.addingTimeInterval(Self.graceAfterStart)
        if now >= showAt {
            if dismissedStart != next.startDate {
                let link = Self.callLink(in: next)
                upcoming = UpcomingMeeting(title: next.title ?? "Event", start: next.startDate, link: link, service: link.flatMap(Self.service))
            }
            timer = Timer.scheduledTimer(withTimeInterval: hideAt.timeIntervalSince(now), repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.upcoming = nil
                    self?.schedule()
                }
            }
        } else {
            upcoming = nil
            timer = Timer.scheduledTimer(withTimeInterval: showAt.timeIntervalSince(now), repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.schedule() }
            }
        }
    }

    static let callHosts = ["meet.google.com", "zoom.us", "teams.microsoft.com", "teams.live.com", "whereby.com", "webex.com", "facetime.apple.com"]

    /// The first call link in the event's URL, location or notes.
    static func callLink(in event: EKEvent) -> URL? {
        callLink(in: [event.url?.absoluteString, event.location, event.notes].compactMap { $0 }.joined(separator: " "))
    }

    static func callLink(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let matches = detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.compactMap(\.url).first { url in
            callHosts.contains { url.host?.hasSuffix($0) == true }
        }
    }

    static func service(of url: URL) -> String? {
        guard let host = url.host else { return nil }
        if host.contains("meet.google") { return "Google Meet" }
        if host.contains("zoom") { return "Zoom" }
        if host.contains("teams") { return "Teams" }
        if host.contains("whereby") { return "Whereby" }
        if host.contains("webex") { return "Webex" }
        if host.contains("facetime") { return "FaceTime" }
        return nil
    }
}
