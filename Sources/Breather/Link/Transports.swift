import BreatherKit
import CoreBluetooth
import Foundation
import Network

/// Local network link: a Bonjour-advertised TCP server. Phones (and the iOS Simulator)
/// on the same network connect while the Breather app is open.
@MainActor
final class LANServer {
    typealias Handler = (Data, @escaping (Data) -> Void) -> Void
    private let macName: String
    private let handler: Handler
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: (NWConnection, LinkFramer)] = [:]
    var onConnectionsChanged: ((Int) -> Void)?

    init(macName: String, handler: @escaping Handler) {
        self.macName = macName
        self.handler = handler
    }

    func start() {
        guard let listener = try? NWListener(using: .tcp) else { return }
        listener.service = NWListener.Service(name: macName, type: LinkConstants.bonjourType)
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connections.values.forEach { $0.0.cancel() }
        connections.removeAll()
        onConnectionsChanged?(0)
    }

    func broadcast(_ data: Data) {
        let framed = LinkFramer.frame(data)
        for (connection, _) in connections.values {
            connection.send(content: framed, completion: .contentProcessed { _ in })
        }
    }

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections[id] = (connection, LinkFramer())
        onConnectionsChanged?(connections.count)
        connection.stateUpdateHandler = { [weak self] state in
            if case .failed = state { Task { @MainActor in self?.drop(id) } }
            if case .cancelled = state { Task { @MainActor in self?.drop(id) } }
        }
        connection.start(queue: .main)
        receive(on: connection)
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return }
                let id = ObjectIdentifier(connection)
                if let data, var entry = self.connections[id] {
                    let messages = entry.1.append(data)
                    self.connections[id] = entry
                    for message in messages {
                        self.handler(message) { reply in
                            connection.send(content: LinkFramer.frame(reply), completion: .contentProcessed { _ in })
                        }
                    }
                }
                if isComplete || error != nil {
                    connection.cancel()
                    self.drop(id)
                } else {
                    self.receive(on: connection)
                }
            }
        }
    }

    private func drop(_ id: ObjectIdentifier) {
        guard connections.removeValue(forKey: id) != nil else { return }
        onConnectionsChanged?(connections.count)
    }
}

/// Bluetooth LE link: the Mac is a peripheral; the phone subscribes and iOS wakes the
/// Breather app in the background whenever the Mac sends something.
@MainActor
final class BLEPeripheral: NSObject {
    typealias Handler = (Data, @escaping (Data) -> Void) -> Void
    private let handler: Handler
    private var manager: CBPeripheralManager?
    private var outbox: CBMutableCharacteristic?
    private var subscribers: [CBCentral] = []
    private var sendChunker = LinkChunker()
    private var receiveChunkers: [UUID: LinkChunker] = [:]
    private var pending: [Data] = []
    var onStatus: ((String) -> Void)?
    var onSubscribersChanged: ((Int) -> Void)?

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func start() {
        manager = CBPeripheralManager(delegate: self, queue: .main)
    }

    func stop() {
        manager?.stopAdvertising()
        manager?.removeAllServices()
        manager = nil
        subscribers.removeAll()
    }

    func broadcast(_ data: Data) {
        guard let outbox, !subscribers.isEmpty else { return }
        let size = subscribers.map(\.maximumUpdateValueLength).min() ?? 20
        for chunk in sendChunker.split(data, maxChunk: size) where !(manager?.updateValue(chunk, for: outbox, onSubscribedCentrals: nil) ?? false) {
            pending.append(chunk) // queue full; resend when ready
        }
    }

    private func setUpService() {
        let outbox = CBMutableCharacteristic(type: CBUUID(string: LinkConstants.outboxUUID), properties: [.notify, .read],
                                             value: nil, permissions: [.readable])
        let inbox = CBMutableCharacteristic(type: CBUUID(string: LinkConstants.inboxUUID), properties: [.write, .writeWithoutResponse],
                                            value: nil, permissions: [.writeable])
        let service = CBMutableService(type: CBUUID(string: LinkConstants.serviceUUID), primary: true)
        service.characteristics = [outbox, inbox]
        manager?.add(service)
        self.outbox = outbox
        manager?.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [service.uuid], CBAdvertisementDataLocalNameKey: "Breather"])
    }

    private func reply(to central: CBCentral) -> (Data) -> Void {
        { [weak self] data in
            guard let self, let outbox = self.outbox else { return }
            for chunk in self.sendChunker.split(data, maxChunk: central.maximumUpdateValueLength) {
                if !(self.manager?.updateValue(chunk, for: outbox, onSubscribedCentrals: [central]) ?? false) { self.pending.append(chunk) }
            }
        }
    }
}

extension BLEPeripheral: CBPeripheralManagerDelegate {
    nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        let state = peripheral.state
        MainActor.assumeIsolated {
            switch state {
            case .poweredOn: onStatus?("On"); setUpService()
            case .poweredOff: onStatus?("Bluetooth is off")
            case .unauthorized: onStatus?("Not allowed in System Settings → Privacy → Bluetooth")
            case .unsupported: onStatus?("Unsupported")
            default: onStatus?("Starting…")
            }
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        MainActor.assumeIsolated {
            if !subscribers.contains(where: { $0.identifier == central.identifier }) { subscribers.append(central) }
            onSubscribersChanged?(subscribers.count)
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        MainActor.assumeIsolated {
            subscribers.removeAll { $0.identifier == central.identifier }
            onSubscribersChanged?(subscribers.count)
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        let writes = requests.compactMap { r in r.value.map { (r.central, $0) } }
        if let first = requests.first { peripheral.respond(to: first, withResult: .success) }
        MainActor.assumeIsolated {
            for (central, value) in writes {
                var chunker = receiveChunkers[central.identifier] ?? LinkChunker()
                let message = chunker.receive(value)
                receiveChunkers[central.identifier] = chunker
                if let message { handler(message, reply(to: central)) }
            }
        }
    }

    nonisolated func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        MainActor.assumeIsolated {
            guard let outbox else { return }
            while let chunk = pending.first, manager?.updateValue(chunk, for: outbox, onSubscribedCentrals: nil) == true {
                pending.removeFirst()
            }
        }
    }
}
