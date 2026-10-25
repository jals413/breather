import BreatherKit
import SwiftUI
#if BREATHER_PAID
import FamilyControls
#endif

struct HomeView: View {
    let model: PhoneModel
    @State private var confirmUnpair = false
    @State private var pickingApps = false

    private var onBreak: Bool { model.state?.mode == .onBreak }

    var body: some View {
        ZStack {
            if onBreak {
                AuroraBackground()
            } else {
                NightBackground()
            }
            ScrollView {
                VStack(spacing: 18) {
                    header
                    if model.needsRepair { repairBanner }
                    if onBreak, let state = model.state {
                        BreakHero(state: state) { model.send($0) }
                    } else {
                        StatusHero(state: model.state)
                    }
                    ActionGrid(model: model)
                    profiles
                    phoneSettings
                    blockApps
                    macCard
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            // Content fades softly under the clock instead of colliding with it.
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
        .foregroundStyle(.white)
        .animation(.easeInOut(duration: 0.6), value: onBreak)
        .confirmationDialog("Unpair from \(model.mac?.name ?? "your Mac")?", isPresented: $confirmUnpair, titleVisibility: .visible) {
            Button("Unpair", role: .destructive) { model.unpair() }
        }
        #if BREATHER_PAID
        .familyActivityPicker(isPresented: $pickingApps, selection: Bindable(model.blocker).selection)
        #endif
    }

    private var header: some View {
        HStack(spacing: 10) {
            BreatherMark(color: Brand.mint, rippleOpacity: 0.6).frame(width: 26, height: 26)
            Text(Brand.name).font(.system(size: 26, weight: .bold))
            Spacer()
            DeviceChip(symbol: "laptopcomputer", connected: model.isConnected)
            DeviceChip(symbol: "applewatch", connected: model.watchConnected)
        }
        .padding(.top, 8)
    }

    private var repairBanner: some View {
        HStack(spacing: 12) {
            BrandBadge(tone: .soon, symbol: "link.badge.plus", size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text("Pair again").font(.system(size: 15, weight: .semibold))
                Text("\(model.mac?.name ?? "Your Mac") no longer recognizes this iPhone.")
                    .font(.footnote).foregroundStyle(BrandStyle.secondaryText)
            }
            Spacer()
            PillButton("Pair", style: .primary) { model.unpair() }
        }
        .brandCard()
    }

    @ViewBuilder
    private var profiles: some View {
        if let list = model.state?.profiles, !list.isEmpty {
            VStack(spacing: 8) {
                BrandSectionLabel("Profile")
                // Left-aligned rows that wrap, so every profile is visible without scrolling.
                FlowLayout(spacing: 10) {
                    ForEach(list) { profile in
                        ProfileCard(profile: profile, active: profile.id == model.state?.activeProfileID) {
                            model.send(.setProfile(id: profile.id))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(!model.isConnected)
            }
        }
    }

    private var phoneSettings: some View {
        @Bindable var model = model
        return VStack(spacing: 8) {
            BrandSectionLabel("On this iPhone")
            VStack(spacing: 14) {
                BrandToggle("Lock Screen & Dynamic Island", detail: AppFlags.paid
                            ? "Breaks appear even when your iPhone is asleep."
                            : "Open Breather once a day to start it; it updates over Bluetooth near your Mac.",
                            isOn: $model.liveActivityEnabled)
                Divider().overlay(BrandStyle.cardStroke)
                BrandToggle("Notify me", detail: "Taps your Apple Watch when a break starts.", isOn: $model.notificationsEnabled)
            }
            .brandCard()
        }
    }

    private var blockApps: some View {
        VStack(spacing: 8) {
            BrandSectionLabel("Block apps during breaks")
            VStack(alignment: .leading, spacing: 12) {
                #if BREATHER_PAID
                if model.blocker.isAuthorized {
                    HStack {
                        PillButton("Choose Apps", symbol: "apps.iphone", style: .primary) { pickingApps = true }
                        if model.blocker.isBlocking {
                            PillButton("Force Unblock", style: .subtle) { model.blocker.unblock() }
                        }
                    }
                    Text("Picked apps are blocked until the break ends. With nothing picked, everything except essentials is.")
                        .font(.footnote).foregroundStyle(BrandStyle.secondaryText)
                } else {
                    PillButton("Allow Screen Time", symbol: "hourglass", style: .primary) {
                        Task { await model.blocker.requestAuthorization() }
                    }
                }
                #else
                HStack(spacing: 12) {
                    BrandBadge(color: .white.opacity(0.5), symbol: "lock.fill", size: 34)
                    Text("Uses Screen Time, which needs an Apple Developer Program membership. It's built in and switches on with the Paid build.")
                        .font(.footnote).foregroundStyle(BrandStyle.secondaryText)
                }
                #endif
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .brandCard()
        }
    }

    private var macCard: some View {
        HStack(spacing: 12) {
            BrandBadge(color: Brand.sky, symbol: "laptopcomputer", size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.mac?.name ?? "Mac").font(.system(size: 15, weight: .semibold))
                Text(model.routes.isEmpty ? "Not connected" : "Connected via " + model.routes.map(\.rawValue).sorted().joined(separator: " + "))
                    .font(.footnote).foregroundStyle(BrandStyle.secondaryText)
            }
            Spacer()
            PillButton("Unpair", style: .subtle) { confirmUnpair = true }
        }
        .brandCard()
    }
}

/// The ring hero while working: same ring as the notch and the Watch.
private struct StatusHero: View {
    let state: MacState?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 16) {
                StatusRing(progress: progress(state, context.date), tone: state?.tone(at: context.date) ?? .idle, lineWidth: 12) {
                    VStack(spacing: 4) {
                        if let range = state?.countdown {
                            Text(timerInterval: range, countsDown: true)
                                .font(BrandStyle.numeral(46))
                                .multilineTextAlignment(.center)
                        } else {
                            BreatherMark(color: .white).frame(width: 54, height: 54)
                        }
                        Text(state?.headline ?? "Waiting for your Mac")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(BrandStyle.secondaryText)
                    }
                    .frame(width: 170)
                }
                .frame(width: 210, height: 210)
                .animation(.linear(duration: 1), value: progress(state, context.date))

                Text(state?.detail ?? "Breather on your Mac will show up here.")
                    .font(.callout)
                    .foregroundStyle(BrandStyle.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .brandCard(padding: 0, radius: 28)
        }
    }
}

/// During a break the phone shows the Mac's break: halo, countdown, message, breathing cue.
private struct BreakHero: View {
    let state: MacState
    var send: (PhoneCommand) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 20) {
                HStack(spacing: 8) {
                    BreatherMark(color: .white.opacity(0.75), rippleOpacity: 0.6).frame(width: 16, height: 16)
                    Text((state.breakTitle ?? "Break").uppercased()).font(.system(size: 12, weight: .semibold)).tracking(3)
                }
                .foregroundStyle(BrandStyle.secondaryText)

                ZStack {
                    BreathingHalo(color: .white, reduceMotion: reduceMotion).frame(width: 290, height: 290)
                    StatusRing(progress: progress(state, context.date), tone: .rest, lineWidth: 6) {
                        if let range = state.countdown {
                            Text(timerInterval: range, countsDown: true)
                                .font(BrandStyle.numeral(52, .light))
                                .multilineTextAlignment(.center)
                                .frame(width: 170)
                        }
                    }
                    .frame(width: 210, height: 210)
                }

                Text(BreathCycle.inhaling(at: context.date) ? "Breathe in" : "Breathe out")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(BrandStyle.secondaryText)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.6), value: BreathCycle.inhaling(at: context.date))

                Text(state.breakMessage ?? "Look away from your screens.")
                    .font(.system(size: 24, weight: .semibold))
                    .multilineTextAlignment(.center)

                HStack(spacing: 10) {
                    PillButton("+5 min", symbol: "clock.arrow.circlepath", style: .normal) { send(.snooze(minutes: 5)) }
                    PillButton("End break", symbol: "checkmark", style: .primary) { send(.endBreak) }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }
}

private func progress(_ state: MacState?, _ date: Date) -> Double {
    guard let range = state?.countdown else { return 0 }
    let total = range.upperBound.timeIntervalSince(range.lowerBound)
    guard total > 0 else { return 0 }
    return max(0, min(1, range.upperBound.timeIntervalSince(date) / total))
}

/// The same four icons, in the same order, as the Mac's menu bar and notch.
private struct ActionGrid: View {
    let model: PhoneModel

    var body: some View {
        let mode = model.state?.mode
        let paused = mode == .paused
        let onBreak = mode == .onBreak
        HStack(spacing: 10) {
            ActionTile("Break now", symbol: "eye.fill") { model.send(.breakNow) }
                .disabled(onBreak)
            ActionTile(paused ? "Resume" : "Pause", symbol: paused ? "play.fill" : "pause.fill", tint: .white, active: paused) {
                model.send(paused ? .resume : .pause(minutes: 60))
            }
            ActionTile("Skip next", symbol: "forward.end.fill", tint: Brand.amber) { model.send(.skipNext) }
            ActionTile("Long break", symbol: "figure.walk", tint: Brand.sky) { model.send(.longBreak) }
                .disabled(onBreak)
        }
        .disabled(!model.isConnected)
    }
}

/// Mac / Watch connection at a glance: mint when connected.
private struct DeviceChip: View {
    var symbol: String
    var connected: Bool

    var body: some View {
        // Mint when connected; red with a slash through the icon when not.
        HStack(spacing: 5) {
            Image(systemName: connected ? symbol : symbol + ".slash").font(.system(size: 12, weight: .semibold))
            Circle().frame(width: 6, height: 6)
        }
        .foregroundStyle(connected ? Brand.mint : Brand.alert)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Capsule().fill(BrandStyle.cardFill))
        .accessibilityLabel(connected ? "Connected" : "Not connected")
    }
}

private struct ProfileCard: View {
    let profile: ProfileSummary
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                BrandBadge(color: active ? Brand.mint : .white.opacity(0.75), symbol: profile.symbol, size: 36)
                Text(profile.name).font(.system(size: 15, weight: .semibold)).lineLimit(1).fixedSize()
                if active {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.mint)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: BrandStyle.tileRadius, style: .continuous)
                    .fill(active ? Brand.mint.opacity(0.12) : BrandStyle.cardFill)
                    .overlay(RoundedRectangle(cornerRadius: BrandStyle.tileRadius, style: .continuous)
                        .strokeBorder(active ? Brand.mint.opacity(0.6) : BrandStyle.cardStroke, lineWidth: active ? 1.5 : 1))
            )
        }
        .buttonStyle(.plain)
    }
}

/// A toggle styled for the night cards.
private struct BrandToggle: View {
    var title: String
    var detail: String
    @Binding var isOn: Bool

    init(_ title: String, detail: String, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        _isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(detail).font(.footnote).foregroundStyle(BrandStyle.secondaryText)
            }
        }
        .tint(Brand.mint)
    }
}

/// Places views left to right, wrapping onto new rows when they run out of width.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows = [Row()]
        for (i, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(i)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
