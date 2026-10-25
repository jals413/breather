import AppKit
import SwiftUI

/// First-run setup. Every choice is a real setting, applied as you go, so most people never need Settings.
struct WelcomeView: View {
    let app: AppModel
    var onDone: () -> Void
    @State var step: Step = .hello

    enum Step: Int, CaseIterable {
        case hello, rhythm, breaks, look, finish
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .hello: HelloStep()
                case .rhythm: RhythmStep(app: app)
                case .breaks: BreaksStep(app: app)
                case .look: LookStep(app: app)
                case .finish: FinishStep(app: app)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 24)),
                                    removal: .opacity.combined(with: .offset(x: -24))))
            .id(step)

            footer
        }
        .frame(width: 620, height: 720)
        .animation(.smooth(duration: 0.35), value: step)
    }

    private var footer: some View {
        HStack {
            Button("Back") { move(-1) }
                .controlSize(.large)
                .opacity(step == .hello ? 0 : 1)
                .disabled(step == .hello)

            Spacer()
            HStack(spacing: 7) {
                ForEach(Step.allCases, id: \.self) { s in
                    Capsule()
                        .fill(s == step ? Brand.teal : Color.secondary.opacity(0.3))
                        .frame(width: s == step ? 18 : 7, height: 7)
                }
            }
            Spacer()

            Button {
                if step == .finish { onDone() } else { move(1) }
            } label: {
                Text(primaryTitle).frame(minWidth: 110)
            }
            .buttonStyle(.glassProminent)
            .tint(Brand.teal)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }

    private var primaryTitle: String {
        switch step {
        case .hello: "Set Up"
        case .finish: "Start Breathing"
        default: "Continue"
        }
    }

    private func move(_ delta: Int) {
        if let next = Step(rawValue: step.rawValue + delta) { step = next }
    }
}

// MARK: - Steps

private struct HelloStep: View {
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                BreatherAppIcon().frame(width: 104, height: 104)
                Text("Welcome to \(Brand.name)").font(.system(size: 30, weight: .bold))
                Text(Brand.tagline).font(.title3).foregroundStyle(.secondary)
            }
            .padding(.top, 52)

            VStack(alignment: .leading, spacing: 22) {
                Feature(symbol: "rectangle.topthird.inset.filled", tint: Brand.teal, title: "Lives in your notch",
                        detail: "A heads-up grows out of the notch before each break. Hover the notch to peek at your next one.")
                Feature(symbol: "brain.head.profile.fill", tint: .indigo, title: "Knows when not to interrupt",
                        detail: "Breaks wait while you're in a call, watching a video, presenting, or mid-sentence.")
                Feature(symbol: "figure.walk", tint: Brand.mint, title: "Counts real rest",
                        detail: "Step away from your Mac and that time counts as a break, so you won't be asked again right after.")
                Feature(symbol: "lock.shield.fill", tint: .gray, title: "Private by design",
                        detail: "No account and no tracking. Everything stays on this Mac.")
            }
            .padding(.horizontal, 64)
            .padding(.top, 40)

            Spacer()
            Text("Takes about a minute. You can change anything later in Settings.")
                .font(.callout).foregroundStyle(.secondary)
                .padding(.bottom, 4)
        }
    }
}

private struct RhythmStep: View {
    let app: AppModel

    var body: some View {
        @Bindable var store = app.store
        VStack(spacing: 0) {
            StepHeader(symbol: "timer", tint: Brand.teal, title: "Pick your rhythm",
                       detail: "How long you work between breaks, and how long each break lasts.")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(TimingPreset.all) { preset in
                    PresetCard(preset: preset, selected: matches(preset)) { apply(preset) }
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 4)

            Form {
                Section {
                    LabeledSlider(title: "Work for", value: $store.settings.workMinutes, range: 5...90, step: 5) { "\(Int($0)) min" }
                    LabeledSlider(title: "Break for", value: $store.settings.breakSeconds, range: 10...300, step: 5) { duration($0) }
                }
                Section {
                    Toggle("Long breaks", isOn: $store.settings.longBreakEnabled)
                    if store.settings.longBreakEnabled {
                        Stepper("After every \(store.settings.longBreakEvery) breaks", value: $store.settings.longBreakEvery, in: 2...8)
                        LabeledSlider(title: "Long break length", value: $store.settings.longBreakMinutes, range: 1...20, step: 1) { "\(Int($0)) min" }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .padding(.horizontal, 20)
        }
    }

    private func matches(_ p: TimingPreset) -> Bool {
        let s = app.store.settings
        return p.workMinutes == s.workMinutes && p.breakSeconds == s.breakSeconds
    }

    private func apply(_ p: TimingPreset) {
        app.store.settings.workMinutes = p.workMinutes
        app.store.settings.breakSeconds = p.breakSeconds
        app.store.settings.longBreakEvery = p.longEvery
        app.store.settings.longBreakMinutes = p.longMinutes
    }

    private func duration(_ seconds: Double) -> String {
        seconds < 60 ? "\(Int(seconds)) sec" : seconds.truncatingRemainder(dividingBy: 60) == 0
            ? "\(Int(seconds / 60)) min" : "\(Int(seconds / 60)) min \(Int(seconds.truncatingRemainder(dividingBy: 60))) sec"
    }
}

private struct BreaksStep: View {
    let app: AppModel

    var body: some View {
        @Bindable var store = app.store
        VStack(spacing: 0) {
            StepHeader(symbol: "brain.head.profile.fill", tint: .indigo, title: "How breaks behave",
                       detail: "How strict breaks are, and when Breather should hold off.")
            Form {
                Section {
                    Picker("Skipping", selection: $store.settings.difficulty) {
                        ForEach(SkipDifficulty.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text(store.settings.difficulty.detail).font(.callout).foregroundStyle(.secondary)
                }
                Section {
                    Toggle("Heads-up in the notch a minute before", isOn: $store.settings.headsUpEnabled)
                    Toggle("Wait until I stop typing", isOn: $store.settings.waitForTypingPause)
                    Toggle("Count time away from the Mac as a break", isOn: $store.settings.idleCountsAsBreak)
                }
                Section("Hold breaks while") {
                    Toggle("I'm in a call or meeting", isOn: $store.settings.pauseForMeetings)
                    Picker("A video is playing", selection: $store.settings.videoMode) {
                        ForEach(VideoPauseMode.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("I'm sharing or recording my screen", isOn: $store.settings.pauseForScreenRecording)
                    Toggle("A game is full screen", isOn: $store.settings.pauseForFullscreenGames)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .padding(.horizontal, 20)
        }
    }
}

private struct LookStep: View {
    let app: AppModel

    var body: some View {
        @Bindable var store = app.store
        VStack(spacing: 0) {
            StepHeader(symbol: nil, tint: .pink, title: "Make it yours",
                       detail: "This is what your screen shows during a break.")
            LivePreview(appearance: store.settings.appearance)
                .frame(height: 200)
                .padding(.horizontal, 40)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(BreakTheme.all) { theme in
                        ThemeCard(theme: theme, selected: store.settings.appearance == theme.appearance) {
                            withAnimation(.snappy) { store.settings.appearance = theme.appearance }
                        }
                    }
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 6)
            }
            .padding(.top, 10)

            Form {
                Section {
                    Picker("Timer", selection: $store.settings.appearance.timerStyle) {
                        ForEach(TimerStyle.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Breathe in and out guide", isOn: $store.settings.appearance.showBreathingCue)
                    Toggle("Show the time", isOn: $store.settings.appearance.showClock)
                    Toggle("Play a sound when a break starts and ends", isOn: $store.settings.soundEnabled)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .padding(.horizontal, 20)
        }
    }
}

private struct FinishStep: View {
    let app: AppModel

    var body: some View {
        @Bindable var store = app.store
        VStack(spacing: 0) {
            StepHeader(symbol: "checkmark.seal.fill", tint: Brand.mint, title: "Almost done",
                       detail: "A few last choices about where Breather shows up.")
            Form {
                Section {
                    Toggle("Open Breather when I log in", isOn: $store.settings.launchAtLogin)
                }
                Section("Around the notch") {
                    Toggle("Countdown beside the notch before a break", isOn: $store.settings.notchLiveActivity)
                    Toggle("Expand when I hover the notch", isOn: $store.settings.notchHoverExpands)
                    Toggle("Time left in the menu bar", isOn: $store.settings.menuBarShowsTime)
                }
                Section {
                    Toggle("Track which apps I use (stays on this Mac)", isOn: $store.settings.trackAppUsage)
                    Toggle("Check GitHub for new versions", isOn: $store.settings.checkForUpdates)
                } footer: {
                    Text("Pair your iPhone and Apple Watch any time from Settings › Devices.")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Pieces

private struct StepHeader: View {
    var symbol: String?
    var tint: Color
    var title: String
    var detail: String

    var body: some View {
        VStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 60, height: 60)
                    .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            Text(title).font(.system(size: 24, weight: .bold))
            Text(detail).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.top, symbol == nil ? 36 : 40)
        .padding(.bottom, 18)
        .padding(.horizontal, 40)
    }
}

private struct PresetCard: View {
    var preset: TimingPreset
    var selected: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(preset.id).font(.headline)
                Text("\(Int(preset.workMinutes)) min work · \(Int(preset.breakSeconds)) sec break")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Brand.teal.opacity(0.18) : Color.primary.opacity(hovering ? 0.08 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(selected ? Brand.teal : Color.clear, lineWidth: 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pointerStyle(.link)
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
        if let window {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
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
