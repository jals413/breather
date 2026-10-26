import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Panes, grouped in the sidebar like System Settings.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case schedule, strictness, breakScreen, messages
    case smartPause, notch
    case reminders, privacy
    case devices
    case profiles, automations, about

    var id: String { rawValue }

    struct Group: Identifiable {
        let title: String?
        let panes: [SettingsPane]
        var id: String { title ?? "top" }
    }

    static let groups: [Group] = [
        Group(title: nil, panes: [.general]),
        Group(title: "Breaks", panes: [.schedule, .strictness, .breakScreen, .messages]),
        Group(title: "Staying in Flow", panes: [.smartPause, .notch]),
        Group(title: "Wellbeing", panes: [.reminders, .privacy]),
        Group(title: "Devices", panes: [.devices]),
        Group(title: "Advanced", panes: [.profiles, .automations, .about]),
    ]

    var title: String {
        switch self {
        case .general: "General"
        case .schedule: "Schedule"
        case .strictness: "Skipping & Snoozing"
        case .breakScreen: "Break Screen"
        case .messages: "Messages & Sounds"
        case .smartPause: "Smart Pause"
        case .notch: "Notch & Alerts"
        case .reminders: "Reminders"
        case .privacy: "Stats & Privacy"
        case .devices: "iPhone & Apple Watch"
        case .profiles: "Profiles"
        case .automations: "Automations"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .schedule: "calendar"
        case .strictness: "hand.raised.fill"
        case .breakScreen: "paintbrush.fill"
        case .messages: "text.bubble.fill"
        case .smartPause: "brain.head.profile.fill"
        case .notch: "rectangle.topthird.inset.filled"
        case .reminders: "drop.fill"
        case .privacy: "chart.bar.xaxis"
        case .devices: "iphone.gen3"
        case .profiles: "person.crop.square.filled.and.at.rectangle.fill"
        case .automations: "command"
        case .about: "info"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .schedule: .red
        case .strictness: .orange
        case .breakScreen: .pink
        case .messages: Brand.teal
        case .smartPause: .indigo
        case .notch: .black
        case .reminders: .cyan
        case .privacy: .green
        case .devices: Brand.ocean
        case .profiles: .purple
        case .automations: .blue
        case .about: .gray
        }
    }

    var summary: String {
        switch self {
        case .general: "Startup, menu bar, and which profile you're using."
        case .schedule: "How long you work and rest, when reminders run, and breaks at fixed times."
        case .strictness: "How easy it is to skip, snooze or end a break early."
        case .breakScreen: "Make the full-screen break yours: background, timer, type and themes."
        case .messages: "What breaks say, and how they sound."
        case .smartPause: "Breaks wait while you're in a call, watching, presenting or mid-sentence."
        case .notch: "Breather lives in your notch. Decide what it shows and when."
        case .reminders: "Gentle nudges between breaks: water, posture, blinking, standing up."
        case .privacy: "See your screen habits. Everything is stored only on this Mac."
        case .devices: "See breaks on your iPhone's Lock Screen and Dynamic Island, and feel them on your Apple Watch."
        case .profiles: "Switch between saved setups, by hand or automatically by app."
        case .automations: "Shortcuts and scripts when breaks start or end, keyboard shortcuts, and link commands."
        case .about: Brand.tagline
        }
    }

    /// Extra words the sidebar search matches.
    var keywords: String {
        switch self {
        case .general: "login startup menu bar icon profile reset data"
        case .schedule: "rhythm preset work minutes break seconds long break office hours days planned lunch custom length"
        case .strictness: "difficulty casual balanced hardcore skip snooze advance end early keep open lock overtime"
        case .breakScreen: "background theme timer font colour color wallpaper photo aurora gradient breathing"
        case .messages: "message text sound volume chime long break"
        case .smartPause: "meeting call video fullscreen game recording focus app typing idle away"
        case .notch: "notch island heads-up countdown pill display hover"
        case .reminders: "water posture blink stand stretch nudge"
        case .privacy: "stats score apps websites browser tracking"
        case .devices: "iphone watch phone pair bluetooth live activity dynamic island lock screen block screen time push"
        case .profiles: "profile deep work everyday gentle switch"
        case .automations: "shortcut applescript shell script keyboard hotkey url breather://"
        case .about: "version"
        }
    }

    func matches(_ query: String) -> Bool {
        query.isEmpty || "\(title) \(summary) \(keywords)".localizedCaseInsensitiveContains(query)
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
        HeaderCard(symbol: pane.symbol, tint: pane.tint, title: pane.title, summary: pane.summary)
    }
}

extension SettingsPane: SidebarItem {}

struct SettingsView: View {
    let app: AppModel
    @State private var query = ""

    var body: some View {
        @Bindable var app = app
        SidebarWindow(selection: $app.settingsPane,
                      groups: SettingsPane.groups.map { SidebarGroup(title: $0.title, items: $0.panes) },
                      query: $query, matches: { $0.matches($1) }) {
            switch app.settingsPane {
            case .general: GeneralPane(app: app)
            case .schedule: SchedulePane(app: app)
            case .strictness: StrictnessPane(app: app)
            case .breakScreen: BreakScreenPane(app: app)
            case .messages: MessagesPane(app: app)
            case .smartPause: SmartPausePane(app: app)
            case .notch: NotchPane(app: app)
            case .reminders: RemindersPane(app: app)
            case .privacy: PrivacyPane(app: app)
            case .devices: DevicesPane(app: app)
            case .profiles: ProfilesPane(app: app)
            case .automations: AutomationsPane(app: app)
            case .about: AboutPane(app: app)
            }
        }
    }
}

// MARK: - General

private struct GeneralPane: View {
    let app: AppModel

    var body: some View {
        @Bindable var store = app.store
        Form {
            PaneHeader(pane: .general)
            Section("Profile") {
                Picker("Active profile", selection: Binding {
                    store.settings.activeProfileID
                } set: { id in
                    if let id { app.applyProfile(id) } else { store.settings.activeProfileID = nil }
                }) {
                    Text("Custom").tag(UUID?.none)
                    ForEach(store.settings.profiles) { profile in
                        Label(profile.name, systemImage: profile.symbol).tag(UUID?.some(profile.id))
                    }
                }
            }
            Section("Startup") {
                Toggle("Open Breather when you log in", isOn: $store.settings.launchAtLogin)
            }
            Section {
                Toggle("Show icon in the menu bar", isOn: $store.settings.showMenuBarIcon)
                if store.settings.showMenuBarIcon {
                    Toggle("Show time until break next to the icon", isOn: $store.settings.menuBarShowsTime)
                }
            } header: {
                Text("Menu bar")
            } footer: {
                if !store.settings.showMenuBarIcon {
                    Text("With the icon hidden, open Breather from Spotlight or Finder to get back here, or hover the notch.")
                }
            }
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
            Section {
                LabeledSlider(title: "“Take a break for…” length", value: $store.settings.customBreakMinutes, range: 1...60, step: 1) { "\(Int($0)) min" }
            } header: {
                Text("Breaks on demand")
            } footer: {
                Text("Used by the “Take a break for…” shortcut. The menu bar also offers 1–15 minute breaks.")
            }

            Section {
                Toggle("Only remind me during office hours", isOn: $store.settings.officeHours.enabled)
                if store.settings.officeHours.enabled {
                    ForEach(weekdayOrder, id: \.self) { index in
                        DayRow(name: Calendar.current.weekdaySymbols[index], day: $store.settings.officeHours.days[index])
                    }
                }
            } header: {
                Text("Office hours")
            } footer: {
                Text("An end time earlier than the start runs past midnight. Planned breaks run outside office hours too.")
            }

            PlannedBreaksSection(app: app)
        }
    }

    private var weekdayOrder: [Int] {
        let first = Calendar.current.firstWeekday - 1
        return (0..<7).map { (first + $0) % 7 }
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

// MARK: - Skipping & snoozing

private struct StrictnessPane: View {
    let app: AppModel

    var body: some View {
        @Bindable var store = app.store
        Form {
            PaneHeader(pane: .strictness)
            Section {
                Picker("Difficulty", selection: $store.settings.difficulty) {
                    ForEach(SkipDifficulty.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(store.settings.difficulty.detail).font(.caption).foregroundStyle(.secondary)
                if store.settings.difficulty == .balanced {
                    LabeledSlider(title: "Skip unlocks after", value: $store.settings.balancedSkipDelaySeconds, range: 2...20, step: 1) { "\(Int($0))s" }
                }
            } header: {
                Text("Skip difficulty")
            }
            if store.settings.difficulty != .hardcore {
                Section("Snoozing and skipping ahead") {
                    Stepper("Snoozes per break: \(store.settings.snoozeLimitPerBreak)", value: $store.settings.snoozeLimitPerBreak, in: 0...10)
                    Stepper("Skips in advance per day: \(store.settings.dailyAdvanceSkipLimit)", value: $store.settings.dailyAdvanceSkipLimit, in: 0...20)
                }
            }
            Section("During a break") {
                Toggle("Allow ending a break early", isOn: $store.settings.allowEndEarly)
                if store.settings.allowEndEarly {
                    LabeledSlider(title: "“End break” appears after", value: $store.settings.endEarlyAfterFraction, range: 0.25...1, step: 0.05) {
                        "\(Int($0 * 100))% of the break"
                    }
                }
                Toggle("Keep the break open until I click “End break”", isOn: $store.settings.keepBreakOpenUntilEnded)
                Toggle("Lock the screen when a long break starts", isOn: $store.settings.lockScreenOnBreak)
            }
            Section {
                Toggle("Nudge me when I go too long without a break", isOn: $store.settings.overtimeNudge)
                if store.settings.overtimeNudge {
                    LabeledSlider(title: "After going over by", value: $store.settings.overtimeNudgeMinutes, range: 5...60, step: 5) { "\(Int($0)) min" }
                }
            } header: {
                Text("Overtime")
            } footer: {
                Text("Counts time since your last real break. Snoozes and skips don't reset it.")
            }
        }
    }
}

// MARK: - Messages & sounds

private struct MessagesPane: View {
    let app: AppModel

    var body: some View {
        @Bindable var store = app.store
        Form {
            PaneHeader(pane: .messages)
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
                    SoundPicker(title: "Long break starts", selection: $store.settings.longBreakStartSound,
                                volume: store.settings.soundVolume, allowsSameAsShort: true)
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
    var allowsSameAsShort = false

    var body: some View {
        HStack {
            Picker(title, selection: $selection) {
                if allowsSameAsShort { Text("Same as short break").tag("") }
                ForEach(Sound.systemSounds, id: \.self) { Text($0).tag($0) }
                if selection.hasPrefix("/") { Text(Sound.displayName(selection)).tag(selection) }
            }
            Button("Choose…") { chooseFile() }
                .help("Use your own sound file")
            Button {
                Sound.play(selection, volume: volume)
            } label: {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.borderless)
            .disabled(selection.isEmpty)
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.prompt = "Use"
        if panel.runModal() == .OK, let url = panel.url { selection = url.path }
    }
}

// MARK: - Notch & alerts

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
            } header: {
                Text("Notch")
            } footer: {
                Text("On a MacBook with a notch, the island grows out of it. Hover the notch to peek at your next break.")
            }

            Section {
                Picker("Show alerts on", selection: $store.settings.alertDisplay) {
                    ForEach(AlertDisplay.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Use a floating pill on displays without a notch", isOn: $store.settings.pillOnScreensWithoutNotch)
            } header: {
                Text("Displays")
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
                        app.notch.show(NotchToast(symbol: "figure.walk", tint: Brand.mint, title: "Welcome back",
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
                LabeledSlider(title: "After an activity ends, wait", value: $store.settings.postActivityDelaySeconds, range: 0...300, step: 15) {
                    $0 == 0 ? "No delay" : Format.spoken($0)
                }
            } header: {
                Text("Interruptions")
            }

            Section("Time away") {
                Toggle("Count time away from the Mac as a break", isOn: $store.settings.idleCountsAsBreak)
                LabeledSlider(title: "You're away after", value: $store.settings.idleThresholdSeconds, range: 30...600, step: 30) { Format.spoken($0) + " idle" }
            }

            Section("Meetings") {
                Toggle("Calls & meetings (microphone or camera in use)", isOn: $store.settings.pauseForMeetings)
                if store.settings.pauseForMeetings {
                    AppList(title: "Apps that don't count as a call", apps: $store.settings.meetingExcludedApps)
                }
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

// MARK: - Automations

private struct AutomationsPane: View {
    let app: AppModel

    var body: some View {
        @Bindable var store = app.store
        Form {
            PaneHeader(pane: .automations)
            AutomationsSection(app: app)
            Section {
                ShortcutRow(title: "Take a break now", key: $store.settings.hotKeys.breakNow)
                ShortcutRow(title: "Take a break for \(Int(store.settings.customBreakMinutes)) min", key: $store.settings.hotKeys.customBreak)
                ShortcutRow(title: "Pause / resume", key: $store.settings.hotKeys.togglePause)
                ShortcutRow(title: "Skip next", key: $store.settings.hotKeys.skipNext)
            } header: {
                Text("Keyboard shortcuts")
            } footer: {
                Text("Global shortcuts work from any app. During a break, press Esc twice to skip.")
            }
            Section {
                ForEach(Self.commands, id: \.0) { url, what in
                    HStack {
                        Text(url).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                        Spacer()
                        Text(what).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Link commands")
            } footer: {
                Text("Open these from Shortcuts (Open URL), Raycast, Alfred, or Terminal with `open \"breather://break\"`.")
            }
        }
    }

    static let commands: [(String, String)] = [
        ("breather://break", "Break now"),
        ("breather://break?minutes=10", "Break of 1–60 minutes"),
        ("breather://long-break", "Long break"),
        ("breather://pause?minutes=30", "Pause (omit minutes: until resumed)"),
        ("breather://resume", "Resume"),
        ("breather://skip-next", "Skip the next break"),
        ("breather://profile?name=Deep%20Work", "Switch profile"),
        ("breather://stats", "Open Stats"),
        ("breather://settings", "Open Settings"),
    ]
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
        @Bindable var store = app.store
        Form {
            Section {
                VStack(spacing: 10) {
                    BreatherAppIcon().frame(width: 96, height: 96)
                    Text(Brand.name).font(.title.bold())
                    Text("Version \(app.updates.currentVersion)").foregroundStyle(.secondary)
                    Text("\(Brand.tagline)\nBreak reminders that live in your notch. Free and open source.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }

            Section {
                Toggle("Check for updates automatically", isOn: $store.settings.checkForUpdates)
                HStack {
                    if app.updates.isBusy { ProgressView().controlSize(.small) }
                    Text(updateText)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let release = app.updates.available {
                        Button("What's New") { NSWorkspace.shared.open(release.page) }
                        Button("Update Now") { Task { await app.updates.install() } }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("Check Now") { Task { await app.updates.check() } }
                            .disabled(app.updates.isBusy)
                    }
                }
                .animation(.snappy, value: app.updates.status)
            } header: {
                Text("Updates")
            } footer: {
                Text("Once a day Breather asks GitHub for the latest version. That's its only internet connection; nothing about you is sent. Update Now downloads the new version, checks its SHA-256 checksum and signature, and reopens Breather.")
            }

            Section {
                Link("Website", destination: Brand.website)
                Link("Source code on GitHub", destination: Brand.repository)
                Link("Report a bug or suggest a feature", destination: Brand.newIssue)
                LabeledContent("Licence", value: "GNU GPL v3.0")
            }

            Section {
                Button("Show Welcome Screen…") { app.showWelcome() }
                Button("Show data folder in Finder") {
                    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Breather")
                    NSWorkspace.shared.activateFileViewerSelecting([dir])
                }
                Button("Reset all settings", role: .destructive) { app.store.reset() }
            }
        }
    }

    private var updateText: String {
        switch app.updates.status {
        case .idle: "Not checked yet"
        case .checking: "Checking…"
        case .upToDate: "Breather is up to date"
        case .available(let release): "Breather \(release.version) is available"
        case .downloading(let version): "Downloading Breather \(version)…"
        case .installing(let version): "Installing Breather \(version)…"
        case .failed: "Couldn't reach GitHub"
        case .installFailed(_, let message): message
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
