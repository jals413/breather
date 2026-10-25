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

    private var onBreak: Bool { model.state?.mode == .onBreak }

    var body: some View {
        ZStack {
            if onBreak { AuroraBackground() } else { NightBackground() }
            ScrollView {
                VStack(spacing: 10) {
                    WatchHero(state: model.state)
                    actions
                }
                .padding(.horizontal, 6)
            }
        }
        .foregroundStyle(.white)
        .animation(.easeInOut(duration: 0.6), value: onBreak)
    }

    private var actions: some View {
        let mode = model.state?.mode
        let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]
        let onBreak = mode == .onBreak
        // Same four icons, same order, as the Mac and iPhone.
        return LazyVGrid(columns: columns, spacing: 6) {
            ActionTile("Break now", symbol: "eye.fill") { model.send(.breakNow) }
                .disabled(onBreak)
            if mode == .paused {
                ActionTile("Resume", symbol: "play.fill", tint: .white, active: true) { model.send(.resume) }
            } else {
                ActionTile("Pause", symbol: "pause.fill", tint: .white) { model.send(.pause(minutes: 60)) }
            }
            ActionTile("Skip next break", symbol: "forward.end.fill", tint: Brand.amber) { model.send(.skipNext) }
            ActionTile("Long break", symbol: "figure.walk", tint: Brand.sky) { model.send(.longBreak) }
                .disabled(onBreak)
        }
        .actionTileTitles(false)  // icon-only, like the notch
        .disabled(!model.phoneReachable)
    }
}

/// Same ring, tones and countdown as the notch and the iPhone.
private struct WatchHero: View {
    let state: MacState?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 6) {
                ZStack {
                    if state?.mode == .onBreak {
                        BreathingHalo(color: .white, reduceMotion: reduceMotion).frame(width: 160, height: 160)
                    }
                    StatusRing(progress: progress(context.date), tone: state?.tone(at: context.date) ?? .idle, lineWidth: 7) {
                        VStack(spacing: 1) {
                            if let range = state?.countdown {
                                Text(timerInterval: range, countsDown: true)
                                    .font(BrandStyle.numeral(26))
                                    .multilineTextAlignment(.center)
                            } else {
                                BreatherMark(color: .white).frame(width: 32, height: 32)
                            }
                            Text(state?.headline ?? "Open on iPhone")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(BrandStyle.secondaryText)
                                .lineLimit(1)
                        }
                        .frame(width: 96)
                    }
                    .frame(width: 118, height: 118)
                }
                .frame(height: 124)
                Text(subtitle(context.date))
                    .font(.system(size: 13))
                    .foregroundStyle(BrandStyle.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
    }

    private func subtitle(_ date: Date) -> String {
        guard let state else { return "Pair Breather on your iPhone." }
        if state.mode == .onBreak { return BreathCycle.inhaling(at: date) ? "Breathe in" : "Breathe out" }
        return state.detail
    }

    private func progress(_ date: Date) -> Double {
        guard let range = state?.countdown else { return 0 }
        let total = range.upperBound.timeIntervalSince(range.lowerBound)
        return total > 0 ? max(0, min(1, range.upperBound.timeIntervalSince(date) / total)) : 0
    }
}
