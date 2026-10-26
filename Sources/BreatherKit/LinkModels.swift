import CryptoKit
import Foundation

/// What the Mac tells its paired iPhone / Watch. Compact on purpose: it travels over Bluetooth.
public struct MacState: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, Sendable {
        /// Counting toward the next break.
        case working
        /// A break is due but waiting (typing, a call, a video…).
        case onHold
        case paused
        case away
        case offHours
        case onBreak
    }

    public var mode: Mode
    /// Human status, e.g. "In a call · Zoom".
    public var detail: String
    public var nextBreakAt: Date?
    public var breakStart: Date?
    public var breakEnd: Date?
    public var breakTitle: String?
    public var breakMessage: String?
    public var isLongBreak: Bool
    public var pausedUntil: Date?
    public var takenToday: Int
    public var score: Int
    /// Work interval, for drawing progress rings.
    public var workSeconds: TimeInterval
    public var profile: String?
    public var macName: String
    /// Whether the phone should block distracting apps during this break.
    public var blockPhone: Bool
    public var sentAt: Date
    /// The Mac's saved profiles, so the phone can show and switch them.
    public var profiles: [ProfileSummary]?
    public var activeProfileID: String?

    public init(mode: Mode, detail: String, nextBreakAt: Date? = nil, breakStart: Date? = nil, breakEnd: Date? = nil,
                breakTitle: String? = nil, breakMessage: String? = nil, isLongBreak: Bool = false, pausedUntil: Date? = nil,
                takenToday: Int = 0, score: Int = 0, workSeconds: TimeInterval = 1200, profile: String? = nil,
                macName: String, blockPhone: Bool = false, sentAt: Date = .now) {
        self.mode = mode
        self.detail = detail
        self.nextBreakAt = nextBreakAt
        self.breakStart = breakStart
        self.breakEnd = breakEnd
        self.breakTitle = breakTitle
        self.breakMessage = breakMessage
        self.isLongBreak = isLongBreak
        self.pausedUntil = pausedUntil
        self.takenToday = takenToday
        self.score = score
        self.workSeconds = workSeconds
        self.profile = profile
        self.macName = macName
        self.blockPhone = blockPhone
        self.sentAt = sentAt
    }

    /// True when two states differ enough to be worth sending (ignores clock drift).
    public func differsMeaningfully(from other: MacState?) -> Bool {
        guard let other else { return true }
        if mode != other.mode || detail != other.detail || breakEnd != other.breakEnd || pausedUntil != other.pausedUntil
            || takenToday != other.takenToday || profile != other.profile || blockPhone != other.blockPhone
            || activeProfileID != other.activeProfileID || profiles != other.profiles {
            return true
        }
        switch (nextBreakAt, other.nextBreakAt) {
        case let (a?, b?): return abs(a.timeIntervalSince(b)) > 5
        case (nil, nil): return false
        default: return true
        }
    }

    public static let preview = MacState(mode: .working, detail: "Break in 12 min", nextBreakAt: .now.addingTimeInterval(720),
                                         takenToday: 6, score: 84, profile: "Everyday", macName: "MacBook Pro")
    public static let previewBreak = MacState(mode: .onBreak, detail: "Short break", breakStart: .now,
                                              breakEnd: .now.addingTimeInterval(20), breakTitle: "Short break",
                                              breakMessage: "Look at something 20 feet away.", takenToday: 6, score: 84,
                                              macName: "MacBook Pro", blockPhone: true)
}

public struct ProfileSummary: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var symbol: String
    public init(id: String, name: String, symbol: String) {
        self.id = id
        self.name = name
        self.symbol = symbol
    }
}

/// A day-and-week summary of screen habits, sent to the phone for its Stats dashboard.
public struct StatsSnapshot: Codable, Equatable, Sendable {
    public struct Day: Codable, Equatable, Sendable, Identifiable {
        public var day: String          // yyyy-MM-dd
        public var screenSeconds: TimeInterval
        public var score: Int
        public var taken: Int
        public var skipped: Int
        public var id: String { day }
        public init(day: String, screenSeconds: TimeInterval, score: Int, taken: Int, skipped: Int) {
            self.day = day
            self.screenSeconds = screenSeconds
            self.score = score
            self.taken = taken
            self.skipped = skipped
        }
    }

    public struct Usage: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var seconds: TimeInterval
        public init(id: String, name: String, seconds: TimeInterval) {
            self.id = id
            self.name = name
            self.seconds = seconds
        }
    }

    public var score: Int
    /// Out of 60: how close work stretches stay to the rhythm.
    public var rhythmPoints: Int
    /// Out of 40: breaks taken vs skipped.
    public var breakPoints: Int
    public var screenSeconds: TimeInterval
    public var taken: Int
    public var skipped: Int
    public var longestSession: TimeInterval
    public var medianSession: TimeInterval
    public var currentSession: TimeInterval
    public var targetSeconds: TimeInterval
    /// Oldest first, including today.
    public var week: [Day]
    public var topApps: [Usage]
    public var topSites: [Usage]
    public var macName: String
    public var generatedAt: Date

    public init(score: Int, rhythmPoints: Int, breakPoints: Int, screenSeconds: TimeInterval, taken: Int, skipped: Int,
                longestSession: TimeInterval, medianSession: TimeInterval, currentSession: TimeInterval,
                targetSeconds: TimeInterval, week: [Day], topApps: [Usage], topSites: [Usage], macName: String,
                generatedAt: Date = .now) {
        self.score = score
        self.rhythmPoints = rhythmPoints
        self.breakPoints = breakPoints
        self.screenSeconds = screenSeconds
        self.taken = taken
        self.skipped = skipped
        self.longestSession = longestSession
        self.medianSession = medianSession
        self.currentSession = currentSession
        self.targetSeconds = targetSeconds
        self.week = week
        self.topApps = topApps
        self.topSites = topSites
        self.macName = macName
        self.generatedAt = generatedAt
    }
}

/// What the phone or Watch can ask the Mac to do.
public enum PhoneCommand: Codable, Equatable, Sendable {
    case breakNow
    case longBreak
    case setProfile(id: String)
    case breakFor(minutes: Double)
    case snooze(minutes: Double)
    case skipNext
    case pause(minutes: Double?)
    case resume
    case endBreak
}

/// Push credentials the phone hands the Mac (paid builds only).
public struct PushTokens: Codable, Equatable, Sendable {
    public var deviceToken: String?
    public var liveActivityStartToken: String?
    public var bundleID: String
    public var sandbox: Bool
    public init(deviceToken: String?, liveActivityStartToken: String?, bundleID: String, sandbox: Bool) {
        self.deviceToken = deviceToken
        self.liveActivityStartToken = liveActivityStartToken
        self.bundleID = bundleID
        self.sandbox = sandbox
    }
}

/// What paired devices say to each other. Always travels encrypted (see `LinkCrypto`).
public enum LinkMessage: Codable, Equatable, Sendable {
    /// Phone → Mac: "I'm here, send me the current state." Also marks the connection as this phone's.
    case hello(deviceName: String)
    case state(MacState)
    case command(PhoneCommand)
    case tokens(PushTokens)
    /// Phone → Mac: whether its Apple Watch has Breather and can be reached.
    case deviceStatus(watchConnected: Bool)
    /// Mac → phone: today's and this week's stats for the dashboard.
    case stats(StatsSnapshot)
    /// Mac → phone: a small PNG app icon for the Stats dashboard, sent once per app.
    case appIcon(id: String, png: Data)
}

public enum LinkCoding {
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()
    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()
}

public extension SymmetricKey {
    init?(base64: String) {
        guard let data = Data(base64Encoded: base64) else { return nil }
        self.init(data: data)
    }

    var base64: String { withUnsafeBytes { Data($0).base64EncodedString() } }
}
