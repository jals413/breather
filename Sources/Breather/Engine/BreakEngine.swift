import Foundation
import Observation

enum BreakKind: Equatable, Codable {
    case short, long, custom

    var title: String {
        switch self {
        case .short: "Short break"
        case .long: "Long break"
        case .custom: "Break"
        }
    }
}

struct BreakSession: Equatable {
    var kind: BreakKind
    var start: Date
    var duration: TimeInterval
    var message: String
    var end: Date { start.addingTimeInterval(duration) }

    func remaining(at now: Date) -> TimeInterval { max(0, end.timeIntervalSince(now)) }
    func progress(at now: Date) -> Double {
        guard duration > 0 else { return 1 }
        return min(1, max(0, now.timeIntervalSince(start) / duration))
    }
}

enum PauseReason: Hashable {
    case meeting(String?)
    case video(String?)
    case fullscreen(String?)
    case focusApp(String)
    case screenRecording

    var title: String {
        switch self {
        case .meeting(let app): app.map { "In a call · \($0)" } ?? "In a call"
        case .video(let app): app.map { "Watching · \($0)" } ?? "Video playing"
        case .fullscreen(let app): app.map { "Fullscreen · \($0)" } ?? "Fullscreen app"
        case .focusApp(let app): "Focusing · \(app)"
        case .screenRecording: "Screen recording"
        }
    }

    var symbol: String {
        switch self {
        case .meeting: "video.fill"
        case .video: "play.rectangle.fill"
        case .fullscreen: "gamecontroller.fill"
        case .focusApp: "scope"
        case .screenRecording: "record.circle"
        }
    }
}

/// Everything the engine needs to know about the outside world for one tick.
struct ActivitySignals: Equatable {
    var secondsSinceInput: TimeInterval = 0
    var secondsSinceTyping: TimeInterval = .infinity
    var isLockedOrAsleep = false
    var pauseReasons: [PauseReason] = []
}

enum EngineEvent: Equatable {
    case headsUp(BreakKind)
    case breakStarted(BreakSession)
    case breakEnded(BreakSession, completed: Bool)
    case breakSkipped(BreakKind, inAdvance: Bool)
    case snoozed(TimeInterval)
    case naturalBreak(away: TimeInterval, countedAs: BreakKind)
    case resumed
}

/// The engine's visible state.
enum EnginePhase: Equatable {
    /// Counting work time.
    case working
    /// Break is due but held back; the reason is shown to the user.
    case holding(HoldReason)
    case smartPaused([PauseReason])
    case paused(until: Date?)
    case away(since: Date)
    case offHours
    case onBreak(BreakSession)
}

enum HoldReason: Equatable {
    case typing
    case afterActivity
}

/// A snapshot used to undo a natural break or restore after a crash.
struct EngineSnapshot: Codable, Equatable {
    var workElapsed: TimeInterval
    var breaksSinceLong: Int
    var savedAt: Date
}

@MainActor
@Observable
final class BreakEngine {
    private(set) var phase: EnginePhase = .working
    /// Work seconds counted toward the next break.
    private(set) var workElapsed: TimeInterval = 0
    private(set) var breaksSinceLong = 0
    private(set) var snoozesThisCycle = 0
    private(set) var skipNextPending = false
    private(set) var advanceSkipsToday = 0
    private(set) var headsUpShown = false
    /// When the last undoable natural break happened, and the state before it.
    private(set) var undoableNaturalBreak: (at: Date, before: EngineSnapshot)?

    var settings: Settings {
        didSet { clampAfterSettingsChange(oldValue) }
    }

    @ObservationIgnored var onEvent: ((EngineEvent) -> Void)?
    @ObservationIgnored private var lastTick: Date?
    @ObservationIgnored private var lastPauseEnded: Date?
    @ObservationIgnored private var holdStarted: Date?
    @ObservationIgnored private var skipDay: Date?
    @ObservationIgnored private let calendar: Calendar

    init(settings: Settings, calendar: Calendar = .current) {
        self.settings = settings
        self.calendar = calendar
    }

    // MARK: Derived

    var nextBreakKind: BreakKind {
        settings.longBreakEnabled && breaksSinceLong >= settings.longBreakEvery ? .long : .short
    }

    var workTarget: TimeInterval { settings.workSeconds }

    var timeUntilBreak: TimeInterval { max(0, workTarget - workElapsed) }

    var workProgress: Double { workTarget > 0 ? min(1, workElapsed / workTarget) : 0 }

    var isInFinalCountdown: Bool {
        if case .working = phase { return timeUntilBreak <= settings.finalCountdownSeconds && timeUntilBreak > 0 }
        return false
    }

    var canSnooze: Bool {
        settings.difficulty != .hardcore && snoozesThisCycle < settings.snoozeLimitPerBreak
    }

    var canSkipInAdvance: Bool {
        settings.difficulty != .hardcore && advanceSkipsToday < settings.dailyAdvanceSkipLimit
    }

    var isOnBreak: Bool {
        if case .onBreak = phase { return true }
        return false
    }

    // MARK: Tick

    func tick(now: Date, signals: ActivitySignals) {
        let dt = lastTick.map { max(0, now.timeIntervalSince($0)) } ?? 0
        let previousTick = lastTick ?? now
        lastTick = now
        rollDailyCounters(now)

        // Undo is only offered briefly after returning.
        if let undo = undoableNaturalBreak, now.timeIntervalSince(undo.at) > 30 { undoableNaturalBreak = nil }

        switch phase {
        case .onBreak(let session):
            if now >= session.end { finishBreak(session, completed: true) }
            return

        case .paused(let until):
            if let until, now >= until { resume(now: now) }
            return

        default:
            break
        }

        // Office hours.
        if !settings.officeHours.contains(now, calendar: calendar) {
            if phase != .offHours {
                phase = .offHours
                resetCycle(keepLongCounter: false)
            }
            return
        } else if phase == .offHours {
            phase = .working
        }

        // Asleep / locked / a long gap between ticks (the Mac was asleep) → away.
        let gapAway = dt > 30
        let idle = signals.isLockedOrAsleep || signals.secondsSinceInput >= settings.idleThresholdSeconds
        if case .away(let since) = phase {
            if idle { return }
            returnFromAway(since: since, now: now)
        } else if gapAway {
            // The Mac slept between ticks; the gap itself was time away.
            phase = .away(since: previousTick)
            if idle { return }
            returnFromAway(since: previousTick, now: now)
        } else if idle {
            // Smart pause reasons like video mean the user is watching, not away.
            if signals.isLockedOrAsleep || signals.pauseReasons.isEmpty {
                // Don't count the idle run-up as work.
                workElapsed = max(0, workElapsed - signals.secondsSinceInput)
                phase = .away(since: now.addingTimeInterval(-signals.secondsSinceInput))
                return
            }
        }

        let step = gapAway ? 0 : dt

        // Smart pause: work keeps counting (eyes are on screen) but the break waits.
        if !signals.pauseReasons.isEmpty {
            workElapsed = min(workTarget, workElapsed + step)
            phase = .smartPaused(signals.pauseReasons)
            return
        }
        if case .smartPaused = phase {
            lastPauseEnded = now
            phase = .working
        }

        workElapsed += step
        let remaining = workTarget - workElapsed

        if settings.headsUpEnabled && !headsUpShown && remaining <= settings.headsUpLeadSeconds && remaining > settings.finalCountdownSeconds {
            headsUpShown = true
            onEvent?(.headsUp(nextBreakKind))
        }

        // Hold the break at the start of the final countdown if now is a bad moment.
        if remaining <= settings.finalCountdownSeconds, let reason = holdReason(now: now, signals: signals) {
            workElapsed = workTarget - settings.finalCountdownSeconds
            if holdStarted == nil { holdStarted = now }
            phase = .holding(reason)
            return
        }
        if case .holding = phase { phase = .working }

        if remaining <= 0 {
            holdStarted = nil
            if skipNextPending {
                skipNextPending = false
                onEvent?(.breakSkipped(nextBreakKind, inAdvance: true))
                advanceCycle(after: nextBreakKind)
                return
            }
            startBreak(kind: nextBreakKind, now: now)
        }
    }

    private func holdReason(now: Date, signals: ActivitySignals) -> HoldReason? {
        if let ended = lastPauseEnded, now.timeIntervalSince(ended) < settings.postActivityDelaySeconds {
            return .afterActivity
        }
        if settings.waitForTypingPause && signals.secondsSinceTyping < settings.typingLullSeconds {
            let heldFor = holdStarted.map { now.timeIntervalSince($0) } ?? 0
            if heldFor < settings.maxTypingDelaySeconds { return .typing }
        }
        return nil
    }

    private func returnFromAway(since: Date, now: Date) {
        let away = now.timeIntervalSince(since)
        phase = .working
        guard settings.idleCountsAsBreak else {
            onEvent?(.resumed)
            return
        }
        let before = snapshot(now: now)
        let countedAs: BreakKind = settings.longBreakEnabled && away >= settings.longBreakSeconds ? .long : .short
        guard away >= max(settings.breakSeconds, 1) else { return }
        // Only worth mentioning (and undoing) if it actually reset meaningful progress.
        if workElapsed > 60 || countedAs == .long {
            undoableNaturalBreak = (now, before)
            onEvent?(.naturalBreak(away: away, countedAs: countedAs))
        }
        advanceCycle(after: countedAs)
    }

    // MARK: Actions

    func startBreak(kind: BreakKind? = nil, duration: TimeInterval? = nil, now: Date = .now) {
        let kind = kind ?? nextBreakKind
        let length = duration ?? (kind == .long ? settings.longBreakSeconds : settings.breakSeconds)
        let messages = kind == .long ? settings.longBreakMessages : settings.shortBreakMessages
        let session = BreakSession(kind: kind, start: now, duration: length, message: messages.randomElement() ?? "")
        holdStarted = nil
        phase = .onBreak(session)
        onEvent?(.breakStarted(session))
    }

    /// Ends the current break. `completed` is false when the user skipped it.
    func endBreak(now: Date = .now) {
        guard case .onBreak(let session) = phase else { return }
        let completed = now.timeIntervalSince(session.start) >= session.duration * settings.endEarlyAfterFraction
        finishBreak(session, completed: completed)
    }

    func skipBreak() {
        guard case .onBreak(let session) = phase else { return }
        finishBreak(session, completed: false)
    }

    func snooze(_ seconds: TimeInterval, now: Date = .now) {
        guard canSnooze else { return }
        snoozesThisCycle += 1
        if case .onBreak(let session) = phase {
            onEvent?(.breakEnded(session, completed: false))
            phase = .working
        }
        workElapsed = max(0, workTarget - seconds)
        headsUpShown = seconds <= settings.headsUpLeadSeconds
        holdStarted = nil
        onEvent?(.snoozed(seconds))
    }

    func toggleSkipNext() {
        if skipNextPending {
            skipNextPending = false
            advanceSkipsToday = max(0, advanceSkipsToday - 1)
        } else if canSkipInAdvance {
            skipNextPending = true
            advanceSkipsToday += 1
        }
    }

    func pause(for duration: TimeInterval?, now: Date = .now) {
        if case .onBreak(let session) = phase { finishBreak(session, completed: false) }
        phase = .paused(until: duration.map { now.addingTimeInterval($0) })
    }

    func resume(now: Date = .now) {
        guard case .paused = phase else { return }
        phase = .working
        onEvent?(.resumed)
    }

    func restartCycle() {
        resetCycle(keepLongCounter: false)
        if !isOnBreak, phase != .offHours { phase = .working }
    }

    func undoNaturalBreak() {
        guard let undo = undoableNaturalBreak else { return }
        workElapsed = undo.before.workElapsed
        breaksSinceLong = undo.before.breaksSinceLong
        undoableNaturalBreak = nil
    }

    // MARK: Persistence

    func snapshot(now: Date = .now) -> EngineSnapshot {
        EngineSnapshot(workElapsed: workElapsed, breaksSinceLong: breaksSinceLong, savedAt: now)
    }

    func restore(_ snapshot: EngineSnapshot, now: Date = .now) {
        // Stale snapshots mean the user has been away long enough for a fresh cycle.
        guard now.timeIntervalSince(snapshot.savedAt) < settings.idleThresholdSeconds else { return }
        workElapsed = min(snapshot.workElapsed, workTarget)
        breaksSinceLong = snapshot.breaksSinceLong
    }

    func restoreDailyCounters(advanceSkips: Int) {
        advanceSkipsToday = advanceSkips
        skipDay = calendar.startOfDay(for: .now)
    }

    // MARK: Internals

    private func finishBreak(_ session: BreakSession, completed: Bool) {
        phase = .working
        if completed {
            onEvent?(.breakEnded(session, completed: true))
        } else {
            onEvent?(.breakSkipped(session.kind, inAdvance: false))
        }
        advanceCycle(after: session.kind)
    }

    private func advanceCycle(after kind: BreakKind) {
        switch kind {
        case .long: breaksSinceLong = 0
        case .short: breaksSinceLong += 1
        case .custom: break
        }
        resetCycle(keepLongCounter: true)
    }

    private func resetCycle(keepLongCounter: Bool) {
        workElapsed = 0
        snoozesThisCycle = 0
        headsUpShown = false
        holdStarted = nil
        lastPauseEnded = nil
        if !keepLongCounter { breaksSinceLong = 0 }
    }

    private func rollDailyCounters(_ now: Date) {
        let day = calendar.startOfDay(for: now)
        if skipDay != day {
            skipDay = day
            advanceSkipsToday = 0
        }
    }

    private func clampAfterSettingsChange(_ old: Settings) {
        if workElapsed > workTarget { workElapsed = max(0, workTarget - settings.finalCountdownSeconds - 1) }
        if old.headsUpLeadSeconds != settings.headsUpLeadSeconds { headsUpShown = timeUntilBreak <= settings.headsUpLeadSeconds }
    }
}
