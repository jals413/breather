import BreatherKit
import SwiftUI
import UIKit

@main
struct BreatherPhoneApp: App {
    @UIApplicationDelegateAdaptor(PhoneAppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase
    private let model = PhoneModel.shared

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .tint(Brand.mint)
                .preferredColorScheme(.dark)  // Breather is a night brand on every device
                // breather-phone://pair?code=123456 — from the QR code on the Mac.
                .onOpenURL { url in
                    if url.host() == "stats" || url.host() == "home" {
                        model.selectedTab = url.host() == "stats" ? .stats : .home
                        return
                    }
                    guard url.host() == "pair",
                          let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                            .queryItems?.first(where: { $0.name == "code" })?.value else { return }
                    model.pair(code: code)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            model.setActive(phase == .active)
        }
    }
}

final class PhoneAppDelegate: NSObject, UIApplicationDelegate {
    /// Also runs when iOS relaunches Breather in the background for a Bluetooth event.
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        MainActor.assumeIsolated { PhoneModel.shared.start() }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushRegistration.deviceToken = deviceToken.map { String(format: "%02x", $0) }.joined()
        MainActor.assumeIsolated { PhoneModel.shared.liveActivity.sendTokensIfAvailable() }
    }
}

struct RootView: View {
    let model: PhoneModel

    var body: some View {
        if model.mac == nil {
            PairView(model: model)
        } else {
            @Bindable var model = model
            TabView(selection: $model.selectedTab) {
                Tab("Breather", systemImage: "eye.fill", value: PhoneModel.AppTab.home) { HomeView(model: model) }
                Tab("Stats", systemImage: "chart.bar.fill", value: PhoneModel.AppTab.stats) { StatsDashboard(model: model) }
            }
        }
    }
}
