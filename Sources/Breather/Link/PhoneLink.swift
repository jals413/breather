import AppKit
import BreatherKit
import CryptoKit
import Observation

struct PairedDevice: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var pairedAt: Date
    var lastSeen: Date?
    var tokens: PushTokens?
    /// Counters already accepted from this phone, so a captured message can't be replayed.
    var received = ReplayGuard()
}

/// Keeps the Mac's paired iPhones (and their Watches) in sync with breaks.
///
/// Transports, all carrying the same encrypted messages (see `LinkCrypto`):
///  - Bluetooth LE: works in the background on the phone, no account needed (real devices).
///  - Local network (Bonjour/TCP): instant while the phone app is open; also how the iOS Simulator connects.
///  - Apple push: reaches the phone anywhere, even asleep (paid builds only, see `APNsClient`).
///
/// Each phone has its own key, agreed during pairing (see `PairMessage`). Nothing is sent to a
/// connection until a paired phone proves itself on it, and forgetting a phone deletes its key.
@MainActor
@Observable
final class PhoneLink {
    private(set) var devices: [PairedDevice] = []
    private(set) var pairing: MacPairing?
    /// Progress or the reason the last pairing attempt stopped.
    private(set) var pairingStatus: String?
    private(set) var connectedCount = 0
    private(set) var bluetoothCount = 0
    /// Reported by the phone: its Apple Watch has Breather and is reachable.
    private(set) var watchConnected = false

    /// A paired phone is connected over Bluetooth or the local network right now.
    var phoneConnected: Bool { !devices.isEmpty && (connectedCount + bluetoothCount) > 0 }
    private(set) var bluetoothStatus = "Off"
    private(set) var lastSent: MacState?

    var pairingCode: String? { pairing?.code }
    var pairingExpires: Date? { pairing?.expires }

    @ObservationIgnored var onCommand: ((PhoneCommand) -> Void)?
    /// Supplies the stats dashboard data (sent on connect and every few minutes).
    @ObservationIgnored var statsProvider: (() -> StatsSnapshot)?
    @ObservationIgnored private var lastStatsAt = Date.distantPast
    /// App icons already sent since the phone last said hello.
    @ObservationIgnored private var sentIcons: Set<String> = []
    @ObservationIgnored private var keys: [String: LinkKeys] = [:]
    @ObservationIgnored private var counter = LinkCounter()
    @ObservationIgnored private var lan: LANServer?
    @ObservationIgnored private var ble: BLEPeripheral?
    @ObservationIgnored private var lastSentAt = Date.distantPast
    @ObservationIgnored private let macID: String
    @ObservationIgnored let apns = APNsClient()

    private static let devicesKey = "phone.devices"

    var isRunning: Bool { lan != nil || ble != nil }
    var macName: String { Host.current().localizedName ?? "Mac" }

    init() {
        if let id = UserDefaults.standard.string(forKey: "phone.macID") {
            macID = id
        } else {
            macID = UUID().uuidString
            UserDefaults.standard.set(macID, forKey: "phone.macID")
        }
        // Older builds shared one secret with every phone and kept the code in preferences.
        LegacySecretFile.delete()
        UserDefaults.standard.removeObject(forKey: "phone.pairing")
        if let data = UserDefaults.standard.data(forKey: Self.devicesKey),
           let saved = try? JSONDecoder().decode([PairedDevice].self, from: data) {
            devices = saved
        }
        keys = KeyFile.read().compactMapValues { SymmetricKey(base64: $0).map(LinkKeys.init) }
        // Phones without a key (paired by an older build, or the key file is gone) must pair again.
        let before = devices.count
        devices.removeAll { keys[$0.id] == nil }
        if devices.count != before { saveDevices() }
    }

    // MARK: Lifecycle

    func setEnabled(_ enabled: Bool) {
        if enabled && !isRunning {
            lan = LANServer(macName: macName) { [weak self] data, peer in self?.receive(data, from: peer) }
            lan?.onConnectionsChanged = { [weak self] count in self?.connectedCount = count }
            ble = BLEPeripheral { [weak self] data, peer in self?.receive(data, from: peer) }
            ble?.onStatus = { [weak self] status in self?.bluetoothStatus = status }
            ble?.onSubscribersChanged = { [weak self] count in self?.bluetoothCount = count }
            lan?.start()
            ble?.start()
        } else if !enabled && isRunning {
            lan?.stop()
            ble?.stop()
            lan = nil
            ble = nil
            connectedCount = 0
            bluetoothCount = 0
            watchConnected = false
            bluetoothStatus = "Off"
            cancelPairing()
        }
    }

    // MARK: Pairing

    func startPairing() {
        pairing = MacPairing()
        pairingStatus = nil
    }

    func cancelPairing() {
        pairing = nil
    }

    /// Scanning this with the iPhone camera opens Breather and pairs with the QR code's long key, no typing.
    var pairingURL: URL? {
        guard let pairing else { return nil }
        var components = URLComponents()
        components.scheme = "breather-phone"
        components.host = "pair"
        components.queryItems = [URLQueryItem(name: "code", value: pairing.code), URLQueryItem(name: "key", value: pairing.qrKey)]
        return components.url
    }

    func forget(_ device: PairedDevice) {
        devices.removeAll { $0.id == device.id }
        keys[device.id] = nil
        saveDevices()
        saveKeys()
        lan?.disconnect(device.id)
        ble?.disconnect(device.id)
    }

    // MARK: State out

    /// Sends the state when it meaningfully changes, plus a heartbeat every minute.
    func publish(_ state: MacState, force: Bool = false) {
        guard isRunning || FeatureFlags.paidAccount, !devices.isEmpty else { return }
        let changed = state.differsMeaningfully(from: lastSent)
        guard force || changed || Date.now.timeIntervalSince(lastSentAt) > 60 else { return }
        let previous = lastSent
        lastSent = state
        lastSentAt = .now
        broadcast(.state(state))
        if changed { apns.deliver(state, previous: previous, to: devices) }
    }

    /// Sends fresh stats now, or on a 5-minute cadence when `force` is false.
    func publishStats(force: Bool = false) {
        guard isRunning, !devices.isEmpty, force || Date.now.timeIntervalSince(lastStatsAt) > 300,
              let stats = statsProvider?() else { return }
        lastStatsAt = .now
        broadcast(.stats(stats))
        for (id, png) in newIcons(for: stats) { broadcast(.appIcon(id: id, png: png)) }
    }

    /// Encrypts the message separately for each paired phone and sends it only to that phone.
    private func broadcast(_ message: LinkMessage) {
        for device in devices {
            guard let data = seal(message, for: device.id) else { continue }
            lan?.send(data, to: device.id)
            ble?.send(data, to: device.id)
        }
    }

    private func seal(_ message: LinkMessage, for deviceID: String) -> Data? {
        guard let keys = keys[deviceID] else { return nil }
        return try? LinkCrypto.seal(message, keys: keys, direction: .macToPhone, sender: macID, counter: counter.next())
    }

    private func newIcons(for stats: StatsSnapshot) -> [(String, Data)] {
        stats.topApps.filter { !sentIcons.contains($0.id) }.compactMap { app in
            guard let png = AppIconRenderer.png(bundleID: app.id) else { return nil }
            sentIcons.insert(app.id)
            return (app.id, png)
        }
    }

    // MARK: Messages in

    private func receive(_ data: Data, from peer: LinkPeer) {
        switch LinkPacket.decode(data) {
        case .pairing(let message): handlePairing(message, from: peer)
        case .sealed(let sealed): handleSealed(sealed, from: peer)
        case nil: break
        }
    }

    private func handleSealed(_ sealed: SealedMessage, from peer: LinkPeer) {
        guard let index = devices.firstIndex(where: { $0.id == sealed.sender }), let keys = keys[sealed.sender],
              let message = LinkCrypto.open(sealed, keys: keys, direction: .phoneToMac),
              devices[index].received.accept(sealed.counter) else { return }
        let deviceID = sealed.sender
        peer.authenticate(deviceID)
        devices[index].lastSeen = .now
        switch message {
        case .hello:
            if let state = lastSent, let data = seal(.state(state), for: deviceID) { peer.reply(data) }
            if let stats = statsProvider?(), let data = seal(.stats(stats), for: deviceID) {
                peer.reply(data)
                sentIcons.removeAll()
                for (id, png) in newIcons(for: stats) {
                    if let data = seal(.appIcon(id: id, png: png), for: deviceID) { peer.reply(data) }
                }
            }
        case .command(let command):
            onCommand?(command)
        case .tokens(let tokens):
            devices[index].tokens = tokens
        case .deviceStatus(let watch):
            watchConnected = watch
        case .state, .stats, .appIcon:
            break
        }
        saveDevices()
    }

    private func handlePairing(_ message: PairMessage, from peer: LinkPeer) {
        func send(_ reply: PairMessage) {
            if let data = try? LinkPacket.pairing(reply).encoded() { peer.reply(data) }
        }
        guard var attempt = pairing else {
            if case .start = message { send(.rejected(reason: "Start pairing in Breather's iPhone settings on your Mac first.")) }
            return
        }
        if case .start(let start) = message, attempt.started == nil,
           devices.count >= LinkConstants.maxPairedDevices, !devices.contains(where: { $0.id == start.deviceID }) {
            return send(.rejected(reason: "This Mac already has \(LinkConstants.maxPairedDevices) paired devices."))
        }
        switch attempt.handle(message, macID: macID, macName: macName) {
        case .reply(let reply):
            if case .start(let start) = message, attempt.started == start { pairingStatus = "Pairing with \(start.deviceName)…" }
            pairing = attempt
            send(reply)
        case .failed(let reason):
            // One attempt per code: whoever got this far can't try again with the same code.
            cancelPairing()
            pairingStatus = "Pairing stopped. \(reason)"
            send(.rejected(reason: reason))
        case .paired(let start, let key, let reply):
            keys[start.deviceID] = LinkKeys(key)
            devices.removeAll { $0.id == start.deviceID }
            devices.append(PairedDevice(id: start.deviceID, name: start.deviceName, pairedAt: .now, lastSeen: .now))
            saveDevices()
            var stored = KeyFile.read()
            stored[start.deviceID] = key.base64
            KeyFile.write(stored)
            cancelPairing()
            pairingStatus = nil
            send(reply)
        case .ignore:
            break
        }
    }

    private func saveDevices() {
        if let data = try? JSONEncoder().encode(devices) { UserDefaults.standard.set(data, forKey: Self.devicesKey) }
    }

    private func saveKeys() {
        KeyFile.write(KeyFile.read().filter { keys[$0.key] != nil })
    }
}

/// Each paired phone's link key, in Breather's own data folder and readable only by your user account.
///
/// Not in the Keychain on purpose: while Breather is built and signed ad hoc, every rebuild
/// looks like a new app to macOS, which then asks for your login password to read the item.
/// A Developer ID–signed release could use the Keychain without prompts.
enum KeyFile {
    private static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Breather/link-keys.json")
    }

    /// Device ID → base64 key.
    static func read() -> [String: String] {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    }

    static func write(_ keys: [String: String]) {
        guard !keys.isEmpty, let data = try? JSONEncoder().encode(keys) else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600])
    }
}

/// The single shared secret older builds used for every phone.
enum LegacySecretFile {
    static func delete() {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Breather/link.key")
        try? FileManager.default.removeItem(at: url)
    }
}

/// Small PNG app icons for the phone's Stats dashboard.
enum AppIconRenderer {
    @MainActor
    static func png(bundleID: String, size: CGFloat = 64) -> Data? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        icon.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
