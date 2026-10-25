import AppKit
import SwiftUI

// MARK: - Reminders

struct RemindersPane: View {
    let app: AppModel

    var body: some View {
        @Bindable var store = app.store
        Form {
            PaneHeader(pane: .reminders)
            Section {
                ForEach($store.settings.reminders) { $reminder in
                    ReminderRow(reminder: $reminder) {
                        store.settings.reminders.removeAll { $0.id == reminder.id }
                    }
                }
                HStack {
                    Spacer()
                    Button("Add Reminder") {
                        store.settings.reminders.append(Reminder(title: "New reminder", message: "", symbol: "bell.fill",
                                                                 tint: RGBA(Brand.mint), intervalMinutes: 30))
                    }
                }
            } footer: {
                Text("Reminders appear in the notch with Done and Later. They count only time you're actually at your Mac.")
            }
            Section {
                Toggle("Hold reminders during calls and screen recording", isOn: $store.settings.remindersPauseInCalls)
            }
        }
    }
}

private struct ReminderRow: View {
    @Binding var reminder: Reminder
    var onDelete: () -> Void
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Title", text: $reminder.title)
                TextField("Message", text: $reminder.message)
                LabeledSlider(title: "Every", value: $reminder.intervalMinutes, range: 5...180, step: 5) { "\(Int($0)) min" }
                LabeledSlider(title: "“Later” waits", value: $reminder.laterMinutes, range: 1...60, step: 1) { "\(Int($0)) min" }
                HStack {
                    Picker("Icon", selection: $reminder.symbol) {
                        ForEach(Reminder.symbolChoices, id: \.self) { Image(systemName: $0).tag($0) }
                    }
                    ColorPicker("Colour", selection: Binding { reminder.tint.color } set: { reminder.tint = RGBA($0) }, supportsOpacity: false)
                }
                Picker("Sound", selection: Binding { reminder.sound ?? "" } set: { reminder.sound = $0.isEmpty ? nil : $0 }) {
                    Text("None").tag("")
                    ForEach(Sound.systemSounds, id: \.self) { Text($0).tag($0) }
                }
                HStack {
                    Spacer()
                    Button("Delete", role: .destructive, action: onDelete)
                }
            }
            .padding(.vertical, 6)
        } label: {
            HStack(spacing: 10) {
                SettingsBadge(symbol: reminder.symbol, tint: reminder.tint.color)
                VStack(alignment: .leading, spacing: 1) {
                    Text(reminder.title)
                    Text("Every \(Int(reminder.intervalMinutes)) min").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $reminder.enabled).labelsHidden().toggleStyle(.switch)
            }
        }
    }
}

// MARK: - Planned breaks & automations (sections used by the Schedule and Automations panes)

struct PlannedBreaksSection: View {
    let app: AppModel

    var body: some View {
        @Bindable var store = app.store
        Section {
            ForEach($store.settings.plannedBreaks) { $planned in
                PlannedRow(planned: $planned) { store.settings.plannedBreaks.removeAll { $0.id == planned.id } }
            }
            HStack {
                Spacer()
                Button("Add Planned Break") {
                    store.settings.plannedBreaks.append(PlannedBreak(title: "Walk", message: "Get some fresh air.",
                                                                     minuteOfDay: 16 * 60, durationMinutes: 10))
                }
            }
        } header: {
            Text("Planned breaks")
        } footer: {
            Text("Breaks at a fixed time, like lunch. You get a heads-up 2 minutes before, and a regular break due just before is skipped so they don't stack. If you're busy, Breather waits up to 45 minutes, then offers Start or Skip today.")
        }
    }
}

struct AutomationsSection: View {
    let app: AppModel
    @State private var shortcuts: [String] = []

    var body: some View {
        @Bindable var store = app.store
        Section {
            Toggle("Run automations", isOn: $store.settings.automations.enabled)
            if store.settings.automations.enabled {
                ShortcutPicker(title: "When a break starts, run Shortcut", selection: $store.settings.automations.startShortcut, names: shortcuts)
                ShortcutPicker(title: "When a break ends, run Shortcut", selection: $store.settings.automations.endShortcut, names: shortcuts)
                Picker("Script language", selection: $store.settings.automations.language) {
                    ForEach(Automations.Language.allCases) { Text($0.title).tag($0) }
                }
                ScriptField(title: "Script on break start", text: $store.settings.automations.startScript)
                ScriptField(title: "Script on break end", text: $store.settings.automations.endScript)
            }
        } header: {
            Text("When breaks start and end")
        } footer: {
            Text("Pause music, turn on Do Not Disturb, dim the lights: anything a Shortcut or script can do.")
        }
        .task {
            shortcuts = await Task.detached { AutomationRunner.shortcutNames() }.value
        }
    }
}

private struct PlannedRow: View {
    @Binding var planned: PlannedBreak
    var onDelete: () -> Void
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Name", text: $planned.title)
                TextField("Message", text: $planned.message)
                DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                LabeledSlider(title: "Length", value: $planned.durationMinutes, range: 1...90, step: 1) { "\(Int($0)) min" }
                HStack(spacing: 6) {
                    Button("Weekdays") { planned.weekdays = [1, 2, 3, 4, 5] }
                    Button("Weekends") { planned.weekdays = [0, 6] }
                    Button("Every day") { planned.weekdays = Set(0...6) }
                }
                .buttonStyle(.link)
                .font(.caption)
                HStack(spacing: 4) {
                    ForEach(weekdayOrder, id: \.self) { day in
                        let on = planned.weekdays.contains(day)
                        Button(Calendar.current.veryShortWeekdaySymbols[day]) {
                            if on { planned.weekdays.remove(day) } else { planned.weekdays.insert(day) }
                        }
                        .buttonStyle(.bordered)
                        .tint(on ? .accentColor : .secondary)
                    }
                }
                HStack {
                    Spacer()
                    Button("Delete", role: .destructive, action: onDelete)
                }
            }
            .padding(.vertical, 6)
        } label: {
            HStack(spacing: 10) {
                SettingsBadge(symbol: "calendar.badge.clock", tint: .orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text(planned.title)
                    Text("\(timeString) · \(Int(planned.durationMinutes)) min").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $planned.enabled).labelsHidden().toggleStyle(.switch)
            }
        }
    }

    private var weekdayOrder: [Int] {
        let first = Calendar.current.firstWeekday - 1
        return (0..<7).map { (first + $0) % 7 }
    }

    private var timeBinding: Binding<Date> {
        Binding {
            Calendar.current.startOfDay(for: .now).addingTimeInterval(TimeInterval(planned.minuteOfDay * 60))
        } set: {
            let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
            planned.minuteOfDay = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }
    }

    private var timeString: String {
        timeBinding.wrappedValue.formatted(date: .omitted, time: .shortened)
    }
}

private struct ShortcutPicker: View {
    var title: String
    @Binding var selection: String
    var names: [String]

    var body: some View {
        Picker(title, selection: $selection) {
            Text("None").tag("")
            if !selection.isEmpty && !names.contains(selection) { Text(selection).tag(selection) }
            ForEach(names, id: \.self) { Text($0).tag($0) }
        }
    }
}

private struct ScriptField: View {
    var title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            TextEditor(text: $text)
                .font(.system(.callout, design: .monospaced))
                .frame(minHeight: 50)
                .scrollContentBackground(.hidden)
        }
    }
}

// MARK: - Profiles

struct ProfilesPane: View {
    let app: AppModel
    @State private var newName = ""

    var body: some View {
        @Bindable var store = app.store
        Form {
            PaneHeader(pane: .profiles)
            Section {
                ForEach($store.settings.profiles) { $profile in
                    ProfileRow(app: app, profile: $profile, active: store.settings.activeProfileID == profile.id)
                }
            } footer: {
                Text("A profile saves your rhythm, strictness, heads-up and break screen look. Changes you make while a profile is active are saved to it.")
            }
            Section("New profile") {
                HStack {
                    TextField("Name", text: $newName)
                    Button("Save Current Settings") {
                        app.saveCurrentAsProfile(named: newName.isEmpty ? "My Profile" : newName)
                        newName = ""
                    }
                }
            }
        }
    }
}

private struct ProfileRow: View {
    let app: AppModel
    @Binding var profile: Profile
    var active: Bool
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Name", text: $profile.name)
                Picker("Icon", selection: $profile.symbol) {
                    ForEach(Profile.symbolChoices, id: \.self) { Image(systemName: $0).tag($0) }
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Switch automatically when using")
                        Spacer()
                        Button("Add App…") {
                            for chosen in AppChooser.choose() where !profile.triggerApps.contains(where: { $0.bundleID == chosen.bundleID }) {
                                profile.triggerApps.append(ExcludedApp(bundleID: chosen.bundleID, name: chosen.name))
                            }
                        }
                    }
                    ForEach(profile.triggerApps) { trigger in
                        HStack {
                            AppIcon(bundleID: trigger.bundleID)
                            Text(trigger.name)
                            Spacer()
                            Button { profile.triggerApps.removeAll { $0.bundleID == trigger.bundleID } } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                        }
                    }
                }
                HStack {
                    Spacer()
                    Button("Delete", role: .destructive) {
                        let id = profile.id
                        if app.store.settings.activeProfileID == id { app.store.settings.activeProfileID = nil }
                        app.store.settings.profiles.removeAll { $0.id == id }
                    }
                }
            }
            .padding(.vertical, 6)
        } label: {
            HStack(spacing: 10) {
                SettingsBadge(symbol: profile.symbol, tint: active ? Brand.teal : .gray)
                VStack(alignment: .leading, spacing: 1) {
                    Text(profile.name)
                    Text("Every \(Int(profile.values.workMinutes)) min · \(Format.spoken(profile.values.breakSeconds)) · \(profile.values.difficulty.title)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if active {
                    Label("Active", systemImage: "checkmark.circle.fill").labelStyle(.titleAndIcon).foregroundStyle(Brand.teal).font(.caption.weight(.semibold))
                } else {
                    Button("Use") { app.applyProfile(profile.id) }
                }
            }
        }
    }
}

// MARK: - Stats & privacy

struct PrivacyPane: View {
    let app: AppModel

    var body: some View {
        @Bindable var store = app.store
        Form {
            PaneHeader(pane: .privacy)
            Section {
                Toggle("Track time per app", isOn: $store.settings.trackAppUsage)
                Toggle("Track time per website", isOn: $store.settings.trackWebsites)
                HStack {
                    Spacer()
                    Button("Open Stats") { app.openStats() }
                }
            } footer: {
                Text("Website tracking reads the front tab's address in Safari and Chromium browsers (Chrome, Arc, Brave, Edge, Vivaldi, Opera). macOS asks once per browser. Firefox isn't supported. Stats are stored only on this Mac, in ~/Library/Application Support/Breather.")
            }
        }
    }
}
