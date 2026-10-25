import BreatherKit
import CryptoKit
import Foundation

/// Sends Apple pushes straight from the Mac to paired phones (paid builds only).
///
/// - Break starts: push-to-start the Live Activity (shows even when the phone is asleep or in
///   Low Power Mode) and an alert the phone's Notification Service Extension uses to block apps.
/// - Break ends: an alert the extension uses to lift the block.
///
/// Personal use signs requests with your own APNs key (.p8). A distributed build must move this
/// to a server, since the key can't ship inside the app.
@MainActor
final class APNsClient {
    struct Config: Equatable {
        var teamID: String
        var keyID: String
        var keyPath: String
        var isComplete: Bool { !teamID.isEmpty && !keyID.isEmpty && FileManager.default.fileExists(atPath: keyPath) }
    }

    var config = Config(teamID: "", keyID: "", keyPath: "")
    private(set) var lastResult: String?

    func deliver(_ state: MacState, previous: MacState?, to devices: [PairedDevice]) {
        #if BREATHER_PAID
        guard config.isComplete else { return }
        let started = state.mode == .onBreak && previous?.mode != .onBreak
        let ended = state.mode != .onBreak && previous?.mode == .onBreak
        guard started || ended else { return }
        for device in devices {
            guard let tokens = device.tokens else { continue }
            if started, let token = tokens.liveActivityStartToken {
                send(Self.liveActivityStart(state), token: token, topic: tokens.bundleID + ".push-type.liveactivity",
                     pushType: "liveactivity", sandbox: tokens.sandbox)
            }
            if let token = tokens.deviceToken {
                send(Self.alert(state, started: started), token: token, topic: tokens.bundleID, pushType: "alert", sandbox: tokens.sandbox)
            }
        }
        #endif
    }

    #if BREATHER_PAID
    private var cachedJWT: (token: String, issued: Date)?

    private func send(_ payload: [String: Any], token: String, topic: String, pushType: String, sandbox: Bool) {
        guard let jwt = jwt(), let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        let host = sandbox ? "api.sandbox.push.apple.com" : "api.push.apple.com"
        var request = URLRequest(url: URL(string: "https://\(host)/3/device/\(token)")!)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("bearer \(jwt)", forHTTPHeaderField: "authorization")
        request.setValue(topic, forHTTPHeaderField: "apns-topic")
        request.setValue(pushType, forHTTPHeaderField: "apns-push-type")
        request.setValue("10", forHTTPHeaderField: "apns-priority")
        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let detail = error?.localizedDescription ?? data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            Task { @MainActor [weak self] in self?.lastResult = "\(pushType): \(status) \(detail)" }
        }.resume()
    }

    /// ES256 provider token, reused for 50 minutes (Apple allows up to 60).
    private func jwt() -> String? {
        if let cached = cachedJWT, Date.now.timeIntervalSince(cached.issued) < 50 * 60 { return cached.token }
        guard let pem = try? String(contentsOfFile: config.keyPath, encoding: .utf8),
              let key = try? P256.Signing.PrivateKey(pemRepresentation: pem) else {
            lastResult = "Couldn't read the APNs key"
            return nil
        }
        func b64(_ data: Data) -> String {
            data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        let header = b64(Data(#"{"alg":"ES256","kid":"\#(config.keyID)"}"#.utf8))
        let claims = b64(Data(#"{"iss":"\#(config.teamID)","iat":\#(Int(Date.now.timeIntervalSince1970))}"#.utf8))
        guard let signature = try? key.signature(for: Data("\(header).\(claims)".utf8)) else { return nil }
        let token = "\(header).\(claims).\(b64(signature.rawRepresentation))"
        cachedJWT = (token, .now)
        return token
    }
    #endif

    // MARK: Payloads (pure, testable)

    /// ActivityKit decodes `content-state` with a default JSONDecoder, so dates are seconds
    /// since the 2001 reference date.
    static func contentState(_ state: MacState) -> [String: Any] {
        var content: [String: Any] = [
            "mode": "onBreak",
            "title": state.breakTitle ?? (state.isLongBreak ? "Long break" : "Break"),
            "subtitle": state.breakMessage ?? "Look away from your screens.",
        ]
        if let end = state.breakEnd { content["target"] = end.timeIntervalSinceReferenceDate }
        if let start = state.breakStart { content["from"] = start.timeIntervalSinceReferenceDate }
        return content
    }

    static func liveActivityStart(_ state: MacState) -> [String: Any] {
        var aps: [String: Any] = [
            "timestamp": Int(Date.now.timeIntervalSince1970),
            "event": "start",
            "content-state": contentState(state),
            "attributes-type": "BreatherActivityAttributes",
            "attributes": ["macName": state.macName],
            "alert": ["title": state.breakTitle ?? "Break time", "body": state.breakMessage ?? "Look away from your screens."],
        ]
        if let end = state.breakEnd { aps["dismissal-date"] = Int(end.addingTimeInterval(5).timeIntervalSince1970) }
        return ["aps": aps]
    }

    static func alert(_ state: MacState, started: Bool) -> [String: Any] {
        [
            "aps": [
                "alert": started
                    ? ["title": state.breakTitle ?? "Break time", "body": state.breakMessage ?? "Look away from your screens."]
                    : ["title": "Break over", "body": "Welcome back."],
                "mutable-content": 1,
                "sound": "default",
                "interruption-level": "time-sensitive",
            ],
            "breather": [
                "action": started ? "block" : "unblock",
                "block": started && state.blockPhone,
                "until": state.breakEnd?.timeIntervalSince1970 ?? 0,
            ],
        ]
    }
}
