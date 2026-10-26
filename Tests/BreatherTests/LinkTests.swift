import CryptoKit
import XCTest
@testable import Breather
typealias UpdateCheckerShim = UpdateChecker
@testable import BreatherKit

final class LinkTests: XCTestCase {
    func testChunkingRoundTripsLargeMessages() throws {
        var sender = LinkChunker()
        var receiver = LinkChunker()
        let payload = Data((0..<1000).map { UInt8($0 % 251) })
        let chunks = sender.split(payload, maxChunk: 180)
        XCTAssertGreaterThan(chunks.count, 5)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 180 })
        var result: Data?
        for chunk in chunks.shuffled() { result = receiver.receive(chunk) ?? result }
        XCTAssertEqual(result, payload)
    }

    func testFramerSplitsStream() {
        var framer = LinkFramer()
        let a = Data("hello".utf8), b = Data("breather".utf8)
        var stream = LinkFramer.frame(a) + LinkFramer.frame(b)
        let first = framer.append(stream.prefix(7))
        stream = stream.dropFirst(7)
        let rest = framer.append(stream)
        XCTAssertEqual(first + rest, [a, b])
    }

    // MARK: Encryption and replay

    func testSealedMessagesRoundTripOnlyWithTheRightKeyAndDirection() throws {
        let keys = LinkKeys(SymmetricKey(size: .bits256))
        let data = try LinkCrypto.seal(.command(.breakNow), keys: keys, direction: .phoneToMac, sender: "phone", counter: 7)
        guard case .sealed(let sealed) = LinkPacket.decode(data) else { return XCTFail("not sealed") }
        XCTAssertEqual(LinkCrypto.open(sealed, keys: keys, direction: .phoneToMac), .command(.breakNow))
        // Another phone's key, or the message reflected back the other way, doesn't open.
        XCTAssertNil(LinkCrypto.open(sealed, keys: LinkKeys(SymmetricKey(size: .bits256)), direction: .phoneToMac))
        XCTAssertNil(LinkCrypto.open(sealed, keys: keys, direction: .macToPhone))
        // Changing the counter or sender (to dodge replay checks) breaks authentication.
        var bumped = sealed
        bumped.counter += 1
        XCTAssertNil(LinkCrypto.open(bumped, keys: keys, direction: .phoneToMac))
        var renamed = sealed
        renamed.sender = "other"
        XCTAssertNil(LinkCrypto.open(renamed, keys: keys, direction: .phoneToMac))
    }

    func testMessagesAreNotReadableOnTheWire() throws {
        let keys = LinkKeys(SymmetricKey(size: .bits256))
        let stats = StatsSnapshot(score: 1, rhythmPoints: 0, breakPoints: 0, screenSeconds: 0, taken: 0, skipped: 0, longestSession: 0,
                                  medianSession: 0, currentSession: 0, targetSeconds: 0, week: [], topApps: [],
                                  topSites: [.init(id: "secret-site.example", name: "secret-site.example", seconds: 60)], macName: "Mac")
        let data = try LinkCrypto.seal(.stats(stats), keys: keys, direction: .macToPhone, sender: "mac", counter: 1)
        XCTAssertNil(String(decoding: data, as: UTF8.self).range(of: "secret-site"))
    }

    func testReplayGuardAcceptsEachCounterOnce() throws {
        var guardian = ReplayGuard()
        XCTAssertTrue(guardian.accept(10))
        XCTAssertFalse(guardian.accept(10))
        // Out of order (Bluetooth vs network) is fine, once.
        XCTAssertTrue(guardian.accept(12))
        XCTAssertTrue(guardian.accept(11))
        XCTAssertFalse(guardian.accept(11))
        for n in 100..<(100 + UInt64(ReplayGuard.window)) { XCTAssertTrue(guardian.accept(n)) }
        // Once the window has moved past them, old counters are refused even if never seen.
        XCTAssertFalse(guardian.accept(5))
        XCTAssertFalse(guardian.accept(12))
        // Survives a relaunch.
        var restored = try JSONDecoder().decode(ReplayGuard.self, from: JSONEncoder().encode(guardian))
        XCTAssertFalse(restored.accept(120))
        XCTAssertTrue(restored.accept(1000))
    }

    func testCountersKeepIncreasing() {
        var counter = LinkCounter()
        let now = Date()
        let a = counter.next(now: now), b = counter.next(now: now), c = counter.next(now: now.addingTimeInterval(-60))
        XCTAssertLessThan(a, b)
        XCTAssertLessThan(b, c)
    }

    // MARK: Pairing

    /// Runs the whole handshake; returns the phone's and the Mac's keys.
    private func pair(phoneSecret: (MacPairing) -> String, usesQRKey: Bool = false) -> (SymmetricKey?, SymmetricKey?) {
        var mac = MacPairing()
        var phone = PhonePairing(secret: phoneSecret(mac), usesQRKey: usesQRKey, deviceID: "phone", deviceName: "iPhone")
        guard case .reply(.challenge(let challenge)) = mac.handle(.start(phone.start), macID: "mac", macName: "Mac"),
              let reveal = phone.answer(challenge),
              case .paired(_, let macKey, .accepted(let accepted)) = mac.handle(reveal, macID: "mac", macName: "Mac")
        else { return (nil, nil) }
        return (phone.finish(accepted), macKey)
    }

    func testPairingWithTheCodeAgreesOnAKey() throws {
        let (phoneKey, macKey) = pair(phoneSecret: { $0.code })
        XCTAssertNotNil(phoneKey)
        XCTAssertEqual(phoneKey.map(\.base64), macKey.map(\.base64))
    }

    func testPairingWithTheQRKeyAgreesOnAKey() throws {
        let (phoneKey, macKey) = pair(phoneSecret: { $0.qrKey }, usesQRKey: true)
        XCTAssertNotNil(phoneKey)
        XCTAssertEqual(phoneKey.map(\.base64), macKey.map(\.base64))
    }

    func testTheKeyNeverTravelsInPairingMessages() throws {
        var mac = MacPairing()
        var phone = PhonePairing(secret: mac.code, usesQRKey: false, deviceID: "phone", deviceName: "iPhone")
        guard case .reply(let challenge) = mac.handle(.start(phone.start), macID: "mac", macName: "Mac"),
              case .challenge(let c) = challenge, let reveal = phone.answer(c),
              case .paired(_, let key, let accepted) = mac.handle(reveal, macID: "mac", macName: "Mac") else { return XCTFail() }
        let wire = try [PairMessage.start(phone.start), challenge, reveal, accepted].map { try LinkPacket.pairing($0).encoded() }
        let keyBytes = key.withUnsafeBytes { Data($0) }
        for packet in wire {
            XCTAssertNil(packet.range(of: keyBytes))
            XCTAssertNil(String(decoding: packet, as: UTF8.self).range(of: key.base64))
        }
    }

    func testAFakeMacWithoutTheCodeLearnsNothing() {
        let realMac = MacPairing()
        var fakeMac = MacPairing() // a different code
        var phone = PhonePairing(secret: realMac.code, usesQRKey: false, deviceID: "phone", deviceName: "iPhone")
        guard case .reply(.challenge(let challenge)) = fakeMac.handle(.start(phone.start), macID: "fake", macName: "Fake")
        else { return XCTFail() }
        if realMac.code != fakeMac.code { XCTAssertNil(phone.answer(challenge)) }
    }

    func testAWrongCodeEndsTheAttempt() {
        var mac = MacPairing()
        let wrong = mac.code == "000000" ? "000001" : "000000"
        var phone = PhonePairing(secret: wrong, usesQRKey: false, deviceID: "phone", deviceName: "iPhone")
        guard case .reply(.challenge(let challenge)) = mac.handle(.start(phone.start), macID: "mac", macName: "Mac")
        else { return XCTFail() }
        XCTAssertNil(phone.answer(challenge))
        guard case .failed = mac.handle(.cancel(deviceID: "phone"), macID: "mac", macName: "Mac") else { return XCTFail() }
    }

    func testAnAttackerGetsOneGuessPerCode() {
        var mac = MacPairing()
        // An attacker guesses, gets the Mac's proof (and could crack the code offline from it)…
        let attacker = PhonePairing(secret: "123456", usesQRKey: false, deviceID: "attacker", deviceName: "x")
        guard case .reply(.challenge) = mac.handle(.start(attacker.start), macID: "mac", macName: "Mac") else { return XCTFail() }
        // …but can't start over with the cracked code: the code is spent on its committed guess.
        let retry = PhonePairing(secret: mac.code, usesQRKey: false, deviceID: "attacker", deviceName: "x")
        guard case .reply(.rejected) = mac.handle(.start(retry.start), macID: "mac", macName: "Mac") else { return XCTFail() }
        // Opening its commitment with any nonce fails unless the first guess was right.
        if mac.code != "123456" {
            guard case .failed = mac.handle(.reveal(deviceID: "attacker", nonce: Data(count: 32)), macID: "mac", macName: "Mac")
            else { return XCTFail() }
        }
    }

    func testRetriedStartGetsTheSameChallenge() {
        var mac = MacPairing()
        let phone = PhonePairing(secret: mac.code, usesQRKey: false, deviceID: "phone", deviceName: "iPhone")
        guard case .reply(let first) = mac.handle(.start(phone.start), macID: "mac", macName: "Mac"),
              case .reply(let second) = mac.handle(.start(phone.start), macID: "mac", macName: "Mac") else { return XCTFail() }
        XCTAssertEqual(first, second)
    }

    func testExpiredCodeIsRefused() {
        let start = Date()
        var mac = MacPairing(lifetime: 120, now: start)
        let phone = PhonePairing(secret: mac.code, usesQRKey: false, deviceID: "phone", deviceName: "iPhone")
        guard case .failed = mac.handle(.start(phone.start), macID: "mac", macName: "Mac", now: start.addingTimeInterval(121))
        else { return XCTFail() }
    }

    // MARK: Limits on links and commands

    @MainActor
    func testLengthsFromLinksAreClamped() {
        XCTAssertEqual(AppModel.clamp(1_000_000, to: AppModel.breakMinutes), 60)
        XCTAssertEqual(AppModel.clamp(-5, to: AppModel.breakMinutes), 1)
        XCTAssertEqual(AppModel.clamp(10, to: AppModel.breakMinutes), 10)
        XCTAssertNil(AppModel.clamp(.nan, to: AppModel.breakMinutes))
        XCTAssertNil(AppModel.clamp(.infinity, to: AppModel.pauseMinutes))
        XCTAssertNil(AppModel.clamp(nil, to: AppModel.snoozeMinutes))
        XCTAssertEqual(AppModel.clamp(1e9, to: AppModel.pauseMinutes), 24 * 60)
    }

    func testStateChangeDetectionIgnoresDrift() {
        var a = MacState.preview
        var b = a
        b.nextBreakAt = a.nextBreakAt?.addingTimeInterval(2)
        XCTAssertFalse(b.differsMeaningfully(from: a))
        a.mode = .onBreak
        XCTAssertTrue(b.differsMeaningfully(from: a))
    }
}

final class UpdateVersionTests: XCTestCase {
    func testNumericComparison() {
        XCTAssertTrue(UpdateCheckerShim.isNewer("0.10.0", than: "0.9.3"))
        XCTAssertTrue(UpdateCheckerShim.isNewer("1.0", than: "0.9.9"))
        XCTAssertFalse(UpdateCheckerShim.isNewer("0.9.0", than: "0.9.0"))
        XCTAssertFalse(UpdateCheckerShim.isNewer("0.9", than: "0.9.0"))
        XCTAssertFalse(UpdateCheckerShim.isNewer("0.8.9", than: "0.9.0"))
    }
}

final class UpdateChecksumTests: XCTestCase {
    func testFindsChecksumInShasumOutput() {
        let text = """
        0d12b261768ff20eb62fcecde37ca85bdfa4d2cb8e78f8f5d6870d699509beb8  Breather-0.9.1.zip
        aaaa  Breather-0.9.1.dmg
        bbbb *Breather.zip
        """
        XCTAssertEqual(UpdateCheckerShim.checksum(for: "Breather-0.9.1.zip", in: text),
                       "0d12b261768ff20eb62fcecde37ca85bdfa4d2cb8e78f8f5d6870d699509beb8")
        XCTAssertEqual(UpdateCheckerShim.checksum(for: "Breather.zip", in: text), "bbbb")
        XCTAssertNil(UpdateCheckerShim.checksum(for: "Breather-0.9.2.zip", in: text))
    }
}
