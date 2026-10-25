import SwiftUI

struct NotchView: View {
    let app: AppModel
    let geometry: NotchGeometry

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var settings: Settings { app.store.settings }
    private var content: NotchContent { app.notch.content }
    private var notchSize: CGSize {
        geometry.hasNotch ? geometry.notch.size : CGSize(width: 0, height: 0)
    }
    private var bodySize: CGSize {
        NotchLayout.size(for: content, notch: notchSize, liveActivity: settings.notchLiveActivity && geometry.hasNotch)
    }
    private var shoulder: CGFloat { geometry.hasNotch ? NotchLayout.shoulder : 0 }
    private var visible: Bool {
        switch content {
        case .hidden: false
        case .resting: geometry.hasNotch
        default: true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            island
                .padding(.top, geometry.hasNotch ? 0 : geometry.menuBarHeight + 8)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var island: some View {
        let shape = geometry.hasNotch
            ? AnyShape(NotchShape(topRadius: shoulder, bottomRadius: NotchLayout.bottomRadius(for: content)))
            : AnyShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

        ZStack(alignment: .top) {
            shape.fill(Color.black)
            inner
                .padding(.horizontal, shoulder)
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                .id(contentKey)
        }
        .frame(width: bodySize.width + 2 * shoulder, height: max(bodySize.height, geometry.hasNotch ? 0 : 56))
        .clipShape(shape)
        .shadow(color: .black.opacity(content == .resting ? 0 : 0.35), radius: 18, y: 8)
        .opacity(visible ? 1 : 0)
        .scaleEffect(geometry.hasNotch || visible ? 1 : 0.85, anchor: .top)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.78), value: content)
        .environment(\.colorScheme, .dark)
    }

    private var contentKey: String {
        switch content {
        case .resting: "resting"
        case .expanded: "expanded"
        case .headsUp: "headsUp"
        case .countdown: "countdown"
        case .toast(let t): "toast-\(t.id)"
        case .hidden: "hidden"
        }
    }

    @ViewBuilder
    private var inner: some View {
        VStack(spacing: 0) {
            if geometry.hasNotch {
                ears.frame(height: notchSize.height)
            }
            switch content {
            case .resting, .hidden: EmptyView()
            case .expanded: DashboardView(app: app)
            case .headsUp(let kind): HeadsUpView(app: app, kind: kind)
            case .countdown: CountdownView(app: app)
            case .toast(let toast): ToastView(app: app, toast: toast)
            }
        }
    }

    /// The "live activity" that flanks the hardware notch.
    @ViewBuilder
    private var ears: some View {
        let showEars = settings.notchLiveActivity || content != .resting
        HStack(spacing: 0) {
            StatusGlyph(engine: app.engine)
                .frame(width: 16, height: 16)
                .frame(width: NotchLayout.earWidth, alignment: .center)
            Spacer(minLength: notchSize.width)
            StatusTime(engine: app.engine)
                .frame(width: NotchLayout.earWidth, alignment: .center)
        }
        .opacity(showEars ? 1 : 0)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Status

struct StatusGlyph: View {
    let engine: BreakEngine

    var body: some View {
        switch engine.phase {
        case .working, .onBreak:
            ProgressRing(progress: engine.workProgress, color: engine.timeUntilBreak <= 60 ? .orange : .breatherMint, lineWidth: 2.5)
        case .holding(let reason):
            Image(systemName: reason == .typing ? "keyboard" : "hourglass")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.orange)
        case .smartPaused(let reasons):
            Image(systemName: reasons.first?.symbol ?? "pause.fill")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.cyan)
        case .paused:
            Image(systemName: "pause.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.6))
        case .away:
            Image(systemName: "moon.zzz.fill").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
        case .offHours:
            Image(systemName: "moon.fill").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
        }
    }
}

struct StatusTime: View {
    let engine: BreakEngine

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(color)
            .contentTransition(.numericText(countsDown: true))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private var text: String {
        switch engine.phase {
        case .working, .holding, .smartPaused, .onBreak: Format.short(engine.timeUntilBreak)
        case .paused(let until): until.map { Format.short($0.timeIntervalSinceNow) } ?? "Off"
        case .away: "Away"
        case .offHours: "Off"
        }
    }

    private var color: Color {
        switch engine.phase {
        case .working: engine.timeUntilBreak <= 60 ? .orange : .white.opacity(0.9)
        case .holding: .orange
        case .smartPaused: .cyan
        default: .white.opacity(0.55)
        }
    }
}

// MARK: - Heads-up

struct HeadsUpView: View {
    let app: AppModel
    let kind: BreakKind

    var body: some View {
        let engine = app.engine
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind == .long ? "Long break coming up" : "Eye break coming up")
                        .font(.system(size: 14, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                Text(Format.clock(engine.timeUntilBreak))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 6) {
                IslandButton(title: "Start now", symbol: "eye", style: .primary) { app.breakNow() }
                if engine.canSnooze {
                    IslandButton(title: "+1m") { app.snooze(60) }
                    IslandButton(title: "+5m") { app.snooze(5 * 60) }
                }
                Spacer()
                if engine.canSkipInAdvance {
                    IslandButton(title: "Skip", style: .subtle) { app.skipUpcoming() }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 14)
        .foregroundStyle(.white)
    }

    private var subtitle: String {
        let length = kind == .long ? app.store.settings.longBreakSeconds : app.store.settings.breakSeconds
        let wait = app.store.settings.waitForTypingPause ? " · waits for a pause in typing" : ""
        return Format.spoken(length) + wait
    }
}

// MARK: - Final countdown

struct CountdownView: View {
    let app: AppModel

    var body: some View {
        let engine = app.engine
        let lead = max(1, app.store.settings.finalCountdownSeconds)
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Look away in").font(.system(size: 13, weight: .semibold))
                Text(engine.nextBreakKind.title).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            if engine.canSnooze {
                IslandButton(title: "+1m", style: .subtle) { app.snooze(60) }
            }
            ZStack {
                ProgressRing(progress: engine.timeUntilBreak / lead, color: .orange, lineWidth: 3.5)
                Text("\(Int(engine.timeUntilBreak.rounded(.up)))")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .contentTransition(.numericText(countsDown: true))
            }
            .frame(width: 42, height: 42)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
        .foregroundStyle(.white)
        .animation(.easeInOut(duration: 0.3), value: Int(engine.timeUntilBreak.rounded(.up)))
    }
}

// MARK: - Toast

struct ToastView: View {
    let app: AppModel
    let toast: NotchToast

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(toast.tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(toast.title).font(.system(size: 13, weight: .semibold))
                if let subtitle = toast.subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                }
            }
            Spacer()
            if let action = toast.action {
                IslandButton(title: toast.actionTitle ?? "Undo") { app.perform(action) }
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
        .foregroundStyle(.white)
    }
}

// MARK: - Hover dashboard

struct DashboardView: View {
    let app: AppModel

    var body: some View {
        let engine = app.engine
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    ProgressRing(progress: engine.workProgress, color: ringColor, lineWidth: 5)
                    VStack(spacing: -1) {
                        Text(Format.clock(engine.timeUntilBreak))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText(countsDown: true))
                        Text("left").font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
                    }
                }
                .frame(width: 62, height: 62)

                VStack(alignment: .leading, spacing: 3) {
                    Text(app.statusTitle).font(.system(size: 15, weight: .semibold))
                    Text(app.statusSubtitle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                        .lineLimit(2)
                    if engine.skipNextPending {
                        Label("Next break will be skipped", systemImage: "forward.fill")
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(.orange)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    StatPill(value: app.log.takenToday, label: "taken", color: .breatherMint)
                    StatPill(value: app.log.skippedToday, label: "skipped", color: .white.opacity(0.5))
                }
            }

            HStack(spacing: 6) {
                IslandButton(title: "Break now", symbol: "eye", style: .primary) { app.breakNow() }
                if case .paused = engine.phase {
                    IslandButton(title: "Resume", symbol: "play.fill") { app.resume() }
                } else {
                    PauseMenu(app: app)
                }
                if engine.canSkipInAdvance || engine.skipNextPending {
                    IslandButton(title: engine.skipNextPending ? "Don't skip" : "Skip next", symbol: "forward.end") {
                        app.engine.toggleSkipNext()
                    }
                }
                Spacer()
                IslandButton(title: "", symbol: "gearshape.fill", style: .subtle) { app.openSettings() }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .foregroundStyle(.white)
    }

    private var ringColor: Color {
        switch app.engine.phase {
        case .smartPaused: .cyan
        case .holding: .orange
        case .paused, .away, .offHours: .white.opacity(0.4)
        default: app.engine.timeUntilBreak <= 60 ? .orange : .breatherMint
        }
    }
}

struct StatPill: View {
    var value: Int
    var label: String
    var color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text("\(value)").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(color)
            Text(label).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
        }
    }
}

struct PauseMenu: View {
    let app: AppModel

    var body: some View {
        Menu {
            ForEach(PauseOption.all) { option in
                Button(option.title) { app.pause(option) }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "pause.fill").font(.system(size: 10, weight: .bold))
                Text("Pause").font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Capsule().fill(.white.opacity(0.14)))
            .foregroundStyle(.white)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
