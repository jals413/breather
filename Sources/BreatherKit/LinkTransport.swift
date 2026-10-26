import Foundation

/// Identifiers shared by the Mac and the phone.
public enum LinkConstants {
    /// Bonjour service for the local-network link (also how the iOS Simulator talks to the Mac).
    public static let bonjourType = "_breather._tcp"
    /// Bluetooth LE service and characteristics.
    public static let serviceUUID = "6B1E4A10-2C77-4E0B-9F3A-9B7C2B0E1A01"
    /// Mac → phone: notify + read.
    public static let outboxUUID = "6B1E4A10-2C77-4E0B-9F3A-9B7C2B0E1A02"
    /// Phone → Mac: write.
    public static let inboxUUID = "6B1E4A10-2C77-4E0B-9F3A-9B7C2B0E1A03"
    public static let pairingCodeLength = 6
    /// Bumped whenever the wire format changes; part of every encrypted message's header.
    public static let protocolVersion = 2
    public static let maxPairedDevices = 3
}

/// Splits messages into Bluetooth-sized chunks and reassembles them.
/// Chunk layout: [message id (1 byte)][index (1 byte)][count (1 byte)][payload…]
public struct LinkChunker: Sendable {
    public static let headerSize = 3
    private var nextID: UInt8 = 0
    private var partial: [UInt8: [Int: Data]] = [:]
    private var expected: [UInt8: Int] = [:]

    public init() {}

    public mutating func split(_ data: Data, maxChunk: Int) -> [Data] {
        let payloadSize = max(1, maxChunk - Self.headerSize)
        let count = max(1, Int((Double(data.count) / Double(payloadSize)).rounded(.up)))
        precondition(count < 256, "message too large for the link")
        nextID &+= 1
        return (0..<count).map { i in
            let start = data.startIndex + i * payloadSize
            let end = min(start + payloadSize, data.endIndex)
            var chunk = Data([nextID, UInt8(i), UInt8(count)])
            chunk.append(data[start..<end])
            return chunk
        }
    }

    /// Feed one chunk; returns the full message once every chunk has arrived.
    public mutating func receive(_ chunk: Data) -> Data? {
        guard chunk.count >= Self.headerSize else { return nil }
        let bytes = [UInt8](chunk.prefix(Self.headerSize))
        let (id, index, count) = (bytes[0], Int(bytes[1]), Int(bytes[2]))
        guard count > 0, index < count else { return nil }
        var parts = partial[id] ?? [:]
        parts[index] = chunk.dropFirst(Self.headerSize)
        if parts.count == count {
            partial[id] = nil
            expected[id] = nil
            return (0..<count).reduce(into: Data()) { $0.append(parts[$1] ?? Data()) }
        }
        partial[id] = parts
        expected[id] = count
        // Keep memory bounded if a sender vanished mid-message.
        if partial.count > 8, let oldest = partial.keys.first { partial[oldest] = nil }
        return nil
    }
}

/// Length-prefixed framing for stream transports (TCP).
public struct LinkFramer: Sendable {
    private var buffer = Data()
    public init() {}

    public static func frame(_ data: Data) -> Data {
        var length = UInt32(data.count).bigEndian
        var out = Data(bytes: &length, count: 4)
        out.append(data)
        return out
    }

    public mutating func append(_ data: Data) -> [Data] {
        buffer.append(data)
        var messages: [Data] = []
        while buffer.count >= 4 {
            let length = buffer.prefix(4).reduce(0) { ($0 << 8) | UInt32($1) }
            guard buffer.count >= 4 + Int(length) else { break }
            messages.append(buffer.dropFirst(4).prefix(Int(length)))
            buffer = Data(buffer.dropFirst(4 + Int(length)))
        }
        return messages
    }
}

/// Paid-account features. Compiled in only when building with `BREATHER_PAID`
/// (an Xcode "Paid" configuration, or `BREATHER_PAID=1 scripts/build.sh` on the Mac).
public enum FeatureFlags {
    public static var paidAccount: Bool {
        #if BREATHER_PAID
        true
        #else
        false
        #endif
    }

    public static let paidExplanation = "Needs an Apple Developer Program membership. It's built in and switches on with the Paid build configuration."
}
