import BreatherKit
import CoreBluetooth
import Foundation
import Network

/// Who sent a message: answer them directly, or mark the connection as a paired phone's once one of
/// its messages decrypts. Only marked connections receive the Mac's state.
struct LinkPeer {
    let reply: (Data) -> Void
    let authenticate: (String) -> Void
}

/// Local network link: a Bonjour-advertised TCP server. Phones (and the iOS Simulator)
/// on the same network connect while the Breather app is open.
@MainActor
final class LANServer {
    typealias Handler = (Data, LinkPeer) -> Void
    private struct Client {
        let connection: NWConnection
        var framer = LinkFramer()
        /// The paired phone this connection proved to be.
        var deviceID: String?
    }
    private let macName: String
    private let handler: Handler
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: Client] = [:]
    /// Number of connections from paired phones.
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
        connections.values.forEach { $0.connection.cancel() }
        connections.removeAll()
        onConnectionsChanged?(0)
    }

    /// Sends to every connection that proved to be this phone.
    func send(_ data: Data, to deviceID: String) {
        let framed = LinkFramer.frame(data)
        for client in connections.values where client.deviceID == deviceID {
            client.connection.send(content: framed, completion: .contentProcessed { _ in })
        }
    }

    /// Drops a forgotten phone's connections.
    func disconnect(_ deviceID: String) {
        for client in connections.values where client.deviceID == deviceID { client.connection.cancel() }
    }

    private var authenticatedCount: Int { connections.values.filter { $0.deviceID != nil }.count }

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections[id] = Client(connection: connection)
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
                if let data, var client = self.connections[id] {
                    let messages = client.framer.append(data)
                    self.connections[id] = client
                    let peer = LinkPeer(reply: { reply in
                        connection.send(content: LinkFramer.frame(reply), completion: .contentProcessed { _ in })
                    }, authenticate: { [weak self] deviceID in
                        guard let self, self.connections[id]?.deviceID != deviceID else { return }
                        self.connections[id]?.deviceID = deviceID
                        self.onConnectionsChanged?(self.authenticatedCount)
                    })
                    for message in messages { self.handler(message, peer) }
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
        onConnectionsChanged?(authenticatedCount)
    }
}

/// Bluetooth LE link: the Mac is a peripheral; the phone subscribes and iOS wakes the
/// Breather app in the background whenever the Mac sends something.
@MainActor
final class BLEPeripheral: NSObject {
    typealias Handler = (Data, LinkPeer) -> Void
    private let handler: Handler
    private var manager: CBPeripheralManager?
    private var outbox: CBMutableCharacteristic?
    private var subscribers: [CBCentral] = []
    /// Centrals that proved to be a paired phone, by central identifier.
    private var authenticated: [UUID: String] = [:]
    private var sendChunker = LinkChunker()
    private var receiveChunkers: [UUID: LinkChunker] = [:]
    private var pending: [(chunk: Data, to: [CBCentral])] = []
    var onStatus: ((String) -> Void)?
    /// Number of subscribed paired phones.
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
        authenticated.removeAll()
        pending.removeAll()
    }

    /// Sends to the subscribed centrals that proved to be this phone.
    func send(_ data: Data, to deviceID: String) {
        let centrals = subscribers.filter { authenticated[$0.identifier] == deviceID }
        guard let outbox, !centrals.isEmpty else { return }
        let size = centrals.map(\.maximumUpdateValueLength).min() ?? 20
        for chunk in sendChunker.split(data, maxChunk: size)
        where !(manager?.updateValue(chunk, for: outbox, onSubscribedCentrals: centrals) ?? false) {
            pending.append((chunk, centrals)) // queue full; resend when ready
        }
    }

    /// Stops sending to a forgotten phone.
    func disconnect(_ deviceID: String) {
        authenticated = authenticated.filter { $0.value != deviceID }
        reportSubscribers()
    }

    private func reportSubscribers() {
        onSubscribersChanged?(subscribers.filter { authenticated[$0.identifier] != nil }.count)
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
                if !(self.manager?.updateValue(chunk, for: outbox, onSubscribedCentrals: [central]) ?? false) { self.pending.append((chunk, [central])) }
            }
        }
    }

    private func peer(_ central: CBCentral) -> LinkPeer {
        LinkPeer(reply: reply(to: central), authenticate: { [weak self] deviceID in
            guard let self, self.authenticated[central.identifier] != deviceID else { return }
            self.authenticated[central.identifier] = deviceID
            self.reportSubscribers()
        })
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
            reportSubscribers()
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        MainActor.assumeIsolated {
            subscribers.removeAll { $0.identifier == central.identifier }
            authenticated[central.identifier] = nil
            reportSubscribers()
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
                if let message { handler(message, peer(central)) }
            }
        }
    }

    nonisolated func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        MainActor.assumeIsolated {
            guard let outbox else { return }
            while let next = pending.first, manager?.updateValue(next.chunk, for: outbox, onSubscribedCentrals: next.to) == true {
                pending.removeFirst()
            }
        }
    }
}
