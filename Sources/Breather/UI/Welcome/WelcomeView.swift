import AppKit
import SwiftUI

/// First-run setup, in the same sidebar-and-cards layout as Settings and Stats.
/// Every choice is a real setting, applied as you go, so most people never need Settings.
struct WelcomeView: View {
    let app: AppModel
    var onDone: () -> Void
    @State var step: Step = .hello

    enum Step: Int, CaseIterable, SidebarItem {
        case hello, rhythm, breaks, look, notch, done

        var id: Int { rawValue }
        var title: String {
            switch self {
            case .hello: "Welcome"
            case .rhythm: "Your Rhythm"
            case .breaks: "Staying in Flow"
            case .look: "Break Screen"
            case .notch: "Notch & Menu Bar"
            case .done: "All Set"
            }
        }
        var symbol: String {
            switch self {
            case .hello: "hand.wave.fill"
            case .rhythm: "timer"
            case .breaks: "brain.head.profile.fill"
            case .look: "paintbrush.fill"
            case .notch: "rectangle.topthird.inset.filled"
            case .done: "checkmark"
            }
        }
        var tint: Color {
            switch self {
            case .hello: Brand.teal
            case .rhythm: .red
            case .breaks: .indigo
            case .look: .pink
            case .notch: .black
            case .done: .green
            }
        }
        var summary: String {
            switch self {
            case .hello: Brand.tagline
            case .rhythm: "How long you work between breaks, and how long each break lasts."
            case .breaks: "How strict breaks are, and when Breather should wait for you."
            case .look: "What your screen shows during a break. Tweak every detail later in Settings."
            case .notch: "Where Breather shows up, and whether it opens when you log in."
            case .done: "Breather now runs in your menu bar and notch. Your first break is on its way."
            }
        }
    }

    var body: some View {
        SidebarWindow(selection: $step, groups: [SidebarGroup(title: "Set Up", items: Step.allCases)]) {
            VStack(spacing: 0) {
                Group {
                    switch step {
                    case .hello: HelloPane()
                    case .rhythm: RhythmPane(app: app)
                    case .breaks: BreaksPane(app: app)
                    case .look: LookPane(app: app)
                    case .notch: NotchPane(app: app)
                    case .done: DonePane(app: app)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(step)
                footer
            }
        }
        .frame(width: 820, height: 640)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("Step \(step.rawValue + 1) of \(Step.allCases.count)")
                .font(.callout).foregroundStyle(.secondary)
            Spacer()
            if step != .hello {
                Button("Back") { move(-1) }.controlSize(.large)
            }
            Button {
                if step == .done { onDone() } else { move(1) }
            } label: {
                Text(primaryTitle).frame(minWidth: 96)
            }
            .buttonStyle(.glassProminent)
            .tint(Brand.teal)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 30)
        .padding(.top, 10)
        .padding(.bottom, 18)
    }

    private var primaryTitle: String {
        switch step {
        case .hello: "Set Up"
        case .done: "Start Breathing"
        default: "Continue"
        }
    }

    private func move(_ delta: Int) {
        if let next = Step(rawValue: step.rawValue + delta) { step = next }
    }
}

private struct StepHeader: View {
    var step: WelcomeView.Step
    var body: some View {
        HeaderCard(symbol: step.symbol, tint: step.tint, title: step.title, summary: step.summary)
    }
}

// MARK: - Panes

private struct HelloPane: View {
    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    BreatherAppIcon().frame(width: 72, height: 72)
                    Text("Welcome to \(Brand.name)").font(.title2.bold())
                    Text(Brand.tagline).font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            Section {
                Feature(symbol: "rectangle.topthird.inset.filled", tint: Brand.teal, title: "Lives in your notch",
                        detail: "A heads-up grows out of the notch before each break. Hover the notch to peek at your next one.")
                Feature(symbol: "brain.head.profile.fill", tint: .indigo, title: "Knows when not to interrupt",
                        detail: "Breaks wait while you're in a call, watching a video, presenting, or mid-sentence.")
                Feature(symbol: "figure.walk", tint: Brand.mint, title: "Counts real rest",
                        detail: "Step away from your Mac and that time counts as a break.")
                Feature(symbol: "lock.shield.fill", tint: .gray, title: "Private by design",
                        detail: "No account and no tracking. Everything stays on this Mac.")
            } footer: {
                Text("Takes about a minute. You can change anything later in Settings.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

private struct RhythmPane: View {
    let app: AppModel

    var body: some View {
        @Bindable var store = app.store
        Form {
            StepHeader(step: .rhythm)
            Section("Presets") {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(TimingPreset.all) { preset in
                        PresetCard(preset: preset, selected: matches(preset)) { apply(preset) }
                    }
                }
                .padding(.vertical, 4)
            }
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
        let s = Int(seconds)
        if s < 60 { return "\(s) sec" }
        return s % 60 == 0 ? "\(s / 60) min" : "\(s / 60) min \(s % 60) sec"
    }
}

private struct BreaksPane: View {
    let app: AppModel

    var body: some View {
        @Bindable var store = app.store
        Form {
            StepHeader(step: .breaks)
            Section {
                Picker("Skipping", selection: $store.settings.difficulty) {
                    ForEach(SkipDifficulty.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(store.settings.difficulty.detail).font(.callout).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Heads-up in the notch a minute before", isOn: $store.settings.headsUpEnabled)
                Toggle("Wait until I stop typing", isOn: $store.settings.waitForTypingPause)
                Toggle("Count time away from the Mac as a break", isOn: $store.settings.idleCountsAsBreak)
                LabeledSlider(title: "I'm away after no input for", value: $store.settings.idleThresholdSeconds,
                              range: 60...600, step: 30) { s in s.truncatingRemainder(dividingBy: 60) == 0 ? "\(Int(s / 60)) min" : String(format: "%.1f min", s / 60) }
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
    }
}

private struct LookPane: View {
    let app: AppModel

    var body: some View {
        @Bindable var store = app.store
        Form {
            StepHeader(step: .look)
            Section {
                LivePreview(appearance: store.settings.appearance)
                    .frame(height: 230)
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
            }
            Section("Themes") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(BreakTheme.all) { theme in
                            ThemeCard(theme: theme, selected: store.settings.appearance == theme.appearance) {
                                withAnimation(.snappy) { store.settings.appearance = theme.appearance }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            Section {
                Picker("Timer", selection: $store.settings.appearance.timerStyle) {
                    ForEach(TimerStyle.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Breathe in and out guide", isOn: $store.settings.appearance.showBreathingCue)
                Toggle("Show the time", isOn: $store.settings.appearance.showClock)
                Toggle("Play a sound when a break starts and ends", isOn: $store.settings.soundEnabled)
            }
        }
    }
}

private struct NotchPane: View {
    let app: AppModel

    var body: some View {
        @Bindable var store = app.store
        Form {
            StepHeader(step: .notch)
            Section {
                Toggle("Open Breather when I log in", isOn: $store.settings.launchAtLogin)
            }
            Section("Notch") {
                Toggle("Countdown beside the notch before a break", isOn: $store.settings.notchLiveActivity)
                Toggle("Expand when I hover the notch", isOn: $store.settings.notchHoverExpands)
                Picker("Show alerts on", selection: $store.settings.alertDisplay) {
                    ForEach(AlertDisplay.allCases) { Text($0.title).tag($0) }
                }
            }
            Section("Menu bar") {
                Toggle("Show Breather in the menu bar", isOn: $store.settings.showMenuBarIcon)
                Toggle("Time left in the menu bar", isOn: $store.settings.menuBarShowsTime)
            }
        }
    }
}

private struct DonePane: View {
    let app: AppModel

    var body: some View {
        @Bindable var store = app.store
        Form {
            StepHeader(step: .done)
            Section("Stats & updates") {
                Toggle("Track which apps I use (stays on this Mac)", isOn: $store.settings.trackAppUsage)
                Toggle("Check for new versions", isOn: $store.settings.checkForUpdates)
            }
            Section {
                Feature(symbol: "cursorarrow.click.2", tint: Brand.teal, title: "Click the menu bar icon",
                        detail: "Take a break now, pause, switch profiles, or open Settings.")
                Feature(symbol: "rectangle.topthird.inset.filled", tint: .gray, title: "Hover the notch",
                        detail: "See how long until your next break.")
                Feature(symbol: "iphone.gen3", tint: Brand.ocean, title: "Add your iPhone and Apple Watch",
                        detail: "Pair them any time from Settings › iPhone & Apple Watch.")
            }
        }
    }
}

// MARK: - Pieces

private struct PresetCard: View {
    var preset: TimingPreset
    var selected: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(preset.id).font(.headline)
                Text("\(Int(preset.workMinutes)) min work · \(Int(preset.breakSeconds)) sec break")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(hovering ? 0.08 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2)
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
        HStack(alignment: .top, spacing: 12) {
            SettingsBadge(symbol: symbol, tint: tint, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
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
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
