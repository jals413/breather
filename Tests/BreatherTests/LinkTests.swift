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

    func testSignedMessagesVerify() throws {
        let key = SymmetricKey(size: .bits256)
        let sealed = try LinkEnvelope.seal(.command(.breakNow), secret: key)
        XCTAssertEqual(LinkEnvelope.open(sealed, secret: key), .command(.breakNow))
    }

    func testForgedOrUnsignedCommandsAreRejected() throws {
        let key = SymmetricKey(size: .bits256)
        let attacker = SymmetricKey(size: .bits256)
        XCTAssertNil(LinkEnvelope.open(try LinkEnvelope.seal(.command(.breakNow), secret: attacker), secret: key))
        XCTAssertNil(LinkEnvelope.open(try LinkEnvelope.seal(.command(.breakNow), secret: nil), secret: key))
    }

    func testPairingTravelsUnsigned() throws {
        let request = PairRequest(code: "123456", deviceID: "d", deviceName: "iPhone")
        let sealed = try LinkEnvelope.seal(.pairRequest(request), secret: nil)
        XCTAssertEqual(LinkEnvelope.open(sealed, secret: nil), .pairRequest(request))
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
