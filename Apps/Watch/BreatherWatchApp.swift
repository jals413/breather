import BreatherKit
import Observation
import SwiftUI
import WatchConnectivity
import WatchKit
import WidgetKit

@main
struct BreatherWatchApp: App {
    private let model = WatchModel.shared

    init() {
        WatchModel.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchHomeView(model: model)
        }
    }
}

/// Receives the Mac's state through the iPhone and sends button taps back the same way.
@MainActor
@Observable
final class WatchModel: NSObject {
    static let shared = WatchModel()
    private(set) var state: MacState? = SharedStore.state
    private(set) var phoneReachable = false

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ command: PhoneCommand) {
        guard let data = try? LinkCoding.encoder.encode(command) else { return }
        WCSession.default.sendMessage(["command": data], replyHandler: nil) { _ in }
        WKInterfaceDevice.current().play(.click)
    }

    fileprivate func apply(_ new: MacState) {
        let started = new.mode == .onBreak && state?.mode != .onBreak
        state = new
        SharedStore.state = new
        WidgetCenter.shared.reloadAllTimelines()
        if started { WKInterfaceDevice.current().play(.notification) }
    }
}

extension WatchModel: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        let reachable = session.isReachable
        Task { @MainActor in
            self.phoneReachable = reachable
            if let data = context["state"] as? Data, let state = try? LinkCoding.decoder.decode(MacState.self, from: data) {
                self.apply(state)
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.phoneReachable = reachable }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["state"] as? Data,
              let state = try? LinkCoding.decoder.decode(MacState.self, from: data) else { return }
        Task { @MainActor in self.apply(state) }
    }
}

struct WatchHomeView: View {
    let model: WatchModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    WatchRing(state: model.state)
                    if let state = model.state {
                        Text(state.mode == .onBreak ? (state.breakMessage ?? "Look away.") : state.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    actions
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle("Breather")
        }
    }

    @ViewBuilder
    private var actions: some View {
        let mode = model.state?.mode
        VStack(spacing: 8) {
            if mode == .onBreak {
                Button("+5 min", systemImage: "clock.arrow.circlepath") { model.send(.snooze(minutes: 5)) }
                Button("End Break", systemImage: "checkmark") { model.send(.endBreak) }
            } else {
                Button("Break Now", systemImage: "eye.fill") { model.send(.breakNow) }
                    .tint(Brand.teal)
                if mode == .paused {
                    Button("Resume", systemImage: "play.fill") { model.send(.resume) }
                } else {
                    Button("Pause 30 min", systemImage: "pause.fill") { model.send(.pause(minutes: 30)) }
                }
                Button("Skip Next", systemImage: "forward.end.fill") { model.send(.skipNext) }
            }
        }
        .disabled(!model.phoneReachable)
    }
}

private struct WatchRing: View {
    let state: MacState?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ZStack {
                ProgressRing(progress: progress(context.date), color: state?.mode == .onBreak ? Brand.mint : Brand.teal,
                             lineWidth: 8, track: .white.opacity(0.15))
                VStack(spacing: 0) {
                    if let range = state?.countdown {
                        Text(timerInterval: range, countsDown: true)
                            .font(.system(.title2, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                            .multilineTextAlignment(.center)
                    } else {
                        BreatherMark(color: .white).frame(width: 34, height: 34)
                    }
                    Text(state?.headline ?? "Open on iPhone").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 120, height: 120)
        }
    }

    private func progress(_ date: Date) -> Double {
        guard let range = state?.countdown else { return 0 }
        let total = range.upperBound.timeIntervalSince(range.lowerBound)
        return total > 0 ? max(0, min(1, range.upperBound.timeIntervalSince(date) / total)) : 0
    }
}
