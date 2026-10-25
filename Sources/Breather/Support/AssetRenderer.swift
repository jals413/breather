import AppKit
import SwiftUI

/// Developer tooling, run from the command line:
///   Breather --render-icon <dir>       writes AppIcon.iconset PNGs (feed to `iconutil`)
///   Breather --render-snapshots <dir>  writes PNGs of every island and overlay state for design review
@MainActor
enum AssetRenderer {
    static func handleCommandLine() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-icon"), i + 1 < args.count {
            renderIconSet(to: URL(fileURLWithPath: args[i + 1]))
            exit(0)
        }
        if let i = args.firstIndex(of: "--render-snapshots"), i + 1 < args.count {
            renderSnapshots(to: URL(fileURLWithPath: args[i + 1]))
            exit(0)
        }
    }

    static func renderIconSet(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let px = points * scale
                let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
                write(BreatherAppIcon().frame(width: CGFloat(px), height: CGFloat(px)), scale: 1, to: dir.appendingPathComponent(name))
            }
        }
        write(BreatherAppIcon().frame(width: 1024, height: 1024), scale: 1, to: dir.appendingPathComponent("icon_1024.png"))
    }

    static func renderSnapshots(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let app = AppModel.shared
        app.prepareForSnapshots()
        let notch = CGSize(width: 185, height: 32)

        let states: [(String, NotchContent)] = [
            ("peek", .peek),
            ("headsup", .headsUp(.short)),
            ("countdown", .countdown),
            ("toast", .toast(NotchToast(symbol: "figure.walk", tint: Brand.mint, title: "Welcome back",
                                        subtitle: "6 minutes away counted as a break", action: .undoNaturalBreak, actionTitle: "Undo"))),
            ("expanded", .expanded),
            ("reminder", .toast(NotchToast(symbol: "drop.fill", tint: Color(red: 0.35, green: 0.72, blue: 1), title: "Drink water",
                                           subtitle: "Have a few sips.", action: .reminderDone(UUID()), actionTitle: "Done",
                                           secondaryAction: .reminderLater(UUID()), secondaryTitle: "Later"))),
        ]
        for (name, content) in states {
            let size = NotchLayout.size(for: content, notch: notch)
            let view = SnapshotIsland(app: app, content: content, notch: notch)
                .frame(width: size.width + 2 * NotchLayout.shoulder + 80, height: size.height + 40, alignment: .top)
                .background(Color(white: 0.85))
            write(view, scale: 2, to: dir.appendingPathComponent("island-\(name).png"))
        }
        write(BreatherAppIcon().frame(width: 512, height: 512), scale: 1, to: dir.appendingPathComponent("icon.png"))
        write(MenuBarView(app: app).background(Color(white: 0.16)), scale: 2, to: dir.appendingPathComponent("menubar-popover.png"))
        write(WelcomeView(app: app) {}.background(Color(white: 0.12)), scale: 1, to: dir.appendingPathComponent("welcome.png"))
        write(StatsView(app: app, scrolls: false).frame(width: 820, height: 900).background(Color(white: 0.12)), scale: 1, to: dir.appendingPathComponent("stats.png"))

        if let screen = NSScreen.main {
            app.engine.startBreak(kind: .short, now: .now)
            guard case .onBreak(let session) = app.engine.phase else { return }
            for theme in BreakTheme.all {
                let view = BreakScreen(appearance: theme.appearance, session: session, now: session.start.addingTimeInterval(6),
                                       skip: .skip, canSnooze: true, screen: screen)
                    .frame(width: 864, height: 559)
                let name = theme.id.lowercased().replacingOccurrences(of: " ", with: "-")
                write(view, scale: 1, to: dir.appendingPathComponent("theme-\(name).png"))
            }
        }
        write(Image(nsImage: BrandImages.menuBarIcon()).resizable().frame(width: 80, height: 56).padding(10).background(.white),
              scale: 2, to: dir.appendingPathComponent("menubar-glyph.png"))
    }

    private static func write(_ view: some View, scale: CGFloat, to url: URL) {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
        renderer.scale = scale
        renderer.isOpaque = false
        guard let cg = renderer.cgImage else { return }
        let rep = NSBitmapImageRep(cgImage: cg)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

/// A static island for snapshot rendering.
private struct SnapshotIsland: View {
    let app: AppModel
    let content: NotchContent
    let notch: CGSize

    var body: some View {
        let size = NotchLayout.size(for: content, notch: notch)
        let shape = NotchShape(topRadius: NotchLayout.shoulder, bottomRadius: NotchLayout.bottomRadius(for: content))
        ZStack(alignment: .top) {
            shape.fill(Color.black)
            SnapshotContent(app: app, content: content, notch: notch)
        }
        .frame(width: size.width + 2 * NotchLayout.shoulder, height: size.height, alignment: .top)
        .clipShape(shape)
        .overlay(alignment: .top) {
            // The hardware notch, outlined so the review shows where the camera sits.
            RoundedRectangle(cornerRadius: 8).stroke(.red.opacity(0.5), lineWidth: 0.5)
                .frame(width: notch.width, height: notch.height)
        }
        .foregroundStyle(.white)
    }
}

private struct SnapshotContent: View {
    let app: AppModel
    let content: NotchContent
    let notch: CGSize

    var body: some View {
        let size = NotchLayout.size(for: content, notch: notch)
        let below = NotchLayout.contentSize(for: content, notch: notch)
        VStack(spacing: 0) {
            Group {
                if content == .peek {
                    HStack(spacing: 0) {
                        StatusGlyph(engine: app.engine).frame(width: 15, height: 15).frame(width: NotchLayout.earWidth)
                        Spacer(minLength: notch.width)
                        StatusTime(engine: app.engine).frame(width: NotchLayout.earWidth)
                    }
                } else { Color.clear }
            }
            .frame(width: size.width, height: notch.height)
            Group {
                switch content {
                case .expanded: DashboardView(app: app)
                case .headsUp(let kind): HeadsUpView(app: app, kind: kind)
                case .countdown: CountdownView(app: app)
                case .toast(let toast): ToastView(app: app, toast: toast)
                default: Color.clear
                }
            }
            .frame(width: below.width, height: below.height, alignment: .top)
        }
    }
}
