import SwiftUI

struct MenuBarLabel: View {
    let app: AppModel

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: BrandImages.menuBarIcon(paused: isPaused))
            if app.store.settings.menuBarShowsTime, let text {
                Text(text).monospacedDigit()
            }
        }
    }

    private var isPaused: Bool {
        switch app.engine.phase {
        case .paused, .offHours: true
        default: false
        }
    }

    private var text: String? {
        switch app.engine.phase {
        case .working, .holding, .smartPaused: Format.short(app.engine.timeUntilBreak)
        default: nil
        }
    }
}

/// The menu bar popover, in the same night-and-glass style as the notch and the iPhone app.
struct MenuBarView: View {
    let app: AppModel

    var body: some View {
        let engine = app.engine
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                BreatherMark(color: Brand.mint, rippleOpacity: 0.6).frame(width: 18, height: 18)
                Text(Brand.name).font(.system(size: 15, weight: .semibold))
                Spacer()
                if !app.store.settings.profiles.isEmpty { ProfileRowMenu(app: app) }
            }

            HStack(spacing: 14) {
                StatusRing(progress: engine.workProgress, tone: app.tone, lineWidth: 6) {
                    Text(Format.clock(engine.timeUntilBreak))
                        .font(BrandStyle.numeral(14))
                        .contentTransition(.numericText(countsDown: true))
                }
                .frame(width: 66, height: 66)
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.statusTitle).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(app.statusSubtitle).font(.system(size: 12)).foregroundStyle(BrandStyle.secondaryText).lineLimit(2)
                }
                Spacer(minLength: 0)
                BrandStat("\(app.log.takenToday)", label: "today", tint: Brand.mint).fixedSize()
            }
            .brandCard(padding: 14)

            HStack(spacing: 8) {
                ActionTile("Break now", symbol: "eye.fill") { app.breakNow() }
                    .disabled(engine.isOnBreak)
                ActionTile(isPaused ? "Resume" : "Pause", symbol: isPaused ? "play.fill" : "pause.fill",
                           tint: .white, active: isPaused) { app.togglePause() }
                ActionTile("Skip next", symbol: "forward.end.fill", tint: Brand.amber, active: engine.skipNextPending) {
                    engine.toggleSkipNext()
                }
                .disabled(!engine.canSkipInAdvance && !engine.skipNextPending)
                ActionTile("Long break", symbol: "figure.walk", tint: Brand.sky) { engine.startBreak(kind: .long) }
                    .disabled(engine.isOnBreak)
            }

            if !engine.isOnBreak {
                PillRow(title: "Take a break for", options: [1, 5, 10, 15].map { ("\($0) min", Double($0)) }) { app.customBreak(minutes: $0) }
            }
            if !isPaused {
                PillRow(title: "Pause for", options: PauseOption.all.prefix(4).enumerated().map { ($1.shortTitle, Double($0)) }) {
                    app.pause(PauseOption.all[Int($0)])
                }
            }

            HStack(spacing: 6) {
                PillButton("Stats", symbol: "chart.bar.fill", style: .subtle) { app.openStats() }
                PillButton("Settings", symbol: "gearshape.fill", style: .subtle) { app.openSettings() }
                    .keyboardShortcut(",")
                Spacer()
                PillButton("Quit", style: .subtle) { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 340)
        .foregroundStyle(.white)
        .background(NightBackground())
        .environment(\.colorScheme, .dark)
    }

    private var isPaused: Bool {
        if case .paused = app.engine.phase { return true }
        return false
    }
}

/// A labelled row of small pill buttons.
private struct PillRow: View {
    var title: String
    var options: [(String, Double)]
    var action: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            BrandSectionLabel(title)
            HStack(spacing: 6) {
                ForEach(options, id: \.0) { option in
                    PillButton(option.0, style: .normal, stretch: true) { action(option.1) }
                }
            }
        }
    }
}

private struct ProfileRowMenu: View {
    let app: AppModel

    var body: some View {
        let active = app.activeProfile
        Menu {
            ForEach(app.store.settings.profiles) { profile in
                Button {
                    app.applyProfile(profile.id)
                } label: {
                    Label(profile.name, systemImage: profile.id == active?.id ? "checkmark" : profile.symbol)
                }
            }
            Divider()
            Button("Edit Profiles…") { app.openSettings() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: active?.symbol ?? "slider.horizontal.3").font(.system(size: 11, weight: .semibold))
                Text(active?.name ?? "Custom").font(.system(size: 12, weight: .semibold))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(BrandStyle.tertiaryText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(BrandStyle.cardFill))
            .foregroundStyle(.white)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
