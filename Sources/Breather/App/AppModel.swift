import AppKit
import SwiftUI
import Observation

struct PauseOption: Identifiable {
    let id: String
    let title: String
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

    private static let snapshotKey = "engine.snapshot"

    private init() {
        engine = BreakEngine(settings: store.settings)
    }

    func start() {
        notch.attach(engine)
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

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()

        if !UserDefaults.standard.bool(forKey: "onboarded") {
            UserDefaults.standard.set(true, forKey: "onboarded")
            notch.show(NotchToast(symbol: "eye", tint: .breatherMint, title: "Breather is running",
                                  subtitle: "Hover the notch any time to see your next break."), for: 8)
        }
    }

    func saveState() {
        if let data = try? JSONEncoder().encode(engine.snapshot()) {
            UserDefaults.standard.set(data, forKey: Self.snapshotKey)
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
        notch.show(NotchToast(symbol: first.symbol, tint: .cyan, title: "Break on hold",
                              subtitle: first.title + " · it'll wait until you're done"), for: 5)
    }

    private func nagIfPausedTooLong(now: Date) {
        guard case .paused(let until) = engine.phase, until == nil else {
            lastPauseNag = now
            return
        }
        if now.timeIntervalSince(lastPauseNag) > 60 * 60 {
            lastPauseNag = now
            notch.show(NotchToast(symbol: "pause.circle.fill", tint: .orange, title: "Breaks are still paused",
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
            if settings.soundEnabled { Sound.play(settings.breakStartSound, volume: settings.soundVolume) }
            if settings.lockScreenOnBreak && session.kind == .long { ActivityMonitor.lockScreen() }

        case .breakEnded(let session, let completed):
            overlay?.hide()
            if completed {
                log.append(BreakLogEntry(date: .now, outcome: .taken, kind: session.kind, seconds: session.duration))
                if settings.soundEnabled { Sound.play(settings.breakEndSound, volume: settings.soundVolume) }
                notch.show(NotchToast(symbol: "checkmark.circle.fill", tint: .breatherMint, title: "Nice — break done",
                                      subtitle: "Next one in \(Format.spoken(settings.workSeconds))"), for: 4)
            }

        case .breakSkipped(let kind, let inAdvance):
            overlay?.hide()
            log.append(BreakLogEntry(date: .now, outcome: inAdvance ? .skippedInAdvance : .skipped, kind: kind))
            if inAdvance {
                notch.show(NotchToast(symbol: "forward.fill", tint: .orange, title: "Skipped this break",
                                      subtitle: "As you asked. Next one in \(Format.spoken(settings.workSeconds))"), for: 5)
            }

        case .snoozed(let seconds):
            overlay?.hide()
            notch.dismissHeadsUp()
            log.append(BreakLogEntry(date: .now, outcome: .snoozed, seconds: seconds))
            notch.show(NotchToast(symbol: "clock.arrow.circlepath", tint: .orange, title: "Break in \(Format.spoken(seconds))",
                                  subtitle: snoozeSubtitle), for: 3)

        case .naturalBreak(let away, let kind):
            log.append(BreakLogEntry(date: .now, outcome: .natural, kind: kind, seconds: away))
            notch.show(NotchToast(symbol: "figure.walk", tint: .breatherMint, title: "Welcome back",
                                  subtitle: "\(Format.spoken(away)) away counted as a \(kind == .long ? "long " : "")break",
                                  action: .undoNaturalBreak, actionTitle: "Undo"), for: 10)

        case .resumed:
            break
        }
        notch.recompute()
        notchController?.contentChanged()
    }

    private var snoozeSubtitle: String {
        let left = store.settings.snoozeLimitPerBreak - engine.snoozesThisCycle
        return left > 0 ? "\(left) snooze\(left == 1 ? "" : "s") left for this break" : "No snoozes left for this break"
    }

    private func settingsChanged(old: Settings, new: Settings) {
        engine.settings = new
        smartPause.invalidate()
        if old.hotKeys != new.hotKeys { registerHotKeys() }
        if old.launchAtLogin != new.launchAtLogin { LoginItem.sync(enabled: new.launchAtLogin) }
        if old.pillOnScreensWithoutNotch != new.pillOnScreensWithoutNotch {
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
        ])
    }

    // MARK: Actions (UI)

    func breakNow() {
        notch.isHovering = false
        engine.startBreak()
    }

    func snooze(_ seconds: TimeInterval) { engine.snooze(seconds) }

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
        }
        notch.dismissToast()
    }

    func openSettings() {
        notch.isHovering = false
        settingsWindow.show(app: self)
    }

    func skipState(now: Date) -> SkipState {
        guard case .onBreak(let session) = engine.phase else { return .hidden }
        let s = store.settings
        let elapsed = now.timeIntervalSince(session.start)
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
        case .working, .onBreak: "\(engine.nextBreakKind.title) in \(Format.spoken(engine.timeUntilBreak))"
        case .holding(.typing): "Waiting for a pause in typing"
        case .holding(.afterActivity): "Break in a moment"
        case .smartPaused(let reasons): reasons.first?.title ?? "On hold"
        case .paused(let until): until.map { "Paused for \(Format.spoken($0.timeIntervalSinceNow))" } ?? "Paused"
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
