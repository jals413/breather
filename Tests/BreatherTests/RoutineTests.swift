import XCTest
@testable import Breather

@MainActor
final class RoutineTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// Monday 2026-10-26 at the given time, UTC.
    private func monday(_ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: hour, minute: minute, second: second))!
    }

    private func makeEngine(_ configure: (inout Settings) -> Void) -> BreakEngine {
        var s = Settings()
        s.workMinutes = 120 // keep the break far away
        s.reminders = []
        s.plannedBreaks = []
        configure(&s)
        return BreakEngine(settings: s, calendar: calendar)
    }

    private func freshScheduler() -> RoutineScheduler {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        return RoutineScheduler(defaults: defaults, calendar: calendar)
    }

    func testReminderFiresAfterActiveInterval() {
        let water = Reminder(title: "Water", message: "", symbol: "drop", tint: .white, intervalMinutes: 1)
        let engine = makeEngine { $0.reminders = [water] }
        let scheduler = freshScheduler()
        var fired: [RoutineEvent] = []
        for i in 0...61 {
            let now = monday(10).addingTimeInterval(TimeInterval(i))
            engine.tick(now: now, signals: ActivitySignals())
            fired += scheduler.tick(now: now, dt: i == 0 ? 0 : 1, engine: engine)
        }
        XCTAssertEqual(fired, [.remind(water)])
    }

    func testReminderDoesNotCountWhilePaused() {
        let water = Reminder(title: "Water", message: "", symbol: "drop", tint: .white, intervalMinutes: 1)
        let engine = makeEngine { $0.reminders = [water] }
        engine.pause(for: nil, now: monday(10))
        let scheduler = freshScheduler()
        var fired: [RoutineEvent] = []
        for i in 1...120 {
            fired += scheduler.tick(now: monday(10).addingTimeInterval(TimeInterval(i)), dt: 1, engine: engine)
        }
        XCTAssertTrue(fired.isEmpty)
    }

    func testReminderHeldRightBeforeABreak() {
        let water = Reminder(title: "Water", message: "", symbol: "drop", tint: .white, intervalMinutes: 1)
        let engine = makeEngine { $0.reminders = [water]; $0.workMinutes = 1.5; $0.headsUpEnabled = false }
        let scheduler = freshScheduler()
        var fired: [RoutineEvent] = []
        for i in 0...65 {
            let now = monday(10).addingTimeInterval(TimeInterval(i))
            engine.tick(now: now, signals: ActivitySignals())
            fired += scheduler.tick(now: now, dt: i == 0 ? 0 : 1, engine: engine)
        }
        XCTAssertTrue(fired.isEmpty, "break is under 90s away, so the reminder waits")
    }

    func testPlannedBreakWarnsThenStarts() {
        let lunch = PlannedBreak(title: "Lunch", message: "", minuteOfDay: 13 * 60, durationMinutes: 30)
        let engine = makeEngine { $0.plannedBreaks = [lunch] }
        let scheduler = freshScheduler()
        engine.tick(now: monday(12, 58, 30), signals: ActivitySignals())
        XCTAssertEqual(scheduler.tick(now: monday(12, 58, 30), dt: 1, engine: engine), [.plannedBreakSoon(lunch, in: 90)])
        engine.tick(now: monday(13, 0, 1), signals: ActivitySignals())
        XCTAssertEqual(scheduler.tick(now: monday(13, 0, 1), dt: 1, engine: engine), [.startPlannedBreak(lunch)])
        XCTAssertEqual(scheduler.tick(now: monday(13, 0, 2), dt: 1, engine: engine), [], "only once per day")
    }

    func testPlannedBreakWaitsForCallThenMisses() {
        let lunch = PlannedBreak(title: "Lunch", message: "", minuteOfDay: 13 * 60, durationMinutes: 30)
        let engine = makeEngine { $0.plannedBreaks = [lunch] }
        let scheduler = freshScheduler()
        var call = ActivitySignals()
        call.pauseReasons = [.meeting("Zoom")]
        engine.tick(now: monday(13, 5), signals: call)
        XCTAssertEqual(scheduler.tick(now: monday(13, 5), dt: 1, engine: engine), [])
        engine.tick(now: monday(13, 50), signals: call)
        XCTAssertEqual(scheduler.tick(now: monday(13, 50), dt: 1, engine: engine), [.plannedBreakMissed(lunch)])
    }

    func testPlannedBreakSkipsOtherDays() {
        var lunch = PlannedBreak(title: "Lunch", message: "", minuteOfDay: 13 * 60, durationMinutes: 30)
        lunch.weekdays = [0, 6]
        let engine = makeEngine { $0.plannedBreaks = [lunch] }
        engine.tick(now: monday(13, 1), signals: ActivitySignals())
        XCTAssertEqual(freshScheduler().tick(now: monday(13, 1), dt: 1, engine: engine), [])
    }
}

final class ScoreTests: XCTestCase {
    func testPerfectDay() {
        var day = DailyStats(day: "d")
        day.sessions = [20 * 60, 18 * 60, 19 * 60]
        day.taken = 3
        XCTAssertEqual(day.score(), 100)
    }

    func testLongSessionsAndSkipsLowerScore() {
        var day = DailyStats(day: "d")
        day.sessions = [80 * 60] // 4× the target
        day.taken = 1
        day.skipped = 3
        // discipline 0.25 × 60 = 15, adherence 0.25 × 40 = 10
        XCTAssertEqual(day.score(), 25)
    }

    func testEmptyDayIsZero() {
        XCTAssertEqual(DailyStats(day: "d").score(), 0)
    }

    func testMedian() {
        var day = DailyStats(day: "d")
        day.sessions = [10, 30, 20, 40]
        XCTAssertEqual(day.medianSession, 25)
    }
}
