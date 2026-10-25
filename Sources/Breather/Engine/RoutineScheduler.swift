import Foundation

/// What the scheduler wants the app to do this tick.
enum RoutineEvent: Equatable {
    case remind(Reminder)
    case plannedBreakSoon(PlannedBreak, in: TimeInterval)
    case startPlannedBreak(PlannedBreak)
    /// You were busy when it was due; offer Start / Skip today instead of springing it on you.
    case plannedBreakLate(PlannedBreak)
    case plannedBreakMissed(PlannedBreak)
}

/// Reminders count *active* screen time (not idle, paused or off-hours), so a water
/// reminder never fires the moment you sit back down. Planned breaks fire at clock times.
@MainActor
final class RoutineScheduler {
    private var activeSeconds: [UUID: TimeInterval] = [:]
    private var lastNudge = Date.distantPast
    private var plannedWarned: Set<String> = []
    private let defaults: UserDefaults
    private let calendar: Calendar

    /// Planned breaks wait this long for a call to end before being marked missed.
    static let plannedGrace: TimeInterval = 45 * 60
    private static let doneKey = "planned.done"

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
    }

    func tick(now: Date, dt: TimeInterval, engine: BreakEngine) -> [RoutineEvent] {
        let s = engine.settings
        var events: [RoutineEvent] = []

        // Planned breaks first: they're tied to the clock.
        let weekday = calendar.component(.weekday, from: now) - 1
        let minute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let second = Double(minute * 60 + calendar.component(.second, from: now))
        for planned in s.plannedBreaks where planned.enabled && planned.weekdays.contains(weekday) {
            let key = dayKey(now) + planned.id.uuidString
            guard !isDone(key) else { continue }
            let due = Double(planned.minuteOfDay * 60)
            let until = due - second
            if until > 0 && until <= 120 && !plannedWarned.contains(key) {
                plannedWarned.insert(key)
                events.append(.plannedBreakSoon(planned, in: until))
            }
            guard until <= 0 else { continue }
            if -until > Self.plannedGrace {
                markDone(key)
                events.append(.plannedBreakMissed(planned))
            } else if !engine.isOnBreak, case .working = engine.phase {
                markDone(key)
                events.append(-until > 120 ? .plannedBreakLate(planned) : .startPlannedBreak(planned))
            }
            // Smart-paused (call), holding, away: keep waiting within the grace window.
        }

        // Reminders accumulate only while you're actually at the screen.
        let counting: Bool = switch engine.phase {
        case .working, .holding, .smartPaused: true
        default: false
        }
        guard counting, dt > 0, dt < 30 else { return events }
        let inCall = engine.phase.isInCall
        for reminder in s.reminders where reminder.enabled {
            let elapsed = (activeSeconds[reminder.id] ?? 0) + dt
            activeSeconds[reminder.id] = elapsed
            guard elapsed >= reminder.intervalMinutes * 60 else { continue }
            // Don't stack nudges, don't nudge right before a break, optionally not during calls.
            let quiet = now.timeIntervalSince(lastNudge) < 90 || engine.timeUntilBreak < 90 || (inCall && s.remindersPauseInCalls)
            if quiet || !events.isEmpty { continue }
            lastNudge = now
            activeSeconds[reminder.id] = 0
            events.append(.remind(reminder))
        }
        return events
    }

    /// Seconds until the next enabled planned break today, if it hasn't happened yet.
    func secondsUntilNextPlanned(now: Date, settings: Settings) -> TimeInterval? {
        let weekday = calendar.component(.weekday, from: now) - 1
        let c = calendar.dateComponents([.hour, .minute, .second], from: now)
        let second = Double((c.hour ?? 0) * 3600 + (c.minute ?? 0) * 60 + (c.second ?? 0))
        return settings.plannedBreaks
            .filter { $0.enabled && $0.weekdays.contains(weekday) && !isDone(dayKey(now) + $0.id.uuidString) }
            .map { Double($0.minuteOfDay * 60) - second }
            .filter { $0 > 0 }
            .min()
    }

    func snooze(_ id: UUID, minutes: Double, settings: Settings) {
        guard let reminder = settings.reminders.first(where: { $0.id == id }) else { return }
        activeSeconds[id] = max(0, reminder.intervalMinutes * 60 - minutes * 60)
    }

    func resetReminder(_ id: UUID) { activeSeconds[id] = 0 }

    /// A real rest (a long natural break) resets the body-related reminders.
    func didRest(for seconds: TimeInterval) {
        guard seconds >= 5 * 60 else { return }
        activeSeconds.removeAll()
    }

    // MARK: Planned-break bookkeeping

    private func dayKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(c.year!)-\(c.month!)-\(c.day!)|"
    }

    private func isDone(_ key: String) -> Bool {
        (defaults.dictionary(forKey: Self.doneKey) as? [String: Bool])?[key] == true
    }

    private func markDone(_ key: String) {
        var done = (defaults.dictionary(forKey: Self.doneKey) as? [String: Bool]) ?? [:]
        // Keep only today's entries.
        let today = dayKey(.now)
        done = done.filter { $0.key.hasPrefix(today) }
        done[key] = true
        defaults.set(done, forKey: Self.doneKey)
    }
}

extension EnginePhase {
    var isInCall: Bool {
        if case .smartPaused(let reasons) = self {
            return reasons.contains { if case .meeting = $0 { true } else if case .screenRecording = $0 { true } else { false } }
        }
        return false
    }
}

/// Runs the user's Shortcuts / AppleScripts off the main thread.
enum AutomationRunner {
    static func run(shortcut: String, script: String, language: Automations.Language = .appleScript) {
        let shortcut = shortcut.trimmingCharacters(in: .whitespaces)
        let script = script.trimmingCharacters(in: .whitespacesAndNewlines)
        DispatchQueue.global(qos: .utility).async {
            if !shortcut.isEmpty { launch("/usr/bin/shortcuts", ["run", shortcut]) }
            guard !script.isEmpty else { return }
            switch language {
            case .appleScript: launch("/usr/bin/osascript", ["-e", script])
            case .shell: launch("/bin/zsh", ["-lc", script])
            }
        }
    }

    static func shortcutNames() -> [String] {
        let pipe = Pipe()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        task.arguments = ["list"]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init).sorted()
    }

    private static func launch(_ path: String, _ args: [String]) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            NSLog("Breather: automation failed: \(error.localizedDescription)")
        }
    }
}
