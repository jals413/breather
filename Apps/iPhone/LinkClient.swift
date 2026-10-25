import BreatherKit
import CoreBluetooth
import Foundation
import Network

/// Talks to the Mac over every transport available and hands raw messages to the model.
@MainActor
final class LinkClient {
    enum Route: String { case bluetooth = "Bluetooth", network = "Local network" }

    var onMessage: ((Data) -> Void)?
    var onRoutesChanged: ((Set<Route>) -> Void)?
    private(set) var routes: Set<Route> = [] { didSet { onRoutesChanged?(routes) } }

    private lazy var ble = BLECentral { [weak self] data in self?.onMessage?(data) } onReady: { [weak self] ready in
        guard let self else { return }
        if ready { self.routes.insert(.bluetooth) } else { self.routes.remove(.bluetooth) }
    }
    private lazy var lan = LANClient { [weak self] data in self?.onMessage?(data) } onReady: { [weak self] ready in
        guard let self else { return }
        if ready { self.routes.insert(.network) } else { self.routes.remove(.network) }
    }

    func start() {
        ble.start()
        lan.start()
    }

    /// Local network only works while the app is in front; Bluetooth carries on in the background.
    func setForeground(_ foreground: Bool) {
        foreground ? lan.start() : lan.stop()
    }

    func send(_ data: Data) {
        if routes.contains(.network) { lan.send(data) }
        if routes.contains(.bluetooth) { ble.send(data) }
    }
}

// MARK: - Bluetooth

@MainActor
final class BLECentral: NSObject {
    private let onMessage: (Data) -> Void
    private let onReady: (Bool) -> Void
    private var manager: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var inbox: CBCharacteristic?
    private var receiver = LinkChunker()
    private var sender = LinkChunker()
    private static let knownPeripheralKey = "ble.peripheral"
    private let service = CBUUID(string: LinkConstants.serviceUUID)
    private let outboxID = CBUUID(string: LinkConstants.outboxUUID)
    private let inboxID = CBUUID(string: LinkConstants.inboxUUID)

    init(onMessage: @escaping (Data) -> Void, onReady: @escaping (Bool) -> Void) {
        self.onMessage = onMessage
        self.onReady = onReady
    }

    func start() {
        guard manager == nil else { return }
        // The restore identifier lets iOS relaunch Breather in the background for Bluetooth events.
        manager = CBCentralManager(delegate: self, queue: .main,
                                   options: [CBCentralManagerOptionRestoreIdentifierKey: "breather.central"])
    }

    func send(_ data: Data) {
        guard let peripheral, let inbox else { return }
        let size = peripheral.maximumWriteValueLength(for: .withResponse)
        for chunk in sender.split(data, maxChunk: size) {
            peripheral.writeValue(chunk, for: inbox, type: .withResponse)
        }
    }

    private func connectKnownOrScan() {
        guard let manager, manager.state == .poweredOn else { return }
        if let idString = UserDefaults.standard.string(forKey: Self.knownPeripheralKey), let id = UUID(uuidString: idString),
           let known = manager.retrievePeripherals(withIdentifiers: [id]).first {
            attach(known)
            // A pending connect never times out: iOS completes it whenever the Mac comes into range.
            manager.connect(known)
        } else {
            manager.scanForPeripherals(withServices: [service])
        }
    }

    private func attach(_ p: CBPeripheral) {
        peripheral = p
        p.delegate = self
    }
}

extension BLECentral: CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated { connectKnownOrScan() }
    }

    nonisolated func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        let restored = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral])?.first
        MainActor.assumeIsolated { if let restored { attach(restored) } }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        MainActor.assumeIsolated {
            central.stopScan()
            attach(peripheral)
            UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: Self.knownPeripheralKey)
            central.connect(peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated { peripheral.discoverServices([service]) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            inbox = nil
            onReady(false)
            central.connect(peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            UserDefaults.standard.removeObject(forKey: Self.knownPeripheralKey)
            connectKnownOrScan()
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            for s in peripheral.services ?? [] where s.uuid == service {
                peripheral.discoverCharacteristics([outboxID, inboxID], for: s)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        MainActor.assumeIsolated {
            for c in service.characteristics ?? [] {
                if c.uuid == outboxID { peripheral.setNotifyValue(true, for: c) }
                if c.uuid == inboxID { inbox = c }
            }
            if inbox != nil { onReady(true) }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let value = characteristic.value
        MainActor.assumeIsolated {
            guard let value, let message = receiver.receive(value) else { return }
            onMessage(message)
        }
    }
}

// MARK: - Local network

@MainActor
final class LANClient {
    private let onMessage: (Data) -> Void
    private let onReady: (Bool) -> Void
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var framer = LinkFramer()
    private var latest: [NWBrowser.Result] = []
    private var retry: Task<Void, Never>?

    init(onMessage: @escaping (Data) -> Void, onReady: @escaping (Bool) -> Void) {
        self.onMessage = onMessage
        self.onReady = onReady
    }

    func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: LinkConstants.bonjourType, domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                guard let self else { return }
                self.latest = Array(results)
                if self.connection == nil, let first = results.first { self.connect(to: first.endpoint) }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        retry?.cancel()
        browser?.cancel()
        browser = nil
        connection?.cancel()
        connection = nil
        onReady(false)
    }

    func send(_ data: Data) {
        connection?.send(content: LinkFramer.frame(data), completion: .contentProcessed { _ in })
    }

    private func connect(to endpoint: NWEndpoint) {
        let connection = NWConnection(to: endpoint, using: .tcp)
        framer = LinkFramer()
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready: self.onReady(true)
                case .failed, .cancelled:
                    self.onReady(false)
                    if self.connection === connection {
                        self.connection = nil
                        self.scheduleReconnect()
                    }
                default: break
                }
            }
        }
        connection.start(queue: .main)
        self.connection = connection
        receive(on: connection)
    }

    /// The Mac app restarted or the network blipped: try again shortly, while browsing.
    private func scheduleReconnect() {
        retry?.cancel()
        retry = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled, self.browser != nil, self.connection == nil,
                  let first = self.latest.first else { return }
            self.connect(to: first.endpoint)
        }
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self else { return }
                if let data { self.framer.append(data).forEach(self.onMessage) }
                if complete || error != nil {
                    connection.cancel()
                } else {
                    self.receive(on: connection)
                }
            }
        }
    }
}
