import XCTest
@testable import Breather
@testable import BreatherKit

/// The paid push path is compiled out of free builds, but its payloads are pure and testable.
@MainActor
final class PushPayloadTests: XCTestCase {
    private let state = MacState(mode: .onBreak, detail: "Short break", breakStart: Date(timeIntervalSinceReferenceDate: 1000),
                                 breakEnd: Date(timeIntervalSinceReferenceDate: 1020), breakTitle: "Short break",
                                 breakMessage: "Look far away.", macName: "MacBook Pro", blockPhone: true)

    func testLiveActivityStartPayload() throws {
        let aps = try XCTUnwrap(APNsClient.liveActivityStart(state)["aps"] as? [String: Any])
        XCTAssertEqual(aps["event"] as? String, "start")
        XCTAssertEqual(aps["attributes-type"] as? String, "BreatherActivityAttributes")
        XCTAssertEqual((aps["attributes"] as? [String: String])?["macName"], "MacBook Pro")
        let content = try XCTUnwrap(aps["content-state"] as? [String: Any])
        // ActivityKit decodes dates as seconds since the 2001 reference date.
        XCTAssertEqual(content["target"] as? Double, 1020)
        XCTAssertEqual(content["mode"] as? String, "onBreak")
    }

    func testContentStateMatchesActivityKitShape() throws {
        // The keys must match BreatherActivityAttributes.ContentState's Codable keys exactly.
        let keys = Set(APNsClient.contentState(state).keys)
        XCTAssertEqual(keys, ["mode", "title", "subtitle", "target", "from"])
    }

    func testAlertCarriesBlockInstruction() throws {
        let start = APNsClient.alert(state, started: true)
        let info = try XCTUnwrap(start["breather"] as? [String: Any])
        XCTAssertEqual(info["action"] as? String, "block")
        XCTAssertEqual(info["block"] as? Bool, true)
        XCTAssertEqual((start["aps"] as? [String: Any])?["mutable-content"] as? Int, 1)

        let end = APNsClient.alert(state, started: false)
        XCTAssertEqual((end["breather"] as? [String: Any])?["action"] as? String, "unblock")
    }
}
