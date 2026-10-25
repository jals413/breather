import AppKit
import SwiftUI

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// One borderless window per display, above everything including fullscreen apps.
@MainActor
final class BreakOverlayController {
    private let app: AppModel
    private var windows: [OverlayWindow] = []
    private var keyMonitor: Any?
    private var lastEscape: Date?
    private var screenObserver: NSObjectProtocol?
    private var previousApp: NSRunningApplication?

    init(app: AppModel) {
        self.app = app
    }

    var isShowing: Bool { !windows.isEmpty }

    func show() {
        guard windows.isEmpty else { return }
        previousApp = NSWorkspace.shared.frontmostApplication
        buildWindows(fadeIn: true)
        NSApp.activate()
        windows.first?.makeKeyAndOrderFront(nil)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // Esc
                MainActor.assumeIsolated { self.handleEscape() }
                return nil
            }
            return nil // swallow typing during a break
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isShowing else { return }
                self.windows.forEach { $0.orderOut(nil) }
                self.windows.removeAll()
                self.buildWindows(fadeIn: false)
            }
        }
    }

    func hide() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        let closing = windows
        windows.removeAll()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.45
            closing.forEach { $0.animator().alphaValue = 0 }
        } completionHandler: {
            MainActor.assumeIsolated {
                closing.forEach { $0.orderOut(nil) }
            }
        }
        // Give focus back to whatever the user was doing.
        if let previousApp, previousApp.processIdentifier != getpid() {
            previousApp.activate()
        }
        previousApp = nil
    }

    private func buildWindows(fadeIn: Bool) {
        for (index, screen) in NSScreen.screens.enumerated() {
            let window = OverlayWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            let view = BreakOverlayView(app: app, screen: screen, isPrimary: index == 0)
            window.contentView = NSHostingView(rootView: view)
            window.setFrame(screen.frame, display: true)
            window.alphaValue = fadeIn ? 0 : 1
            window.orderFrontRegardless()
            windows.append(window)
        }
        if fadeIn {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.6
                windows.forEach { $0.animator().alphaValue = 1 }
            }
        }
    }

    private func handleEscape() {
        let now = Date()
        if let last = lastEscape, now.timeIntervalSince(last) < 0.8 {
            lastEscape = nil
            if app.canSkipCurrentBreak(now: now) { app.skipOrEndBreak() }
        } else {
            lastEscape = now
        }
    }
}
