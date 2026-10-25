import ActivityKit
import BreatherKit
import Foundation

/// Keeps one Live Activity mirroring the Mac. iOS only lets an app *start* a Live Activity
/// while it's open (or via push-to-start in paid builds); once running it can be updated
/// from the background whenever Bluetooth wakes the app.
@MainActor
final class LiveActivityController {
    var onTokens: ((PushTokens) -> Void)?
    private var tokenTask: Task<Void, Never>?
    private var lastStartToken: String?

    init() {
        #if BREATHER_PAID
        tokenTask = Task { [weak self] in
            for await data in Activity<BreatherActivityAttributes>.pushToStartTokenUpdates {
                let token = data.map { String(format: "%02x", $0) }.joined()
                self?.lastStartToken = token
                self?.sendTokensIfAvailable()
            }
        }
        #endif
    }

    private var current: Activity<BreatherActivityAttributes>? {
        Activity<BreatherActivityAttributes>.activities.first { $0.activityState == .active || $0.activityState == .stale }
    }

    func sync(_ state: MacState, previous: MacState?, enabled: Bool, appActive: Bool) {
        guard enabled, ActivityAuthorizationInfo().areActivitiesEnabled else {
            endAll()
            return
        }
        let content = ActivityContent(state: BreatherActivityAttributes.ContentState(state),
                                      staleDate: staleDate(for: state), relevanceScore: state.mode == .onBreak ? 100 : 50)
        let breakStarted = state.mode == .onBreak && previous?.mode != .onBreak
        if let activity = current {
            Task {
                // Lighting up the Lock Screen (and tapping the Watch) only when a break begins.
                await activity.update(content, alertConfiguration: breakStarted
                    ? AlertConfiguration(title: "\(state.breakTitle ?? "Break") time",
                                         body: "\(state.breakMessage ?? "Look away from your screens.")", sound: .default)
                    : nil)
            }
        } else if appActive {
            _ = try? Activity.request(attributes: BreatherActivityAttributes(macName: state.macName), content: content,
                                      pushType: AppFlags.paid ? .token : nil)
        }
    }

    func endAll() {
        for activity in Activity<BreatherActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    func sendTokensIfAvailable() {
        #if BREATHER_PAID
        let tokens = PushTokens(deviceToken: PushRegistration.deviceToken, liveActivityStartToken: lastStartToken,
                                bundleID: Bundle.main.bundleIdentifier ?? "", sandbox: PushRegistration.isSandbox)
        onTokens?(tokens)
        #endif
    }

    /// If the Mac goes quiet (out of range), show the activity as stale instead of a wrong countdown.
    private func staleDate(for state: MacState) -> Date? {
        switch state.mode {
        case .onBreak: state.breakEnd?.addingTimeInterval(60)
        case .working: state.nextBreakAt?.addingTimeInterval(120)
        default: nil
        }
    }
}

/// APNs device token, recorded by the app delegate (paid builds).
enum PushRegistration {
    nonisolated(unsafe) static var deviceToken: String?
    static var isSandbox: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}
