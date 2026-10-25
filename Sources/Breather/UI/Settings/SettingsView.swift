import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, breaks, notch, smartPause, schedule, shortcuts, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .breaks: "Breaks"
        case .notch: "Notch & Alerts"
        case .smartPause: "Smart Pause"
        case .schedule: "Office Hours"
        case .shortcuts: "Shortcuts"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .breaks: "eye.fill"
        case .notch: "rectangle.topthird.inset.filled"
        case .smartPause: "brain.head.profile.fill"
        case .schedule: "calendar"
        case .shortcuts: "command"
        case .about: "info"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .breaks: Brand.teal
        case .notch: .black
        case .smartPause: .indigo
        case .schedule: .red
        case .shortcuts: .blue
        case .about: Brand.ocean
        }
    }

    var summary: String {
        switch self {
        case .general: "Set your rhythm: how long you work and how long you rest."
        case .breaks: "Choose how strict breaks are, and how they look and sound."
        case .notch: "Breather lives in your notch. Decide what it shows and when."
        case .smartPause: "Breaks wait while you're in a call, watching, presenting or mid-sentence."
        case .schedule: "Only get reminders during the hours you work."
        case .shortcuts: "Control Breather from anywhere with global shortcuts."
        case .about: Brand.tagline
        }
    }
}

/// System Settings–style coloured squircle icon.
struct SettingsBadge: View {
    var symbol: String
    var tint: Color
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .fill(tint.gradient)
            )
    }
}

/// The large header at the top of each pane, like System Settings.
struct PaneHeader: View {
    var pane: SettingsPane

    var body: some View {
        Section {
            VStack(spacing: 8) {
                SettingsBadge(symbol: pane.symbol, tint: pane.tint, size: 52)
                Text(pane.title).font(.title2.bold())
                Text(pane.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }
}

struct SettingsView: View {
    let app: AppModel
    @State private var pane: SettingsPane = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $pane) { pane in
                HStack(spacing: 8) {
                    SettingsBadge(symbol: pane.symbol, tint: pane.tint)
                    Text(pane.title)
                }
                .tag(pane)
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            Group {
                switch pane {
                case .general: GeneralPane(app: app)
                case .breaks: BreaksPane(app: app)
                case .notch: NotchPane(app: app)
                case .smartPause: SmartPausePane(app: app)
                case .schedule: SchedulePane(app: app)
                case .shortcuts: ShortcutsPane(app: app)
                case .about: AboutPane(app: app)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("")
        }
        .frame(minWidth: 720, minHeight: 520)
    }
}

// MARK: - General

private struct GeneralPane: View {
    let app: AppModel

    var body: some View {
        @Bindable var store = app.store
        Form {
            PaneHeader(pane: .general)
            Section("Rhythm") {
                Picker("Preset", selection: presetBinding) {
                    Text("Custom").tag("Custom")
                    ForEach(TimingPreset.all) { Text($0.id).tag($0.id) }
                }
                LabeledSlider(title: "Work for", value: $store.settings.workMinutes, range: 5...90, step: 1) { "\(Int($0)) min" }
                LabeledSlider(title: "Short break", value: $store.settings.breakSeconds, range: 10...180, step: 5) { Format.spoken($0) }
            }
            Section("Long breaks") {
                Toggle("Take long breaks", isOn: $store.settings.longBreakEnabled)
                if store.settings.longBreakEnabled {
                    Stepper("After every \(store.settings.longBreakEvery) short breaks", value: $store.settings.longBreakEvery, in: 1...10)
                    LabeledSlider(title: "Long break", value: $store.settings.longBreakMinutes, range: 1...30, step: 1) { "\(Int($0)) min" }
                }
            }
            Section("System") {
                Toggle("Launch at login", isOn: $store.settings.launchAtLogin)
                Toggle("Show icon in the menu bar", isOn: $store.settings.showMenuBarIcon)
                if store.settings.showMenuBarIcon {
                    Toggle("Show time until break next to the icon", isOn: $store.settings.menuBarShowsTime)
                }
            }
        }
    }

    private var presetBinding: Binding<String> {
        Binding {
            let s = app.store.settings
            return TimingPreset.all.first {
                $0.workMinutes == s.workMinutes && $0.breakSeconds == s.breakSeconds
                    && $0.longEvery == s.longBreakEvery && $0.longMinutes == s.longBreakMinutes
            }?.id ?? "Custom"
        } set: { id in
            guard let preset = TimingPreset.all.first(where: { $0.id == id }) else { return }
            app.store.settings.workMinutes = preset.workMinutes
            app.store.settings.breakSeconds = preset.breakSeconds
            app.store.settings.longBreakEvery = preset.longEvery
            app.store.settings.longBreakMinutes = preset.longMinutes
        }
    }
}

// MARK: - Breaks

private struct BreaksPane: View {
    let app: AppModel

    var body: some View {
        @Bindable var store = app.store
        Form {
            PaneHeader(pane: .breaks)
            Section {
                Picker("Skip difficulty", selection: $store.settings.difficulty) {
                    ForEach(SkipDifficulty.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(store.settings.difficulty.detail).font(.caption).foregroundStyle(.secondary)
                if store.settings.difficulty == .balanced {
                    LabeledSlider(title: "Skip unlocks after", value: $store.settings.balancedSkipDelaySeconds, range: 2...20, step: 1) { "\(Int($0))s" }
                }
                if store.settings.difficulty != .hardcore {
                    Stepper("Snoozes per break: \(store.settings.snoozeLimitPerBreak)", value: $store.settings.snoozeLimitPerBreak, in: 0...10)
                    Stepper("Skips in advance per day: \(store.settings.dailyAdvanceSkipLimit)", value: $store.settings.dailyAdvanceSkipLimit, in: 0...20)
                }
                Toggle("Allow ending a break early", isOn: $store.settings.allowEndEarly)
                if store.settings.allowEndEarly {
                    LabeledSlider(title: "“End break” appears after", value: $store.settings.endEarlyAfterFraction, range: 0.25...1, step: 0.05) {
                        "\(Int($0 * 100))% of the break"
                    }
                }
                Toggle("Lock the screen when a long break starts", isOn: $store.settings.lockScreenOnBreak)
            } header: {
                Text("Enforcement")
            }

            Section("Look") {
                Picker("Background", selection: $store.settings.background) {
                    ForEach(BreakBackground.allCases) { Text($0.title).tag($0) }
                }
                HStack {
                    Spacer()
                    Button("Preview a 10-second break") { app.engine.startBreak(kind: .custom, duration: 10) }
                }
            }

            Section {
                MessagesEditor(messages: $store.settings.shortBreakMessages)
            } header: {
                Text("Short break messages")
            } footer: {
                Text("One per line. A random one is shown each break.")
            }
            Section("Long break messages") {
                MessagesEditor(messages: $store.settings.longBreakMessages)
            }

            Section("Sound") {
                Toggle("Play sounds", isOn: $store.settings.soundEnabled)
                if store.settings.soundEnabled {
                    SoundPicker(title: "Break starts", selection: $store.settings.breakStartSound, volume: store.settings.soundVolume)
                    SoundPicker(title: "Break ends", selection: $store.settings.breakEndSound, volume: store.settings.soundVolume)
                    LabeledSlider(title: "Volume", value: $store.settings.soundVolume, range: 0.05...1, step: 0.05) { "\(Int($0 * 100))%" }
                }
            }
        }
    }
}

private struct MessagesEditor: View {
    @Binding var messages: [String]
    @State private var text = ""

    var body: some View {
        TextEditor(text: $text)
            .font(.body)
            .frame(minHeight: 80)
            .scrollContentBackground(.hidden)
            .onAppear { text = messages.joined(separator: "\n") }
            .onChange(of: text) { _, new in
                let lines = new.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                if lines != messages && !lines.isEmpty { messages = lines }
            }
    }
}

private struct SoundPicker: View {
    var title: String
    @Binding var selection: String
    var volume: Double

    var body: some View {
        HStack {
            Picker(title, selection: $selection) {
                ForEach(Sound.systemSounds, id: \.self) { Text($0).tag($0) }
            }
            Button {
                Sound.play(selection, volume: volume)
            } label: {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.borderless)
        }
    }
}

// MARK: - Notch

private struct NotchPane: View {
    let app: AppModel

    var body: some View {
        @Bindable var store = app.store
        Form {
            PaneHeader(pane: .notch)
            Section {
                Toggle("Show a countdown beside the notch", isOn: $store.settings.notchLiveActivity)
                if store.settings.notchLiveActivity {
                    Picker("Show it", selection: $store.settings.notchRevealSeconds) {
                        Text("Always").tag(0.0)
                        Text("In the last 10 minutes").tag(600.0)
                        Text("In the last 5 minutes").tag(300.0)
                        Text("In the last 2 minutes").tag(120.0)
                    }
                }
                Toggle("Expand the notch on hover", isOn: $store.settings.notchHoverExpands)
                Toggle("Show alerts as a pill on displays without a notch", isOn: $store.settings.pillOnScreensWithoutNotch)
            } header: {
                Text("Notch")
            } footer: {
                Text("On a MacBook with a notch, the island grows out of it. Other displays get a floating pill under the menu bar. Hover the notch to peek at your next break.")
            }

            Section("Heads-up before a break") {
                Toggle("Show a heads-up", isOn: $store.settings.headsUpEnabled)
                if store.settings.headsUpEnabled {
                    LabeledSlider(title: "How early", value: $store.settings.headsUpLeadSeconds, range: 15...300, step: 15) { Format.spoken($0) }
                }
                LabeledSlider(title: "Final countdown", value: $store.settings.finalCountdownSeconds, range: 0...10, step: 1) {
                    $0 == 0 ? "Off" : "\(Int($0))s"
                }
                HStack {
                    Spacer()
                    Button("Preview heads-up") { app.notch.showHeadsUp(app.engine.nextBreakKind, for: 8) }
                    Button("Preview toast") {
                        app.notch.show(NotchToast(symbol: "figure.walk", tint: .breatherMint, title: "Welcome back",
                                                  subtitle: "6 minutes away counted as a break", action: .undoNaturalBreak, actionTitle: "Undo"))
                    }
                }
            }
        }
    }
}

// MARK: - Smart Pause

private struct SmartPausePane: View {
    let app: AppModel

    var body: some View {
        @Bindable var store = app.store
        Form {
            PaneHeader(pane: .smartPause)
            Section {
                HStack {
                    Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(.secondary)
                    Text(app.statusTitle)
                    Spacer()
                }
            } header: {
                Text("Right now")
            }

            Section {
                Toggle("Wait for a pause in typing before a break", isOn: $store.settings.waitForTypingPause)
                if store.settings.waitForTypingPause {
                    LabeledSlider(title: "Pause length", value: $store.settings.typingLullSeconds, range: 1...10, step: 1) { "\(Int($0))s without typing" }
                    LabeledSlider(title: "Never wait longer than", value: $store.settings.maxTypingDelaySeconds, range: 15...600, step: 15) { Format.spoken($0) }
                }
                Toggle("Count time away from the Mac as a break", isOn: $store.settings.idleCountsAsBreak)
                LabeledSlider(title: "You're away after", value: $store.settings.idleThresholdSeconds, range: 30...600, step: 30) { Format.spoken($0) + " idle" }
                LabeledSlider(title: "After an activity ends, wait", value: $store.settings.postActivityDelaySeconds, range: 0...300, step: 15) {
                    $0 == 0 ? "No delay" : Format.spoken($0)
                }
            } header: {
                Text("Interruptions")
            }

            Section {
                Toggle("Calls & meetings (microphone or camera in use)", isOn: $store.settings.pauseForMeetings)
                if store.settings.pauseForMeetings {
                    AppList(title: "Apps that don't count as a call", apps: $store.settings.meetingExcludedApps)
                }
            } header: {
                Text("Meetings")
            }

            Section("Video") {
                Picker("Pause while video plays", selection: $store.settings.videoMode) {
                    ForEach(VideoPauseMode.allCases) { Text($0.title).tag($0) }
                }
                if store.settings.videoMode != .off {
                    AppList(title: "Apps that don't count as video", apps: $store.settings.videoExcludedApps)
                }
            }

            Section("Fullscreen & recording") {
                Toggle("Fullscreen games", isOn: $store.settings.pauseForFullscreenGames)
                Toggle("Any fullscreen app", isOn: $store.settings.pauseForAnyFullscreenApp)
                Toggle("Screen recording (beta)", isOn: $store.settings.pauseForScreenRecording)
            }

            Section {
                FocusAppList(apps: $store.settings.focusApps)
            } header: {
                Text("Deep focus apps")
            } footer: {
                Text("Breaks wait while these apps are in use.")
            }
        }
    }
}

private struct AppList: View {
    var title: String
    @Binding var apps: [ExcludedApp]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Button("Add…") {
                    for app in AppChooser.choose() where !apps.contains(where: { $0.bundleID == app.bundleID }) {
                        apps.append(ExcludedApp(bundleID: app.bundleID, name: app.name))
                    }
                }
            }
            ForEach(apps) { app in
                HStack {
                    AppIcon(bundleID: app.bundleID)
                    Text(app.name)
                    Spacer()
                    Button { apps.removeAll { $0.bundleID == app.bundleID } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                }
            }
        }
    }
}

private struct FocusAppList: View {
    @Binding var apps: [FocusApp]

    var body: some View {
        ForEach($apps) { $app in
            HStack {
                AppIcon(bundleID: app.bundleID)
                Text(app.name)
                Spacer()
                Picker("", selection: $app.mode) {
                    ForEach(FocusAppMode.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                Button { apps.removeAll { $0.bundleID == app.bundleID } } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
            }
        }
        HStack {
            Spacer()
            Button("Add app…") {
                for chosen in AppChooser.choose() where !apps.contains(where: { $0.bundleID == chosen.bundleID }) {
                    apps.append(FocusApp(bundleID: chosen.bundleID, name: chosen.name))
                }
            }
        }
    }
}

struct AppIcon: View {
    var bundleID: String

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 18, height: 18)
        } else {
            Image(systemName: "app").frame(width: 18, height: 18)
        }
    }
}

@MainActor
enum AppChooser {
    static func choose() -> [(bundleID: String, name: String)] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.compactMap { url in
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            return (id, name)
        }
    }
}

// MARK: - Schedule

private struct SchedulePane: View {
    let app: AppModel

    var body: some View {
        @Bindable var store = app.store
        Form {
            PaneHeader(pane: .schedule)
            Section {
                Toggle("Only remind me during office hours", isOn: $store.settings.officeHours.enabled)
            } footer: {
                Text("An end time earlier than the start runs past midnight.")
            }
            if store.settings.officeHours.enabled {
                Section("Days") {
                    ForEach(weekdayOrder, id: \.self) { index in
                        DayRow(name: Calendar.current.weekdaySymbols[index], day: $store.settings.officeHours.days[index])
                    }
                }
            }
        }
    }

    /// Locale-aware week order (Monday first in most of the world).
    private var weekdayOrder: [Int] {
        let first = Calendar.current.firstWeekday - 1
        return (0..<7).map { (first + $0) % 7 }
    }
}

private struct DayRow: View {
    var name: String
    @Binding var day: DaySchedule

    var body: some View {
        HStack {
            Toggle(name, isOn: $day.enabled)
                .frame(width: 140, alignment: .leading)
            Spacer()
            DatePicker("", selection: minutes($day.startMinute), displayedComponents: .hourAndMinute).labelsHidden()
            Text("–").foregroundStyle(.secondary)
            DatePicker("", selection: minutes($day.endMinute), displayedComponents: .hourAndMinute).labelsHidden()
        }
        .disabled(!day.enabled)
        .opacity(day.enabled ? 1 : 0.5)
    }

    private func minutes(_ binding: Binding<Int>) -> Binding<Date> {
        Binding {
            Calendar.current.startOfDay(for: .now).addingTimeInterval(TimeInterval(binding.wrappedValue * 60))
        } set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            binding.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }
    }
}

// MARK: - Shortcuts

private struct ShortcutsPane: View {
    let app: AppModel

    var body: some View {
        @Bindable var store = app.store
        Form {
            PaneHeader(pane: .shortcuts)
            Section {
                ShortcutRow(title: "Take a break now", key: $store.settings.hotKeys.breakNow)
                ShortcutRow(title: "Pause / resume", key: $store.settings.hotKeys.togglePause)
                ShortcutRow(title: "Skip next break", key: $store.settings.hotKeys.skipNext)
            } footer: {
                Text("Global shortcuts work from any app. During a break, press Esc twice to skip.")
            }
        }
    }
}

private struct ShortcutRow: View {
    var title: String
    @Binding var key: HotKey
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Toggle(title, isOn: $key.enabled)
            Spacer()
            Button(recording ? "Type shortcut…" : key.displayString) {
                recording ? stop() : start()
            }
            .frame(minWidth: 110)
            .disabled(!key.enabled)
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil }
            if let new = HotKey(event: event) {
                key = HotKey(keyCode: new.keyCode, modifiers: new.modifiers, enabled: true)
                stop()
            }
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

// MARK: - About

private struct AboutPane: View {
    let app: AppModel

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    BreatherAppIcon().frame(width: 64, height: 64)
                    VStack(alignment: .leading) {
                        Text("Breather").font(.title2.bold())
                        Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
                            .foregroundStyle(.secondary)
                    }
                }
                Text("\(Brand.tagline) Smart break reminders that live in your notch. No accounts, no telemetry — everything stays on this Mac.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Show data folder in Finder") {
                    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Breather")
                    NSWorkspace.shared.activateFileViewerSelecting([dir])
                }
                Button("Reset all settings", role: .destructive) { app.store.reset() }
            }
        }
    }
}

// MARK: - Shared

struct LabeledSlider: View {
    var title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value)).foregroundStyle(.secondary).monospacedDigit()
            }
            Slider(value: $value, in: range, step: step)
        }
    }
}
