import AppKit

/// Combines the detectors into the list of reasons a break should wait.
/// Polled every couple of seconds — every detector is a cheap system query, no background threads.
@MainActor
final class SmartPauseMonitor {
    private(set) var reasons: [PauseReason] = []
    private var lastPoll = Date.distantPast
    private let interval: TimeInterval = 2

    /// Dictation and voice tools use the mic without being a call.
    private static let micIgnoredBundleIDs: Set<String> = [
        "com.apple.SpeechRecognitionCore", "com.apple.assistantd", "com.apple.Siri",
        "com.apple.corespeechd", "com.apple.DictationIM", "com.apple.accessibility.heard",
    ]

    func reasonsIfDue(now: Date, settings: Settings) -> [PauseReason] {
        if now.timeIntervalSince(lastPoll) >= interval {
            lastPoll = now
            reasons = compute(settings)
        }
        return reasons
    }

    func invalidate() { lastPoll = .distantPast }

    private func compute(_ s: Settings) -> [PauseReason] {
        var result: [PauseReason] = []
        let front = NSWorkspace.shared.frontmostApplication

        if s.pauseForMeetings {
            let excluded = Set(s.meetingExcludedApps.map(\.bundleID)).union(Self.micIgnoredBundleIDs)
            let micApps = MicrophoneDetector.appsUsingInput().filter { !excluded.contains($0.bundleID) }
            if let app = micApps.first {
                result.append(.meeting(app.name))
            } else if CameraDetector.isAnyCameraRunning() {
                result.append(.meeting(nil))
            }
        }

        let needsAssertions = s.videoMode != .off || s.pauseForScreenRecording
        let awakeApps = needsAssertions ? DisplayAssertionDetector.appsHoldingDisplayAwake() : []

        if s.videoMode != .off {
            let excluded = Set(s.videoExcludedApps.map(\.bundleID)).union(ScreenRecordingDetector.recorderBundleIDs)
            let players = awakeApps.filter { !excluded.contains($0.bundleID) }
            let playing: AppIdentity? = switch s.videoMode {
            case .frontmost: players.first { $0.bundleID == front?.bundleIdentifier }
            case .background: players.first
            case .off: nil
            }
            // A call app holding the display awake is already covered by the meeting reason.
            if let playing, !result.contains(where: { if case .meeting = $0 { true } else { false } }) {
                result.append(.video(playing.name))
            }
        }

        if s.pauseForScreenRecording {
            let names = AppIdentity.runningProcessNames()
            if ScreenRecordingDetector.isRecording(processNames: names, displayAwakeApps: awakeApps) {
                result.append(.screenRecording)
            }
        }

        let fullscreenApp = (s.pauseForFullscreenGames || s.pauseForAnyFullscreenApp || s.focusApps.contains { $0.mode == .fullscreen })
            ? FullscreenDetector.fullscreenFrontmostApp() : nil
        if let app = fullscreenApp, s.pauseForAnyFullscreenApp || (s.pauseForFullscreenGames && FullscreenDetector.isGame(app)) {
            result.append(.fullscreen(app.localizedName))
        }

        if !s.focusApps.isEmpty {
            let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            for focus in s.focusApps {
                let active: Bool = switch focus.mode {
                case .open: running.contains(focus.bundleID)
                case .foreground: front?.bundleIdentifier == focus.bundleID
                case .fullscreen: fullscreenApp?.bundleIdentifier == focus.bundleID
                }
                if active {
                    result.append(.focusApp(focus.name))
                    break
                }
            }
        }
        return result
    }
}
