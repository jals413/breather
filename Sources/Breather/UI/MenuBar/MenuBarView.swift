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
    @State private var choosingProfile = false

    var body: some View {
        let engine = app.engine
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    BreatherMark(color: Brand.mint, rippleOpacity: 0.6).frame(width: 18, height: 18)
                    Text(Brand.name).font(.system(size: 15, weight: .semibold))
                    Spacer()
                    if !app.store.settings.profiles.isEmpty {
                        ProfileButton(app: app, open: $choosingProfile)
                    }
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

                // Icon-only, like the notch. Hover shows each name.
                HStack(spacing: 8) {
                    ActionTile("Break now", symbol: "eye.fill") { app.breakNow() }
                        .disabled(engine.isOnBreak)
                    ActionTile(isPaused ? "Resume" : "Pause", symbol: isPaused ? "play.fill" : "pause.fill",
                               tint: .white, active: isPaused) { app.togglePause() }
                    ActionTile("Skip next break", symbol: "forward.end.fill", tint: Brand.amber, active: engine.skipNextPending) {
                        engine.toggleSkipNext()
                    }
                    .disabled(!engine.canSkipInAdvance && !engine.skipNextPending)
                    ActionTile("Long break", symbol: "figure.walk", tint: Brand.sky) { engine.startBreak(kind: .long) }
                        .disabled(engine.isOnBreak)
                }
                .actionTileTitles(false)

                if !isPaused {
                    VStack(alignment: .leading, spacing: 7) {
                        BrandSectionLabel("Pause for")
                        HStack(spacing: 6) {
                            ForEach(PauseOption.all.prefix(4)) { option in
                                PillButton(option.shortTitle, style: .normal, stretch: true, fontSize: 11) { app.pause(option) }
                            }
                        }
                    }
                }

                footer
            }
            .padding(14)

            if choosingProfile {
                // Tap anywhere else to close.
                Color.black.opacity(0.001)
                    .onTapGesture { choosingProfile = false }
                ProfilePicker(app: app) { choosingProfile = false }
                    .padding(.top, 44)
                    .padding(.trailing, 14)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .topTrailing)))
            }
        }
        .animation(.snappy(duration: 0.18), value: choosingProfile)
        .frame(width: 300)
        .foregroundStyle(.white)
        .background(NightBackground())
        .environment(\.colorScheme, .dark)
    }

    /// Quit on the far left; devices, stats and settings on the right.
    private var footer: some View {
        let phone = app.phone
        let linked = app.store.settings.phoneLinkEnabled && !phone.devices.isEmpty
        return HStack(spacing: 6) {
            PillButton("", symbol: "power", style: .subtle, hint: "Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
            Spacer()
            if linked {
                PillButton("", symbol: "iphone", style: .subtle,
                           hint: phone.phoneConnected ? "iPhone connected" : "iPhone not connected",
                           tint: phone.phoneConnected ? Brand.mint : BrandStyle.tertiaryText) { app.openSettings() }
                PillButton("", symbol: "applewatch", style: .subtle,
                           hint: phone.phoneConnected && phone.watchConnected ? "Apple Watch connected" : "Apple Watch not connected",
                           tint: phone.phoneConnected && phone.watchConnected ? Brand.mint : BrandStyle.tertiaryText) { app.openSettings() }
            }
            PillButton("", symbol: "chart.bar.fill", style: .subtle, hint: "Stats") { app.openStats() }
            PillButton("", symbol: "gearshape.fill", style: .subtle, hint: "Settings") { app.openSettings() }
                .keyboardShortcut(",")
        }
    }

    private var isPaused: Bool {
        if case .paused = app.engine.phase { return true }
        return false
    }
}

/// The profile pill in the header; opens the in-popover picker.
private struct ProfileButton: View {
    let app: AppModel
    @Binding var open: Bool
    @State private var hovering = false

    var body: some View {
        let active = app.activeProfile
        Button { open.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: active?.symbol ?? "slider.horizontal.3").font(.system(size: 11, weight: .semibold))
                Text(active?.name ?? "Custom").font(.system(size: 12, weight: .semibold))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(BrandStyle.tertiaryText)
                    .rotationEffect(.degrees(open ? 180 : 0))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(hovering || open ? BrandStyle.cardFillHover : BrandStyle.cardFill))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pointerStyle(.link)
    }
}

/// A small dropdown drawn inside the popover, so it never spills outside it.
private struct ProfilePicker: View {
    let app: AppModel
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(app.store.settings.profiles) { profile in
                PickerRow(symbol: profile.symbol, title: profile.name,
                          checked: profile.id == app.store.settings.activeProfileID) {
                    app.applyProfile(profile.id)
                    close()
                }
            }
            Divider().overlay(BrandStyle.cardStroke).padding(.vertical, 3)
            PickerRow(symbol: "pencil", title: "Edit Profiles…", checked: false) {
                close()
                app.openSettings()
            }
        }
        .padding(5)
        .frame(width: 168)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.07, green: 0.11, blue: 0.15))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12)))
                .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
        )
    }
}

private struct PickerRow: View {
    var symbol: String
    var title: String
    var checked: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(checked ? Brand.mint : BrandStyle.secondaryText)
                    .frame(width: 16)
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer(minLength: 4)
                if checked {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Brand.mint)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hovering ? BrandStyle.cardFillHover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pointerStyle(.link)
    }
}
