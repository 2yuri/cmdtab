import AppKit
import EventKit
import Observation
import SwiftUI

/// One event on the Calendar tab.
struct CalendarEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let color: NSColor
    /// "Google Meet", "Room 3", "Teams · 6 people".
    let detail: String?
    let link: URL?
    var isAllDay = false
}

/// Events from the Calendar app (with permission), read for the days on screen and again when the
/// calendar changes; nothing runs otherwise. New events go to the calendar you pick.
@MainActor
@Observable
final class CalendarStore {
    /// Bumped when the Calendar app's data changes, so open views read again.
    private(set) var revision = 0
    private(set) var access: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var dayCache: [Date: [CalendarEvent]] = [:]
    @ObservationIgnored private var countCache: [DateInterval: [Date: Int]] = [:]

    var isAllowed: Bool { access == .fullAccess }

    /// Weeks start on Monday, like the design.
    static var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }

    func load() {
        guard isAllowed else {
            if access == .notDetermined {
                store.requestFullAccessToEvents { [weak self] _, _ in
                    Task { @MainActor in
                        self?.access = EKEventStore.authorizationStatus(for: .event)
                        self?.load()
                    }
                }
            }
            return
        }
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.changed() }
            }
        }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        changed()
    }

    private func changed() {
        dayCache.removeAll()
        countCache.removeAll()
        revision += 1
    }

    private func read(from start: Date, to end: Date) -> [EKEvent] {
        guard isAllowed, start < end else { return [] }
        return store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
            .filter { $0.status != .canceled }
            .sorted { lhs, rhs in
                // All-day events first, then by time.
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                return lhs.startDate < rhs.startDate
            }
    }

    /// The events of one day, earliest first.
    func events(on day: Date) -> [CalendarEvent] {
        let calendar = Self.calendar
        let start = calendar.startOfDay(for: day)
        if let cached = dayCache[start] { return cached }
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let events = read(from: start, to: end).map(Self.item)
        dayCache[start] = events
        return events
    }

    /// How many events each day has between `start` and `end`, keyed by the day's start.
    func counts(from start: Date, to end: Date) -> [Date: Int] {
        let interval = DateInterval(start: start, end: max(start, end))
        if let cached = countCache[interval] { return cached }
        let calendar = Self.calendar
        var counts: [Date: Int] = [:]
        for event in read(from: start, to: end) {
            // Every day it covers, so a trip over three days shows on all three.
            var day = calendar.startOfDay(for: max(event.startDate, start))
            let last = min(event.endDate, end)
            repeat {
                counts[day, default: 0] += 1
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            } while day < last
        }
        countCache[interval] = counts
        return counts
    }

    /// Calendars a new event can go to, the default one first.
    var writableCalendars: [EKCalendar] {
        guard isAllowed else { return [] }
        let all = store.calendars(for: .event).filter(\.allowsContentModifications)
        let preferred = store.defaultCalendarForNewEvents
        return all.sorted { lhs, rhs in
            if lhs == preferred { return true }
            if rhs == preferred { return false }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    /// Saves a new event to the Calendar app.
    func add(title: String, start: Date, end: Date, to calendar: EKCalendar) throws {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.calendar = calendar
        try store.save(event, span: .thisEvent, commit: true)
        changed()
    }

    private static func item(_ event: EKEvent) -> CalendarEvent {
        let link = MeetingWatcher.callLink(in: event)
        let detail = link.flatMap(MeetingWatcher.service) ?? event.location.flatMap { $0.isEmpty ? nil : $0 }
        return CalendarEvent(
            id: (event.eventIdentifier ?? UUID().uuidString) + "\(event.startDate.timeIntervalSince1970)",
            title: event.title ?? "Event",
            start: event.startDate,
            end: event.endDate,
            color: event.calendar.map { NSColor(cgColor: $0.cgColor) ?? .systemBlue } ?? .systemBlue,
            detail: detail,
            link: link,
            isAllDay: event.isAllDay
        )
    }
}

/// The open Calendar tab: a week, a month or a year, the picked day's events, and a quick way to
/// add one.
struct CalendarTab: View {
    let calendar: CalendarStore

    enum Mode: String, CaseIterable { case week = "Week", month = "Month", year = "Year" }

    @State private var mode: Mode = Self.initialMode
    @State private var selected = Date.now
    @State private var isAdding = Self.startsAdding

    #if DEBUG
    /// Screenshots: `CMDTAB_CALENDAR=month|year|add`.
    private static var previewOption: String { ProcessInfo.processInfo.environment["CMDTAB_CALENDAR"] ?? "" }
    private static var initialMode: Mode { Mode(rawValue: previewOption.capitalized) ?? .week }
    private static var startsAdding: Bool { previewOption == "add" }
    #else
    private static let initialMode = Mode.week
    private static let startsAdding = false
    #endif

    private var cal: Calendar { CalendarStore.calendar }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if calendar.isAllowed {
                header
                if isAdding {
                    NewEventForm(calendar: calendar, day: $selected) { isAdding = false }
                } else {
                    switch mode {
                    case .week: WeekStrip(calendar: calendar, selected: $selected, onAdd: startAdding)
                    case .month: MonthGrid(calendar: calendar, selected: $selected, onAdd: startAdding)
                    case .year: YearGrid(calendar: calendar, year: selected) { month in
                        selected = cal.isDate(month, equalTo: .now, toGranularity: .month) ? .now : month
                        mode = .month
                    }
                    }
                }
                if mode != .year || isAdding {
                    DayEvents(calendar: calendar, day: selected, limit: mode == .month && !isAdding ? 3 : nil)
                }
            } else {
                TabHeader(title: "Calendar") { EmptyView() }
                if calendar.access == .notDetermined {
                    Text("Allow Calendar access to see your day here. Events stay on your Mac.")
                        .font(.system(size: 12))
                        .foregroundStyle(IslandStyle.secondary)
                        .padding(.vertical, 6)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CmdTab needs Calendar access to show your day. Events stay on your Mac.")
                            .font(.system(size: 12))
                            .foregroundStyle(IslandStyle.secondary)
                        IslandButton(title: "Open Settings", prominent: true) {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .onAppear { calendar.load() }
    }

    private func startAdding(_ day: Date) {
        selected = day
        isAdding = true
    }

    private var title: String {
        mode == .year
            ? selected.formatted(.dateTime.year())
            : selected.formatted(.dateTime.month(.wide).year())
    }

    private var header: some View {
        HStack(spacing: 6) {
            CalendarIconButton(symbol: "chevron.left") { step(-1) }
            Button { selected = .now } label: {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(IslandStyle.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .buttonStyle(.plain)
            .layoutPriority(-1)
            .help("Back to today")
            CalendarIconButton(symbol: "chevron.right") { step(1) }
            Spacer(minLength: 4)
            HStack(spacing: 2) {
                ForEach(Mode.allCases, id: \.self) { item in
                    Button { mode = item; isAdding = false } label: {
                        Text(item.rawValue)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                            .fixedSize()
                            .foregroundStyle(item == mode ? IslandStyle.primary : IslandStyle.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(item == mode ? Color.white.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            CalendarIconButton(symbol: "plus", prominent: true) {
                if isAdding { isAdding = false } else { startAdding(selected) }
            }
        }
    }

    private func step(_ direction: Int) {
        let component: Calendar.Component = switch mode {
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
        if let next = cal.date(byAdding: component, value: direction, to: selected) { selected = next }
    }
}

private struct CalendarIconButton: View {
    let symbol: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(prominent ? Color.black : IslandStyle.primary)
                .frame(width: 26, height: 26)
                .background(prominent ? IslandStyle.volt : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One day: a click picks it, a double click adds an event on it.
private struct DayCell<Label: View>: View {
    let day: Date
    @Binding var selected: Date
    let onAdd: (Date) -> Void
    @ViewBuilder var label: Label

    var body: some View {
        let isSelected = CalendarStore.calendar.isDate(day, inSameDayAs: selected)
        label
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color.white.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { onAdd(day) }
            .onTapGesture { selected = day }
    }
}

private struct Dots: View {
    let count: Int
    let size: CGFloat
    let isToday: Bool

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<min(count, 3), id: \.self) { _ in
                Circle().fill(isToday ? IslandStyle.volt : Color.white.opacity(0.3)).frame(width: size, height: size)
            }
        }
        .frame(height: size)
    }
}

private struct WeekStrip: View {
    let calendar: CalendarStore
    @Binding var selected: Date
    let onAdd: (Date) -> Void

    var body: some View {
        let _ = calendar.revision // Read again when the calendar changes.
        let cal = CalendarStore.calendar
        let start = cal.dateInterval(of: .weekOfYear, for: selected)?.start ?? cal.startOfDay(for: selected)
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
        let counts = calendar.counts(from: start, to: cal.date(byAdding: .day, value: 7, to: start) ?? start)
        HStack(spacing: 4) {
            ForEach(days, id: \.self) { day in
                let today = cal.isDateInToday(day)
                DayCell(day: day, selected: $selected, onAdd: onAdd) {
                    VStack(spacing: 3) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(today ? IslandStyle.volt : IslandStyle.tertiary)
                        Text(day.formatted(.dateTime.day()))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(today ? IslandStyle.volt : IslandStyle.primary)
                        Dots(count: counts[day] ?? 0, size: 4, isToday: today)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }
}

private struct MonthGrid: View {
    let calendar: CalendarStore
    @Binding var selected: Date
    let onAdd: (Date) -> Void

    var body: some View {
        let _ = calendar.revision // Read again when the calendar changes.
        let cal = CalendarStore.calendar
        let month = cal.dateInterval(of: .month, for: selected) ?? DateInterval(start: selected, duration: 0)
        let gridStart = cal.dateInterval(of: .weekOfYear, for: month.start)?.start ?? month.start
        let weeks = Int(ceil(Double((cal.dateComponents([.day], from: gridStart, to: month.end).day ?? 35)) / 7))
        let days = (0..<(weeks * 7)).compactMap { cal.date(byAdding: .day, value: $0, to: gridStart) }
        let counts = calendar.counts(from: gridStart, to: days.last.flatMap { cal.date(byAdding: .day, value: 1, to: $0) } ?? month.end)
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                ForEach(Array(cal.veryShortWeekdaySymbols.rotated(by: cal.firstWeekday - 1).enumerated()), id: \.offset) { _, letter in
                    Text(letter)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(IslandStyle.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 2)
                }
            }
            ForEach(0..<weeks, id: \.self) { week in
                HStack(spacing: 2) {
                    ForEach(days[(week * 7)..<(week * 7 + 7)], id: \.self) { day in
                        let inMonth = month.contains(day) && day < month.end
                        let today = cal.isDateInToday(day)
                        let isSelected = cal.isDate(day, inSameDayAs: selected)
                        DayCell(day: day, selected: $selected, onAdd: onAdd) {
                            VStack(spacing: 2) {
                                Text(day.formatted(.dateTime.day()))
                                    .font(.system(size: 12, weight: today || isSelected ? .bold : .medium))
                                    .foregroundStyle(today ? IslandStyle.volt : inMonth ? IslandStyle.primary : Color.white.opacity(0.2))
                                Dots(count: inMonth ? counts[day] ?? 0 : 0, size: 3, isToday: today)
                            }
                            .frame(height: 34)
                        }
                    }
                }
            }
        }
    }
}

private struct YearGrid: View {
    let calendar: CalendarStore
    let year: Date
    let onPick: (Date) -> Void

    var body: some View {
        let _ = calendar.revision // Read again when the calendar changes.
        let cal = CalendarStore.calendar
        let interval = cal.dateInterval(of: .year, for: year) ?? DateInterval(start: year, duration: 0)
        let counts = calendar.counts(from: interval.start, to: interval.end)
        let months = (0..<12).compactMap { cal.date(byAdding: .month, value: $0, to: interval.start) }
        let perMonth = months.map { month in
            counts.filter { cal.isDate($0.key, equalTo: month, toGranularity: .month) }.values.reduce(0, +)
        }
        let busiest = max(perMonth.max() ?? 1, 1)
        VStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { column in
                        let index = row * 3 + column
                        let isCurrent = cal.isDate(months[index], equalTo: .now, toGranularity: .month)
                        let tint = isCurrent ? IslandStyle.volt : IslandStyle.primary
                        Button { onPick(months[index]) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(months[index].formatted(.dateTime.month(.abbreviated)))
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(tint)
                                GeometryReader { proxy in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.white.opacity(0.08))
                                        Capsule().fill(isCurrent ? IslandStyle.volt : Color.white.opacity(0.3))
                                            .frame(width: proxy.size.width * CGFloat(perMonth[index]) / CGFloat(busiest))
                                    }
                                }
                                .frame(height: 3)
                                Text("\(perMonth[index]) \(perMonth[index] == 1 ? "event" : "events")")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(isCurrent ? IslandStyle.volt : IslandStyle.tertiary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(isCurrent ? IslandStyle.volt.opacity(0.1) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(isCurrent ? IslandStyle.volt : .clear, lineWidth: 1))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// The picked day: "Wed 4 Nov · 2 events", then its events (today with the now line and Join).
private struct DayEvents: View {
    let calendar: CalendarStore
    let day: Date
    /// The month view keeps its list short.
    var limit: Int?

    var body: some View {
        let _ = calendar.revision // Read again when the calendar changes.
        let events = calendar.events(on: day)
        let shown = limit.map { Array(events.prefix($0)) } ?? events
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(CalendarStore.calendar.isDateInToday(day) ? "Today" : day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(IslandStyle.secondary)
                Spacer()
                Text(events.isEmpty ? "No events" : "\(events.count) \(events.count == 1 ? "event" : "events")")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(IslandStyle.tertiary)
            }
            .padding(.horizontal, 8)
            if !events.isEmpty {
                TimelineView(.everyMinute) { context in
                    EventList(events: shown, now: context.date, showsNow: CalendarStore.calendar.isDateInToday(day))
                }
                if shown.count < events.count {
                    Text("+\(events.count - shown.count) more")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(IslandStyle.tertiary)
                        .padding(.horizontal, 8)
                }
            }
        }
    }
}

/// Title, day, from, to and calendar; Add saves it to the Calendar app. Return adds, esc cancels.
private struct NewEventForm: View {
    let calendar: CalendarStore
    @Binding var day: Date
    let onDone: () -> Void

    @State private var title = ""
    @State private var start = Date.now
    @State private var end = Date.now
    @State private var calendarIndex = 0
    @State private var failed = false
    @FocusState private var typing: Bool

    private var cal: Calendar { CalendarStore.calendar }

    var body: some View {
        let calendars = calendar.writableCalendars
        let target = calendars.isEmpty ? nil : calendars[calendarIndex % calendars.count]
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 2) {
                TextField("New event", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(IslandStyle.primary)
                    .focused($typing)
                    .onSubmit { add(to: target) }
                    .onExitCommand(perform: onDone)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(IslandStyle.volt, lineWidth: 1))
            VStack(alignment: .leading, spacing: 6) {
                timeRow("Starts", start) { start = $0.start; end = $0.end } shift: { NewEventDefaults.moveStart(start, end: end, to: $0) }
                timeRow("Ends", end) { _ = $0; end = $0.end } shift: { (start, NewEventDefaults.moveEnd(to: $0, start: start)) }
                HStack(spacing: 6) {
                    Text("Lasts")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(IslandStyle.tertiary)
                        .frame(width: NewEventForm.labelWidth, alignment: .leading)
                    ForEach(NewEventDefaults.lengths, id: \.self) { minutes in
                        let isOn = Int(end.timeIntervalSince(start) / 60) == minutes
                        Button { end = start.addingTimeInterval(TimeInterval(minutes * 60)) } label: {
                            Text(NewEventDefaults.duration(minutes))
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                                .fixedSize()
                                .foregroundStyle(isOn ? IslandStyle.primary : IslandStyle.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(isOn ? 0.14 : 0.06), in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack {
                if let target {
                    Button { calendarIndex += 1 } label: {
                        HStack(spacing: 6) {
                            Circle().fill(Color(cgColor: target.cgColor)).frame(width: 8, height: 8)
                            Text(target.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(IslandStyle.primary).lineLimit(1)
                            if calendars.count > 1 {
                                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 9, weight: .bold)).foregroundStyle(IslandStyle.secondary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Switch calendar")
                }
                if failed {
                    Text("Couldn't save").font(.system(size: 11, weight: .medium)).foregroundStyle(IslandStyle.warning)
                }
                Spacer()
                IslandButton(title: "Cancel", prominent: false, action: onDone)
                IslandButton(title: "Add", prominent: true) { add(to: target) }
                    .opacity(title.trimmingCharacters(in: .whitespaces).isEmpty || target == nil ? 0.4 : 1)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .onChange(of: start) { _, new in day = new }
        .onAppear {
            let minute = NewEventDefaults.start(on: day, now: .now, calendar: cal)
            start = cal.date(byAdding: .minute, value: minute, to: cal.startOfDay(for: day)) ?? day
            end = start.addingTimeInterval(3600)
            typing = true
        }
    }

    static let labelWidth: CGFloat = 40

    /// "Starts  [‹ Wed 4 Nov ›]  [‹ 10:00 ›]": the day steps by a day, the hour by half an hour.
    private func timeRow(
        _ label: String, _ date: Date,
        apply: @escaping ((start: Date, end: Date)) -> Void,
        shift: @escaping (Date) -> (start: Date, end: Date)
    ) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(IslandStyle.tertiary)
                .frame(width: Self.labelWidth, alignment: .leading)
            StepChip(symbol: "calendar", label: date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)), width: 74) { step in
                if let next = cal.date(byAdding: .day, value: step, to: date) { apply(shift(next)) }
            }
            StepChip(symbol: "clock", label: date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)), width: 40) { step in
                apply(shift(date.addingTimeInterval(TimeInterval(step * NewEventDefaults.step * 60))))
            }
        }
    }

    private func add(to target: EKCalendar?) {
        let name = title.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let target, end > start else { return }
        do {
            try calendar.add(title: name, start: start, end: end, to: target)
            onDone()
        } catch {
            failed = true
        }
    }

}

enum NewEventDefaults {
    static let step = 30
    static let lastStart = 24 * 60 - step

    static let lengths = [30, 60, 120, 180]

    /// Starts moved: Ends moves with it, keeping the length.
    static func moveStart(_ start: Date, end: Date, to newStart: Date) -> (start: Date, end: Date) {
        (newStart, end.addingTimeInterval(newStart.timeIntervalSince(start)))
    }

    /// Ends moved: never before Starts plus half an hour.
    static func moveEnd(to newEnd: Date, start: Date) -> Date {
        max(newEnd, start.addingTimeInterval(TimeInterval(step * 60)))
    }

    /// "30m", "1h", "1h 30m".
    static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(rest)m" }
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    /// Today: the next half hour. Another day: 9:00.
    static func start(on day: Date, now: Date, calendar: Calendar) -> Int {
        guard calendar.isDate(day, inSameDayAs: now) else { return 9 * 60 }
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let minutes = (parts.hour ?? 9) * 60 + (parts.minute ?? 0)
        return min((minutes / step + 1) * step, lastStart)
    }
}

/// A chip with ‹ › to step its value: the day by one, the time by half an hour.
private struct StepChip: View {
    let symbol: String
    let label: String
    /// Fixed, so the row keeps its size as the value changes.
    let width: CGFloat
    let step: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: symbol).font(.system(size: 10, weight: .medium))
            .foregroundStyle(IslandStyle.secondary)
            .padding(.trailing, 2)
            arrow("chevron.left", -1)
            Text(label).font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(IslandStyle.primary)
                .lineLimit(1)
                .frame(width: width)
            arrow("chevron.right", 1)
        }
        .padding(.leading, 8)
        .padding(.vertical, 1)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onScrollStep(step)
    }

    private func arrow(_ name: String, _ value: Int) -> some View {
        Button { step(value) } label: {
            Image(systemName: name).font(.system(size: 9, weight: .bold)).foregroundStyle(IslandStyle.secondary).frame(width: 20, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private extension Array {
    func rotated(by count: Int) -> [Element] {
        guard !isEmpty else { return self }
        let shift = ((count % self.count) + self.count) % self.count
        return Array(self[shift...] + self[..<shift])
    }
}

private struct EventList: View {
    let events: [CalendarEvent]
    let now: Date
    var showsNow = true

    var body: some View {
        let next = events.first { !$0.isAllDay && $0.end > now && $0.link != nil }
        let nowIndex = events.firstIndex { !$0.isAllDay && $0.end > now } ?? events.count
        VStack(spacing: 2) {
            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                if showsNow, index == nowIndex { NowLine(now: now) }
                EventRow(event: event, isPast: !event.isAllDay && event.end <= now, isNext: event == next)
            }
            if showsNow, nowIndex == events.count, !events.isEmpty { NowLine(now: now) }
        }
    }
}

private struct NowLine: View {
    let now: Date

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(IslandStyle.tomato).frame(width: 6, height: 6)
            Rectangle().fill(IslandStyle.tomato).frame(height: 1)
            Text(now.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(IslandStyle.tomato)
        }
        .padding(.vertical, 4)
    }
}

private struct EventRow: View {
    let event: CalendarEvent
    let isPast: Bool
    let isNext: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                if event.isAllDay {
                    Text("All day")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(IslandStyle.secondary)
                } else {
                    Text(event.start.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(IslandStyle.primary)
                    Text(event.end.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(IslandStyle.tertiary)
                }
            }
            .frame(width: 50, alignment: .leading)
            RoundedRectangle(cornerRadius: 2).fill(Color(nsColor: event.color)).frame(width: 3, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(IslandStyle.primary).lineLimit(1)
                if let detail = event.detail {
                    Text(detail).font(.system(size: 11)).foregroundStyle(IslandStyle.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            if isNext, let link = event.link {
                IslandButton(title: "Join", prominent: true) { NSWorkspace.shared.open(link) }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isNext ? Color.white.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .opacity(isPast ? 0.45 : 1)
    }
}
