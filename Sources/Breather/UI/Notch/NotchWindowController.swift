import AppKit
import SwiftUI

/// A transparent panel pinned over the notch. It ignores the mouse everywhere except
/// over the island itself, so the menu bar around it keeps working.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class NotchWindowController {
    private let app: AppModel
    private var panel: NotchPanel?
    private var geometry: NotchGeometry?
    private var monitors: [Any] = []
    private var hoverTask: Task<Void, Never>?
    private var pendingHover: Bool?
    private var menuTracking = false
    private var observers: [NSObjectProtocol] = []

    private static let canvas = CGSize(width: 620, height: 300)

    init(app: AppModel) {
        self.app = app
    }

    /// The island's hosting view (used by the animation recorder).
    var hostView: NSView? { panel?.contentView }

    func start() {
        rebuild()
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.menuTracking = true }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.menuTracking = false
                self?.updateMouse(NSEvent.mouseLocation)
            }
        })
        let handler: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMouse(NSEvent.mouseLocation) }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: handler) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { event in
            handler(event)
            return event
        }) {
            monitors.append(local)
        }
    }

    /// Call whenever the island's content may have changed size.
    func contentChanged() {
        updateMouse(NSEvent.mouseLocation)
    }

    private func rebuild() {
        panel?.orderOut(nil)
        panel = nil
        guard let screen = NotchGeometry.preferredScreen() else { return }
        let geometry = NotchGeometry(screen: screen)
        if !geometry.hasNotch && !app.store.settings.pillOnScreensWithoutNotch { return }
        self.geometry = geometry

        let size = Self.canvas
        let frame = CGRect(x: geometry.centerX - size.width / 2, y: geometry.screenFrame.maxY - size.height,
                           width: size.width, height: size.height)
        let panel = NotchPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let host = FirstMouseHostingView(rootView: NotchView(app: app, geometry: geometry))
        host.frame = CGRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    /// The island's rect in screen coordinates for its current content.
    private func islandRect() -> CGRect? {
        guard let geometry else { return nil }
        let notchSize = geometry.hasNotch ? geometry.notch.size : .zero
        let body = NotchLayout.size(for: app.notch.content, notch: notchSize)
        let width = body.width + (geometry.hasNotch ? 2 * NotchLayout.shoulder : 0)
        let height = geometry.hasNotch ? body.height : max(body.height, NotchLayout.pillMinHeight)
        let topInset = geometry.hasNotch ? 0 : geometry.menuBarHeight + 8
        return CGRect(x: geometry.centerX - width / 2, y: geometry.screenFrame.maxY - topInset - height, width: width, height: height)
    }

    private func updateMouse(_ location: CGPoint) {
        guard let panel, let geometry, let rect = islandRect() else { return }
        let content = app.notch.content

        // Accept clicks only over a visible, interactive island.
        let interactive = rect.insetBy(dx: -4, dy: -4).contains(location) && content.openness >= 1
        if panel.ignoresMouseEvents == interactive { panel.ignoresMouseEvents = !interactive }

        guard app.store.settings.notchHoverExpands, geometry.hasNotch else { return }
        // Hysteresis: open only from the notch itself (so passing by on the way to the menu bar
        // doesn't trigger it); stay open while anywhere over the island.
        let wantsHover: Bool
        if app.notch.isHovering {
            wantsHover = menuTracking || rect.insetBy(dx: -16, dy: -16).contains(location)
        } else {
            let entry = content == .peek ? rect : geometry.notch.insetBy(dx: -6, dy: 0)
            wantsHover = entry.contains(location) && (content == .resting || content == .peek)
        }

        if wantsHover == app.notch.isHovering {
            // Mouse went back before the delay elapsed: cancel the pending change.
            hoverTask?.cancel()
            hoverTask = nil
            pendingHover = nil
            return
        }
        guard pendingHover != wantsHover else { return }
        pendingHover = wantsHover
        hoverTask?.cancel()
        hoverTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(wantsHover ? 220 : 320))
            guard !Task.isCancelled, let self else { return }
            self.pendingHover = nil
            self.app.notch.isHovering = wantsHover
            self.updateMouse(NSEvent.mouseLocation)
        }
    }
}
