import AppKit
import CoreImage
import SwiftUI

/// The live overlay on one display: binds the engine's current break to `BreakScreen`.
struct BreakOverlayView: View {
    let app: AppModel
    let screen: NSScreen
    let isPrimary: Bool

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if case .onBreak(let session) = app.engine.phase {
                TimelineView(.periodic(from: .now, by: 0.25)) { context in
                    BreakScreen(
                        appearance: app.store.settings.appearance,
                        session: session,
                        now: context.date,
                        skip: app.skipState(now: context.date),
                        canSnooze: app.engine.canSnooze,
                        screen: screen,
                        contentVisible: appeared,
                        actions: BreakScreen.Actions(
                            snooze: { app.snooze($0) },
                            skip: { app.skipOrEndBreak() },
                            lock: { ActivityMonitor.lockScreen() })
                    )
                }
            } else {
                Color.clear
            }
        }
        .frame(width: screen.frame.width, height: screen.frame.height)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.8, dampingFraction: 0.85).delay(0.15)) {
                appeared = true
            }
        }
    }
}

/// The break screen itself, independent of the app model so Settings can preview it.
struct BreakScreen: View {
    struct Actions {
        var snooze: (TimeInterval) -> Void = { _ in }
        var skip: () -> Void = {}
        var lock: () -> Void = {}
    }

    var appearance: BreakAppearance
    var session: BreakSession
    var now: Date
    var skip: SkipState
    var canSnooze: Bool
    var screen: NSScreen?
    var contentVisible = true
    var isPreview = false
    var actions = Actions()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var text: Color { appearance.textColor.color }
    private var accent: Color { appearance.accent.color }

    var body: some View {
        GeometryReader { geo in
            // Laid out for a 1728pt-wide screen (16" MacBook Pro) and scaled, so previews match exactly.
            let scale = min(geo.size.width / 1728, 1.3)
            ZStack {
                BreakBackgroundView(appearance: appearance, screen: screen, seed: session.start, size: geo.size)
                content
                    .frame(width: geo.size.width / max(scale, 0.01), height: geo.size.height / max(scale, 0.01))
                    .scaleEffect(scale)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(contentVisible || reduceMotion ? 1 : 0.95)
                    .opacity(contentVisible ? 1 : 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        // Dark text means a light background: let glass buttons go light too.
        .environment(\.colorScheme, appearance.textColor.luminance < 0.5 ? .light : .dark)
    }

    private var content: some View {
        let remaining = session.remaining(at: now)
        return VStack(spacing: 30) {
            if appearance.showClock {
                Text(now, format: .dateTime.hour().minute())
                    .font(.system(size: 15, weight: .medium, design: appearance.timerDesign.design))
                    .monospacedDigit()
                    .foregroundStyle(text.opacity(0.6))
            }
            if appearance.showKindLabel {
                HStack(spacing: 8) {
                    BreatherMark(color: text.opacity(0.75), rippleOpacity: 0.6)
                        .frame(width: 18, height: 18)
                    Text((session.title ?? session.kind.title).uppercased())
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(3)
                }
                .foregroundStyle(text.opacity(0.65))
            }

            ZStack {
                if appearance.showBreathingHalo {
                    BreathingHalo(color: accent, reduceMotion: reduceMotion || !appearance.animateBackground)
                        .frame(width: 320, height: 320)
                }
                TimerView(appearance: appearance, session: session, now: now, remaining: remaining)
            }
            .frame(minHeight: appearance.timerStyle == .hidden ? 80 : nil)

            if appearance.showBreathingCue {
                BreathingCue(now: now, color: text)
            }

            if appearance.showMessage, !session.message.isEmpty {
                Text(session.message)
                    .font(.system(size: 30 * appearance.messageScale, weight: appearance.messageWeight.weight, design: appearance.messageDesign.design))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 720)
                    .foregroundStyle(text)
            }

            controls
                .padding(.top, 10)
                .allowsHitTesting(!isPreview)

            if appearance.showHint {
                Text(hint)
                    .font(.system(size: 12))
                    .foregroundStyle(text.opacity(0.45))
            }
        }
        .padding(40)
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 12) {
            if canSnooze {
                Button("+1 min") { actions.snooze(60) }
                Button("+5 min") { actions.snooze(5 * 60) }
            }
            switch skip {
            case .hidden:
                EmptyView()
            case .locked(let seconds):
                Button("Skip in \(Int(seconds.rounded(.up)))s") {}
                    .disabled(true)
            case .skip:
                Button("Skip") { actions.skip() }
            case .endBreak:
                Button("End break") { actions.skip() }
                    .buttonStyle(.glassProminent)
                    .tint(accent.opacity(0.5))
            }
            Button(action: actions.lock) {
                Image(systemName: "lock.fill")
            }
            .help("Lock screen")
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(text)
    }

    private var hint: String {
        switch skip {
        case .hidden: "This break can't be skipped."
        case .locked: "Look at something far away. Relax your shoulders."
        case .skip: "Press Esc twice to skip."
        case .endBreak: "Press Esc twice to end the break."
        }
    }
}

// MARK: - Timer styles

private struct TimerView: View {
    var appearance: BreakAppearance
    var session: BreakSession
    var now: Date
    var remaining: TimeInterval

    private var progress: Double { 1 - session.progress(at: now) }
    private var seconds: Int { Int(remaining.rounded(.up)) }
    private var accent: Color { appearance.accent.color }
    private var text: Color { appearance.textColor.color }
    private var s: Double { appearance.timerScale }

    var body: some View {
        switch appearance.timerStyle {
        case .ring:
            ZStack {
                ProgressRing(progress: progress, color: accent.opacity(0.9), lineWidth: 5, track: accent.opacity(0.12))
                    .frame(width: 220 * s, height: 220 * s)
                    .animation(.linear(duration: 0.25), value: now)
                clock(size: 60)
            }
        case .digits:
            clock(size: 150)
        case .bar:
            VStack(spacing: 22) {
                clock(size: 72)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(accent.opacity(0.15))
                        Capsule().fill(accent.opacity(0.85))
                            .frame(width: max(6, geo.size.width * progress))
                            .animation(.linear(duration: 0.25), value: now)
                    }
                }
                .frame(width: 420 * s, height: 6)
            }
        case .dots:
            VStack(spacing: 22) {
                clock(size: 64)
                let count = 20
                let lit = Int((progress * Double(count)).rounded(.up))
                HStack(spacing: 9 * s) {
                    ForEach(0..<count, id: \.self) { i in
                        Circle()
                            .fill(accent.opacity(i < lit ? 0.9 : 0.15))
                            .frame(width: 9 * s, height: 9 * s)
                    }
                }
                .animation(.easeInOut(duration: 0.4), value: lit)
            }
        case .hidden:
            EmptyView()
        }
    }

    private func clock(size: CGFloat) -> some View {
        Text(Format.clock(remaining))
            .font(.system(size: size * s, weight: appearance.timerWeight.weight, design: appearance.timerDesign.design))
            .monospacedDigit()
            .foregroundStyle(text)
            .contentTransition(.numericText(countsDown: true))
            .animation(.easeInOut(duration: 0.3), value: seconds)
    }
}

// MARK: - Breathing

/// 8-second breath: 4s in, 4s out. Shared by the halo and the cue so they stay in sync.
enum BreathCycle {
    static let period: TimeInterval = 8
    /// 0 → fully exhaled, 1 → fully inhaled.
    static func level(at date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
        return 0.5 - 0.5 * cos(2 * .pi * t)
    }
    static func inhaling(at date: Date) -> Bool {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) < period / 2
    }
}

struct BreathingHalo: View {
    var color: Color = .white
    var reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let level = reduceMotion ? 0.5 : BreathCycle.level(at: context.date)
            Circle()
                .fill(RadialGradient(colors: [color.opacity(0.18), color.opacity(0)], center: .center, startRadius: 10, endRadius: 160))
                .scaleEffect(0.78 + 0.4 * level)
        }
    }
}

private struct BreathingCue: View {
    var now: Date
    var color: Color

    var body: some View {
        let inhale = BreathCycle.inhaling(at: now)
        Text(inhale ? "Breathe in" : "Breathe out")
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(color.opacity(0.75))
            .contentTransition(.opacity)
            .animation(.easeInOut(duration: 0.6), value: inhale)
    }
}

// MARK: - Backgrounds

struct BreakBackgroundView: View {
    var appearance: BreakAppearance
    var screen: NSScreen?
    /// Picks a stable random photo from a folder for the whole break.
    var seed: Date
    var size: CGSize

    var body: some View {
        switch appearance.background {
        case .aurora:
            AuroraBackground(palette: appearance.auroraPalette, animated: appearance.animateBackground)
        case .gradient:
            LinearGradient(colors: [appearance.gradientTop.color, appearance.gradientBottom.color], startPoint: .top, endPoint: .bottom)
        case .solid:
            appearance.solidColor.color
        case .frosted:
            ZStack {
                VisualEffectBlur()
                Color.black.opacity(appearance.dimming)
            }
        case .wallpaper:
            photo(screen.flatMap { BackgroundImages.wallpaper(for: $0) }, blur: max(appearance.imageBlur, 28))
        case .image:
            photo(BackgroundImages.image(at: appearance.imagePath, seed: seed, blur: appearance.imageBlur), blur: appearance.imageBlur)
        }
    }

    @ViewBuilder
    private func photo(_ image: NSImage?, blur: Double) -> some View {
        if let image {
            // Pin to the screen's size: an aspect-fill image left to size itself would be
            // wider than the window and drag the whole layout off-centre.
            Color.clear
                .overlay {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                }
                .overlay(Color.black.opacity(appearance.dimming))
                .frame(width: size.width, height: size.height)
                .clipped()
        } else {
            AuroraBackground(palette: appearance.auroraPalette, animated: appearance.animateBackground)
        }
    }
}

struct AuroraBackground: View {
    var palette: AuroraPalette = .ocean
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || !animated)) { context in
            let t = (reduceMotion || !animated) ? 0 : context.date.timeIntervalSinceReferenceDate
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [Float(0.5 + 0.18 * sin(t * 0.21)), Float(0.5 + 0.14 * cos(t * 0.17))], [1, 0.5],
                    [0, 1], [Float(0.5 + 0.2 * cos(t * 0.13)), 1], [1, 1],
                ],
                colors: palette.colors
            )
        }
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .fullScreenUI
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Loads, downsizes and (optionally) blurs background photos once, then caches them.
@MainActor
enum BackgroundImages {
    private static var cache: [String: NSImage] = [:]
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tiff", "webp", "gif"]

    static func wallpaper(for screen: NSScreen) -> NSImage? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        return load(url, blur: 28)
    }

    static func image(at path: String?, seed: Date, blur: Double) -> NSImage? {
        guard let path else { return nil }
        let url = URL(fileURLWithPath: path)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return nil }
        if !isDir.boolValue { return load(url, blur: blur) }
        let files = ((try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? [])
            .filter { imageExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.path < $1.path }
        guard !files.isEmpty else { return nil }
        let index = Int(seed.timeIntervalSinceReferenceDate / 60) % files.count
        return load(files[index], blur: blur)
    }

    private static func load(_ url: URL, blur: Double) -> NSImage? {
        let key = "\(url.path)#\(Int(blur))"
        if let cached = cache[key] { return cached }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue,
              let input = CIImage(contentsOf: url) else { return nil }

        let scale = min(1, 2560 / input.extent.width)
        var image = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let extent = image.extent
        if blur > 0 {
            // Clamp first so the blur doesn't fade to transparent at the edges.
            image = image.clampedToExtent().applyingGaussianBlur(sigma: blur).cropped(to: extent)
        }
        guard let cg = CIContext().createCGImage(image, from: extent) else { return nil }
        let result = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        if cache.count > 12 { cache.removeAll() }
        cache[key] = result
        return result
    }
}
