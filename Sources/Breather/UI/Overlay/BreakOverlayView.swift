import AppKit
import CoreImage
import SwiftUI

struct BreakOverlayView: View {
    let app: AppModel
    let screen: NSScreen
    let isPrimary: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack {
            BreakBackgroundView(style: app.store.settings.background, screen: screen)
            if case .onBreak(let session) = app.engine.phase {
                TimelineView(.periodic(from: .now, by: 0.25)) { context in
                    content(session: session, now: context.date)
                }
                .scaleEffect(appeared || reduceMotion ? 1 : 0.94)
                .opacity(appeared ? 1 : 0)
            }
        }
        .frame(width: screen.frame.width, height: screen.frame.height)
        .clipped()
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.85).delay(0.15)) { appeared = true }
        }
    }

    @ViewBuilder
    private func content(session: BreakSession, now: Date) -> some View {
        let remaining = session.remaining(at: now)
        VStack(spacing: 30) {
            HStack(spacing: 8) {
                BreatherMark(color: .white.opacity(0.75), rippleOpacity: 0.6)
                    .frame(width: 18, height: 18)
                Text(session.kind.title.uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(3)
            }
            .foregroundStyle(.white.opacity(0.65))

            ZStack {
                BreathingHalo(reduceMotion: reduceMotion)
                    .frame(width: 300, height: 300)
                ProgressRing(progress: 1 - session.progress(at: now), color: .white.opacity(0.9), lineWidth: 5, track: .white.opacity(0.12))
                    .frame(width: 220, height: 220)
                    .animation(.linear(duration: 0.25), value: now)
                Text(Format.clock(remaining))
                    .font(.system(size: 60, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.easeInOut(duration: 0.3), value: Int(remaining.rounded(.up)))
            }

            Text(session.message)
                .font(.system(size: 30, weight: .semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 640)
                .foregroundStyle(.white)

            controls(session: session, now: now)
                .padding(.top, 10)

            Text(hint(now: now))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(40)
    }

    @ViewBuilder
    private func controls(session: BreakSession, now: Date) -> some View {
        let skip = app.skipState(now: now)
        HStack(spacing: 12) {
            if app.engine.canSnooze {
                Button("+1 min") { app.snooze(60) }
                Button("+5 min") { app.snooze(5 * 60) }
            }
            switch skip {
            case .hidden:
                EmptyView()
            case .locked(let seconds):
                Button("Skip in \(Int(seconds.rounded(.up)))s") {}
                    .disabled(true)
            case .skip:
                Button("Skip") { app.skipOrEndBreak() }
            case .endBreak:
                Button("End break") { app.skipOrEndBreak() }
                    .buttonStyle(.glassProminent)
                    .tint(.breatherMint.opacity(0.6))
            }
            Button {
                ActivityMonitor.lockScreen()
            } label: {
                Image(systemName: "lock.fill")
            }
            .help("Lock screen")
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .font(.system(size: 14, weight: .semibold))
    }

    private func hint(now: Date) -> String {
        switch app.skipState(now: now) {
        case .hidden: "Hardcore mode — this one can't be skipped."
        case .locked: "Look at something far away. Relax your shoulders."
        case .skip: "Press Esc twice to skip."
        case .endBreak: "Press Esc twice to end the break."
        }
    }
}

/// A soft glow that swells and settles at breathing pace (4s in, 4s out).
struct BreathingHalo: View {
    var reduceMotion: Bool
    @State private var expanded = false

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [.white.opacity(0.16), .white.opacity(0)], center: .center, startRadius: 10, endRadius: 150))
            .scaleEffect(expanded ? 1.15 : 0.8)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { expanded = true }
            }
    }
}

struct BreakBackgroundView: View {
    let style: BreakBackground
    let screen: NSScreen

    var body: some View {
        switch style {
        case .aurora:
            AuroraBackground()
        case .frosted:
            ZStack {
                VisualEffectBlur()
                Color.black.opacity(0.35)
            }
        case .wallpaper:
            if let image = WallpaperLoader.blurredImage(for: screen) {
                // Pin to the screen's size: an aspect-fill image left to size itself would be
                // wider than the window and drag the whole layout off-centre.
                Color.clear
                    .overlay {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                    .overlay(Color.black.opacity(0.38))
                    .frame(width: screen.frame.width, height: screen.frame.height)
                    .clipped()
            } else {
                AuroraBackground()
            }
        case .midnight:
            LinearGradient(colors: [Color(red: 0.03, green: 0.04, blue: 0.09), Color(red: 0.07, green: 0.09, blue: 0.18)],
                           startPoint: .top, endPoint: .bottom)
        }
    }
}

struct AuroraBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [Float(0.5 + 0.18 * sin(t * 0.21)), Float(0.5 + 0.14 * cos(t * 0.17))], [1, 0.5],
                    [0, 1], [Float(0.5 + 0.2 * cos(t * 0.13)), 1], [1, 1],
                ],
                colors: [
                    Color(red: 0.04, green: 0.06, blue: 0.14), Color(red: 0.05, green: 0.18, blue: 0.26), Color(red: 0.09, green: 0.06, blue: 0.2),
                    Color(red: 0.06, green: 0.26, blue: 0.3), Color(red: 0.16, green: 0.42, blue: 0.4), Color(red: 0.2, green: 0.12, blue: 0.36),
                    Color(red: 0.03, green: 0.05, blue: 0.12), Color(red: 0.08, green: 0.14, blue: 0.3), Color(red: 0.04, green: 0.05, blue: 0.12),
                ]
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

@MainActor
enum WallpaperLoader {
    private static var cache: [URL: NSImage] = [:]

    /// The screen's wallpaper, downscaled and blurred once with edge clamping (so the blur
    /// doesn't fade to transparent at the screen edges), then cached.
    static func blurredImage(for screen: NSScreen) -> NSImage? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        if let cached = cache[url] { return cached }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue,
              let input = CIImage(contentsOf: url) else { return nil }

        let targetWidth: CGFloat = 1280
        let scale = min(1, targetWidth / input.extent.width)
        let scaled = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let blurred = scaled.clampedToExtent()
            .applyingGaussianBlur(sigma: 28)
            .cropped(to: scaled.extent)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cg = context.createCGImage(blurred, from: scaled.extent) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache[url] = image
        return image
    }
}
