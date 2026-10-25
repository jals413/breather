import BreatherKit
import Foundation

/// The latest Mac state, shared between the app and its widgets / complications via the
/// App Group. Widgets can't talk to the Mac themselves, so the app writes here.
enum SharedStore {
    static let groupID = "group.com.jalthakor.breather"
    private static let stateKey = "mac.state"

    static var defaults: UserDefaults { UserDefaults(suiteName: groupID) ?? .standard }

    static var state: MacState? {
        get { defaults.data(forKey: stateKey).flatMap { try? LinkCoding.decoder.decode(MacState.self, from: $0) } }
        set {
            if let newValue, let data = try? LinkCoding.encoder.encode(newValue) {
                defaults.set(data, forKey: stateKey)
            } else {
                defaults.removeObject(forKey: stateKey)
            }
        }
    }
}

/// Build-time switch for paid Apple Developer Program features (push, Screen Time).
enum AppFlags {
    static var paid: Bool {
        #if BREATHER_PAID
        true
        #else
        false
        #endif
    }
}

extension MacState {
    /// The interval the countdown is running over, if any.
    var countdown: ClosedRange<Date>? {
        switch mode {
        case .onBreak:
            guard let start = breakStart, let end = breakEnd, end > start else { return nil }
            return start...end
        case .working:
            guard let target = nextBreakAt else { return nil }
            let from = target.addingTimeInterval(-workSeconds)
            return from < target ? from...target : nil
        case .paused:
            guard let until = pausedUntil, until > .now else { return nil }
            return Date.now...until
        default:
            return nil
        }
    }

    var headline: String {
        switch mode {
        case .working: "Next break"
        case .onHold: "Break on hold"
        case .onBreak: breakTitle ?? "Break"
        case .paused: "Paused"
        case .away: "Away"
        case .offHours: "Outside office hours"
        }
    }

    var symbol: String {
        switch mode {
        case .working: "eye"
        case .onHold: "hourglass"
        case .onBreak: "sparkles"
        case .paused: "pause.fill"
        case .away: "moon.zzz.fill"
        case .offHours: "moon.fill"
        }
    }
}
