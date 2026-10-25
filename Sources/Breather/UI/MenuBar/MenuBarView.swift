import SwiftUI

struct MenuBarLabel: View {
    let app: AppModel

    var body: some View {
        let settings = app.store.settings
        HStack(spacing: 4) {
            Image(systemName: symbol)
            if settings.menuBarShowsTime, let text {
                Text(text).monospacedDigit()
            }
        }
    }

    private var symbol: String {
        switch app.engine.phase {
        case .paused, .offHours: "eye.slash"
        case .smartPaused: "eye.trianglebadge.exclamationmark"
        case .onBreak: "eye.fill"
        default: "eye"
        }
    }

    private var text: String? {
        switch app.engine.phase {
        case .working, .holding, .smartPaused: Format.short(app.engine.timeUntilBreak)
        case .paused: "Paused"
        default: nil
        }
    }
}

struct MenuBarView: View {
    let app: AppModel

    var body: some View {
        let engine = app.engine
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    ProgressRing(progress: engine.workProgress, color: .breatherMint, lineWidth: 4, track: .secondary.opacity(0.2))
                    Image(systemName: "eye").font(.system(size: 13, weight: .semibold))
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.statusTitle).font(.headline)
                    Text(app.statusSubtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }

            HStack {
                Label("\(app.log.takenToday) taken", systemImage: "checkmark.circle")
                Spacer()
                Label("\(app.log.skippedToday) skipped", systemImage: "forward")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()

            VStack(spacing: 2) {
                MenuRow(title: "Take a break now", symbol: "eye", shortcut: app.store.settings.hotKeys.breakNow) { app.breakNow() }
                    .disabled(engine.isOnBreak)
                MenuRow(title: "Take a long break", symbol: "figure.walk") { engine.startBreak(kind: .long) }
                    .disabled(engine.isOnBreak)
                if engine.skipNextPending {
                    MenuRow(title: "Don't skip next break", symbol: "arrow.uturn.backward", shortcut: app.store.settings.hotKeys.skipNext) { engine.toggleSkipNext() }
                } else {
                    MenuRow(title: "Skip next break", symbol: "forward.end", shortcut: app.store.settings.hotKeys.skipNext) { engine.toggleSkipNext() }
                        .disabled(!engine.canSkipInAdvance)
                }
                MenuRow(title: "Restart timer", symbol: "arrow.counterclockwise") { engine.restartCycle() }
            }

            Divider()

            if case .paused = engine.phase {
                MenuRow(title: "Resume", symbol: "play.fill", shortcut: app.store.settings.hotKeys.togglePause) { app.resume() }
            } else {
                Text("Pause").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8)
                VStack(spacing: 2) {
                    ForEach(PauseOption.all) { option in
                        MenuRow(title: option.title, symbol: "pause") { app.pause(option) }
                    }
                }
            }

            Divider()

            HStack {
                Button("Settings…") { app.openSettings() }
                    .keyboardShortcut(",")
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 8)
        }
        .padding(14)
        .frame(width: 290)
    }
}

struct MenuRow: View {
    var title: String
    var symbol: String
    var shortcut: HotKey? = nil
    var action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).frame(width: 18)
                Text(title)
                Spacer()
                if let shortcut, shortcut.enabled {
                    Text(shortcut.displayString).foregroundStyle(.secondary).font(.caption)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(hovering && isEnabled ? Color.accentColor.opacity(0.18) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .opacity(isEnabled ? 1 : 0.45)
    }
}
