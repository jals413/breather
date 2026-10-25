import SwiftUI

enum Format {
    /// "12m", "45s", "1h 05m".
    static func short(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        if s < 60 { return "\(s)s" }
        let m = Int((Double(s) / 60).rounded(.up))
        if m < 60 { return "\(m)m" }
        return String(format: "%dh %02dm", m / 60, m % 60)
    }

    /// "12:04", "0:45".
    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// "58s", "12 min", "1 hr 5 min" — for tight headlines.
    static func compact(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        if s < 60 { return "\(s)s" }
        let m = Int((Double(s) / 60).rounded(.up))
        if m < 60 { return "\(m) min" }
        return m % 60 == 0 ? "\(m / 60) hr" : "\(m / 60) hr \(m % 60) min"
    }

    /// "20 seconds", "5 minutes".
    static func spoken(_ seconds: TimeInterval) -> String {
        let f = DateComponentsFormatter()
        f.unitsStyle = .full
        f.allowedUnits = seconds >= 3600 ? [.hour, .minute] : seconds >= 60 ? [.minute] : [.second]
        f.maximumUnitCount = 2
        return f.string(from: seconds.rounded()) ?? ""
    }
}

