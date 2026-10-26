import CryptoKit
import Foundation

// MARK: - Wire format

/// Everything on the link is one of these. Pairing messages carry only public keys and proofs;
/// everything else is encrypted with a key only the Mac and that one phone hold.
public enum LinkPacket: Codable, Equatable, Sendable {
    case pairing(PairMessage)
    case sealed(SealedMessage)

    public func encoded() throws -> Data { try LinkCoding.encoder.encode(self) }

    public static func decode(_ data: Data) -> LinkPacket? { try? LinkCoding.decoder.decode(LinkPacket.self, from: data) }
}

/// An encrypted `LinkMessage`. `sender` is the phone's device ID or the Mac's ID; `counter` only
/// ever goes up, so a captured message can't be played back later.
public struct SealedMessage: Codable, Equatable, Sendable {
    public var sender: String
    public var counter: UInt64
    /// ChaCha20-Poly1305 combined box (nonce, ciphertext, tag).
    public var box: Data
}

public enum LinkDirection: String, Sendable {
    case macToPhone
    case phoneToMac
}

/// The two one-way keys derived from a device's pairing key, so a message can't be reflected back.
public struct LinkKeys: Sendable {
    public let macToPhone: SymmetricKey
    public let phoneToMac: SymmetricKey

    public init(_ deviceKey: SymmetricKey) {
        macToPhone = HKDF<SHA256>.deriveKey(inputKeyMaterial: deviceKey, info: Data("breather link v2 mac to phone".utf8), outputByteCount: 32)
        phoneToMac = HKDF<SHA256>.deriveKey(inputKeyMaterial: deviceKey, info: Data("breather link v2 phone to mac".utf8), outputByteCount: 32)
    }

    func key(_ direction: LinkDirection) -> SymmetricKey { direction == .macToPhone ? macToPhone : phoneToMac }
}

public enum LinkCrypto {
    public static func seal(_ message: LinkMessage, keys: LinkKeys, direction: LinkDirection, sender: String, counter: UInt64) throws -> Data {
        let body = try LinkCoding.encoder.encode(message)
        let box = try ChaChaPoly.seal(body, using: keys.key(direction), authenticating: header(direction, sender, counter))
        return try LinkPacket.sealed(SealedMessage(sender: sender, counter: counter, box: box.combined)).encoded()
    }

    /// The message, if it decrypts. Check the counter with a `ReplayGuard` before acting on it.
    public static func open(_ sealed: SealedMessage, keys: LinkKeys, direction: LinkDirection) -> LinkMessage? {
        guard let box = try? ChaChaPoly.SealedBox(combined: sealed.box),
              let body = try? ChaChaPoly.open(box, using: keys.key(direction), authenticating: header(direction, sealed.sender, sealed.counter))
        else { return nil }
        return try? LinkCoding.decoder.decode(LinkMessage.self, from: body)
    }

    /// Authenticated alongside the ciphertext, so sender and counter can't be swapped.
    private static func header(_ direction: LinkDirection, _ sender: String, _ counter: UInt64) -> Data {
        Data("breather/\(LinkConstants.protocolVersion)/\(direction.rawValue)/\(sender)/\(counter)".utf8)
    }
}

/// Hands out increasing message counters. Based on the clock, so they keep increasing across relaunches
/// without being saved.
public struct LinkCounter: Sendable {
    private var last: UInt64 = 0
    public init() {}

    public mutating func next(now: Date = .now) -> UInt64 {
        last = max(last + 1, UInt64(max(0, now.timeIntervalSince1970) * 1000))
        return last
    }
}

/// Accepts each counter once. A small window tolerates the same sender's messages arriving out of
/// order over Bluetooth and the local network; anything older, or already seen, is refused.
public struct ReplayGuard: Codable, Equatable, Sendable {
    public static let window = 64
    /// Everything at or below this is refused.
    private var floor: UInt64 = 0
    /// Accepted counters above `floor`, ascending.
    private var recent: [UInt64] = []

    public init() {}

    public mutating func accept(_ counter: UInt64) -> Bool {
        guard counter > floor, !recent.contains(counter) else { return false }
        recent.insert(counter, at: recent.firstIndex { $0 > counter } ?? recent.endIndex)
        if recent.count > Self.window { floor = recent.removeFirst() }
        return true
    }
}

// MARK: - Pairing

/// Pairing: an X25519 key exchange, tied to the code on the Mac with a commit-then-reveal so neither
/// a fake phone nor a fake Mac can test guesses of the code. The key itself never crosses the air.
///
///  1. Phone → Mac `start`: its public key and a commitment to (code, a random nonce).
///  2. Mac → phone `challenge`: the Mac's public key and proof that it knows the code.
///     The phone stops here if the proof is wrong, without revealing anything.
///  3. Phone → Mac `reveal`: the nonce, opening the commitment. The Mac stops if it doesn't match.
///  4. Mac → phone `accepted`: both now hold the same device key; a confirmation proves it.
///
/// The Mac runs one attempt per code, so anyone racing to guess it gets a single try (one in a
/// million), and a failed attempt ends pairing until you start again. The QR code also carries a
/// 128-bit key, which the phone uses instead of the 6 digits when you scan it.
public enum PairMessage: Codable, Equatable, Sendable {
    case start(PairStart)
    case challenge(PairChallenge)
    case reveal(deviceID: String, nonce: Data)
    /// Phone → Mac: the Mac's proof was wrong (usually a mistyped code), so this attempt is over.
    case cancel(deviceID: String)
    case accepted(PairAccepted)
    case rejected(reason: String)
}

public struct PairStart: Codable, Equatable, Sendable {
    public var deviceID: String
    public var deviceName: String
    public var phoneKey: Data
    public var commitment: Data
    /// Proving the QR code's long key rather than the typed 6-digit code.
    public var usesQRKey: Bool
}

public struct PairChallenge: Codable, Equatable, Sendable {
    public var deviceID: String
    public var macKey: Data
    public var proof: Data
}

public struct PairAccepted: Codable, Equatable, Sendable {
    public var macID: String
    public var macName: String
    /// HMAC of the Mac's ID with the new device key.
    public var confirmation: Data
}

enum PairingCrypto {
    static func codeKey(_ secret: String) -> SymmetricKey {
        SymmetricKey(data: SHA256.hash(data: Data("breather pairing v2 \(secret)".utf8)))
    }

    static func commitment(secret: String, phoneKey: Data, nonce: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Data("phone".utf8) + phoneKey + nonce, using: codeKey(secret)))
    }

    static func proof(secret: String, phoneKey: Data, macKey: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Data("mac".utf8) + phoneKey + macKey, using: codeKey(secret)))
    }

    static func deviceKey(_ privateKey: Curve25519.KeyAgreement.PrivateKey, peer: Data, secret: String,
                          phoneKey: Data, macKey: Data) throws -> SymmetricKey {
        let shared = try privateKey.sharedSecretFromKeyAgreement(with: Curve25519.KeyAgreement.PublicKey(rawRepresentation: peer))
        return shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data(SHA256.hash(data: Data(secret.utf8))),
                                              sharedInfo: Data("breather link v2".utf8) + phoneKey + macKey, outputByteCount: 32)
    }

    static func confirmation(_ key: SymmetricKey, macID: String) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Data("accepted \(macID)".utf8), using: key))
    }

    static func randomBytes(_ count: Int) -> Data {
        SymmetricKey(size: SymmetricKeySize(bitCount: count * 8)).withUnsafeBytes { Data($0) }
    }
}

/// The phone's side of one pairing attempt.
public struct PhonePairing: Sendable {
    public let start: PairStart
    private let secret: String
    private let privateKey: Curve25519.KeyAgreement.PrivateKey
    private let nonce: Data
    private var deviceKey: SymmetricKey?
    /// Set once the Mac has proved it knows the code.
    public private(set) var macKey: Data?

    /// `secret` is the typed 6-digit code, or the QR code's key when `usesQRKey`.
    public init(secret: String, usesQRKey: Bool, deviceID: String, deviceName: String) {
        self.secret = secret
        privateKey = Curve25519.KeyAgreement.PrivateKey()
        nonce = PairingCrypto.randomBytes(32)
        let phoneKey = privateKey.publicKey.rawRepresentation
        start = PairStart(deviceID: deviceID, deviceName: deviceName, phoneKey: phoneKey,
                          commitment: PairingCrypto.commitment(secret: secret, phoneKey: phoneKey, nonce: nonce),
                          usesQRKey: usesQRKey)
    }

    /// The reveal to send back, or nil when the challenge doesn't prove knowledge of the code.
    public mutating func answer(_ challenge: PairChallenge) -> PairMessage? {
        guard macKey == nil, challenge.deviceID == start.deviceID,
              HMAC<SHA256>.isValidAuthenticationCode(challenge.proof, authenticating: Data("mac".utf8) + start.phoneKey + challenge.macKey,
                                                     using: PairingCrypto.codeKey(secret)),
              let key = try? PairingCrypto.deviceKey(privateKey, peer: challenge.macKey, secret: secret,
                                                     phoneKey: start.phoneKey, macKey: challenge.macKey)
        else { return nil }
        macKey = challenge.macKey
        deviceKey = key
        return .reveal(deviceID: start.deviceID, nonce: nonce)
    }

    /// The device key, once the Mac confirms it derived the same one.
    public func finish(_ accepted: PairAccepted) -> SymmetricKey? {
        guard let deviceKey,
              HMAC<SHA256>.isValidAuthenticationCode(accepted.confirmation, authenticating: Data("accepted \(accepted.macID)".utf8),
                                                     using: deviceKey)
        else { return nil }
        return deviceKey
    }
}

/// The Mac's side: one code, one attempt.
public struct MacPairing: Sendable {
    public enum Outcome: Sendable {
        case reply(PairMessage)
        /// The attempt is over; tell the phone `reason`.
        case failed(reason: String)
        case paired(PairStart, key: SymmetricKey, reply: PairMessage)
        case ignore
    }

    /// Six digits to type on the phone.
    public let code: String
    /// The QR code's stronger alternative to `code`.
    public let qrKey: String
    public let expires: Date
    /// The phone this attempt belongs to, once one has started.
    public private(set) var started: PairStart?
    private var privateKey: Curve25519.KeyAgreement.PrivateKey?
    private var challenge: PairChallenge?

    public init(lifetime: TimeInterval = 120, now: Date = .now) {
        code = String(format: "%06d", Int.random(in: 0...999_999))
        qrKey = PairingCrypto.randomBytes(16).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        expires = now.addingTimeInterval(lifetime)
    }

    public mutating func handle(_ message: PairMessage, macID: String, macName: String, now: Date = .now) -> Outcome {
        guard now < expires else { return .failed(reason: "The code expired. Start pairing again on your Mac.") }
        switch message {
        case .start(let start):
            if let started, let challenge {
                // The phone retries, and sends over Bluetooth and the network at once: same attempt, same answer.
                return started == start ? .reply(.challenge(challenge)) : .reply(.rejected(reason: "Your Mac is already pairing with another device. Cancel and try again."))
            }
            let privateKey = Curve25519.KeyAgreement.PrivateKey()
            let macKey = privateKey.publicKey.rawRepresentation
            let challenge = PairChallenge(deviceID: start.deviceID, macKey: macKey,
                                          proof: PairingCrypto.proof(secret: secret(for: start), phoneKey: start.phoneKey, macKey: macKey))
            self.started = start
            self.privateKey = privateKey
            self.challenge = challenge
            return .reply(.challenge(challenge))

        case .reveal(let deviceID, let nonce):
            guard let started, let privateKey, let challenge, started.deviceID == deviceID else { return .ignore }
            let secret = secret(for: started)
            guard HMAC<SHA256>.isValidAuthenticationCode(started.commitment, authenticating: Data("phone".utf8) + started.phoneKey + nonce,
                                                         using: PairingCrypto.codeKey(secret)),
                  let key = try? PairingCrypto.deviceKey(privateKey, peer: started.phoneKey, secret: secret,
                                                         phoneKey: started.phoneKey, macKey: challenge.macKey)
            else { return .failed(reason: "That code doesn't match. Start pairing again on your Mac.") }
            let accepted = PairAccepted(macID: macID, macName: macName, confirmation: PairingCrypto.confirmation(key, macID: macID))
            return .paired(started, key: key, reply: .accepted(accepted))

        case .cancel(let deviceID):
            guard started?.deviceID == deviceID else { return .ignore }
            return .failed(reason: "That code doesn't match. Start pairing again on your Mac.")

        case .challenge, .accepted, .rejected:
            return .ignore
        }
    }

    private func secret(for start: PairStart) -> String { start.usesQRKey ? qrKey : code }
}
