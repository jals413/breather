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
        if !defaults.bool(forKey: "profiles.seeded") {
            defaults.set(true, forKey: "profiles.seeded")
            if settings.profiles.isEmpty { settings.profiles = Profile.seeds() }
            save()
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
        read(\.appearance, "appearance")
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
        read(\.reminders, "reminders")
        read(\.remindersPauseInCalls, "remindersPauseInCalls")
        read(\.plannedBreaks, "plannedBreaks")
        read(\.automations, "automations")
        read(\.profiles, "profiles")
        read(\.activeProfileID, "activeProfileID")
        read(\.trackAppUsage, "trackAppUsage")
        read(\.trackWebsites, "trackWebsites")
        read(\.launchAtLogin, "launchAtLogin")
        read(\.hotKeys, "hotKeys")
    }
}

struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// Decodes keys one by one so adding a field never invalidates saved data.
struct TolerantDecoder {
    let container: KeyedDecodingContainer<AnyKey>
    init(_ decoder: Decoder) throws { container = try decoder.container(keyedBy: AnyKey.self) }
    func callAsFunction<Root, T: Decodable>(_ root: inout Root, _ keyPath: WritableKeyPath<Root, T>, _ name: String) {
        if let value = try? container.decode(T.self, forKey: AnyKey(name)) { root[keyPath: keyPath] = value }
    }
}

extension BreakAppearance {
    init(from decoder: Decoder) throws {
        self.init()
        let read = try TolerantDecoder(decoder)
        read(&self, \.background, "background"); read(&self, \.auroraPalette, "auroraPalette")
        read(&self, \.animateBackground, "animateBackground"); read(&self, \.solidColor, "solidColor")
        read(&self, \.gradientTop, "gradientTop"); read(&self, \.gradientBottom, "gradientBottom")
        read(&self, \.imagePath, "imagePath"); read(&self, \.imageBlur, "imageBlur"); read(&self, \.dimming, "dimming")
        read(&self, \.timerStyle, "timerStyle"); read(&self, \.timerDesign, "timerDesign"); read(&self, \.timerWeight, "timerWeight")
        read(&self, \.timerScale, "timerScale"); read(&self, \.accent, "accent"); read(&self, \.textColor, "textColor")
        read(&self, \.messageDesign, "messageDesign"); read(&self, \.messageWeight, "messageWeight")
        read(&self, \.messageScale, "messageScale"); read(&self, \.showKindLabel, "showKindLabel")
        read(&self, \.showMessage, "showMessage"); read(&self, \.showBreathingHalo, "showBreathingHalo")
        read(&self, \.showBreathingCue, "showBreathingCue"); read(&self, \.showClock, "showClock"); read(&self, \.showHint, "showHint")
    }
}
