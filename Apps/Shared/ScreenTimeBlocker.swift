import Foundation
import Observation

#if os(iOS) && BREATHER_PAID
import FamilyControls
import ManagedSettings

/// Blocks the apps you picked while the Mac is on a break, using Screen Time.
/// Shared with the Notification Service Extension, which applies the same shield when a
/// push arrives with the phone asleep.
@MainActor
@Observable
final class ScreenTimeBlocker {
    private(set) var isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
    private(set) var isBlocking = false
    var selection: FamilyActivitySelection = ScreenTimeShield.loadSelection() {
        didSet { ScreenTimeShield.saveSelection(selection) }
    }

    static let isAvailable = true

    func requestAuthorization() async {
        try? await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
    }

    func block() {
        guard isAuthorized else { return }
        ScreenTimeShield.apply()
        isBlocking = true
    }

    /// Also the "Force unblock" escape hatch.
    func unblock() {
        ScreenTimeShield.clear()
        isBlocking = false
    }
}

enum ScreenTimeShield {
    private static let store = ManagedSettingsStore(named: .init("breather"))
    private static let key = "screentime.selection"

    static func loadSelection() -> FamilyActivitySelection {
        guard let data = SharedStore.defaults.data(forKey: key),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return FamilyActivitySelection()
        }
        return selection
    }

    static func saveSelection(_ selection: FamilyActivitySelection) {
        if let data = try? JSONEncoder().encode(selection) { SharedStore.defaults.set(data, forKey: key) }
    }

    static func apply() {
        let selection = loadSelection()
        if selection.applicationTokens.isEmpty && selection.categoryTokens.isEmpty {
            // Nothing picked: block everything except essentials (Phone, Messages, etc. stay allowed by iOS).
            store.shield.applicationCategories = .all()
            store.shield.webDomainCategories = .all()
        } else {
            store.shield.applications = selection.applicationTokens
            store.shield.applicationCategories = .specific(selection.categoryTokens)
            store.shield.webDomains = selection.webDomainTokens
        }
    }

    static func clear() {
        store.clearAllSettings()
    }
}
#else
/// Free builds: the same API, doing nothing. Screen Time needs the paid developer program.
@MainActor
@Observable
final class ScreenTimeBlocker {
    let isAuthorized = false
    let isBlocking = false
    static let isAvailable = false
    func requestAuthorization() async {}
    func block() {}
    func unblock() {}
}
#endif
