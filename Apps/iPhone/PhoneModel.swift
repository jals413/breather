import BreatherKit
import CryptoKit
import Foundation
import Observation
import UIKit
import UserNotifications
import WidgetKit

struct PairedMac: Codable, Equatable {
    var id: String
    var name: String
    var secret: String
}

/// The phone mirrors the Mac: it never decides breaks, it reflects them on the Lock Screen,
/// the Dynamic Island, the Watch, and (paid) Screen Time.
@MainActor
@Observable
final class PhoneModel {
    static let shared = PhoneModel()

    private(set) var state: MacState? = SharedStore.state
    private(set) var mac: PairedMac?
    private(set) var routes: Set<LinkClient.Route> = []
    private(set) var pairingStatus: String?
    private(set) var isPairing = false
    /// Connected, but the Mac no longer accepts our messages (it was reset or unpaired us).
    private(set) var needsRepair = false
    @ObservationIgnored private var lastVerified = Date.distantPast

    var liveActivityEnabled = UserDefaults.standard.object(forKey: "liveActivity") as? Bool ?? true {
        didSet { UserDefaults.standard.set(liveActivityEnabled, forKey: "liveActivity"); syncSurfaces(previous: state) }
    }
    var notificationsEnabled = UserDefaults.standard.object(forKey: "notifications") as? Bool ?? true {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "notifications") }
    }

    @ObservationIgnored let link = LinkClient()
    @ObservationIgnored let liveActivity = LiveActivityController()
    @ObservationIgnored let watch = WatchBridge()
    let blocker = ScreenTimeBlocker()
    @ObservationIgnored private var appActive = true
    @ObservationIgnored private let deviceID: String

    private static let macKey = "paired.mac"

    private init() {
        if let id = UserDefaults.standard.string(forKey: "deviceID") {
            deviceID = id
        } else {
            deviceID = UUID().uuidString
            UserDefaults.standard.set(deviceID, forKey: "deviceID")
        }
        if let data = UserDefaults.standard.data(forKey: Self.macKey) {
            mac = try? JSONDecoder().decode(PairedMac.self, from: data)
        }
    }

    var secret: SymmetricKey? { mac.flatMap { SymmetricKey(base64: $0.secret) } }
    var isConnected: Bool { !routes.isEmpty }

    func start() {
        link.onMessage = { [weak self] data in self?.receive(data) }
        link.onRoutesChanged = { [weak self] routes in
            guard let self else { return }
            let wasEmpty = self.routes.isEmpty
            self.routes = routes
            if wasEmpty && !routes.isEmpty { self.sayHello() }
        }
        watch.onCommand = { [weak self] command in self?.send(command) }
        watch.onStatusChanged = { [weak self] connected in self?.sendSigned(.deviceStatus(watchConnected: connected)) }
        liveActivity.onTokens = { [weak self] tokens in self?.sendSigned(.tokens(tokens)) }
        link.start()
        watch.activate()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .timeSensitive]) { _, _ in }
        if AppFlags.paid { UIApplication.shared.registerForRemoteNotifications() }
    }

    func setActive(_ active: Bool) {
        appActive = active
        link.setForeground(active)
        if active {
            sayHello()
            syncSurfaces(previous: state)
        }
    }

    // MARK: Pairing

    func pair(code: String) {
        guard code.count == LinkConstants.pairingCodeLength else { return }
        isPairing = true
        pairingStatus = isConnected ? "Pairing…" : "Looking for your Mac…"
        let request = PairRequest(code: code, deviceID: deviceID, deviceName: UIDevice.current.name)
        if let data = try? LinkEnvelope.seal(.pairRequest(request), secret: nil) { link.send(data) }
        // Retry once the link comes up if we weren't connected yet.
        Task {
            for _ in 0..<10 where isPairing && mac == nil {
                try? await Task.sleep(for: .seconds(2))
                if isConnected, let data = try? LinkEnvelope.seal(.pairRequest(request), secret: nil) { link.send(data) }
            }
            if mac == nil && isPairing {
                isPairing = false
                pairingStatus = "Couldn't reach your Mac. Make sure Breather is open there and both have Bluetooth on."
            }
        }
    }

    func unpair() {
        mac = nil
        needsRepair = false
        UserDefaults.standard.removeObject(forKey: Self.macKey)
        state = nil
        SharedStore.state = nil
        liveActivity.endAll()
        blocker.unblock()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Commands

    func send(_ command: PhoneCommand) {
        sendSigned(.command(command))
    }

    private func sendSigned(_ message: LinkMessage) {
        guard let secret, let data = try? LinkEnvelope.seal(message, secret: secret) else { return }
        link.send(data)
    }

    private func sayHello() {
        sendSigned(.hello(deviceID: deviceID, deviceName: UIDevice.current.name))
        sendSigned(.deviceStatus(watchConnected: watch.isWatchConnected))
        // The Mac answers a hello with its state. Silence while connected means it forgot us.
        Task {
            try? await Task.sleep(for: .seconds(8))
            if mac != nil, isConnected, Date.now.timeIntervalSince(lastVerified) > 8 { needsRepair = true }
        }
    }

    // MARK: Incoming

    private func receive(_ data: Data) {
        guard let message = LinkEnvelope.open(data, secret: secret) else { return }
        if case .state = message {
            lastVerified = .now
            needsRepair = false
        }
        switch message {
        case .pairAccepted(let accepted):
            guard isPairing else { return }
            let paired = PairedMac(id: accepted.macID, name: accepted.macName, secret: accepted.secret)
            mac = paired
            if let encoded = try? JSONEncoder().encode(paired) { UserDefaults.standard.set(encoded, forKey: Self.macKey) }
            isPairing = false
            pairingStatus = nil
            sayHello()
            liveActivity.sendTokensIfAvailable()
        case .pairRejected(let reason):
            guard isPairing else { return }
            isPairing = false
            pairingStatus = reason
        case .state(let newState):
            apply(newState)
        default:
            break
        }
    }

    func apply(_ newState: MacState) {
        let previous = state
        state = newState
        SharedStore.state = newState
        WidgetCenter.shared.reloadAllTimelines()
        watch.send(newState)
        syncSurfaces(previous: previous)
        notifyIfNeeded(previous: previous, now: newState)
        if newState.mode == .onBreak, newState.blockPhone {
            blocker.block()
        } else if previous?.mode == .onBreak {
            blocker.unblock()
        }
    }

    private func syncSurfaces(previous: MacState?) {
        guard let state, mac != nil else { return }
        liveActivity.sync(state, previous: previous, enabled: liveActivityEnabled, appActive: appActive)
    }

    /// A notification taps your Apple Watch when the phone is locked; skipped while the app is open.
    private func notifyIfNeeded(previous: MacState?, now: MacState) {
        guard notificationsEnabled, !appActive else { return }
        let started = now.mode == .onBreak && previous?.mode != .onBreak
        let ended = now.mode != .onBreak && previous?.mode == .onBreak
        guard started || ended else { return }
        let content = UNMutableNotificationContent()
        content.title = started ? (now.breakTitle ?? "Break time") : "Break over"
        content.body = started ? (now.breakMessage ?? "Look away from your screens.") : "Welcome back."
        content.sound = .default
        content.interruptionLevel = started ? .timeSensitive : .active
        content.threadIdentifier = "breaks"
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "break", content: content, trigger: nil))
    }
}
