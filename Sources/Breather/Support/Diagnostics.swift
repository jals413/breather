import AppKit

/// `Breather.app/Contents/MacOS/Breather --diagnose` prints what each detector sees right now.
@MainActor
enum Diagnostics {
    static func printAndExit() -> Never {
        let activity = ActivityMonitor()
        let settings = SettingsStore().settings
        var out: [String] = []
        out.append("idle: \(String(format: "%.1f", activity.secondsSinceAnyInput))s, since typing: \(String(format: "%.1f", activity.secondsSinceTyping))s")
        out.append("mic in use by: \(MicrophoneDetector.appsUsingInput().map(\.name))")
        out.append("camera running: \(CameraDetector.isAnyCameraRunning())")
        out.append("display kept awake by: \(DisplayAssertionDetector.appsHoldingDisplayAwake().map { "\($0.name) [\($0.bundleID)]" })")
        out.append("fullscreen frontmost: \(FullscreenDetector.fullscreenFrontmostApp()?.localizedName ?? "none")")
        out.append("frontmost: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")")
        for screen in NSScreen.screens {
            let g = NotchGeometry(screen: screen)
            out.append("screen \(screen.localizedName): notch=\(g.hasNotch) rect=\(g.notch)")
        }
        out.append("smart pause reasons: \(SmartPauseMonitor().reasonsIfDue(now: .now, settings: settings).map(\.title))")
        print(out.joined(separator: "\n"))
        exit(0)
    }
}
