import AppKit
import CoreGraphics

/// Input idleness, typing, and lock/sleep state. None of this needs a privacy permission:
/// CGEventSource only reports *when* the last event happened, not what it was.
@MainActor
final class ActivityMonitor {
    private(set) var isLocked = false
    private(set) var isAsleep = false
    private var observers: [NSObjectProtocol] = []

    /// Called when the Mac wakes, unlocks, or the screens wake — the engine ticks immediately.
    var onWake: (() -> Void)?

    init() {
        let ws = NSWorkspace.shared.notificationCenter
        let dnc = DistributedNotificationCenter.default()

        observers.append(ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isAsleep = true }
        })
        observers.append(ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isAsleep = true }
        })
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.isAsleep = false
                    self?.onWake?()
                }
            })
        }
        observers.append(dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isLocked = true }
        })
        observers.append(dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isLocked = false
                self?.onWake?()
            }
        })
    }

    var secondsSinceAnyInput: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    /// Typing, or dragging something with the mouse.
    var secondsSinceTyping: TimeInterval {
        min(
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown),
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .leftMouseDragged)
        )
    }

    static func lockScreen() {
        // SACLockScreenImmediate lives in the private login framework; pmset's display sleep
        // locks only if "require password immediately" is on. The Ctrl-Cmd-Q shortcut path is
        // the only public, reliable way.
        let script = NSAppleScript(source: """
        tell application "System Events" to keystroke "q" using {control down, command down}
        """)
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        if error != nil {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            task.arguments = ["displaysleepnow"]
            try? task.run()
        }
    }
}
