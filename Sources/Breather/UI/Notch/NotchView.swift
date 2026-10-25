import SwiftUI

/// The island. One persistent black shape whose size morphs between states, with each
/// state's content laid out at its *own* fixed size. When the island shrinks, the
/// outgoing content keeps its layout and is simply clipped and faded instead of
/// reflowing — that's what keeps the close animation clean.
struct NotchView: View {
    let app: AppModel
    let geometry: NotchGeometry

    private var content: NotchContent { app.notch.content }
    private var notchSize: CGSize { geometry.hasNotch ? geometry.notch.size : .zero }
    private var shoulder: CGFloat { geometry.hasNotch ? NotchLayout.shoulder : 0 }

    private var visible: Bool {
        switch content {
        case .hidden: false
        case .resting, .peek: geometry.hasNotch
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
        .environment(\.colorScheme, .dark)
    }

    private var island: some View {
        let size = islandSize(for: content)
        let shape = islandShape
        return ZStack(alignment: .top) {
            shape.fill(Color.black)
            IslandContent(app: app, content: content, geometry: geometry)
                .id(content.key)
                .transition(.island)
        }
        .frame(width: size.width + 2 * shoulder, height: size.height, alignment: .top)
        .clipShape(shape)
        .shadow(color: .black.opacity(content.openness >= 2 ? 0.4 : 0), radius: 22, y: 10)
        .opacity(visible ? 1 : 0)
        .scaleEffect(geometry.hasNotch || visible ? 1 : 0.9, anchor: .top)
    }

    private var islandShape: AnyShape {
        geometry.hasNotch
            ? AnyShape(NotchShape(topRadius: shoulder, bottomRadius: NotchLayout.bottomRadius(for: content)))
            : AnyShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func islandSize(for content: NotchContent) -> CGSize {
        var size = NotchLayout.size(for: content, notch: notchSize)
        if !geometry.hasNotch { size.height = max(size.height, NotchLayout.pillMinHeight) }
        return size
    }
}

/// One state's content at its own fixed size.
private struct IslandContent: View {
    let app: AppModel
    let content: NotchContent
    let geometry: NotchGeometry

    var body: some View {
        let notch = geometry.hasNotch ? geometry.notch.size : .zero
        let size = NotchLayout.size(for: content, notch: notch)
        let below = NotchLayout.contentSize(for: content, notch: notch)
        VStack(spacing: 0) {
            if geometry.hasNotch {
                Group {
                    if content == .peek { PeekEars(engine: app.engine, notchWidth: notch.width) } else { Color.clear }
                }
                .frame(width: size.width, height: notch.height)
            }
            detail
                .frame(width: below.width, height: max(below.height, geometry.hasNotch ? 0 : NotchLayout.pillMinHeight), alignment: .top)
        }
        .frame(width: size.width, alignment: .top)
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var detail: some View {
        switch content {
        case .resting, .hidden, .peek: Color.clear
        case .expanded: DashboardView(app: app)
        case .headsUp(let kind): HeadsUpView(app: app, kind: kind)
        case .countdown: CountdownView(app: app)
        case .toast(let toast): ToastView(app: app, toast: toast)
        }
    }
}

private struct IslandFade: ViewModifier {
    var progress: Double
    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .blur(radius: (1 - progress) * 5)
            .scaleEffect(0.97 + 0.03 * progress, anchor: .top)
    }
}

extension AnyTransition {
    /// New content fades in once the shape has started growing; old content leaves fast
    /// so it's gone before the shape finishes shrinking.
    static var island: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: IslandFade(progress: 0), identity: IslandFade(progress: 1))
                .animation(.easeOut(duration: 0.24).delay(0.09)),
            removal: .modifier(active: IslandFade(progress: 0), identity: IslandFade(progress: 1))
                .animation(.easeIn(duration: 0.11))
        )
    }
}

// MARK: - Peek (live activity)

private struct PeekEars: View {
    let engine: BreakEngine
    let notchWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            StatusGlyph(engine: engine)
                .frame(width: 15, height: 15)
                .frame(width: NotchLayout.earWidth)
            Spacer(minLength: notchWidth)
            StatusTime(engine: engine)
                .frame(width: NotchLayout.earWidth)
        }
    }
}

struct StatusGlyph: View {
    let engine: BreakEngine

    var body: some View {
        switch engine.phase {
        case .working, .onBreak:
            ProgressRing(progress: engine.workProgress, color: engine.timeUntilBreak <= 60 ? Brand.amber : Brand.mint, lineWidth: 2.5)
        case .holding(let reason):
            symbol(reason == .typing ? "keyboard" : "hourglass", Brand.amber)
        case .smartPaused(let reasons):
            symbol(reasons.first?.symbol ?? "pause.fill", Brand.sky)
        case .paused:
            symbol("pause.fill", .white.opacity(0.55))
        case .away:
            symbol("moon.zzz.fill", .white.opacity(0.55))
        case .offHours:
            symbol("moon.fill", .white.opacity(0.45))
        }
    }

    private func symbol(_ name: String, _ color: Color) -> some View {
        Image(systemName: name).font(.system(size: 11, weight: .semibold)).foregroundStyle(color)
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
        case .working, .holding, .smartPaused, .onBreak:
            engine.timeUntilBreak < 600 ? Format.clock(engine.timeUntilBreak) : Format.short(engine.timeUntilBreak)
        case .paused(let until): until.map { Format.short($0.timeIntervalSinceNow) } ?? "Off"
        case .away: "Away"
        case .offHours: "Off"
        }
    }

    private var color: Color {
        switch engine.phase {
        case .working: engine.timeUntilBreak <= 60 ? Brand.amber : .white.opacity(0.92)
        case .holding: Brand.amber
        case .smartPaused: Brand.sky
        default: .white.opacity(0.5)
        }
    }
}

// MARK: - Shared pieces

/// Leading badge used across island states.
struct IslandBadge: View {
    var symbol: String? = nil
    var tint: Color = Brand.mint

    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(0.18))
            if let symbol {
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
            } else {
                BreatherMark(color: tint, rippleOpacity: 0.6)
                    .frame(width: 20, height: 20)
            }
        }
        .frame(width: 36, height: 36)
    }
}

// MARK: - Heads-up

struct HeadsUpView: View {
    let app: AppModel
    let kind: BreakKind

    var body: some View {
        let engine = app.engine
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                IslandBadge(tint: Brand.amber)
                VStack(alignment: .leading, spacing: 1) {
                    Text(kind == .long ? "Long break soon" : "Eye break soon")
                        .font(.system(size: 15, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(Format.clock(engine.timeUntilBreak))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .foregroundStyle(Brand.amber)
            }
            HStack(spacing: 8) {
                IslandButton(title: "Start now", style: .primary) { app.breakNow() }
                if engine.canSnooze {
                    IslandButton(title: "+1 min") { app.snooze(60) }
                    IslandButton(title: "+5 min") { app.snooze(5 * 60) }
                }
                Spacer()
                if engine.canSkipInAdvance {
                    IslandButton(title: "Skip", style: .subtle) { app.skipUpcoming() }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private var subtitle: String {
        let s = app.store.settings
        let length = kind == .long ? s.longBreakSeconds : s.breakSeconds
        return Format.spoken(length) + (s.waitForTypingPause ? " · waits for a pause" : "")
    }
}

// MARK: - Final countdown

struct CountdownView: View {
    let app: AppModel

    var body: some View {
        let engine = app.engine
        let lead = max(1, app.store.settings.finalCountdownSeconds)
        let seconds = Int(engine.timeUntilBreak.rounded(.up))
        HStack(spacing: 12) {
            IslandBadge(tint: Brand.amber)
            VStack(alignment: .leading, spacing: 1) {
                Text("Look away").font(.system(size: 15, weight: .semibold))
                Text(engine.nextBreakKind.title).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            if engine.canSnooze {
                IslandButton(title: "+1 min", style: .subtle) { app.snooze(60) }
            }
            ZStack {
                ProgressRing(progress: engine.timeUntilBreak / lead, color: Brand.amber, lineWidth: 3.5)
                    .animation(.linear(duration: 1), value: seconds)
                Text("\(seconds)")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy, value: seconds)
            }
            .frame(width: 40, height: 40)
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
    }
}

// MARK: - Toast

struct ToastView: View {
    let app: AppModel
    let toast: NotchToast

    var body: some View {
        HStack(spacing: 12) {
            IslandBadge(symbol: toast.symbol, tint: toast.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(toast.title).font(.system(size: 14, weight: .semibold))
                if let subtitle = toast.subtitle {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let secondary = toast.secondaryAction {
                IslandButton(title: toast.secondaryTitle ?? "Later", style: .subtle) { app.perform(secondary) }
            }
            if let action = toast.action {
                IslandButton(title: toast.actionTitle ?? "Undo", style: toast.secondaryAction != nil ? .primary : .normal) {
                    app.perform(action)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
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
                    Text(Format.clock(engine.timeUntilBreak))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                }
                .frame(width: 60, height: 60)

                VStack(alignment: .leading, spacing: 3) {
                    Text(app.statusTitle).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Text(app.statusSubtitle).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55)).lineLimit(2)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(app.log.takenToday)")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.mint)
                    Text("breaks today").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                }
            }

            HStack(spacing: 8) {
                IslandTile(title: "Break now", symbol: "eye.fill", tint: Brand.mint) { app.breakNow() }
                if case .paused = engine.phase {
                    IslandTile(title: "Resume", symbol: "play.fill", tint: Brand.mint, active: true) { app.resume() }
                } else {
                    PauseTile(app: app)
                }
                IslandTile(title: engine.skipNextPending ? "Skipping" : "Skip next", symbol: "forward.end.fill",
                           tint: Brand.amber, active: engine.skipNextPending) {
                    app.engine.toggleSkipNext()
                }
                .disabled(!engine.canSkipInAdvance && !engine.skipNextPending)
                IslandTile(title: "Stats", symbol: "chart.bar.fill", tint: Brand.sky) { app.openStats() }
                IslandTile(title: "Settings", symbol: "gearshape.fill", tint: .white) { app.openSettings() }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
    }

    private var ringColor: Color {
        switch app.engine.phase {
        case .smartPaused: Brand.sky
        case .holding: Brand.amber
        case .paused, .away, .offHours: .white.opacity(0.4)
        default: app.engine.timeUntilBreak <= 60 ? Brand.amber : Brand.mint
        }
    }
}

/// Control Center–style square-ish tile.
struct IslandTile: View {
    var title: String
    var symbol: String
    var tint: Color
    var active = false
    var action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) { label }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .opacity(isEnabled ? 1 : 0.4)
    }

    /// Icon-only: the title becomes the tooltip and the VoiceOver label.
    var label: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(active ? .black : tint)
            .frame(width: 38, height: 38)
            .background(Circle().fill(active ? tint : .white.opacity(0.12)))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(hovering ? 0.12 : 0.07)))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .help(title)
            .accessibilityLabel(title)
    }
}

private struct PauseTile: View {
    let app: AppModel

    var body: some View {
        Menu {
            ForEach(PauseOption.all) { option in
                Button(option.title) { app.pause(option) }
            }
        } label: {
            IslandTile(title: "Pause", symbol: "pause.fill", tint: .white) {}.label
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }
}
