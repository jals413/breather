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
    /// This phone's own link key with the Mac (base64), agreed during pairing.
    var key: String
    /// Counters already accepted from the Mac, so a captured message can't be replayed.
    var received = ReplayGuard()
}

/// The phone mirrors the Mac: it never decides breaks, it reflects them on the Lock Screen,
/// the Dynamic Island, the Watch, and (paid) Screen Time.
@MainActor
@Observable
final class PhoneModel {
    static let shared = PhoneModel()

    private(set) var state: MacState? = SharedStore.state
    private(set) var stats: StatsSnapshot? = SharedStore.stats
    private(set) var watchConnected = false
    /// Mac app icons for the Stats dashboard, cached on disk.
    private(set) var appIcons: [String: UIImage] = AppIconCache.loadAll()
    enum AppTab: Hashable { case home, stats }
    var selectedTab: AppTab = .home
    private(set) var mac: PairedMac?
    private(set) var routes: Set<LinkClient.Route> = []
    private(set) var pairingStatus: String?
    private(set) var isPairing = false
    /// Connected, but the Mac no longer accepts our messages (it was reset or unpaired us).
    private(set) var needsRepair = false
    @ObservationIgnored private var lastVerified = Date.distantPast
    @ObservationIgnored private var attempt: PhonePairing?
    @ObservationIgnored private var counter = LinkCounter()

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
        // A Mac paired by an older build (one shared secret) doesn't decode, so it pairs again.
        if let data = UserDefaults.standard.data(forKey: Self.macKey) {
            mac = try? JSONDecoder().decode(PairedMac.self, from: data)
        }
    }

    private var keys: LinkKeys? { mac.flatMap { SymmetricKey(base64: $0.key) }.map(LinkKeys.init) }
    var isConnected: Bool { !routes.isEmpty }

    /// `-BreatherDemo` (or `-BreatherDemoBreak`) fills the app with sample data for screenshots.
    /// Nothing real is shown and nothing connects.
    private func startDemo(onBreak: Bool) {
        mac = PairedMac(id: "demo", name: "MacBook Pro", key: "")
        routes = [.bluetooth]
        watchConnected = true
        let profiles = [ProfileSummary(id: "1", name: "Everyday", symbol: "sun.max.fill"),
                        ProfileSummary(id: "2", name: "Deep Work", symbol: "brain.head.profile.fill"),
                        ProfileSummary(id: "3", name: "Gentle", symbol: "leaf.fill")]
        var demo = onBreak ? MacState.previewBreak : MacState.preview
        if onBreak { demo.breakEnd = .now.addingTimeInterval(17); demo.breakStart = .now.addingTimeInterval(-3) }
        demo.detail = onBreak ? "Short break" : "Break in 12 min"
        demo.profiles = profiles
        demo.activeProfileID = "1"
        state = demo
        let day: (Int, Double, Int) -> StatsSnapshot.Day = { offset, hours, score in
            let date = Calendar.current.date(byAdding: .day, value: -offset, to: .now)!
            let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
            return StatsSnapshot.Day(day: String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!),
                                     screenSeconds: hours * 3600, score: score, taken: Int(hours * 3), skipped: score < 70 ? 3 : 1)
        }
        let usage: (String, Double) -> StatsSnapshot.Usage = { StatsSnapshot.Usage(id: $0, name: $0, seconds: $1 * 60) }
        stats = StatsSnapshot(score: 88, rhythmPoints: 53, breakPoints: 35, screenSeconds: 5.4 * 3600, taken: 14, skipped: 1,
                              longestSession: 34 * 60, medianSession: 19 * 60, currentSession: 8 * 60, targetSeconds: 1200,
                              week: [day(6, 6.1, 72), day(5, 5.2, 81), day(4, 6.8, 64), day(3, 4.9, 86), day(2, 5.6, 90),
                                     day(1, 3.2, 93), day(0, 5.4, 88)],
                              topApps: [usage("Xcode", 128), usage("Safari", 74), usage("Figma", 51), usage("Messages", 22), usage("Notes", 14)],
                              topSites: [usage("developer.apple.com", 41), usage("github.com", 28), usage("news.ycombinator.com", 9)],
                              macName: "MacBook Pro")
    }

    func start() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-BreatherDemo") || args.contains("-BreatherDemoBreak") {
            startDemo(onBreak: args.contains("-BreatherDemoBreak"))
            return
        }
        link.onMessage = { [weak self] data, route in self?.receive(data, via: route) }
        link.onRoutesChanged = { [weak self] routes in
            guard let self else { return }
            let wasEmpty = self.routes.isEmpty
            let added = routes.subtracting(self.routes)
            self.routes = routes
            if wasEmpty && !routes.isEmpty {
                self.sayHello()
            } else {
                // The Mac only sends over a connection once we've said hello on it.
                for route in added { self.sendSealed(.hello(deviceName: UIDevice.current.name), via: route) }
            }
        }
        watch.onCommand = { [weak self] command in self?.send(command) }
        watch.onStatusChanged = { [weak self] connected in
            self?.watchConnected = connected
            self?.sendSealed(.deviceStatus(watchConnected: connected))
        }
        liveActivity.onTokens = { [weak self] tokens in self?.sendSealed(.tokens(tokens)) }
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

    /// Pairs with the typed code, or with the QR code's long key when scanned (`qrKey`).
    func pair(code: String, qrKey: String? = nil) {
        guard code.count == LinkConstants.pairingCodeLength || qrKey?.isEmpty == false else { return }
        let pairing = PhonePairing(secret: qrKey ?? code, usesQRKey: qrKey != nil, deviceID: deviceID, deviceName: UIDevice.current.name)
        attempt = pairing
        isPairing = true
        pairingStatus = isConnected ? "Pairing…" : "Looking for your Mac…"
        guard let start = try? LinkPacket.pairing(.start(pairing.start)).encoded() else { return }
        link.send(start)
        // Retry once the link comes up if we weren't connected yet, until the Mac answers.
        Task {
            for _ in 0..<10 where isPairing && attempt?.start == pairing.start && attempt?.macKey == nil {
                try? await Task.sleep(for: .seconds(2))
                if isConnected, attempt?.start == pairing.start, attempt?.macKey == nil { link.send(start) }
            }
            if isPairing && attempt?.start == pairing.start && mac == nil {
                stopPairing("Couldn't reach your Mac. Make sure Breather is open there and both have Bluetooth on.")
            }
        }
    }

    private func stopPairing(_ status: String?) {
        attempt = nil
        isPairing = false
        pairingStatus = status
    }

    func unpair() {
        mac = nil
        needsRepair = false
        UserDefaults.standard.removeObject(forKey: Self.macKey)
        state = nil
        stats = nil
        SharedStore.state = nil
        SharedStore.stats = nil
        liveActivity.endAll()
        blocker.unblock()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Commands

    func send(_ command: PhoneCommand) {
        sendSealed(.command(command))
    }

    /// Encrypts once and sends over every route; the Mac acts on whichever copy arrives first.
    private func sendSealed(_ message: LinkMessage, via route: LinkClient.Route? = nil) {
        guard let keys,
              let data = try? LinkCrypto.seal(message, keys: keys, direction: .phoneToMac, sender: deviceID, counter: counter.next())
        else { return }
        link.send(data, via: route)
    }

    private func sayHello() {
        // Separately on each route, so the Mac recognizes each connection as ours.
        for route in link.routes { sendSealed(.hello(deviceName: UIDevice.current.name), via: route) }
        sendSealed(.deviceStatus(watchConnected: watch.isWatchConnected))
        // The Mac answers a hello with its state. Hearing nothing verifiable since then,
        // while connected, means it forgot us.
        let saidHello = Date.now
        Task {
            try? await Task.sleep(for: .seconds(8))
            if mac != nil, isConnected, lastVerified < saidHello { needsRepair = true }
        }
    }

    // MARK: Incoming

    private func receive(_ data: Data, via route: LinkClient.Route) {
        switch LinkPacket.decode(data) {
        case .pairing(let message): handlePairing(message, via: route)
        case .sealed(let sealed): handleSealed(sealed, via: route)
        case nil: break
        }
    }

    private func handlePairing(_ message: PairMessage, via route: LinkClient.Route) {
        guard isPairing, var pairing = attempt else { return }
        switch message {
        case .challenge(let challenge):
            guard challenge.deviceID == deviceID, pairing.macKey == nil else { return }
            guard let reveal = pairing.answer(challenge) else {
                // Wrong code, or not our Mac. Reveal nothing, and end the attempt on the Mac too.
                if let cancel = try? LinkPacket.pairing(.cancel(deviceID: deviceID)).encoded() { link.send(cancel, via: route) }
                return stopPairing("That code doesn't match your Mac's. Start pairing again on your Mac.")
            }
            attempt = pairing
            pairingStatus = "Pairing…"
            // Only to the Mac that proved it knows the code.
            if let data = try? LinkPacket.pairing(reveal).encoded() { link.send(data, via: route) }
        case .accepted(let accepted):
            guard let key = pairing.finish(accepted) else { return }
            let paired = PairedMac(id: accepted.macID, name: accepted.macName, key: key.base64)
            mac = paired
            saveMac()
            stopPairing(nil)
            link.verified(route)
            sayHello()
            liveActivity.sendTokensIfAvailable()
        case .rejected(let reason):
            guard pairing.macKey == nil else { return }
            stopPairing(reason)
        case .start, .reveal, .cancel:
            break
        }
    }

    private func handleSealed(_ sealed: SealedMessage, via route: LinkClient.Route) {
        guard var paired = mac, sealed.sender == paired.id, let keys,
              let message = LinkCrypto.open(sealed, keys: keys, direction: .macToPhone),
              paired.received.accept(sealed.counter) else { return }
        mac = paired
        saveMac()
        link.verified(route)
        lastVerified = .now
        needsRepair = false
        switch message {
        case .state(let newState):
            apply(newState)
        case .stats(let snapshot):
            stats = snapshot
            SharedStore.stats = snapshot
        case .appIcon(let id, let png):
            if let image = UIImage(data: png) {
                appIcons[id] = image
                AppIconCache.save(png, id: id)
            }
        default:
            break
        }
    }

    private func saveMac() {
        if let encoded = try? JSONEncoder().encode(mac) { UserDefaults.standard.set(encoded, forKey: Self.macKey) }
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

enum AppIconCache {
    private static var dir: URL {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("AppIcons")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func save(_ png: Data, id: String) {
        try? png.write(to: dir.appendingPathComponent(id + ".png"))
    }

    static func loadAll() -> [String: UIImage] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return Dictionary(uniqueKeysWithValues: files.compactMap { url in
            UIImage(contentsOfFile: url.path).map { (url.deletingPathExtension().lastPathComponent, $0) }
        })
    }
}
