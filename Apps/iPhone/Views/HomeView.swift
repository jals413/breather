import BreatherKit
import SwiftUI
#if BREATHER_PAID
import FamilyControls
#endif

struct HomeView: View {
    let model: PhoneModel
    @State private var confirmUnpair = false
    @State private var pickingApps = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                Section {
                    StatusHero(state: model.state)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    ActionGrid(model: model)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                }

                if let state = model.state {
                    Section("Today") {
                        LabeledContent("Breaks taken", value: "\(state.takenToday)")
                        LabeledContent("Screen Score", value: "\(state.score)")
                        if let profile = state.profile { LabeledContent("Profile", value: profile) }
                    }
                }

                Section {
                    Toggle("Lock Screen & Dynamic Island", isOn: $model.liveActivityEnabled)
                    Toggle("Notify me (taps your Apple Watch)", isOn: $model.notificationsEnabled)
                } header: {
                    Text("On this iPhone")
                } footer: {
                    Text(AppFlags.paid
                         ? "Breaks appear on your Lock Screen even when your iPhone is asleep."
                         : "Open Breather once a day to start the Lock Screen countdown; it then updates over Bluetooth while you're near your Mac.")
                }

                Section {
                    #if BREATHER_PAID
                    if model.blocker.isAuthorized {
                        Button("Choose Apps to Block") { pickingApps = true }
                        if model.blocker.isBlocking {
                            Button("Force Unblock", role: .destructive) { model.blocker.unblock() }
                        }
                    } else {
                        Button("Allow Screen Time Access") { Task { await model.blocker.requestAuthorization() } }
                    }
                    #else
                    Label("Block distracting apps during breaks", systemImage: "lock.fill")
                        .foregroundStyle(.secondary)
                    #endif
                } header: {
                    Text("Block apps during breaks")
                } footer: {
                    Text(AppFlags.paid
                         ? "Picked apps are blocked until your break ends. With nothing picked, everything except essentials is blocked."
                         : "Uses Screen Time, which needs an Apple Developer Program membership. It's built in and switches on with the Paid build.")
                }

                Section {
                    LabeledContent("Mac", value: model.mac?.name ?? "")
                    LabeledContent("Connected via", value: model.routes.isEmpty ? "Not connected" : model.routes.map(\.rawValue).sorted().joined(separator: " + "))
                    Button("Unpair", role: .destructive) { confirmUnpair = true }
                }
            }
            .navigationTitle("Breather")
            .confirmationDialog("Unpair from \(model.mac?.name ?? "your Mac")?", isPresented: $confirmUnpair, titleVisibility: .visible) {
                Button("Unpair", role: .destructive) { model.unpair() }
            }
            #if BREATHER_PAID
            .familyActivityPicker(isPresented: $pickingApps, selection: $model.blocker.selection)
            #endif
        }
    }
}

/// The big ring: next break (or the break itself) at a glance.
private struct StatusHero: View {
    let state: MacState?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let progress = progress(at: context.date)
            VStack(spacing: 14) {
                ZStack {
                    ProgressRing(progress: progress, color: tint, lineWidth: 12, track: .white.opacity(0.12))
                        .frame(width: 190, height: 190)
                        .animation(.linear(duration: 1), value: progress)
                    VStack(spacing: 2) {
                        if let range = state?.countdown {
                            Text(timerInterval: range, countsDown: true)
                                .font(.system(size: 44, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .multilineTextAlignment(.center)
                        } else {
                            Image(systemName: state?.symbol ?? "iphone.slash").font(.system(size: 36, weight: .medium))
                        }
                        Text(state?.headline ?? "Waiting for your Mac")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.7))
                    }
                    .frame(width: 160)
                }
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(LinearGradient(colors: [Brand.night, Brand.ocean.opacity(0.9)], startPoint: .top, endPoint: .bottom))
            )
        }
    }

    private var tint: Color {
        switch state?.mode {
        case .onBreak: Brand.mint
        case .onHold: Brand.sky
        case .working: Brand.mint
        default: .white.opacity(0.4)
        }
    }

    private var subtitle: String {
        guard let state else { return "Breather on your Mac will show up here." }
        switch state.mode {
        case .onBreak: return state.breakMessage ?? "Look away from your screens."
        default: return state.detail
        }
    }

    private func progress(at date: Date) -> Double {
        guard let range = state?.countdown else { return 0 }
        let total = range.upperBound.timeIntervalSince(range.lowerBound)
        guard total > 0 else { return 0 }
        return max(0, min(1, range.upperBound.timeIntervalSince(date) / total))
    }
}

private struct ActionGrid: View {
    let model: PhoneModel

    var body: some View {
        let mode = model.state?.mode
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            if mode == .onBreak {
                Tile(title: "+5 min", symbol: "clock.arrow.circlepath") { model.send(.snooze(minutes: 5)) }
                Tile(title: "End break", symbol: "checkmark") { model.send(.endBreak) }
            } else {
                Tile(title: "Break now", symbol: "eye.fill") { model.send(.breakNow) }
                Tile(title: "5 min break", symbol: "cup.and.saucer.fill") { model.send(.breakFor(minutes: 5)) }
            }
            if mode == .paused {
                Tile(title: "Resume", symbol: "play.fill") { model.send(.resume) }
            } else {
                Tile(title: "Pause 30 min", symbol: "pause.fill") { model.send(.pause(minutes: 30)) }
            }
            Tile(title: "Skip next", symbol: "forward.end.fill") { model.send(.skipNext) }
        }
        .disabled(!model.isConnected)
        .opacity(model.isConnected ? 1 : 0.5)
    }
}

private struct Tile: View {
    var title: String
    var symbol: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Brand.teal)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Brand.teal.opacity(0.14)))
                Text(title).font(.footnote.weight(.medium)).foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        }
        .buttonStyle(.plain)
    }
}
