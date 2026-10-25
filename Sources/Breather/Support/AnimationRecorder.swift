import AppKit
import SwiftUI

/// `Breather --animation-test <dir>`: drives the real notch window through every
/// open/close transition and records frames from its own layer tree at ~60fps, so
/// animation glitches can be reviewed frame by frame without Screen Recording permission.
@MainActor
enum AnimationRecorder {
    struct Step {
        var at: TimeInterval
        var label: String
        var action: (AppModel) -> Void
    }

    static func runIfRequested(app: AppModel, notchView: @escaping () -> NSView?) {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--animation-test"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1])
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let toast = NotchToast(symbol: "figure.walk", tint: Brand.mint, title: "Welcome back",
                               subtitle: "6 minutes away counted as a break", action: .undoNaturalBreak, actionTitle: "Undo")
        let steps: [Step] = [
            Step(at: 0.3, label: "hover-open") { $0.notch.isHovering = true },
            Step(at: 1.5, label: "hover-close") { $0.notch.isHovering = false },
            Step(at: 2.7, label: "headsup-open") { $0.notch.showHeadsUp(.short, for: 1.2) },
            Step(at: 4.4, label: "toast-open") { $0.notch.show(toast, for: 1.2) },
            Step(at: 6.1, label: "hover-open-2") { $0.notch.isHovering = true },
            Step(at: 6.5, label: "hover-to-headsup") { $0.notch.showHeadsUp(.short, for: 0.8) },
            Step(at: 7.8, label: "close-all") { $0.notch.isHovering = false },
        ]
        let start = Date()
        var frame = 0
        var nextStep = 0
        var log: [String] = []

        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { timer in
            MainActor.assumeIsolated {
                let t = Date().timeIntervalSince(start)
                while nextStep < steps.count, t >= steps[nextStep].at {
                    log.append(String(format: "%04d %.2fs %@", frame, t, steps[nextStep].label))
                    steps[nextStep].action(app)
                    nextStep += 1
                }
                app.notch.recompute()
                if let view = notchView() { capture(view, to: dir.appendingPathComponent(String(format: "f%04d.png", frame))) }
                frame += 1
                if t > 9.2 {
                    timer.invalidate()
                    try? log.joined(separator: "\n").write(to: dir.appendingPathComponent("steps.txt"), atomically: true, encoding: .utf8)
                    exit(0)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    private static func capture(_ view: NSView, to url: URL) {
        // Only the top part of the canvas, where the island lives.
        let bounds = view.bounds
        let crop = CGRect(x: 0, y: view.isFlipped ? 0 : bounds.height - 230, width: bounds.width, height: 230)
        guard let rep = view.bitmapImageRepForCachingDisplay(in: crop) else { return }
        view.cacheDisplay(in: crop, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
