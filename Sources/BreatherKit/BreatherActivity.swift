import Foundation
#if canImport(ActivityKit) && os(iOS)
import ActivityKit

/// The Live Activity shown on the iPhone Lock Screen, in the Dynamic Island,
/// and (mirrored) in the Apple Watch Smart Stack.
public struct BreatherActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public enum Mode: String, Codable, Hashable, Sendable { case working, onHold, onBreak, paused }
        public var mode: Mode
        public var title: String
        public var subtitle: String
        /// The moment the countdown runs to: next break, or end of the break.
        public var target: Date?
        /// Start of the counted interval, for progress bars.
        public var from: Date?

        public init(mode: Mode, title: String, subtitle: String, target: Date?, from: Date?) {
            self.mode = mode
            self.title = title
            self.subtitle = subtitle
            self.target = target
            self.from = from
        }
    }

    public var macName: String

    public init(macName: String) {
        self.macName = macName
    }
}

public extension BreatherActivityAttributes.ContentState {
    /// Maps the Mac's state to what the Lock Screen shows.
    init(_ state: MacState) {
        switch state.mode {
        case .onBreak:
            self.init(mode: .onBreak, title: state.breakTitle ?? (state.isLongBreak ? "Long break" : "Break"),
                      subtitle: state.breakMessage ?? "Look away from your screens.",
                      target: state.breakEnd, from: state.breakStart)
        case .working:
            let target = state.nextBreakAt
            self.init(mode: .working, title: "Next break", subtitle: state.profile.map { "\($0) · on \(state.macName)" } ?? "On \(state.macName)",
                      target: target, from: target.map { $0.addingTimeInterval(-state.workSeconds) })
        case .onHold:
            self.init(mode: .onHold, title: "Break on hold", subtitle: state.detail, target: nil, from: nil)
        case .paused, .away, .offHours:
            self.init(mode: .paused, title: state.mode == .offHours ? "Outside office hours" : "Paused",
                      subtitle: state.detail, target: state.pausedUntil, from: nil)
        }
    }
}
#endif
