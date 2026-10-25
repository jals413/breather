import AppKit
import SwiftUI

struct WelcomeView: View {
    let app: AppModel
    var onDone: () -> Void

    var body: some View {
        @Bindable var store = app.store
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                BreatherAppIcon().frame(width: 96, height: 96)
                Text("Welcome to \(Brand.name)").font(.system(size: 28, weight: .bold))
                Text(Brand.tagline).font(.title3).foregroundStyle(.secondary)
            }
            .padding(.top, 36)

            VStack(alignment: .leading, spacing: 20) {
                Feature(symbol: "rectangle.topthird.inset.filled", tint: Brand.teal, title: "Lives in your notch",
                        detail: "A heads-up grows out of the notch before each break. Hover the notch to peek at your next one.")
                Feature(symbol: "brain.head.profile.fill", tint: .indigo, title: "Knows when not to interrupt",
                        detail: "Breaks wait while you're in a call, watching a video, presenting, or mid-sentence.")
                Feature(symbol: "figure.walk", tint: Brand.mint, title: "Counts real rest",
                        detail: "Step away from your Mac and that time counts as a break, so you won't be asked again right after.")
                Feature(symbol: "lock.shield.fill", tint: .gray, title: "Private by design",
                        detail: "No account, no tracking, no network. Everything stays on this Mac.")
            }
            .padding(.horizontal, 48)
            .padding(.top, 30)

            Spacer(minLength: 20)

            VStack(spacing: 12) {
                Picker("Rhythm", selection: presetBinding) {
                    ForEach(TimingPreset.all) { Text($0.id).tag($0.id) }
                }
                .pickerStyle(.menu)
                .frame(width: 280)
                Toggle("Open Breather when I log in", isOn: $store.settings.launchAtLogin)
                    .toggleStyle(.checkbox)
                Button {
                    onDone()
                } label: {
                    Text("Get Started").frame(width: 240)
                }
                .buttonStyle(.glassProminent)
                .tint(Brand.teal)
                .controlSize(.extraLarge)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.bottom, 32)
        }
        .frame(width: 560, height: 640)
    }

    private var presetBinding: Binding<String> {
        Binding {
            let s = app.store.settings
            return TimingPreset.all.first { $0.workMinutes == s.workMinutes && $0.breakSeconds == s.breakSeconds }?.id
                ?? TimingPreset.all[0].id
        } set: { id in
            guard let p = TimingPreset.all.first(where: { $0.id == id }) else { return }
            app.store.settings.workMinutes = p.workMinutes
            app.store.settings.breakSeconds = p.breakSeconds
            app.store.settings.longBreakEvery = p.longEvery
            app.store.settings.longBreakMinutes = p.longMinutes
        }
    }
}

private struct Feature: View {
    var symbol: String
    var tint: Color
    var title: String
    var detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

@MainActor
final class WelcomeWindowController {
    private var window: NSWindow?

    func show(app: AppModel, onDone: @escaping () -> Void) {
        let host = NSHostingController(rootView: WelcomeView(app: app) { [weak self] in
            self?.window?.close()
            self?.window = nil
            onDone()
        })
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
