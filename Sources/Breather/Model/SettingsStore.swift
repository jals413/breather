import Foundation
import Observation

@MainActor
@Observable
final class SettingsStore {
    private static let key = "settings.v1"
    private let defaults: UserDefaults

    var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            save()
            onChange?(oldValue, settings)
        }
    }

    @ObservationIgnored var onChange: ((Settings, Settings) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(Settings.self, from: data) {
            settings = decoded
        } else {
            settings = Settings()
        }
    }

    func reset() { settings = Settings() }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.key)
        }
    }
}

// Tolerate settings files written by older builds: any missing key falls back to its default.
extension Settings {
    init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: AnyKey.self)
        func read<T: Decodable>(_ keyPath: WritableKeyPath<Settings, T>, _ name: String) {
            if let value = try? container.decode(T.self, forKey: AnyKey(name)) { self[keyPath: keyPath] = value }
        }
        read(\.workMinutes, "workMinutes")
        read(\.breakSeconds, "breakSeconds")
        read(\.longBreakEnabled, "longBreakEnabled")
        read(\.longBreakEvery, "longBreakEvery")
        read(\.longBreakMinutes, "longBreakMinutes")
        read(\.difficulty, "difficulty")
        read(\.balancedSkipDelaySeconds, "balancedSkipDelaySeconds")
        read(\.snoozeLimitPerBreak, "snoozeLimitPerBreak")
        read(\.dailyAdvanceSkipLimit, "dailyAdvanceSkipLimit")
        read(\.allowEndEarly, "allowEndEarly")
        read(\.endEarlyAfterFraction, "endEarlyAfterFraction")
        read(\.lockScreenOnBreak, "lockScreenOnBreak")
        read(\.shortBreakMessages, "shortBreakMessages")
        read(\.longBreakMessages, "longBreakMessages")
        read(\.background, "background")
        read(\.soundEnabled, "soundEnabled")
        read(\.breakStartSound, "breakStartSound")
        read(\.breakEndSound, "breakEndSound")
        read(\.soundVolume, "soundVolume")
        read(\.headsUpEnabled, "headsUpEnabled")
        read(\.headsUpLeadSeconds, "headsUpLeadSeconds")
        read(\.finalCountdownSeconds, "finalCountdownSeconds")
        read(\.notchLiveActivity, "notchLiveActivity")
        read(\.notchRevealSeconds, "notchRevealSeconds")
        read(\.notchHoverExpands, "notchHoverExpands")
        read(\.showMenuBarIcon, "showMenuBarIcon")
        read(\.pillOnScreensWithoutNotch, "pillOnScreensWithoutNotch")
        read(\.menuBarShowsTime, "menuBarShowsTime")
        read(\.pauseForMeetings, "pauseForMeetings")
        read(\.meetingExcludedApps, "meetingExcludedApps")
        read(\.videoMode, "videoMode")
        read(\.videoExcludedApps, "videoExcludedApps")
        read(\.pauseForFullscreenGames, "pauseForFullscreenGames")
        read(\.pauseForAnyFullscreenApp, "pauseForAnyFullscreenApp")
        read(\.pauseForScreenRecording, "pauseForScreenRecording")
        read(\.focusApps, "focusApps")
        read(\.postActivityDelaySeconds, "postActivityDelaySeconds")
        read(\.waitForTypingPause, "waitForTypingPause")
        read(\.typingLullSeconds, "typingLullSeconds")
        read(\.maxTypingDelaySeconds, "maxTypingDelaySeconds")
        read(\.idleCountsAsBreak, "idleCountsAsBreak")
        read(\.idleThresholdSeconds, "idleThresholdSeconds")
        read(\.officeHours, "officeHours")
        read(\.launchAtLogin, "launchAtLogin")
        read(\.hotKeys, "hotKeys")
    }
}

private struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}
