import BreatherKit
import Foundation
import WatchConnectivity

/// Relays the Mac's state to the Apple Watch, and the Watch's buttons back to the Mac.
@MainActor
final class WatchBridge: NSObject {
    var onCommand: ((PhoneCommand) -> Void)?
    var onStatusChanged: ((Bool) -> Void)?

    /// Breather is installed on a paired Apple Watch and the session is up.
    var isWatchConnected: Bool {
        WCSession.isSupported() && WCSession.default.activationState == .activated
            && WCSession.default.isPaired && WCSession.default.isWatchAppInstalled
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Application context is delivered even when the Watch app isn't running; the latest wins.
    func send(_ state: MacState) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isWatchAppInstalled,
              let data = try? LinkCoding.encoder.encode(state) else { return }
        try? WCSession.default.updateApplicationContext(["state": data])
    }
}

extension WatchBridge: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.onStatusChanged?(self.isWatchConnected) }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.onStatusChanged?(self.isWatchConnected) }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let data = message["command"] as? Data
        replyHandler(["ok": true])
        Task { @MainActor in
            guard let data, let command = try? LinkCoding.decoder.decode(PhoneCommand.self, from: data) else { return }
            self.onCommand?(command)
        }
    }
}
