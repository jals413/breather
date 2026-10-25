import AppKit
import ServiceManagement
import SwiftUI

enum Sound {
    static let systemSounds = ["Purr", "Glass", "Tink", "Pop", "Blow", "Bottle", "Frog", "Funk", "Hero", "Morse", "Ping", "Submarine"]

    @MainActor
    static func play(_ name: String, volume: Double) {
        guard let sound = NSSound(named: NSSound.Name(name))?.copy() as? NSSound else { return }
        sound.volume = Float(volume)
        sound.play()
    }
}

enum LoginItem {
    static func sync(enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled, service.status != .enabled { try service.register() }
            if !enabled, service.status == .enabled { try service.unregister() }
        } catch {
            NSLog("Breather: login item change failed: \(error.localizedDescription)")
        }
    }
}

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show(app: AppModel) {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(app: app))
            let window = NSWindow(contentViewController: host)
            window.title = "Breather Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
            window.setContentSize(NSSize(width: 760, height: 560))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
