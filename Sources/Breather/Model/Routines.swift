import Foundation

/// A gentle nudge that isn't a break: drink water, fix posture, blink, stand up.
struct Reminder: Codable, Identifiable, Equatable {
    var id = UUID()
    var enabled = true
    var title: String
    var message: String
    var symbol: String
    var tint: RGBA
    /// Minutes of active screen time between nudges.
    var intervalMinutes: Double
    var laterMinutes: Double = 10
    var sound: String? = nil

    static let defaults: [Reminder] = [
        Reminder(title: "Drink water", message: "Have a few sips.", symbol: "drop.fill",
                 tint: RGBA(0.35, 0.72, 1), intervalMinutes: 45),
        Reminder(enabled: false, title: "Check posture", message: "Shoulders down, back straight.", symbol: "figure.stand",
                 tint: RGBA(0.62, 0.55, 1), intervalMinutes: 30),
        Reminder(enabled: false, title: "Blink", message: "Ten slow blinks.", symbol: "eye",
                 tint: RGBA(0.40, 0.91, 0.76), intervalMinutes: 15),
        Reminder(enabled: false, title: "Stand up", message: "Stand for a few minutes.", symbol: "figure.walk",
                 tint: RGBA(1, 0.72, 0.33), intervalMinutes: 60),
        Reminder(enabled: false, title: "Stretch", message: "Neck, wrists, back.", symbol: "figure.flexibility",
                 tint: RGBA(1, 0.5, 0.55), intervalMinutes: 90),
    ]

    static let symbolChoices = [
        "drop.fill", "figure.stand", "eye", "figure.walk", "figure.flexibility", "cup.and.saucer.fill",
        "pills.fill", "lungs.fill", "hand.raised.fill", "sun.max.fill", "leaf.fill", "bell.fill",
    ]
}

/// A break at a fixed time of day, like lunch.
struct PlannedBreak: Codable, Identifiable, Equatable {
    var id = UUID()
    var enabled = true
    var title: String
    var message: String
    var minuteOfDay: Int
    var durationMinutes: Double
    /// 0 = Sunday … 6 = Saturday.
    var weekdays: Set<Int> = [1, 2, 3, 4, 5]

    static let lunch = PlannedBreak(enabled: false, title: "Lunch", message: "Step away and enjoy your lunch.",
                                    minuteOfDay: 13 * 60, durationMinutes: 30)
}

/// Run a Shortcut or AppleScript when breaks start and end.
struct Automations: Codable, Equatable {
    var enabled = false
    var startShortcut = ""
    var endShortcut = ""
    var startScript = ""
    var endScript = ""
}

/// A saved set of the settings people switch between (e.g. Deep Work vs Everyday).
struct ProfileValues: Codable, Equatable {
    var workMinutes: Double
    var breakSeconds: Double
    var longBreakEnabled: Bool
    var longBreakEvery: Int
    var longBreakMinutes: Double
    var difficulty: SkipDifficulty
    var headsUpEnabled: Bool
    var waitForTypingPause: Bool
    var appearance: BreakAppearance

    init(from s: Settings) {
        workMinutes = s.workMinutes
        breakSeconds = s.breakSeconds
        longBreakEnabled = s.longBreakEnabled
        longBreakEvery = s.longBreakEvery
        longBreakMinutes = s.longBreakMinutes
        difficulty = s.difficulty
        headsUpEnabled = s.headsUpEnabled
        waitForTypingPause = s.waitForTypingPause
        appearance = s.appearance
    }

    func apply(to s: inout Settings) {
        s.workMinutes = workMinutes
        s.breakSeconds = breakSeconds
        s.longBreakEnabled = longBreakEnabled
        s.longBreakEvery = longBreakEvery
        s.longBreakMinutes = longBreakMinutes
        s.difficulty = difficulty
        s.headsUpEnabled = headsUpEnabled
        s.waitForTypingPause = waitForTypingPause
        s.appearance = appearance
    }
}

struct Profile: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var symbol: String
    var values: ProfileValues
    /// Switch to this profile while one of these apps is frontmost.
    var triggerApps: [ExcludedApp] = []

    static let symbolChoices = [
        "sun.max.fill", "brain.head.profile.fill", "leaf.fill", "laptopcomputer", "paintbrush.pointed.fill",
        "book.fill", "gamecontroller.fill", "person.2.fill", "moon.fill", "bolt.fill",
    ]

    static func seeds() -> [Profile] {
        let base = Settings()
        var deep = base
        deep.workMinutes = 45; deep.breakSeconds = 45; deep.longBreakEvery = 2
        var deepLook = BreakTheme.all.first { $0.id == "Midnight Minimal" }!.appearance
        deepLook.showKindLabel = true
        deep.appearance = deepLook
        var gentle = base
        gentle.workMinutes = 30; gentle.difficulty = .casual
        gentle.appearance = BreakTheme.all.first { $0.id == "Forest" }!.appearance
        return [
            Profile(name: "Everyday", symbol: "sun.max.fill", values: ProfileValues(from: base)),
            Profile(name: "Deep Work", symbol: "brain.head.profile.fill", values: ProfileValues(from: deep)),
            Profile(name: "Gentle", symbol: "leaf.fill", values: ProfileValues(from: gentle)),
        ]
    }
}
