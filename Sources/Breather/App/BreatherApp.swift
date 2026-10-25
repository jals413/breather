import AppKit
import SwiftUI

@main
struct BreatherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let app = AppModel.shared

    var body: some Scene {
        @Bindable var store = app.store
        MenuBarExtra(isInserted: $store.settings.showMenuBarIcon) {
            MenuBarView(app: app)
        } label: {
            MenuBarLabel(app: app)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            AssetRenderer.handleCommandLine()
            if CommandLine.arguments.contains("--render-settings") || CommandLine.arguments.contains("--render-stats") { return }
            if CommandLine.arguments.contains("--diagnose") {
                Diagnostics.printAndExit()
            }
            AppModel.shared.start()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated { urls.forEach { AppModel.shared.handle(url: $0) } }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.saveState() }
    }

    /// Opening the app again from Finder/Spotlight shows Settings, since there's no Dock icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { AppModel.shared.openSettings() }
        return true
    }
}
