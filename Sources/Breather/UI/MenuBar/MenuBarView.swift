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
                .frame(width: 62, height: 62)
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.statusTitle).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(app.statusSubtitle).font(.system(size: 12)).foregroundStyle(BrandStyle.secondaryText).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .brandCard(padding: 14)

            // Icon-only, like the notch. Names show as tooltips; durations live in the tiles' menus.
            HStack(spacing: 8) {
                ActionTile("Break now", symbol: "eye.fill") { app.breakNow() }
                    .disabled(engine.isOnBreak)
                if isPaused {
                    ActionTile("Resume", symbol: "play.fill", tint: .white, active: true) { app.resume() }
                } else {
                    TileMenu(title: "Pause", symbol: "pause.fill", tint: .white) {
                        ForEach(PauseOption.all) { option in
                            Button(option.title) { app.pause(option) }
                        }
                    }
                }
                ActionTile("Skip next break", symbol: "forward.end.fill", tint: Brand.amber, active: engine.skipNextPending) {
                    engine.toggleSkipNext()
                }
                .disabled(!engine.canSkipInAdvance && !engine.skipNextPending)
                TileMenu(title: "Take a break for…", symbol: "cup.and.saucer.fill", tint: Brand.sky) {
                    ForEach([1.0, 5, 10, 15], id: \.self) { minutes in
                        Button("\(Int(minutes)) minutes") { app.customBreak(minutes: minutes) }
                    }
                    Divider()
                    Button("Long break") { engine.startBreak(kind: .long) }
                }
                .disabled(engine.isOnBreak)
            }
            .actionTileTitles(false)

            HStack(spacing: 6) {
                PillButton("", symbol: "chart.bar.fill", style: .subtle) { app.openStats() }
                    .help("Stats")
                PillButton("", symbol: "gearshape.fill", style: .subtle) { app.openSettings() }
                    .help("Settings")
                    .keyboardShortcut(",")
                Spacer()
                PillButton("", symbol: "power", style: .subtle) { NSApp.terminate(nil) }
                    .help("Quit Breather")
                    .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 300)
        .foregroundStyle(.white)
        .background(NightBackground())
        .environment(\.colorScheme, .dark)
    }

    private var isPaused: Bool {
        if case .paused = app.engine.phase { return true }
        return false
    }
}

/// A tile that opens a menu (pause durations, break lengths).
private struct TileMenu<Items: View>: View {
    var title: String
    var symbol: String
    var tint: Color
    @ViewBuilder var items: Items

    var body: some View {
        Menu {
            items
        } label: {
            ActionTile(title, symbol: symbol, tint: tint) {}.label
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .help(title)
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
