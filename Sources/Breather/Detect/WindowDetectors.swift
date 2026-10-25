import AppKit
import CoreGraphics

/// Fullscreen detection from window bounds only. Window *titles* would need Screen Recording
/// permission; bounds and owners don't.
@MainActor
enum FullscreenDetector {
    private static var gameCache: [String: Bool] = [:]

    /// The frontmost app if one of its windows covers an entire display.
    static func fullscreenFrontmostApp() -> NSRunningApplication? {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != getpid() else { return nil }
        let displays = NSScreen.screens.compactMap { screen -> CGRect? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
        }
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for window in info {
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == front.processIdentifier,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { continue }
            if displays.contains(where: { bounds.contains($0) }) { return front }
        }
        return nil
    }

    static func isGame(_ app: NSRunningApplication) -> Bool {
        let key = app.bundleIdentifier ?? app.bundleURL?.path ?? ""
        if let cached = gameCache[key] { return cached }
        var game = false
        if let url = app.bundleURL, let info = Bundle(url: url)?.infoDictionary {
            let category = (info["LSApplicationCategoryType"] as? String) ?? ""
            game = category.contains("games")
                || info["GCSupportsControllerUserInteraction"] as? Bool == true
                || info["GCSupportsGameMode"] as? Bool == true
        }
        gameCache[key] = game
        return game
    }
}

/// Best-effort screen recording detection without Screen Recording permission.
enum ScreenRecordingDetector {
    /// Processes that only exist while macOS itself is recording (⇧⌘5, QuickTime "New Screen Recording").
    private static let systemRecorders: Set<String> = ["screencapture"]
    /// Recorder apps that hold a display-awake assertion while capturing.
    static let recorderBundleIDs: Set<String> = [
        "com.obsproject.obs-studio", "com.loom.desktop", "pl.maketheweb.cleanshotx",
        "com.techsmith.camtasia2023", "com.techsmith.camtasia2024", "com.techsmith.camtasia2025",
        "net.telestream.screenflow10", "net.telestream.screenflow11", "com.apple.ScreenSharing",
        "com.screenstudio.app", "com.kap.Kap",
    ]

    static func isRecording(processNames: Set<String>, displayAwakeApps: [AppIdentity]) -> Bool {
        if !processNames.isDisjoint(with: systemRecorders) { return true }
        return displayAwakeApps.contains { recorderBundleIDs.contains($0.bundleID) }
    }
}
