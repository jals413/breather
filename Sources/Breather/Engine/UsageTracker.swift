import AppKit
import Observation

/// One day of screen habits, stored as `stats/YYYY-MM-DD.json`.
struct DailyStats: Codable, Equatable {
    var day: String
    var screenSeconds: TimeInterval = 0
    var appSeconds: [String: TimeInterval] = [:]
    var appNames: [String: String] = [:]
    var siteSeconds: [String: TimeInterval] = [:]
    /// Lengths of finished work sessions (time between real breaks).
    var sessions: [TimeInterval] = []
    var taken = 0
    var skipped = 0
    var targetSeconds: TimeInterval = 20 * 60

    var longestSession: TimeInterval { sessions.max() ?? 0 }
    var medianSession: TimeInterval {
        let sorted = sessions.sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    /// 0–100. Up to 60 for keeping sessions near your rhythm, up to 40 for taking breaks.
    func score(includingCurrent current: TimeInterval = 0) -> Int {
        let all = sessions + (current > 60 ? [current] : [])
        guard !all.isEmpty || taken + skipped > 0 else { return 0 }
        let target = max(60, targetSeconds)
        // Each session scores 1 when at or under target, decaying as it runs long.
        let discipline = all.isEmpty ? 1 : all.map { min(1, target / max($0, 1)) }.reduce(0, +) / Double(all.count)
        let total = taken + skipped
        let adherence = total == 0 ? 1 : Double(taken) / Double(total)
        return Int((discipline * 60 + adherence * 40).rounded())
    }
}

@MainActor
@Observable
final class UsageTracker {
    private(set) var today: DailyStats
    /// Work seconds since the last real break.
    private(set) var currentSession: TimeInterval = 0

    @ObservationIgnored private let dir: URL
    @ObservationIgnored private var lastSave = Date()
    @ObservationIgnored private var siteByBrowser: [String: String] = [:]
    @ObservationIgnored private var lastSiteFetch = Date.distantPast
    @ObservationIgnored private var fetching = false

    /// Browsers whose front tab can be read over Apple Events, with the script for each.
    static let browsers: [String: String] = [
        "com.apple.Safari": "tell application id \"com.apple.Safari\" to get URL of front document",
        "com.google.Chrome": chromium("com.google.Chrome"),
        "com.brave.Browser": chromium("com.brave.Browser"),
        "com.microsoft.edgemac": chromium("com.microsoft.edgemac"),
        "company.thebrowser.Browser": chromium("company.thebrowser.Browser"),
        "com.vivaldi.Vivaldi": chromium("com.vivaldi.Vivaldi"),
        "com.operasoftware.Opera": chromium("com.operasoftware.Opera"),
    ]
    private static func chromium(_ id: String) -> String {
        "tell application id \"\(id)\" to get URL of active tab of front window"
    }

    init() {
        dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Breather/stats", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let key = Self.dayKey(.now)
        today = Self.load(key, from: dir) ?? DailyStats(day: key)
        currentSession = UserDefaults.standard.double(forKey: "stats.currentSession")
    }

    func tick(now: Date, dt: TimeInterval, engine: BreakEngine, settings: Settings) {
        rollDay(now)
        today.targetSeconds = settings.workSeconds
        let active: Bool = switch engine.phase {
        case .working, .holding, .smartPaused: true
        default: false
        }
        guard active, dt > 0, dt < 30 else { return }

        today.screenSeconds += dt
        currentSession += dt

        if settings.trackAppUsage, let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier,
           app.processIdentifier != getpid() {
            today.appSeconds[id, default: 0] += dt
            if today.appNames[id] == nil { today.appNames[id] = app.localizedName ?? id }

            if settings.trackWebsites, Self.browsers[id] != nil {
                if let host = siteByBrowser[id] { today.siteSeconds[host, default: 0] += dt }
                if now.timeIntervalSince(lastSiteFetch) >= 5 { fetchSite(for: id) }
            }
        }

        if now.timeIntervalSince(lastSave) > 60 { save() }
    }

    func endSession(completed: Bool) {
        if currentSession > 60 { today.sessions.append(currentSession) }
        currentSession = 0
        if completed { today.taken += 1 }
        save()
    }

    func recordSkip() {
        today.skipped += 1
        save()
    }

    var score: Int { today.score(includingCurrent: currentSession) }

    func save() {
        lastSave = .now
        UserDefaults.standard.set(currentSession, forKey: "stats.currentSession")
        if let data = try? JSONEncoder().encode(today) {
            try? data.write(to: dir.appendingPathComponent("\(today.day).json"), options: .atomic)
        }
    }

    /// The last `days` days, oldest first, including today.
    func history(days: Int) -> [DailyStats] {
        (0..<days).reversed().map { offset in
            let date = Calendar.current.date(byAdding: .day, value: -offset, to: .now)!
            let key = Self.dayKey(date)
            return key == today.day ? today : (Self.load(key, from: dir) ?? DailyStats(day: key))
        }
    }

    // MARK: Internals

    private func rollDay(_ now: Date) {
        let key = Self.dayKey(now)
        guard key != today.day else { return }
        save()
        today = DailyStats(day: key)
    }

    private func fetchSite(for bundleID: String) {
        guard !fetching, let source = Self.browsers[bundleID] else { return }
        fetching = true
        lastSiteFetch = .now
        DispatchQueue.global(qos: .utility).async {
            let host = Self.runScript(source).flatMap { URL(string: $0)?.host() }
                .map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.fetching = false
                    if let host { self.siteByBrowser[bundleID] = host } else { self.siteByBrowser[bundleID] = nil }
                }
            }
        }
    }

    /// `osascript` in a subprocess with a timeout, so a hung browser can't stall the app.
    nonisolated private static func runScript(_ source: String) -> String? {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", source]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return nil }
        let deadline = Date().addingTimeInterval(3)
        while task.isRunning && Date() < deadline { usleep(50_000) }
        if task.isRunning { task.terminate(); return nil }
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? nil : out
    }

    static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    private static func load(_ key: String, from dir: URL) -> DailyStats? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("\(key).json")) else { return nil }
        return try? JSONDecoder().decode(DailyStats.self, from: data)
    }
}
