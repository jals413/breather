import AppKit
import BreatherKit
import SwiftUI
import Observation

struct PauseOption: Identifiable {
    let id: String
    let title: String
    var shortTitle: String {
        switch id {
        case "30m": "30 min"
        case "1h": "1 hr"
        case "2h": "2 hr"
        case "tomorrow": "Rest of day"
        default: "Until resumed"
        }
    }
    /// nil = until resumed.
    let duration: () -> TimeInterval?

    static let all: [PauseOption] = [
        PauseOption(id: "30m", title: "For 30 minutes") { 30 * 60 },
        PauseOption(id: "1h", title: "For 1 hour") { 60 * 60 },
        PauseOption(id: "2h", title: "For 2 hours") { 2 * 60 * 60 },
        PauseOption(id: "tomorrow", title: "Until tomorrow") {
            let tomorrow = Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400))
            return tomorrow.timeIntervalSinceNow
        },
        PauseOption(id: "forever", title: "Until I resume") { nil },
    ]
}

enum SkipState: Equatable {
    case hidden
    case locked(TimeInterval)
    case skip
    case endBreak
}

/// Owns every subsystem and wires engine events to UI, sound and the log.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let store = SettingsStore()
    let engine: BreakEngine
    let log = BreakLog()
    let notch = NotchModel()
    let usage = UsageTracker()
    let phone = PhoneLink()

    @ObservationIgnored private let activity = ActivityMonitor()
    @ObservationIgnored private let smartPause = SmartPauseMonitor()
    @ObservationIgnored private var notchController: NotchWindowController?
    @ObservationIgnored private var overlay: BreakOverlayController?
    @ObservationIgnored private let hotKeys = HotKeyCenter()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastSnapshot = Date.distantPast
    @ObservationIgnored private var lastPauseNag = Date()
    @ObservationIgnored private var lastSmartReasons: [PauseReason] = []
    @ObservationIgnored private let settingsWindow = SettingsWindowController()
    @ObservationIgnored private let welcome = WelcomeWindowController()
    @ObservationIgnored let routines = RoutineScheduler()
    @ObservationIgnored private let statsWindow = StatsWindowController()
    @ObservationIgnored private var lastTickDate: Date?
    @ObservationIgnored private var lastOvertimeNudge = Date.distantPast

    private static let snapshotKey = "engine.snapshot"

    private init() {
        engine = BreakEngine(settings: store.settings)
    }

    /// Puts the model in a representative state for `--render-snapshots`.
    func prepareForSnapshots() {
        notch.attach(engine)
        engine.setWorkElapsedForPreview(engine.workTarget - 58)
    }

    func start() {
        notch.attach(engine)
        notch.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        store.onChange = { [weak self] old, new in self?.settingsChanged(old: old, new: new) }
        engine.onEvent = { [weak self] event in self?.handle(event) }

        if let data = UserDefaults.standard.data(forKey: Self.snapshotKey),
           let snapshot = try? JSONDecoder().decode(EngineSnapshot.self, from: data) {
            engine.restore(snapshot)
        }
        engine.restoreDailyCounters(advanceSkips: log.advanceSkipsToday)

        activity.onWake = { [weak self] in
            self?.smartPause.invalidate()
            self?.tick()
        }

        notchController = NotchWindowController(app: self)
        notchController?.start()
        overlay = BreakOverlayController(app: self)

        registerHotKeys()
        LoginItem.sync(enabled: store.settings.launchAtLogin)
        phone.onCommand = { [weak self] command in self?.handle(command) }
        configurePhone(store.settings)
        baseProfileID = store.settings.activeProfileID
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let id = app?.bundleIdentifier
            MainActor.assumeIsolated { self?.frontmostAppChanged(id) }
        }

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()

        let testingAnimation = CommandLine.arguments.contains("--animation-test")
        AnimationRecorder.runIfRequested(app: self) { [weak self] in self?.notchController?.hostView }
        if !testingAnimation, !UserDefaults.standard.bool(forKey: "welcomed") {
            welcome.show(app: self) { [weak self] in
                UserDefaults.standard.set(true, forKey: "welcomed")
                self?.notch.show(NotchToast(symbol: "checkmark.circle.fill", tint: Brand.mint, title: "Breather is running",
                                            subtitle: "It'll stay out of the way until a break is near."), for: 6)
            }
        }
    }

    func saveState() {
        if let data = try? JSONEncoder().encode(engine.snapshot()) {
            UserDefaults.standard.set(data, forKey: Self.snapshotKey)
        }
        usage.save()
    }

    // MARK: Profiles

    @ObservationIgnored private var applyingProfile = false
    /// The profile chosen by hand; app-triggered switches return to it.
    @ObservationIgnored private var baseProfileID: UUID?
    @ObservationIgnored private var autoSwitched = false

    var activeProfile: Profile? {
        store.settings.profiles.first { $0.id == store.settings.activeProfileID }
    }

    func applyProfile(_ id: UUID, manual: Bool = true) {
        guard let profile = store.settings.profiles.first(where: { $0.id == id }) else { return }
        applyingProfile = true
        var s = store.settings
        profile.values.apply(to: &s)
        s.activeProfileID = id
        store.settings = s
        applyingProfile = false
        if manual {
            baseProfileID = id
            autoSwitched = false
        }
        notch.show(NotchToast(symbol: profile.symbol, tint: Brand.mint, title: profile.name,
                              subtitle: "Breaks every \(Format.compact(s.workSeconds)) · \(s.difficulty.title.lowercased())"), for: 3)
    }

    func saveCurrentAsProfile(named name: String) {
        let profile = Profile(name: name, symbol: "bolt.fill", values: ProfileValues(from: store.settings))
        store.settings.profiles.append(profile)
        store.settings.activeProfileID = profile.id
        baseProfileID = profile.id
    }

    private func frontmostAppChanged(_ bundleID: String?) {
        guard let bundleID else { return }
        let profiles = store.settings.profiles
        if let match = profiles.first(where: { $0.triggerApps.contains { $0.bundleID == bundleID } }) {
            if store.settings.activeProfileID != match.id {
                if !autoSwitched { baseProfileID = store.settings.activeProfileID }
                autoSwitched = true
                applyProfile(match.id, manual: false)
            }
        } else if autoSwitched {
            autoSwitched = false
            if let base = baseProfileID { applyProfile(base, manual: false) }
        }
    }

    // MARK: iPhone & Watch

    private func configurePhone(_ s: Settings) {
        phone.setEnabled(s.phoneLinkEnabled)
        phone.apns.config = APNsClient.Config(teamID: s.apnsTeamID, keyID: s.apnsKeyID, keyPath: s.apnsKeyPath)
    }

    /// The Mac's state as the phone and Watch see it.
    func phoneState(now: Date = .now) -> MacState {
        let s = store.settings
        var state = MacState(mode: .working, detail: statusTitle, takenToday: log.takenToday, score: usage.score,
                             workSeconds: s.workSeconds, profile: activeProfile?.name, macName: phone.macName,
                             blockPhone: s.phoneBlockDuringBreaks)
        switch engine.phase {
        case .working:
            state.nextBreakAt = now.addingTimeInterval(engine.timeUntilBreak)
        case .holding, .smartPaused:
            state.mode = .onHold
            state.nextBreakAt = now.addingTimeInterval(engine.timeUntilBreak)
        case .paused(let until):
            state.mode = .paused
            state.pausedUntil = until
        case .away:
            state.mode = .away
        case .offHours:
            state.mode = .offHours
        case .onBreak(let session):
            state.mode = .onBreak
            state.breakStart = session.start
            state.breakEnd = session.end
            state.breakTitle = session.title ?? session.kind.title
            state.breakMessage = session.message
            state.isLongBreak = session.kind == .long
        }
        return state
    }

    private func handle(_ command: PhoneCommand) {
        switch command {
        case .breakNow: breakNow()
        case .breakFor(let minutes): customBreak(minutes: minutes)
        case .snooze(let minutes): snooze(minutes * 60)
        case .skipNext: if !engine.skipNextPending { engine.toggleSkipNext() }
        case .pause(let minutes): engine.pause(for: minutes.map { $0 * 60 })
        case .resume: resume()
        case .endBreak: skipOrEndBreak()
        }
        phone.publish(phoneState(), force: true)
    }

    // MARK: URL scheme

    /// breather://break[?minutes=N], long-break, pause[?minutes=N], resume, skip-next,
    /// profile?name=…, settings, stats
    func handle(url: URL) {
        guard url.scheme == "breather" else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let minutes = items.first { $0.name == "minutes" }?.value.flatMap(Double.init)
        switch url.host() ?? "" {
        case "break": engine.startBreak(kind: minutes == nil ? nil : .custom, duration: minutes.map { $0 * 60 })
        case "long-break": engine.startBreak(kind: .long)
        case "pause":
            engine.pause(for: minutes.map { $0 * 60 })
        case "resume": resume()
        case "skip-next": if !engine.skipNextPending { engine.toggleSkipNext() }
        case "profile":
            if let name = items.first(where: { $0.name == "name" })?.value,
               let p = store.settings.profiles.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
                applyProfile(p.id)
            }
        case "settings": openSettings()
        case "stats": openStats()
        default: break
        }
    }

    // MARK: Tick

    private func tick() {
        let now = Date()
        let settings = store.settings
        var signals = ActivitySignals()
        signals.secondsSinceInput = activity.secondsSinceAnyInput
        signals.secondsSinceTyping = activity.secondsSinceTyping
        signals.isLockedOrAsleep = activity.isLocked || activity.isAsleep
        // Smart pause only matters while counting toward a break.
        if !engine.isOnBreak && !signals.isLockedOrAsleep {
            signals.pauseReasons = smartPause.reasonsIfDue(now: now, settings: settings)
        }
        engine.tick(now: now, signals: signals)

        let dt = lastTickDate.map { now.timeIntervalSince($0) } ?? 0
        lastTickDate = now
        for event in routines.tick(now: now, dt: dt, engine: engine) { handle(event) }
        // A regular break due just before a planned one is dropped so they don't stack.
        if let planned = routines.secondsUntilNextPlanned(now: now, settings: settings) {
            engine.absorbUpcomingBreak(planned < 10 * 60 && engine.timeUntilBreak < planned)
        } else if engine.absorbNext {
            engine.absorbUpcomingBreak(false)
        }
        nudgeIfOvertime(now: now)
        if store.settings.phoneLinkEnabled { phone.publish(phoneState(now: now)) }
        usage.tick(now: now, dt: dt, engine: engine, settings: settings)

        announceSmartPauseChanges(signals.pauseReasons)
        nagIfPausedTooLong(now: now)
        notch.recompute(now: now)
        notchController?.contentChanged()

        if now.timeIntervalSince(lastSnapshot) > 15 {
            lastSnapshot = now
            saveState()
        }
    }

    private func announceSmartPauseChanges(_ reasons: [PauseReason]) {
        defer { lastSmartReasons = reasons }
        // Only worth a toast if a break was close and is now being held off.
        guard let first = reasons.first, lastSmartReasons.isEmpty, engine.timeUntilBreak < 120 else { return }
        notch.show(NotchToast(symbol: first.symbol, tint: Brand.sky, title: "Break on hold",
                              subtitle: first.title + " · it'll wait until you're done"), for: 5)
    }

    private func nudgeIfOvertime(now: Date) {
        let s = store.settings
        guard s.overtimeNudge, !engine.isOnBreak, !engine.phase.isInCall else { return }
        let interval = s.overtimeNudgeMinutes * 60
        guard usage.currentSession > s.workSeconds + interval, now.timeIntervalSince(lastOvertimeNudge) > interval else { return }
        lastOvertimeNudge = now
        notch.show(NotchToast(symbol: "exclamationmark.circle.fill", tint: Brand.amber,
                              title: "\(Format.hoursMinutes(usage.currentSession)) without a real break",
                              subtitle: "Your eyes would like one.", action: .breakNow, actionTitle: "Take one"), for: 12)
    }

    private func nagIfPausedTooLong(now: Date) {
        guard case .paused(let until) = engine.phase, until == nil else {
            lastPauseNag = now
            return
        }
        if now.timeIntervalSince(lastPauseNag) > 60 * 60 {
            lastPauseNag = now
            notch.show(NotchToast(symbol: "pause.circle.fill", tint: Brand.amber, title: "Breaks are still paused",
                                  subtitle: "It's been over an hour.", action: .resume, actionTitle: "Resume"), for: 12)
        }
    }

    // MARK: Events

    private func handle(_ event: EngineEvent) {
        let settings = store.settings
        switch event {
        case .headsUp(let kind):
            notch.showHeadsUp(kind)

        case .breakStarted(let session):
            notch.dismissHeadsUp()
            notch.dismissToast()
            notch.recompute()
            notchController?.contentChanged()
            overlay?.show()
            if settings.soundEnabled {
                let sound = session.kind == .long && !settings.longBreakStartSound.isEmpty ? settings.longBreakStartSound : settings.breakStartSound
                Sound.play(sound, volume: settings.soundVolume)
            }
            if settings.lockScreenOnBreak && session.kind == .long { ActivityMonitor.lockScreen() }
            if settings.automations.enabled {
                AutomationRunner.run(shortcut: settings.automations.startShortcut, script: settings.automations.startScript,
                                     language: settings.automations.language)
            }

        case .breakEnded(let session, let completed):
            overlay?.hide()
            runEndAutomations()
            // A snooze ends the overlay but not the work session.
            if completed { usage.endSession(completed: true) }
            if completed {
                log.append(BreakLogEntry(date: .now, outcome: .taken, kind: session.kind, seconds: session.duration))
                if settings.soundEnabled { Sound.play(settings.breakEndSound, volume: settings.soundVolume) }
            }

        case .breakSkipped(let kind, let inAdvance):
            overlay?.hide()
            if !inAdvance { runEndAutomations() }
            usage.recordSkip()
            log.append(BreakLogEntry(date: .now, outcome: inAdvance ? .skippedInAdvance : .skipped, kind: kind))
            if inAdvance {
                notch.show(NotchToast(symbol: "forward.fill", tint: Brand.amber, title: "Skipped this break",
                                      subtitle: "As you asked. Next one in \(Format.spoken(settings.workSeconds))"), for: 5)
            }

        case .snoozed(let seconds):
            overlay?.hide()
            notch.dismissHeadsUp()
            log.append(BreakLogEntry(date: .now, outcome: .snoozed, seconds: seconds))
            notch.show(NotchToast(symbol: "clock.arrow.circlepath", tint: Brand.amber, title: "Break in \(Format.spoken(seconds))",
                                  subtitle: snoozeSubtitle), for: 3)

        case .naturalBreak(let away, let kind):
            log.append(BreakLogEntry(date: .now, outcome: .natural, kind: kind, seconds: away))
            routines.didRest(for: away)
            usage.endSession(completed: true)
            notch.show(NotchToast(symbol: "figure.walk", tint: .breatherMint, title: "Welcome back",
                                  subtitle: "\(Format.spoken(away)) away counted as a \(kind == .long ? "long " : "")break",
                                  action: .undoNaturalBreak, actionTitle: "Undo"), for: 10)

        case .resumed:
            break
        }
        notch.recompute()
        notchController?.contentChanged()
    }

    private func runEndAutomations() {
        let a = store.settings.automations
        if a.enabled { AutomationRunner.run(shortcut: a.endShortcut, script: a.endScript, language: a.language) }
    }

    private func handle(_ event: RoutineEvent) {
        switch event {
        case .remind(let reminder):
            if let sound = reminder.sound, store.settings.soundEnabled { Sound.play(sound, volume: store.settings.soundVolume) }
            notch.show(NotchToast(symbol: reminder.symbol, tint: reminder.tint.color, title: reminder.title,
                                  subtitle: reminder.message, action: .reminderDone(reminder.id), actionTitle: "Done",
                                  secondaryAction: .reminderLater(reminder.id), secondaryTitle: "Later"), for: 15)
        case .plannedBreakSoon(let planned, let seconds):
            notch.show(NotchToast(symbol: "calendar.badge.clock", tint: Brand.amber, title: "\(planned.title) in \(Format.compact(seconds))",
                                  subtitle: Format.spoken(planned.durationMinutes * 60) + " break"), for: 8)
        case .startPlannedBreak(let planned):
            engine.startBreak(kind: .custom, duration: planned.durationMinutes * 60, title: planned.title,
                              message: planned.message.isEmpty ? nil : planned.message)
        case .plannedBreakLate(let planned):
            notch.show(NotchToast(symbol: "calendar.badge.clock", tint: Brand.amber, title: "Time for \(planned.title.lowercased())",
                                  subtitle: "It was due while you were busy.", action: .startPlanned(planned.id), actionTitle: "Start",
                                  secondaryAction: .skipPlanned, secondaryTitle: "Skip today"), for: 30)
        case .plannedBreakMissed(let planned):
            log.append(BreakLogEntry(date: .now, outcome: .skipped, kind: .custom))
            notch.show(NotchToast(symbol: "calendar.badge.exclamationmark", tint: Brand.amber, title: "Missed \(planned.title.lowercased())",
                                  subtitle: "You were busy. Take it when you can."), for: 8)
        }
    }

    private var snoozeSubtitle: String {
        let left = store.settings.snoozeLimitPerBreak - engine.snoozesThisCycle
        return left > 0 ? "\(left) snooze\(left == 1 ? "" : "s") left for this break" : "No snoozes left for this break"
    }

    private func settingsChanged(old: Settings, new: Settings) {
        engine.settings = new
        configurePhone(new)
        // Edits made while a profile is active are saved into that profile.
        if !applyingProfile, let id = new.activeProfileID, ProfileValues(from: old) != ProfileValues(from: new),
           let index = new.profiles.firstIndex(where: { $0.id == id }) {
            store.settings.profiles[index].values = ProfileValues(from: new)
        }
        smartPause.invalidate()
        if old.hotKeys != new.hotKeys { registerHotKeys() }
        if old.launchAtLogin != new.launchAtLogin { LoginItem.sync(enabled: new.launchAtLogin) }
        if old.pillOnScreensWithoutNotch != new.pillOnScreensWithoutNotch || old.alertDisplay != new.alertDisplay {
            notchController = NotchWindowController(app: self)
            notchController?.start()
        }
    }

    private func registerHotKeys() {
        let keys = store.settings.hotKeys
        hotKeys.register([
            (keys.breakNow, { [weak self] in self?.breakNow() }),
            (keys.togglePause, { [weak self] in self?.togglePause() }),
            (keys.skipNext, { [weak self] in self?.engine.toggleSkipNext() }),
            (keys.customBreak, { [weak self] in self?.customBreak() }),
        ])
    }

    // MARK: Actions (UI)

    func breakNow() {
        notch.isHovering = false
        engine.startBreak()
    }

    func snooze(_ seconds: TimeInterval) { engine.snooze(seconds) }

    /// "Take a break for…": any length, any time.
    func customBreak(minutes: Double? = nil) {
        notch.isHovering = false
        engine.startBreak(kind: .custom, duration: (minutes ?? store.settings.customBreakMinutes) * 60)
    }

    /// Heads-up "Skip": skip the upcoming break without seeing it.
    func skipUpcoming() {
        if !engine.skipNextPending { engine.toggleSkipNext() }
        notch.dismissHeadsUp()
    }

    func pause(_ option: PauseOption) {
        notch.isHovering = false
        engine.pause(for: option.duration())
        notch.show(NotchToast(symbol: "pause.circle.fill", tint: .white, title: "Breaks paused",
                              subtitle: option.title,
                              action: .resume, actionTitle: "Resume"), for: 4)
    }

    func togglePause() {
        if case .paused = engine.phase { resume() } else { pause(PauseOption.all[1]) }
    }

    func resume() {
        engine.resume()
        notch.show(NotchToast(symbol: "play.circle.fill", tint: .breatherMint, title: "Breaks resumed",
                              subtitle: "Next one in \(Format.spoken(engine.timeUntilBreak))"), for: 3)
    }

    func perform(_ action: NotchToast.Action) {
        switch action {
        case .undoNaturalBreak: engine.undoNaturalBreak()
        case .resume: resume()
        case .reminderDone(let id): routines.resetReminder(id)
        case .startPlanned(let id):
            if let p = store.settings.plannedBreaks.first(where: { $0.id == id }) {
                engine.startBreak(kind: .custom, duration: p.durationMinutes * 60, title: p.title, message: p.message.isEmpty ? nil : p.message)
            }
        case .skipPlanned: break
        case .breakNow: breakNow()
        case .reminderLater(let id):
            let minutes = store.settings.reminders.first { $0.id == id }?.laterMinutes ?? 10
            routines.snooze(id, minutes: minutes, settings: store.settings)
        }
        notch.dismissToast()
    }

    func openSettings() {
        notch.isHovering = false
        settingsWindow.show(app: self)
    }

    func showWelcome() {
        welcome.show(app: self) {}
    }

    func openStats() {
        notch.isHovering = false
        statsWindow.show(app: self)
    }

    func skipState(now: Date) -> SkipState {
        guard case .onBreak(let session) = engine.phase else { return .hidden }
        let s = store.settings
        let elapsed = now.timeIntervalSince(session.start)
        if elapsed >= session.duration { return .endBreak } // kept open past its timer
        if s.allowEndEarly && elapsed >= session.duration * s.endEarlyAfterFraction { return .endBreak }
        switch s.difficulty {
        case .hardcore: return .hidden
        case .casual: return .skip
        case .balanced:
            return elapsed < s.balancedSkipDelaySeconds ? .locked(s.balancedSkipDelaySeconds - elapsed) : .skip
        }
    }

    func canSkipCurrentBreak(now: Date) -> Bool {
        switch skipState(now: now) {
        case .skip, .endBreak: true
        case .hidden, .locked: false
        }
    }

    func skipOrEndBreak() {
        switch skipState(now: .now) {
        case .endBreak: engine.endBreak()
        case .skip: engine.skipBreak()
        default: break
        }
    }

    // MARK: Status text (menu bar + dashboard)

    var statusTitle: String {
        switch engine.phase {
        case .working, .onBreak: "\(engine.nextBreakKind == .long ? "Long break" : "Break") in \(Format.compact(engine.timeUntilBreak))"
        case .holding(.typing): "Waiting for a pause in typing"
        case .holding(.afterActivity): "Break in a moment"
        case .smartPaused(let reasons): reasons.first?.title ?? "On hold"
        case .paused(let until): until.map { "Paused · \(Format.compact($0.timeIntervalSinceNow)) left" } ?? "Paused"
        case .away: "Away"
        case .offHours: "Outside office hours"
        }
    }

    var statusSubtitle: String {
        switch engine.phase {
        case .smartPaused: return "Your break will wait until this ends."
        case .holding(.typing): return "Finish your thought — the break starts when you stop typing."
        case .holding(.afterActivity): return "Giving you a minute after that activity."
        case .away: return "Time away counts as a break."
        case .offHours: return "Breaks resume when your office hours start."
        case .paused: return "Smart reminders are off until you resume."
        default:
            let longIn = max(0, store.settings.longBreakEvery - engine.breaksSinceLong)
            return store.settings.longBreakEnabled
                ? (longIn == 0 ? "Next break is a long one." : "Long break after \(longIn) more")
                : "Every \(Format.spoken(store.settings.workSeconds))"
        }
    }
}
