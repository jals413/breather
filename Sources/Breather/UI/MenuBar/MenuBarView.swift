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

/// Control Center–style popover: a status card, round toggles, then quiet text actions.
struct MenuBarView: View {
    let app: AppModel

    var body: some View {
        let engine = app.engine
        VStack(spacing: 10) {
            StatusCard(app: app)

            HStack(spacing: 10) {
                RoundToggle(title: "Break now", symbol: "eye.fill", isOn: false) { app.breakNow() }
                    .disabled(engine.isOnBreak)
                RoundToggle(title: isPaused ? "Paused" : "Pause", symbol: "pause.fill", isOn: isPaused) { app.togglePause() }
                RoundToggle(title: "Skip next", symbol: "forward.end.fill", isOn: engine.skipNextPending, tint: Brand.amber) {
                    engine.toggleSkipNext()
                }
                .disabled(!engine.canSkipInAdvance && !engine.skipNextPending)
                RoundToggle(title: "Long break", symbol: "figure.walk", isOn: false) { engine.startBreak(kind: .long) }
                    .disabled(engine.isOnBreak)
            }
            .padding(12)
            .background(Card())

            if !app.store.settings.profiles.isEmpty {
                ProfileRowMenu(app: app)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Card())
            }

            if !isPaused {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pause for").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(PauseOption.all.prefix(4)) { option in
                            Chip(title: option.shortTitle) { app.pause(option) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Card())
            }

            HStack {
                Button("Restart timer") { engine.restartCycle() }
                Spacer()
                Button("Stats") { app.openStats() }
                Button("Settings…") { app.openSettings() }
                    .keyboardShortcut(",")
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .buttonStyle(.borderless)
            .font(.callout)
            .padding(.horizontal, 6)
            .padding(.top, 2)
        }
        .padding(12)
        .frame(width: 320)
    }

    private var isPaused: Bool {
        if case .paused = app.engine.phase { return true }
        return false
    }
}

private struct Card: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.quaternary.opacity(0.5))
    }
}

private struct StatusCard: View {
    let app: AppModel

    var body: some View {
        let engine = app.engine
        HStack(spacing: 14) {
            ZStack {
                ProgressRing(progress: engine.workProgress, color: Brand.mint, lineWidth: 5, track: .secondary.opacity(0.18))
                BreatherMark(color: .primary, rippleOpacity: 0.5)
                    .frame(width: 22, height: 22)
            }
            .frame(width: 50, height: 50)
            VStack(alignment: .leading, spacing: 3) {
                Text(app.statusTitle).font(.headline).lineLimit(1)
                Text(app.statusSubtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(app.log.takenToday)").font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("today").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Card())
    }
}

/// Round Control Center–style toggle with a label underneath.
private struct RoundToggle: View {
    var title: String
    var symbol: String
    var isOn: Bool
    var tint: Color = Brand.teal
    var action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isOn ? .white : .primary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(isOn ? AnyShapeStyle(tint) : AnyShapeStyle(.quaternary)))
                    .overlay(Circle().fill(.primary.opacity(hovering && isEnabled ? 0.08 : 0)))
                Text(title).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .opacity(isEnabled ? 1 : 0.4)
    }
}

private struct Chip: View {
    var title: String
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .background(Capsule().fill(.quaternary.opacity(hovering ? 1 : 0.6)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
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
            HStack(spacing: 10) {
                Image(systemName: active?.symbol ?? "slider.horizontal.3")
                    .foregroundStyle(Brand.teal)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Profile").font(.caption).foregroundStyle(.secondary)
                    Text(active?.name ?? "Custom").font(.callout.weight(.medium))
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }
}
