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
}

/// Keeps the Mac's paired iPhones (and their Watches) in sync with breaks.
///
/// Transports, all carrying the same signed `LinkMessage`s:
///  - Bluetooth LE: works in the background on the phone, no account needed (real devices).
///  - Local network (Bonjour/TCP): instant while the phone app is open; also how the iOS Simulator connects.
///  - Apple push: reaches the phone anywhere, even asleep (paid builds only, see `APNsClient`).
@MainActor
@Observable
final class PhoneLink {
    private(set) var devices: [PairedDevice] = []
    private(set) var pairingCode: String?
    private(set) var pairingExpires: Date?
    private(set) var connectedCount = 0
    private(set) var bluetoothCount = 0
    /// Reported by the phone: its Apple Watch has Breather and is reachable.
    private(set) var watchConnected = false

    /// A paired phone is connected over Bluetooth or the local network right now.
    var phoneConnected: Bool { !devices.isEmpty && (connectedCount + bluetoothCount) > 0 }
    private(set) var bluetoothStatus = "Off"
    private(set) var lastSent: MacState?

    @ObservationIgnored var onCommand: ((PhoneCommand) -> Void)?
    /// Supplies the stats dashboard data (sent on connect and every few minutes).
    @ObservationIgnored var statsProvider: (() -> StatsSnapshot)?
    @ObservationIgnored private var lastStatsAt = Date.distantPast
    @ObservationIgnored private var secret: SymmetricKey?
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
        if let data = UserDefaults.standard.data(forKey: Self.devicesKey),
           let saved = try? JSONDecoder().decode([PairedDevice].self, from: data) {
            devices = saved
        }
        secret = SecretFile.read().flatMap { SymmetricKey(base64: $0) }
        // A secret from an older build (or a reset) is gone: those phones must pair again.
        if secret == nil && !devices.isEmpty {
            devices.removeAll()
            saveDevices()
        }
    }

    // MARK: Lifecycle

    func setEnabled(_ enabled: Bool) {
        if enabled && !isRunning {
            lan = LANServer(macName: macName) { [weak self] data, reply in self?.receive(data, reply: reply) }
            lan?.onConnectionsChanged = { [weak self] count in self?.connectedCount = count }
            ble = BLEPeripheral { [weak self] data, reply in self?.receive(data, reply: reply) }
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
        }
    }

    // MARK: Pairing

    func startPairing() {
        pairingCode = String(format: "%06d", Int.random(in: 0...999_999))
        pairingExpires = .now.addingTimeInterval(120)
        UserDefaults.standard.set(["code": pairingCode!, "expires": pairingExpires!.timeIntervalSince1970], forKey: "phone.pairing")
    }

    func cancelPairing() {
        pairingCode = nil
        pairingExpires = nil
        UserDefaults.standard.removeObject(forKey: "phone.pairing")
    }

    /// Scanning this with the iPhone camera opens Breather and pairs, no typing.
    var pairingURL: URL? {
        pairingCode.flatMap { URL(string: "breather-phone://pair?code=\($0)") }
    }

    func forget(_ device: PairedDevice) {
        devices.removeAll { $0.id == device.id }
        saveDevices()
        if devices.isEmpty {
            // Rotate the secret so a forgotten phone can't reconnect.
            secret = nil
            SecretFile.delete()
        }
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
        if let data = try? LinkEnvelope.seal(.state(state), secret: secret) {
            lan?.broadcast(data)
            ble?.broadcast(data)
        }
        if changed { apns.deliver(state, previous: previous, to: devices) }
    }

    /// Sends fresh stats now, or on a 5-minute cadence when `force` is false.
    func publishStats(force: Bool = false) {
        guard isRunning, !devices.isEmpty, force || Date.now.timeIntervalSince(lastStatsAt) > 300,
              let stats = statsProvider?(), let data = try? LinkEnvelope.seal(.stats(stats), secret: secret) else { return }
        lastStatsAt = .now
        lan?.broadcast(data)
        ble?.broadcast(data)
    }

    // MARK: Messages in

    private func receive(_ data: Data, reply: @escaping (Data) -> Void) {
        guard let message = LinkEnvelope.open(data, secret: secret) else { return }
        switch message {
        case .pairRequest(let request):
            handlePairing(request, reply: reply)
        case .hello(let deviceID, _):
            guard let index = devices.firstIndex(where: { $0.id == deviceID }) else { return }
            devices[index].lastSeen = .now
            saveDevices()
            if let state = lastSent, let data = try? LinkEnvelope.seal(.state(state), secret: secret) { reply(data) }
            if let stats = statsProvider?(), let data = try? LinkEnvelope.seal(.stats(stats), secret: secret) { reply(data) }
        case .command(let command):
            onCommand?(command)
        case .tokens(let tokens):
            // Tokens arrive signed, from a paired phone; attach to the most recently seen device.
            if let index = devices.indices.max(by: { (devices[$0].lastSeen ?? .distantPast) < (devices[$1].lastSeen ?? .distantPast) }) {
                devices[index].tokens = tokens
                saveDevices()
            }
        case .deviceStatus(let watch):
            watchConnected = watch
        case .state, .pairAccepted, .pairRejected, .stats:
            break
        }
    }

    private func handlePairing(_ request: PairRequest, reply: @escaping (Data) -> Void) {
        func reject(_ reason: String) {
            if let data = try? LinkEnvelope.seal(.pairRejected(reason: reason), secret: nil) { reply(data) }
        }
        guard let code = pairingCode, let expires = pairingExpires, Date.now < expires else {
            return reject("Start pairing in Breather's iPhone settings on your Mac first.")
        }
        guard request.code == code else { return reject("That code doesn't match.") }
        guard devices.count < LinkConstants.maxPairedDevices || devices.contains(where: { $0.id == request.deviceID }) else {
            return reject("This Mac already has \(LinkConstants.maxPairedDevices) paired devices.")
        }
        let key: SymmetricKey
        if let secret {
            key = secret
        } else {
            key = SymmetricKey(size: .bits256)
            secret = key
            SecretFile.write(key.base64)
        }
        devices.removeAll { $0.id == request.deviceID }
        devices.append(PairedDevice(id: request.deviceID, name: request.deviceName, pairedAt: .now, lastSeen: .now))
        saveDevices()
        cancelPairing()
        let accepted = PairAccepted(secret: key.base64, macID: macID, macName: macName)
        if let data = try? LinkEnvelope.seal(.pairAccepted(accepted), secret: nil) { reply(data) }
        if let state = lastSent, let data = try? LinkEnvelope.seal(.state(state), secret: key) { reply(data) }
    }

    private func saveDevices() {
        if let data = try? JSONEncoder().encode(devices) { UserDefaults.standard.set(data, forKey: Self.devicesKey) }
    }
}

/// The link secret, in Breather's own data folder and readable only by your user account.
///
/// Not in the Keychain on purpose: while Breather is built and signed ad hoc, every rebuild
/// looks like a new app to macOS, which then asks for your login password to read the item.
/// A Developer ID–signed release could use the Keychain without prompts.
enum SecretFile {
    private static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Breather/link.key")
    }

    static func read() -> String? {
        (try? String(contentsOf: url, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func write(_ value: String) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: Data(value.utf8), attributes: [.posixPermissions: 0o600])
    }

    static func delete() {
        try? FileManager.default.removeItem(at: url)
    }
}
