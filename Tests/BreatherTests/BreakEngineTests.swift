import XCTest
@testable import Breather

@MainActor
final class BreakEngineTests: XCTestCase {
    private var start = Date(timeIntervalSince1970: 1_800_000_000)
    private var events: [EngineEvent] = []

    private func makeEngine(_ configure: (inout Settings) -> Void = { _ in }) -> BreakEngine {
        var s = Settings()
        s.workMinutes = 1
        s.breakSeconds = 10
        s.headsUpLeadSeconds = 20
        s.finalCountdownSeconds = 3
        s.postActivityDelaySeconds = 0
        configure(&s)
        let engine = BreakEngine(settings: s)
        events = []
        engine.onEvent = { [weak self] in self?.events.append($0) }
        return engine
    }

    /// Ticks once per second for `seconds`, starting at `from` seconds after `start`.
    private func run(_ engine: BreakEngine, from: Int = 0, seconds: Int, signals: ActivitySignals = ActivitySignals()) {
        for i in from...(from + seconds) {
            engine.tick(now: start.addingTimeInterval(TimeInterval(i)), signals: signals)
        }
    }

    func testBreakStartsAfterWorkInterval() {
        let engine = makeEngine()
        run(engine, seconds: 59)
        XCTAssertFalse(engine.isOnBreak)
        run(engine, from: 60, seconds: 0)
        XCTAssertTrue(engine.isOnBreak)
        XCTAssertTrue(events.contains(.headsUp(.short)))
    }

    func testBreakEndsAndCycleResets() {
        let engine = makeEngine()
        run(engine, seconds: 60)
        run(engine, from: 61, seconds: 10)
        XCTAssertFalse(engine.isOnBreak)
        XCTAssertEqual(engine.breaksSinceLong, 1)
        XCTAssertLessThan(engine.workElapsed, 2)
    }

    func testLongBreakAfterConfiguredShortBreaks() {
        let engine = makeEngine { $0.longBreakEvery = 2 }
        XCTAssertEqual(engine.nextBreakKind, .short)
        engine.startBreak(now: start); engine.skipBreak()
        engine.startBreak(now: start); engine.skipBreak()
        XCTAssertEqual(engine.nextBreakKind, .long)
    }

    func testTypingHoldsBreakUntilLull() {
        let engine = makeEngine { $0.typingLullSeconds = 2; $0.maxTypingDelaySeconds = 30 }
        var typing = ActivitySignals()
        typing.secondsSinceTyping = 0.5
        run(engine, seconds: 70, signals: typing)
        XCTAssertEqual(engine.phase, .holding(.typing))
        run(engine, from: 71, seconds: 4)
        XCTAssertTrue(engine.isOnBreak)
    }

    func testTypingHoldGivesUpAfterMaxDelay() {
        let engine = makeEngine { $0.maxTypingDelaySeconds = 10 }
        var typing = ActivitySignals()
        typing.secondsSinceTyping = 0.1
        // Hold starts at 57s, gives up 10s later; break must be running by 72s.
        run(engine, seconds: 72, signals: typing)
        XCTAssertTrue(engine.isOnBreak)
    }

    func testSmartPauseHoldsBreakButCountsWork() {
        let engine = makeEngine()
        var meeting = ActivitySignals()
        meeting.pauseReasons = [.meeting("Zoom")]
        run(engine, seconds: 120, signals: meeting)
        XCTAssertFalse(engine.isOnBreak)
        XCTAssertEqual(engine.workElapsed, 60, accuracy: 0.01)
        run(engine, from: 121, seconds: 1)
        XCTAssertTrue(engine.isOnBreak)
    }

    func testAwayCountsAsNaturalBreak() {
        let engine = makeEngine { $0.workMinutes = 20; $0.idleThresholdSeconds = 60 }
        run(engine, seconds: 300)
        var idle = ActivitySignals()
        idle.secondsSinceInput = 61
        engine.tick(now: start.addingTimeInterval(301), signals: idle)
        XCTAssertEqual(engine.phase, .away(since: start.addingTimeInterval(240)))
        // Back after a few minutes.
        engine.tick(now: start.addingTimeInterval(600), signals: ActivitySignals())
        XCTAssertEqual(engine.phase, .working)
        XCTAssertLessThan(engine.workElapsed, 1)
        XCTAssertTrue(events.contains { if case .naturalBreak = $0 { true } else { false } })

        engine.undoNaturalBreak()
        XCTAssertEqual(engine.workElapsed, 240, accuracy: 1)
    }

    func testSleepGapIsTreatedAsAway() {
        let engine = makeEngine { $0.workMinutes = 20 }
        run(engine, seconds: 200)
        // Mac slept for an hour: next tick arrives late.
        engine.tick(now: start.addingTimeInterval(3800), signals: ActivitySignals())
        XCTAssertEqual(engine.phase, .working)
        XCTAssertLessThan(engine.workElapsed, 1)
        XCTAssertEqual(engine.breaksSinceLong, 0, "an hour away counts as a long break")
    }

    func testSnoozeRespectsLimit() {
        let engine = makeEngine { $0.snoozeLimitPerBreak = 1 }
        run(engine, seconds: 60)
        XCTAssertTrue(engine.isOnBreak)
        engine.snooze(30, now: start.addingTimeInterval(61))
        XCTAssertFalse(engine.isOnBreak)
        XCTAssertEqual(engine.timeUntilBreak, 30, accuracy: 0.01)
        XCTAssertFalse(engine.canSnooze)
    }

    func testSkipInAdvance() {
        let engine = makeEngine()
        engine.toggleSkipNext()
        run(engine, seconds: 61)
        XCTAssertFalse(engine.isOnBreak)
        XCTAssertTrue(events.contains(.breakSkipped(.short, inAdvance: true)))
        XCTAssertFalse(engine.skipNextPending)
    }

    func testHardcoreDisablesSnoozeAndAdvanceSkip() {
        let engine = makeEngine { $0.difficulty = .hardcore }
        XCTAssertFalse(engine.canSnooze)
        XCTAssertFalse(engine.canSkipInAdvance)
    }

    func testPauseAndTimedResume() {
        let engine = makeEngine()
        engine.pause(for: 30, now: start)
        run(engine, seconds: 29)
        if case .paused = engine.phase {} else { XCTFail("should be paused") }
        run(engine, from: 31, seconds: 0)
        XCTAssertEqual(engine.phase, .working)
    }
}

final class OfficeHoursTests: XCTestCase {
    private func date(weekday: Int, hour: Int, minute: Int = 0) -> Date {
        // 2026-10-25 is a Sunday (weekday 1).
        var c = DateComponents(year: 2026, month: 10, day: 24 + weekday, hour: hour, minute: minute)
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar.utc.date(from: c)!
    }

    func testWeekdayHours() {
        var hours = OfficeHours()
        hours.enabled = true
        XCTAssertTrue(hours.contains(date(weekday: 2, hour: 10), calendar: .utc))
        XCTAssertFalse(hours.contains(date(weekday: 2, hour: 19), calendar: .utc))
        XCTAssertFalse(hours.contains(date(weekday: 1, hour: 10), calendar: .utc), "Sunday is off by default")
    }

    func testOvernightShift() {
        var hours = OfficeHours()
        hours.enabled = true
        hours.days[2] = DaySchedule(enabled: true, startMinute: 22 * 60, endMinute: 2 * 60) // Tuesday 22:00–02:00
        XCTAssertTrue(hours.contains(date(weekday: 3, hour: 23), calendar: .utc))
        XCTAssertTrue(hours.contains(date(weekday: 4, hour: 1), calendar: .utc), "spills into Wednesday")
        XCTAssertFalse(hours.contains(date(weekday: 4, hour: 3), calendar: .utc) && !hours.days[3].enabled)
    }

    func testDisabledMeansAlways() {
        XCTAssertTrue(OfficeHours().contains(date(weekday: 1, hour: 3), calendar: .utc))
    }
}

private extension Calendar {
    static var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
}
