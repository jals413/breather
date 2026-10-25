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
    private var menuTracking = false
    private var observers: [NSObjectProtocol] = []

    private static let canvas = CGSize(width: 620, height: 300)

    init(app: AppModel) {
        self.app = app
    }

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
        if let panel {
            if app.notch.content == .hidden { panel.orderOut(nil) } else if !panel.isVisible { panel.orderFrontRegardless() }
        }
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
        let settings = app.store.settings
        let notchSize = geometry.hasNotch ? geometry.notch.size : .zero
        let body = NotchLayout.size(for: app.notch.content, notch: notchSize, liveActivity: settings.notchLiveActivity && geometry.hasNotch)
        let width = body.width + (geometry.hasNotch ? 2 * NotchLayout.shoulder : 0)
        let height = max(body.height, geometry.hasNotch ? 0 : 56)
        let topInset = geometry.hasNotch ? 0 : geometry.menuBarHeight + 8
        return CGRect(x: geometry.centerX - width / 2, y: geometry.screenFrame.maxY - topInset - height, width: width, height: height)
    }

    private func updateMouse(_ location: CGPoint) {
        guard let panel, let geometry, let rect = islandRect() else { return }
        let content = app.notch.content
        let inside = rect.insetBy(dx: -4, dy: -4).contains(location)

        // Accept clicks only over the island.
        let interactive = inside && content != .resting && content != .hidden
        if panel.ignoresMouseEvents == interactive { panel.ignoresMouseEvents = !interactive }

        guard app.store.settings.notchHoverExpands, geometry.hasNotch else { return }
        // Hover target: the hardware notch (plus ears) when resting; the whole island when open.
        let hotZone = content == .resting
            ? rect.insetBy(dx: -6, dy: -2).union(geometry.notch.insetBy(dx: -10, dy: -2))
            : rect.insetBy(dx: -12, dy: -12)
        let hovering = hotZone.contains(location) || menuTracking

        if hovering != app.notch.isHovering {
            hoverTask?.cancel()
            hoverTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(hovering ? 120 : 300))
                guard !Task.isCancelled, let self else { return }
                self.app.notch.isHovering = hovering
                self.updateMouse(NSEvent.mouseLocation)
            }
        }
    }
}
