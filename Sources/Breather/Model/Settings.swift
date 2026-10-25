import Foundation

enum SkipDifficulty: String, Codable, CaseIterable, Identifiable {
    case casual, balanced, hardcore
    var id: String { rawValue }
    var title: String {
        switch self {
        case .casual: "Casual"
        case .balanced: "Balanced"
        case .hardcore: "Hardcore"
        }
    }
    var detail: String {
        switch self {
        case .casual: "Skip any break, any time."
        case .balanced: "Skip unlocks after a few seconds."
        case .hardcore: "Breaks can't be skipped or snoozed."
        }
    }
}

enum VideoPauseMode: String, Codable, CaseIterable, Identifiable {
    case off, frontmost, background
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: "Off"
        case .frontmost: "Only when the player is frontmost"
        case .background: "Also when playing in the background"
        }
    }
}

enum FocusAppMode: String, Codable, CaseIterable, Identifiable {
    case fullscreen, foreground, open
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fullscreen: "Frontmost & fullscreen"
        case .foreground: "Frontmost"
        case .open: "Whenever open"
        }
    }
}

struct FocusApp: Codable, Hashable, Identifiable {
    var bundleID: String
    var name: String
    var mode: FocusAppMode = .foreground
    var id: String { bundleID }
}

struct ExcludedApp: Codable, Hashable, Identifiable {
    var bundleID: String
    var name: String
    var id: String { bundleID }
}

struct Settings: Codable, Equatable {
    // Timing
    var workMinutes: Double = 20
    var breakSeconds: Double = 20
    var longBreakEnabled = true
    /// A long break replaces the next break after this many short breaks.
    var longBreakEvery = 3
    var longBreakMinutes: Double = 5

    // Break behaviour
    var difficulty: SkipDifficulty = .balanced
    var balancedSkipDelaySeconds: Double = 5
    var snoozeLimitPerBreak = 3
    var dailyAdvanceSkipLimit = 3
    var allowEndEarly = true
    /// Fraction of the break after which "End Break" replaces "Skip".
    var endEarlyAfterFraction = 0.5
    var lockScreenOnBreak = false
    /// When the timer ends, wait for "End break" instead of closing on its own.
    var keepBreakOpenUntilEnded = false
    var customBreakMinutes: Double = 5
    /// Nudge when you've gone this long past your rhythm without a real break.
    var overtimeNudge = true
    var overtimeNudgeMinutes: Double = 15
    var shortBreakMessages = [
        "Look at something 20 feet away.",
        "Blink slowly. Let your eyes go soft.",
        "Roll your shoulders and breathe out.",
        "Find the farthest thing you can see.",
    ]
    var longBreakMessages = [
        "Stand up, stretch, refill your water.",
        "Take a short walk. The screen will wait.",
        "Step away and rest your eyes properly.",
    ]
    var appearance = BreakAppearance()

    // Sound
    var soundEnabled = true
    var breakStartSound = "Purr"
    var breakEndSound = "Glass"
    /// Empty = same as the short break sound. A name is a system sound; a path is your own file.
    var longBreakStartSound = ""
    var soundVolume = 0.35

    // Heads-up & notch
    var headsUpEnabled = true
    var headsUpLeadSeconds: Double = 60
    var finalCountdownSeconds: Double = 5
    /// Countdown "ears" beside the notch.
    var notchLiveActivity = true
    /// Show the ears only this long before a break; 0 = always.
    var notchRevealSeconds: Double = 0
    var notchHoverExpands = true
    var pillOnScreensWithoutNotch = true
    var alertDisplay: AlertDisplay = .notch
    var showMenuBarIcon = true
    var menuBarShowsTime = false

    // Smart pause
    var pauseForMeetings = true
    var meetingExcludedApps: [ExcludedApp] = []
    var videoMode: VideoPauseMode = .frontmost
    var videoExcludedApps: [ExcludedApp] = []
    var pauseForFullscreenGames = true
    var pauseForAnyFullscreenApp = false
    var pauseForScreenRecording = true
    var focusApps: [FocusApp] = [
        FocusApp(bundleID: "com.apple.iWork.Keynote", name: "Keynote", mode: .fullscreen),
    ]
    /// After a pausing activity ends, wait this long before a due break starts.
    var postActivityDelaySeconds: Double = 60

    // Smarter interruptions
    var waitForTypingPause = true
    /// Seconds without typing/dragging that count as a pause.
    var typingLullSeconds: Double = 3
    /// Never hold a break longer than this waiting for a lull.
    var maxTypingDelaySeconds: Double = 120
    var idleCountsAsBreak = true
    /// No input for this long means you're away (timer stops, away time can count as a break).
    var idleThresholdSeconds: Double = 120

    // Schedule
    var officeHours = OfficeHours()

    // Routines
    var reminders = Reminder.defaults
    var remindersPauseInCalls = true
    var plannedBreaks: [PlannedBreak] = [.lunch]
    var automations = Automations()

    // Profiles
    /// Seeded with starter profiles on first launch (see SettingsStore).
    var profiles: [Profile] = []
    var activeProfileID: UUID?

    // Stats
    var trackAppUsage = true
    /// Reads the front tab's address in Safari & Chromium browsers (asks for Automation permission).
    var trackWebsites = false

    // iPhone & Apple Watch
    var phoneLinkEnabled = false
    var phoneBlockDuringBreaks = true
    var apnsTeamID = ""
    var apnsKeyID = ""
    var apnsKeyPath = ""

    // System
    /// Once a day, ask GitHub whether a newer release exists. The only network request Breather makes.
    var checkForUpdates = true
    var launchAtLogin = false
    var hotKeys = HotKeySettings()

    var workSeconds: TimeInterval { workMinutes * 60 }
    var longBreakSeconds: TimeInterval { longBreakMinutes * 60 }
}

enum AlertDisplay: String, Codable, CaseIterable, Identifiable {
    case notch, main, mouse
    var id: String { rawValue }
    var title: String {
        switch self {
        case .notch: "The display with a notch"
        case .main: "The main display"
        case .mouse: "The display with the pointer"
        }
    }
}

struct HotKeySettings: Codable, Equatable {
    var breakNow = HotKey(keyCode: 11, modifiers: [.control, .option, .command])      // ⌃⌥⌘B
    var togglePause = HotKey(keyCode: 35, modifiers: [.control, .option, .command])   // ⌃⌥⌘P
    var skipNext = HotKey(keyCode: 1, modifiers: [.control, .option, .command])       // ⌃⌥⌘S
    var customBreak = HotKey(keyCode: 17, modifiers: [.control, .option, .command])   // ⌃⌥⌘T
}

struct HotKey: Codable, Equatable {
    enum Modifier: String, Codable, CaseIterable { case control, option, shift, command }
    var keyCode: UInt32
    var modifiers: Set<Modifier>
    var enabled = true
}

/// Presets offered in General settings.
struct TimingPreset: Identifiable {
    let id: String
    let workMinutes: Double
    let breakSeconds: Double
    let longEvery: Int
    let longMinutes: Double

    static let all = [
        TimingPreset(id: "Eye Care (20-20-20)", workMinutes: 20, breakSeconds: 20, longEvery: 3, longMinutes: 5),
        TimingPreset(id: "Balanced", workMinutes: 25, breakSeconds: 30, longEvery: 3, longMinutes: 5),
        TimingPreset(id: "Deep Focus", workMinutes: 45, breakSeconds: 45, longEvery: 2, longMinutes: 5),
        TimingPreset(id: "Wellness", workMinutes: 15, breakSeconds: 15, longEvery: 4, longMinutes: 3),
    ]
}
