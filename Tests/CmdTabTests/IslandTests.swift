import XCTest
@testable import CmdTab

final class IslandPresentationTests: XCTestCase {
    private func session(_ id: String, _ state: AgentState, kind: AgentKind = .claude) -> AgentSession {
        AgentSession(id: id, kind: kind, project: id, detail: nil, state: state, since: Self.start, pid: nil)
    }

    private static let start = Date(timeIntervalSince1970: 1_000_000)

    private let request = ApprovalRequest(id: UUID(), kind: .claude, project: "p", tool: "Bash", summary: "npm test", receivedAt: .now)

    func testNothingLiveIsIdle() {
        XCTAssertEqual(IslandContent.resolve(.init()), .idle)
    }

    private func row(_ inputs: IslandContent.Inputs) -> AgentsRow? {
        if case let .agents(row) = IslandContent.resolve(inputs) { return row }
        return nil
    }

    func testWorkingShowsTheSessionLimit() throws {
        var inputs = IslandContent.Inputs()
        inputs.sessions = [session("a", .working)]
        inputs.usage = [.claude: AgentUsage(kind: .claude, windows: [UsageWindow(label: "Session", usedPercent: 62, resetsAt: nil)])]
        let shown = try XCTUnwrap(row(inputs))
        XCTAssertEqual(shown.percent, 62)
        XCTAssertTrue(shown.percentOnLeft)
        XCTAssertEqual(shown.marks, [.init(kind: .claude, needsYou: false)])
        inputs.showsLimit = false
        XCTAssertNil(try XCTUnwrap(row(inputs)).percent)
    }

    func testNeedsYouComesFirst() throws {
        var inputs = IslandContent.Inputs()
        inputs.sessions = [session("a", .working), session("b", .needsYou, kind: .codex)]
        inputs.now = Self.start.addingTimeInterval(60)
        let shown = try XCTUnwrap(row(inputs))
        XCTAssertEqual(shown.waiting, session("b", .needsYou, kind: .codex))
        XCTAssertEqual(shown.marks, [.init(kind: .codex, needsYou: true), .init(kind: .claude, needsYou: false)])
        inputs.now = Self.start.addingTimeInterval(2 * 86400)
        let later = try XCTUnwrap(row(inputs))
        XCTAssertNil(later.waiting, "A question left for days doesn't take over")
        XCTAssertEqual(later.marks, [.init(kind: .claude, needsYou: false)])
    }

    func testEverythingAtOnce() throws {
        var inputs = IslandContent.Inputs()
        inputs.sessions = [session("a", .working), session("b", .working), session("c", .working, kind: .codex)]
        inputs.usage = [
            .claude: AgentUsage(kind: .claude, windows: [UsageWindow(label: "Session", usedPercent: 40, resetsAt: nil)]),
            .codex: AgentUsage(kind: .codex, windows: [UsageWindow(label: "Session", usedPercent: 62, resetsAt: nil)]),
        ]
        inputs.musicPlaying = true
        inputs.focusPhase = .focus
        let shown = try XCTUnwrap(row(inputs))
        XCTAssertEqual(shown.marks.map(\.kind), [.claude, .codex], "One mark per tool")
        XCTAssertEqual(shown.percent, 62, "The busiest one's limit")
        XCTAssertTrue(shown.withMusic)
        XCTAssertEqual(shown.focus, .focus)
        XCTAssertFalse(shown.percentOnLeft)
        let notch = CGSize(width: 180, height: 32)
        let alone = AgentsRow(marks: [.init(kind: .claude, needsYou: false)], waiting: nil, primary: session("a", .working), percent: 62)
        XCTAssertGreaterThan(
            IslandLayout.size(of: .agents(shown), notch: notch).width,
            IslandLayout.size(of: .agents(alone), notch: notch).width,
            "Widens just enough for the song and the timer"
        )
    }

    func testApprovalBeatsEverythingButADrag() {
        var inputs = IslandContent.Inputs()
        inputs.sessions = [session("b", .needsYou)]
        inputs.isExpanded = true
        inputs.tab = .agents
        inputs.approvals = [request]
        XCTAssertEqual(IslandContent.resolve(inputs), .approval(request))
        inputs.isDropTargeted = true
        XCTAssertEqual(IslandContent.resolve(inputs), .drop)
    }

    func testOpenTabBeatsNews() {
        var inputs = IslandContent.Inputs()
        inputs.finished = FinishedEvent(session: session("a", .done), at: .now)
        XCTAssertEqual(IslandContent.resolve(inputs), .finished(session("a", .done)))
        inputs.isExpanded = true
        inputs.tab = .agents
        XCTAssertEqual(IslandContent.resolve(inputs), .expanded(.agents))
    }

    func testAgentsOffHidesAgentStates() {
        var inputs = IslandContent.Inputs()
        inputs.agentsOn = false
        inputs.sessions = [session("a", .working)]
        inputs.approvals = [request]
        XCTAssertEqual(IslandContent.resolve(inputs), .idle)
    }

    func testClosedIslandCoversTheNotch() {
        let notch = CGSize(width: 200, height: 32)
        XCTAssertEqual(IslandLayout.size(of: .idle, notch: notch), notch)
        let alone = AgentsRow(marks: [.init(kind: .claude, needsYou: false)], waiting: nil, primary: session("a", .working), percent: nil)
        let working = IslandLayout.size(of: .agents(alone), notch: notch)
        XCTAssertEqual(working.height, notch.height)
        XCTAssertGreaterThan(working.width, notch.width)
        XCTAssertGreaterThan(IslandLayout.size(of: .expanded(.agents), notch: notch).height, notch.height)
    }
}

final class AgentTransitionsTests: XCTestCase {
    private func session(_ state: AgentState, since: Date = .distantPast) -> AgentSession {
        AgentSession(id: "s", kind: .claude, project: "p", detail: nil, state: state, since: since, pid: nil)
    }

    func testWorkingThenIdleIsDoneAndReportedOnce() {
        var transitions = AgentTransitions()
        _ = transitions.apply([session(.working)], now: Date(timeIntervalSince1970: 10))
        let finished = transitions.apply([session(.idle)], now: Date(timeIntervalSince1970: 20))
        XCTAssertEqual(finished.sessions.first?.state, .done)
        XCTAssertEqual(finished.finished.count, 1)
        let again = transitions.apply([session(.idle)], now: Date(timeIntervalSince1970: 30))
        XCTAssertEqual(again.sessions.first?.state, .done, "Stays done until it works again")
        XCTAssertEqual(again.sessions.first?.since, Date(timeIntervalSince1970: 20))
        XCTAssertTrue(again.finished.isEmpty)
    }

    func testIdleFromTheStartIsNotDone() {
        var transitions = AgentTransitions()
        let result = transitions.apply([session(.idle)], now: .now)
        XCTAssertEqual(result.sessions.first?.state, .idle)
        XCTAssertTrue(result.finished.isEmpty)
    }

    func testWorkingAgainClearsDone() {
        var transitions = AgentTransitions()
        _ = transitions.apply([session(.working)], now: .now)
        _ = transitions.apply([session(.idle)], now: .now)
        XCTAssertEqual(transitions.apply([session(.working)], now: .now).sessions.first?.state, .working)
    }
}

final class AgentReaderTests: XCTestCase {
    func testClaudeSessionFile() throws {
        let json = #"{"pid":1,"sessionId":"abc","cwd":"/Users/me/Projects/cmdtab","status":"waiting","waitingFor":"permission prompt","kind":"interactive","statusUpdatedAt":1000}"#
        let session = try XCTUnwrap(ClaudeSessionReader.session(fromJSON: Data(json.utf8), isAlive: true))
        XCTAssertEqual(session.project, "cmdtab")
        XCTAssertEqual(session.state, .needsYou)
        XCTAssertEqual(session.detail, "Wants permission")
        XCTAssertEqual(session.since, Date(timeIntervalSince1970: 1))
        XCTAssertNil(ClaudeSessionReader.session(fromJSON: Data(json.utf8), isAlive: false), "Dead processes are left out")
    }

    func testClaudeBusyIsWorking() throws {
        let json = #"{"pid":1,"sessionId":"abc","cwd":"/x","status":"busy"}"#
        XCTAssertEqual(ClaudeSessionReader.session(fromJSON: Data(json.utf8), isAlive: true)?.state, .working)
    }

    func testClaudeStatusLineLimits() throws {
        let now = Date(timeIntervalSince1970: 1000)
        let json = #"{"rate_limits":{"five_hour":{"used_percentage":62,"resets_at":5000},"seven_day":{"used_percentage":38,"resets_at":500}}}"#
        let usage = try XCTUnwrap(ClaudeUsageReader.usage(fromJSON: Data(json.utf8), now: now))
        XCTAssertEqual(usage.windows.map(\.usedPercent), [62, 0], "A window past its reset has started over")
        XCTAssertEqual(usage.session?.resetsAt, Date(timeIntervalSince1970: 5000))
        XCTAssertNil(ClaudeUsageReader.usage(fromJSON: Data(#"{"model":{}}"#.utf8), now: now))
    }

    func testCodexLog() throws {
        let head = #"{"type":"session_meta","payload":{"cwd":"/Users/me/tinycorp","source":"cli"}}"#
        let tail = """
        {"type":"event_msg","payload":{"type":"task_started"}}
        {"type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":21.0,"window_minutes":300,"resets_at":2000},"secondary":{"used_percent":84.0,"window_minutes":10080,"resets_at":9000}}}}
        """
        let summary = try XCTUnwrap(CodexReader.summarize(head: Data(head.utf8), tail: Data(tail.utf8)))
        XCTAssertEqual(summary.project, "tinycorp")
        XCTAssertTrue(summary.isInteractive)
        XCTAssertEqual(summary.state, .working)
        XCTAssertEqual(summary.usage?.windows.map(\.label), ["5 hours", "This week"])
        XCTAssertEqual(summary.usage?.windows.map(\.usedPercent), [21, 84])
    }

    func testCodexFinishedAndExecRuns() throws {
        let head = #"{"type":"session_meta","payload":{"cwd":"/x","source":"exec"}}"#
        let tail = """
        {"type":"event_msg","payload":{"type":"task_started"}}
        {"type":"event_msg","payload":{"type":"task_complete"}}
        """
        let summary = try XCTUnwrap(CodexReader.summarize(head: Data(head.utf8), tail: Data(tail.utf8)))
        XCTAssertEqual(summary.state, .idle)
        XCTAssertFalse(summary.isInteractive, "Runs started by other apps aren't shown")
    }
}

final class ClaudeHookTests: XCTestCase {
    func testPermissionRequestIsParsed() throws {
        let object: [String: Any] = [
            "hook_event_name": "PermissionRequest",
            "tool_name": "Bash",
            "tool_input": ["command": "npm test", "description": "Run tests"],
            "cwd": "/Users/me/tinycorp",
            "permission_suggestions": [["type": "addRules"]],
        ]
        let request = try XCTUnwrap(ClaudeHookServer.request(id: UUID(), from: object))
        XCTAssertEqual(request.approval.project, "tinycorp")
        XCTAssertEqual(request.approval.summary, "npm test")
        XCTAssertNotNil(request.suggestions)
        XCTAssertNil(ClaudeHookServer.request(id: UUID(), from: ["hook_event_name": "Stop"]))
    }

    func testReplies() throws {
        func decision(_ data: Data) throws -> [String: Any] {
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let output = try XCTUnwrap(object["hookSpecificOutput"] as? [String: Any])
            XCTAssertEqual(output["hookEventName"] as? String, "PermissionRequest")
            return try XCTUnwrap(output["decision"] as? [String: Any])
        }
        XCTAssertEqual(try decision(ClaudeHookServer.reply(.allow, suggestions: nil))["behavior"] as? String, "allow")
        XCTAssertEqual(try decision(ClaudeHookServer.reply(.deny, suggestions: nil))["behavior"] as? String, "deny")
        let always = try decision(ClaudeHookServer.reply(.allowAlways, suggestions: Data(#"[{"type":"addRules"}]"#.utf8)))
        XCTAssertNotNil(always["updatedPermissions"])
    }
}

final class IslandSettingsTests: XCTestCase {
    func testModulesKeepOrderAndGainNewOnesOff() {
        let saved = [IslandModuleSetting(module: .clock, isOn: true), IslandModuleSetting(module: .agents, isOn: true)]
        let normalized = IslandModuleSetting.normalized(saved)
        XCTAssertEqual(normalized.prefix(3).map(\.module), [.overview, .clock, .agents], "The Overview goes first")
        XCTAssertEqual(normalized.count, IslandModule.allCases.count)
        XCTAssertTrue(normalized.filter { $0.module != .clock && $0.module != .agents }.allSatisfy { !$0.isOn })
    }

    func testUsageText() {
        let now = Date(timeIntervalSince1970: 0)
        let window = UsageWindow(label: "Session", usedPercent: 62.4, resetsAt: Date(timeIntervalSince1970: 2 * 3600 + 14 * 60))
        XCTAssertEqual(UsageText.value(window, now: now), "62% · resets 2h 14m")
        XCTAssertEqual(UsageText.value(UsageWindow(label: "x", usedPercent: 5, resetsAt: nil), now: now), "5%")
    }
}

final class NowPlayingTests: XCTestCase {
    func testParseAndPosition() throws {
        let object: [String: Any] = ["title": "Neon Harbor", "artist": "", "duration": 240.0, "elapsed": 100.0,
                                     "rate": 1.0, "timestamp": 1000.0, "playing": true, "pid": 42]
        let track = try XCTUnwrap(NowPlaying.parse(object))
        XCTAssertNil(track.artist, "Empty artist is no artist")
        XCTAssertEqual(track.position(at: Date(timeIntervalSince1970: 1010)), 110)
        XCTAssertEqual(track.position(at: Date(timeIntervalSince1970: 2000)), 240, "Never past the end")
        var paused = track
        paused.isPlaying = false
        XCTAssertEqual(paused.position(at: Date(timeIntervalSince1970: 1010)), 100)
        XCTAssertNil(NowPlaying.parse(["title": NSNull(), "playing": false]))
        let bare = try XCTUnwrap(NowPlaying.parse(["title": NSNull(), "playing": true, "pid": 7]), "Playing without details still counts")
        XCTAssertFalse(bare.hasDetails)
    }

    func testMusicShowsOnlyWhenNothingElseIs() {
        var inputs = IslandContent.Inputs()
        inputs.musicPlaying = true
        XCTAssertEqual(IslandContent.resolve(inputs), .music)
        inputs.sessions = [AgentSession(id: "a", kind: .claude, project: "p", detail: nil, state: .working, since: .now, pid: nil)]
        if case .agents = IslandContent.resolve(inputs) {} else { XCTFail("Agents at work come first") }
    }
}

@MainActor
final class IslandModulesTests: XCTestCase {
    func testWindowDropLayoutsSplitThePicker() {
        let rect = CGRect(x: 100, y: 0, width: 400, height: 80)
        XCTAssertEqual(WindowDropLayout.at(x: 110, in: rect), .leftHalf)
        XCTAssertEqual(WindowDropLayout.at(x: 260, in: rect), .rightHalf)
        XCTAssertEqual(WindowDropLayout.at(x: 499, in: rect), .centre)
        XCTAssertNil(WindowDropLayout.at(x: 50, in: rect))
        XCTAssertNil(WindowDropLayout.at(x: 200, in: .zero))
        let area = CGRect(x: 0, y: 30, width: 1001, height: 900)
        XCTAssertEqual(WindowDropLayout.leftHalf.frame(in: area).maxX, WindowDropLayout.rightHalf.frame(in: area).minX)
        XCTAssertEqual(WindowDropLayout.rightHalf.frame(in: area).maxX, area.maxX)
        XCTAssertEqual(WindowDropLayout.fill.frame(in: area), area)
    }

    func testWorldCities() {
        XCTAssertEqual(WorldCity.cityName(of: "America/Sao_Paulo"), "Sao Paulo")
        XCTAssertEqual(WorldCity.search("lisb").first?.timeZoneID, "Europe/Lisbon")
        XCTAssertTrue(WorldCity.search("l").isEmpty, "Needs two letters")
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let lisbon = WorldCity(timeZoneID: "Europe/Lisbon", name: "Lisbon")
        XCTAssertEqual(lisbon.offsetText(at: date, from: TimeZone(identifier: "Europe/Lisbon")!), "Here")
        XCTAssertTrue(lisbon.offsetText(at: date, from: TimeZone(identifier: "America/Sao_Paulo")!).hasPrefix("+3 h"))
        XCTAssertEqual(lisbon.short, "LIS")
    }

    func testMeetingLinks() {
        XCTAssertEqual(MeetingWatcher.callLink(in: "Daily https://meet.google.com/abc-defg-hij notes")?.host, "meet.google.com")
        XCTAssertEqual(MeetingWatcher.callLink(in: "Join: https://acme.zoom.us/j/123")?.host, "acme.zoom.us")
        XCTAssertNil(MeetingWatcher.callLink(in: "Lunch at https://example.com"))
        XCTAssertEqual(MeetingWatcher.service(of: URL(string: "https://teams.microsoft.com/l/x")!), "Teams")
    }

    func testShelfKeepsOnlyRecentFilesThatExist() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-\(UUID()).txt")
        FileManager.default.createFile(atPath: file.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: file) }
        let now = Date()
        let items = [
            ShelfItem(path: file.path, addedAt: now.addingTimeInterval(-60)),
            ShelfItem(path: file.path, addedAt: now.addingTimeInterval(-25 * 3600)),
            ShelfItem(path: "/nope/\(UUID())", addedAt: now),
        ]
        XCTAssertEqual(ShelfStore.current(items, now: now).count, 1)
        XCTAssertFalse(ShelfStore.isFinished(URL(fileURLWithPath: "/x/movie.mp4.crdownload")))
        XCTAssertTrue(ShelfStore.isFinished(URL(fileURLWithPath: "/x/movie.mp4")))
    }

    func testWeatherParse() throws {
        let json = """
        {"current":{"temperature_2m":24.2,"weather_code":2,"is_day":1},
         "hourly":{"time":[1000,4600,8200],"temperature_2m":[24,23,21],"weather_code":[2,3,61],"precipitation_probability":[0,20,80]},
         "daily":{"temperature_2m_max":[27],"temperature_2m_min":[18]}}
        """
        let report = try XCTUnwrap(WeatherService.parse(Data(json.utf8), place: "São Paulo", now: Date(timeIntervalSince1970: 1000)))
        XCTAssertEqual(report.hours.count, 3)
        XCTAssertEqual(report.rainFrom, Date(timeIntervalSince1970: 8200))
        XCTAssertEqual(report.high, 27)
        XCTAssertEqual(WeatherService.symbol(61), "cloud.rain.fill")
    }

    func testPrioritiesOfTheNewStates() {
        var inputs = IslandContent.Inputs()
        inputs.musicPlaying = true
        inputs.focusPhase = .focus
        XCTAssertEqual(IslandContent.resolve(inputs), .focus(.focus), "A running Pomodoro beats music")
        let moment = Moment(kind: .charging, title: "Charging", value: "64%")
        inputs.moment = moment
        XCTAssertEqual(IslandContent.resolve(inputs), .moment(moment))
        let meeting = UpcomingMeeting(title: "Daily", start: .now, link: nil, service: nil)
        inputs.meeting = meeting
        XCTAssertEqual(IslandContent.resolve(inputs), .meeting(meeting))
        inputs.windowDrop = .some(.fill)
        XCTAssertEqual(IslandContent.resolve(inputs), .windowDrop(.fill), "Dragging a window wins")
    }
}

final class IslandSharedCompactTests: XCTestCase {
    func testAgentAndMusicShareTheClosedIsland() {
        let session = AgentSession(id: "a", kind: .claude, project: "p", detail: nil, state: .working, since: .now, pid: nil)
        var inputs = IslandContent.Inputs()
        inputs.sessions = [session]
        inputs.musicPlaying = true
        guard case let .agents(row) = IslandContent.resolve(inputs) else { return XCTFail("Agents show") }
        XCTAssertTrue(row.withMusic)
    }
}

final class WeatherPlaceTests: XCTestCase {
    func testSearchResultsCarryRegionAndCoordinates() {
        let json = #"{"results":[{"name":"Cascavel","latitude":-24.95,"longitude":-53.45,"admin1":"Paraná","country":"Brasil"},{"name":"Cascavel","latitude":-4.13,"longitude":-38.24,"admin1":"Ceará","country":"Brasil"}]}"#
        let places = WeatherPlace.parseSearch(Data(json.utf8))
        XCTAssertEqual(places.map(\.region), ["Paraná, Brasil", "Ceará, Brasil"])
        XCTAssertNotEqual(places[0].id, places[1].id, "Same name, different cities")
        XCTAssertTrue(WeatherPlace.parseSearch(Data("{}".utf8)).isEmpty)
    }
}

@MainActor
final class ShelfAddingTests: XCTestCase {
    func testAddingAFileAgainMovesItToTheTopWithAFreshDay() {
        let old = Date(timeIntervalSince1970: 0)
        let now = Date(timeIntervalSince1970: 100)
        let items = [ShelfItem(path: "/a", addedAt: old), ShelfItem(path: "/b", addedAt: old)]
        let result = ShelfStore.adding(["/b", "/c", "/b"], to: items, at: now)
        XCTAssertEqual(result.map(\.path), ["/b", "/c", "/a"])
        XCTAssertEqual(result[0].addedAt, now)
    }

    func testOpenShelfTakesDropsItself() {
        var inputs = IslandContent.Inputs()
        inputs.isDropTargeted = true
        XCTAssertEqual(IslandContent.resolve(inputs), .drop)
        inputs.isExpanded = true
        inputs.tab = .shelf
        XCTAssertEqual(IslandContent.resolve(inputs), .expanded(.shelf))
    }
}


final class FocusCycleTests: XCTestCase {
    func testASetIsFourFocusRoundsWithBreaks() {
        var cycle = FocusCycle()
        XCTAssertEqual(cycle.minutes(in: .short), 25)
        cycle.advance()
        XCTAssertEqual(cycle.phase, .rest)
        XCTAssertEqual(cycle.completed, 1)
        XCTAssertEqual(cycle.minutes(in: .short), 5)
        cycle.advance()
        XCTAssertEqual(cycle.phase, .focus)
        XCTAssertEqual(cycle.round, 2)
        for _ in 0..<5 { cycle.advance() }
        XCTAssertEqual(cycle.round, 4)
        XCTAssertEqual(cycle.phase, .rest)
        XCTAssertEqual(cycle.completed, 4)
        cycle.advance()
        XCTAssertEqual(cycle, FocusCycle(), "After the fourth break a new set starts")
    }

    func testClockText() {
        XCTAssertEqual(FocusTimer.clock(1122), "18:42")
        XCTAssertEqual(FocusTimer.clock(59.2), "1:00")
    }
}

final class CalendarFormTests: XCTestCase {
    func testNewEventStartsAtTheNextHalfHourToday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 10, minute: 12))!
        XCTAssertEqual(NewEventDefaults.start(on: now, now: now, calendar: calendar), 10 * 60 + 30)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        XCTAssertEqual(NewEventDefaults.start(on: tomorrow, now: now, calendar: calendar), 9 * 60, "Another day starts at 9")
        let late = calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 23, minute: 50))!
        XCTAssertEqual(NewEventDefaults.start(on: late, now: late, calendar: calendar), 23 * 60 + 30, "Never past the day")
    }

    func testStartsAndEnds() {
        let start = Date(timeIntervalSince1970: 36_000)
        let end = start.addingTimeInterval(5400)
        let moved = NewEventDefaults.moveStart(start, end: end, to: start.addingTimeInterval(86400))
        XCTAssertEqual(moved.end.timeIntervalSince(moved.start), 5400, "Ends keeps the length when Starts moves, even a day")
        XCTAssertEqual(NewEventDefaults.moveEnd(to: start, start: start), start.addingTimeInterval(1800), "Never before Starts")
        let late = start.addingTimeInterval(86400)
        XCTAssertEqual(NewEventDefaults.moveEnd(to: late, start: start), late, "Can run into the next day")
        XCTAssertEqual(NewEventDefaults.duration(30), "30m")
        XCTAssertEqual(NewEventDefaults.duration(60), "1h")
        XCTAssertEqual(NewEventDefaults.duration(90), "1h 30m")
    }
}

final class OverviewTests: XCTestCase {
    func testOverviewJoinsFirstAndOff() {
        let saved = [IslandModuleSetting(module: .agents, isOn: true), IslandModuleSetting(module: .music, isOn: true)]
        let normalized = IslandModuleSetting.normalized(saved)
        XCTAssertEqual(normalized.first, IslandModuleSetting(module: .overview, isOn: false))
        XCTAssertEqual(normalized[1].module, .agents, "Your order stays")
    }

    func testSamplesKeepTheLastThirtyInRange() {
        var samples: [Double] = []
        for value in 0..<40 { samples = SystemStats.appending(Double(value) / 10, to: samples) }
        XCTAssertEqual(samples.count, SystemStats.sampleCount)
        XCTAssertEqual(samples.last, 1, "Clamped to 100%")
    }

    func testCPUUsageFromTicks() {
        let earlier = SystemStats.CPUTicks(busy: 100, total: 400)
        let later = SystemStats.CPUTicks(busy: 150, total: 500)
        XCTAssertEqual(later.usage(since: earlier), 0.5)
        XCTAssertNil(earlier.usage(since: later))
    }

    func testReadingTheMacWorks() {
        XCTAssertNotNil(SystemStats.cpuTicks())
        let memory = try? XCTUnwrap(SystemStats.memoryUsed())
        XCTAssertNotNil(memory)
        XCTAssertGreaterThan(memory ?? 0, 0)
        XCTAssertLessThanOrEqual(memory ?? 2, 1.2)
    }
}

final class IslandPanelTests: XCTestCase {
    func testThePanelHoldsTheWidestTab() {
        for module in IslandModule.allCases {
            XCTAssertLessThanOrEqual(IslandLayout.width(of: module), IslandLayout.maximumWidth, "\(module) would push the panel off centre")
        }
        XCTAssertEqual(IslandLayout.maximumWidth, 980)
    }
}

@MainActor
final class WeatherAheadTests: XCTestCase {
    func testKeepsTheWeekAndItsDays() throws {
        let json = """
        {"current":{"temperature_2m":24,"weather_code":2,"is_day":1},
         "hourly":{"time":[0,3600,7200,10800,14400,18000,21600,25200,28800],
                   "temperature_2m":[20,21,22,23,24,25,26,27,28],
                   "weather_code":[0,0,0,0,0,0,0,61,61],
                   "precipitation_probability":[0,0,0,0,0,0,0,80,90]},
         "daily":{"time":[0,86400],"temperature_2m_max":[27,25],"temperature_2m_min":[18,17]}}
        """
        let report = try XCTUnwrap(WeatherService.parse(Data(json.utf8), place: "Town", now: Date(timeIntervalSince1970: 0)))
        XCTAssertEqual(report.hours.count, 9, "Every hour ahead, not just six")
        XCTAssertNil(report.rainFrom, "No rain in the first six hours")
        XCTAssertEqual(WeatherService.rainFrom(report.hours, start: 3), Date(timeIntervalSince1970: 25200), "Scrolled ahead, the rain shows")
        XCTAssertEqual(report.days.map(\.high), [27, 25])
    }
}

final class IslandDockScreenTests: XCTestCase {
    func testFindsTheDockEdge() {
        let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        XCTAssertFalse(IslandController.dockEdge(frame: frame, visible: CGRect(x: 0, y: 0, width: 1512, height: 949)), "Only the menu bar")
        XCTAssertTrue(IslandController.dockEdge(frame: frame, visible: CGRect(x: 0, y: 80, width: 1512, height: 869)), "Dock at the bottom")
        XCTAssertTrue(IslandController.dockEdge(frame: frame, visible: CGRect(x: 0, y: 4, width: 1512, height: 945)), "Hidden Dock")
        XCTAssertTrue(IslandController.dockEdge(frame: frame, visible: CGRect(x: 70, y: 0, width: 1442, height: 949)), "Dock on the left")
        XCTAssertTrue(IslandController.dockEdge(frame: frame, visible: CGRect(x: 0, y: 0, width: 1442, height: 949)), "Dock on the right")
    }
}
