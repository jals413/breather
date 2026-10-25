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
        if let i = args.firstIndex(of: "--render-mobile-icon"), i + 1 < args.count {
            // iOS / watchOS want a full-bleed, opaque square; the system applies its own mask.
            let view = ZStack {
                LinearGradient(colors: [Color(red: 0.44, green: 0.92, blue: 0.78), Color(red: 0.10, green: 0.62, blue: 0.66),
                                        Color(red: 0.04, green: 0.30, blue: 0.48)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [.white.opacity(0.3), .white.opacity(0)], center: .top, startRadius: 0, endRadius: 760)
                BreatherMark(color: .white).frame(width: 600, height: 600)
            }
            .frame(width: 1024, height: 1024)
            let renderer = ImageRenderer(content: view)
            renderer.isOpaque = true
            if let cg = renderer.cgImage {
                try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: args[i + 1]))
            }
            exit(0)
        }
        if let i = args.firstIndex(of: "--render-settings"), i + 1 < args.count {
            renderSettings(to: URL(fileURLWithPath: args[i + 1]))
            return
        }
        if let i = args.firstIndex(of: "--render-welcome"), i + 2 < args.count,
           let step = Int(args[i + 2]).flatMap(WelcomeView.Step.init(rawValue:)) {
            renderWindow(WelcomeView(app: AppModel.shared, onDone: {}, step: step), size: NSSize(width: 820, height: 640),
                         to: URL(fileURLWithPath: args[i + 1]))
            return
        }
        if let i = args.firstIndex(of: "--render-stats"), i + 1 < args.count {
            renderWindow(StatsView(app: AppModel.shared), to: URL(fileURLWithPath: args[i + 1]))
            return
        }
        if let i = args.firstIndex(of: "--render-social"), i + 1 < args.count {
            AppModel.shared.prepareForSnapshots()
            // Open Graph card at 2× (2400×1260); with a second path, GitHub's 1280×640 card at 2× too.
            write(SocialCard(app: AppModel.shared, macScale: 0.85), scale: 2, to: URL(fileURLWithPath: args[i + 1]))
            if i + 2 < args.count, !args[i + 2].hasPrefix("-") {
                write(SocialCard(app: AppModel.shared, size: CGSize(width: 1280, height: 640)), scale: 2,
                      to: URL(fileURLWithPath: args[i + 2]))
            }
            exit(0)
        }
        if let i = args.firstIndex(of: "--render-snapshots"), i + 1 < args.count {
            renderSnapshots(to: URL(fileURLWithPath: args[i + 1]))
            exit(0)
        }
    }

    /// Opens the real Settings window and captures it from its own view tree (no screen-recording permission).
    static func renderSettings(to url: URL) {
        renderWindow(SettingsView(app: AppModel.shared), to: url)
    }

    static func renderWindow(_ root: some View, size: NSSize = NSSize(width: 760, height: 560), to url: URL) {
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.setContentSize(size)
        window.center()
        window.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            // The window server can photograph an app's own windows without Screen Recording permission.
            typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
            guard let handle = dlopen(nil, RTLD_NOW), let sym = dlsym(handle, "CGWindowListCreateImage") else { exit(2) }
            let create = unsafeBitCast(sym, to: CreateImage.self)
            // .optionIncludingWindow = 1 << 3, .boundsIgnoreFraming = 1 << 0 | .bestResolution = 1 << 3
            guard let image = create(.null, 1 << 3, UInt32(window.windowNumber), (1 << 0) | (1 << 3))?.takeRetainedValue() else { exit(3) }
            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
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
                .background(CommandLine.arguments.contains("--transparent") ? Color.clear : Color(white: 0.85))
            write(view, scale: 2, to: dir.appendingPathComponent("island-\(name).png"))
        }
        write(BreatherAppIcon().frame(width: 512, height: 512), scale: 1, to: dir.appendingPathComponent("icon.png"))
        write(MenuBarView(app: app).background(Color(white: 0.16)), scale: 2, to: dir.appendingPathComponent("menubar-popover.png"))
        write(WelcomeView(app: app) {}.background(Color(white: 0.12)), scale: 1, to: dir.appendingPathComponent("welcome.png"))

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
            if !CommandLine.arguments.contains("--transparent") && !CommandLine.arguments.contains("--render-social") {
                RoundedRectangle(cornerRadius: 8).stroke(.red.opacity(0.5), lineWidth: 0.5)
                    .frame(width: notch.width, height: notch.height)
            }
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

/// The 1200×630 link preview used by the website and GitHub (Open Graph / X cards).
private struct SocialCard: View {
    let app: AppModel
    var size = CGSize(width: 1200, height: 630)
    var macScale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Background: night, with the brand aurora glowing from behind the screen.
            Brand.night
            RadialGradient(colors: [Brand.teal.opacity(0.45), .clear], center: UnitPoint(x: 0.78, y: 0.15),
                           startRadius: 0, endRadius: 560)
            RadialGradient(colors: [Color(red: 0.32, green: 0.22, blue: 0.62).opacity(0.35), .clear],
                           center: UnitPoint(x: 0.08, y: 1.0), startRadius: 0, endRadius: 520)

            macBook
                .frame(width: 580 * 1.1)
                .scaleEffect(macScale)
                .offset(x: size.width - 580 * 1.1 - 40, y: (size.height - 392) / 2)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    BreatherAppIcon().frame(width: 60, height: 60)
                    Text("Breather").font(.system(size: 34, weight: .bold)).foregroundStyle(.white)
                }
                Spacer().frame(height: 46)
                Text("Rest your eyes.")
                    .font(.system(size: 62, weight: .bold)).tracking(-1.6).foregroundStyle(.white)
                Text("Keep your flow.")
                    .font(.system(size: 62, weight: .bold)).tracking(-1.6)
                    .foregroundStyle(LinearGradient(colors: [Brand.mint, Brand.teal, Brand.sky], startPoint: .leading, endPoint: .trailing))
                Spacer().frame(height: 22)
                Text("Break reminders that grow out of\nyour MacBook's notch.")
                    .font(.system(size: 25, weight: .medium)).lineSpacing(4)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                HStack(spacing: 10) {
                    Chip(text: "Free & open source", dot: true)
                    Chip(text: "macOS 26+")
                    Chip(text: "GPL-3.0")
                }
            }
            .padding(.leading, 72)
            .padding(.vertical, 64)
            .frame(width: 640, height: size.height, alignment: .topLeading)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    /// A MacBook with the island grown out of its notch over the app you're working in.
    private var macBook: some View {
        let outer: CGFloat = 580, bezel: CGFloat = 12
        let inner = outer - 2 * bezel
        return VStack(spacing: 0) {
            display
                .frame(width: 1000, height: 625)
                .scaleEffect(inner / 1000, anchor: .topLeading)
                .frame(width: inner, height: inner * 0.625, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding([.horizontal, .top], bezel)
                .padding(.bottom, 16)
                .background(
                    UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 6, bottomTrailingRadius: 6,
                                           topTrailingRadius: 22, style: .continuous)
                        .fill(Color(white: 0.045))
                        .overlay(UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 6, bottomTrailingRadius: 6,
                                                        topTrailingRadius: 22, style: .continuous)
                            .strokeBorder(.white.opacity(0.13), lineWidth: 1))
                )
            // The base, with the thumb notch for opening the lid.
            ZStack(alignment: .top) {
                UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 14, bottomTrailingRadius: 14,
                                       topTrailingRadius: 2, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.19), Color(white: 0.08)], startPoint: .top, endPoint: .bottom))
                UnevenRoundedRectangle(bottomLeadingRadius: 6, bottomTrailingRadius: 6)
                    .fill(Color(white: 0.05))
                    .frame(width: 90, height: 5)
            }
            .frame(width: outer * 1.1, height: 16)
        }
        .shadow(color: .black.opacity(0.6), radius: 40, y: 24)
        .shadow(color: Brand.teal.opacity(0.18), radius: 60)
    }

    /// The display, laid out at 1000×625 like the website demo.
    private var display: some View {
        ZStack(alignment: .top) {
            AuroraBackground(animated: false)
            CodeWindow()
                .frame(width: 680, height: 440)
                .padding(.top, 150)
            HStack(spacing: 18) {
                Image(systemName: "apple.logo").font(.system(size: 15, weight: .semibold))
                Text("Xcode").font(.system(size: 14, weight: .bold))
                Text("File").font(.system(size: 14))
                Text("Edit").font(.system(size: 14))
                Text("View").font(.system(size: 14))
                Spacer()
                BreatherMark(color: .white).frame(width: 16, height: 16)
                Text("9:41").font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 18)
            .frame(height: 32)
            .background(.black.opacity(0.2))
            SnapshotIsland(app: app, content: .headsUp(.short), notch: CGSize(width: 170, height: 32))
        }
    }
}

private struct CodeWindow: View {
    var body: some View {
        let lines: [[(Color, CGFloat)]] = [
            [(.pink, 50), (.cyan, 90), (.white, 40)],
            [(.pink, 30), (.white, 110)],
            [],
            [(.pink, 30), (.white, 50), (.pink, 40), (.cyan, 40)],
            [(.cyan, 60), (.white, 30), (.yellow, 16)],
            [(.white, 140)],
            [(.white, 90), (.yellow, 16)],
        ]
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                ForEach([Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18),
                         Color(red: 0.16, green: 0.78, blue: 0.25)], id: \.self) { Circle().fill($0).frame(width: 10, height: 10) }
            }
            .padding(.horizontal, 14).frame(height: 32)
            VStack(alignment: .leading, spacing: 13) {
                ForEach(lines.indices, id: \.self) { i in
                    HStack(spacing: 8) {
                        ForEach(lines[i].indices, id: \.self) { j in
                            Capsule().fill(lines[i][j].0.opacity(0.55)).frame(width: lines[i][j].1, height: 8)
                        }
                    }
                    .padding(.leading, i == 0 || i == 3 ? 0 : 22)
                    .frame(height: 8)
                }
            }
            .padding(20)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(red: 0.09, green: 0.1, blue: 0.12).opacity(0.94)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
    }
}

private struct Chip: View {
    var text: String
    var dot = false

    var body: some View {
        HStack(spacing: 8) {
            if dot { Circle().fill(Brand.mint).frame(width: 8, height: 8).shadow(color: Brand.mint, radius: 4) }
            Text(text).font(.system(size: 18, weight: .semibold))
        }
        .foregroundStyle(dot ? Brand.mint : .white.opacity(0.85))
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background(Capsule().fill(dot ? Brand.mint.opacity(0.12) : .white.opacity(0.07)))
        .overlay(Capsule().strokeBorder(dot ? Brand.mint.opacity(0.35) : .white.opacity(0.12)))
    }
}
