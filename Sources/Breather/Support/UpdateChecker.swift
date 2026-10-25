import AppKit
import CryptoKit
import Foundation
import Observation

/// Checks GitHub Releases for a newer Breather and can install it in place. No data is sent beyond the requests themselves.
///
/// Installing downloads the release zip, checks it against the SHA-256 in the release's `checksums.txt`,
/// makes sure it's a validly signed Breather of the expected version, swaps it in for the running copy and relaunches.
@MainActor
@Observable
final class UpdateChecker {
    struct Release: Equatable {
        var version: String
        var page: URL
        var zip: URL?
        var checksums: URL?
    }

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case downloading(String)
        case installing(String)
        case failed
        case installFailed(Release, String)
    }

    private(set) var status: Status = .idle
    @ObservationIgnored var onNewVersion: ((String, URL) -> Void)?

    private static let api = URL(string: "https://api.github.com/repos/jals413/breather/releases/latest")!
    private static let lastCheckKey = "updates.lastCheck"
    private static let announcedKey = "updates.announced"

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    var available: Release? {
        switch status {
        case .available(let r), .installFailed(let r, _): r
        default: nil
        }
    }

    var isBusy: Bool {
        switch status {
        case .checking, .downloading, .installing: true
        default: false
        }
    }

    /// Checks at most once a day.
    func checkIfDue() {
        let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
        guard Date.now.timeIntervalSince(last) > 24 * 3600 else { return }
        Task { await check() }
    }

    func check() async {
        status = .checking
        UserDefaults.standard.set(Date.now, forKey: Self.lastCheckKey)
        var request = URLRequest(url: Self.api)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        struct Payload: Decodable { let tag_name: String; let html_url: URL; let assets: [Asset]? }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { status = .failed; return }
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            let latest = payload.tag_name.hasPrefix("v") ? String(payload.tag_name.dropFirst()) : payload.tag_name
            guard Self.isNewer(latest, than: currentVersion) else {
                status = .upToDate
                return
            }
            let assets = payload.assets ?? []
            let release = Release(version: latest, page: payload.html_url,
                                  zip: assets.first { $0.name == "Breather-\(latest).zip" }?.browser_download_url,
                                  checksums: assets.first { $0.name == "checksums.txt" }?.browser_download_url)
            status = .available(release)
            // Mention each new version once, not every day.
            if UserDefaults.standard.string(forKey: Self.announcedKey) != latest {
                UserDefaults.standard.set(latest, forKey: Self.announcedKey)
                onNewVersion?(latest, release.page)
            }
        } catch {
            status = .failed
        }
    }

    /// Checks if needed, then downloads, verifies and installs the latest version, and relaunches.
    func install() async {
        if available == nil { await check() }
        guard let release = available else { return }
        guard let zip = release.zip, let checksums = release.checksums else {
            return fail(release, "This release can't be installed automatically.")
        }
        let target = Bundle.main.bundleURL
        guard FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
            return fail(release, "Breather can't write to \(target.deletingLastPathComponent().path).")
        }

        status = .downloading(release.version)
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("BreatherUpdate-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let (sumsData, _) = try await URLSession.shared.data(from: checksums)
            guard let expected = Self.checksum(for: "Breather-\(release.version).zip", in: String(decoding: sumsData, as: UTF8.self)) else {
                return fail(release, "The release has no checksum for its download.")
            }
            let (downloaded, _) = try await URLSession.shared.download(from: zip)
            let archive = work.appendingPathComponent("Breather.zip")
            try FileManager.default.moveItem(at: downloaded, to: archive)

            status = .installing(release.version)
            let version = release.version
            let fresh: URL = try await Task.detached {
                guard try Self.sha256(of: archive) == expected else { throw UpdateError("The download didn't match its checksum.") }
                try Self.run("/usr/bin/ditto", ["-x", "-k", archive.path, work.path])
                let app = work.appendingPathComponent("Breather.app")
                let info = Bundle(url: app)?.infoDictionary
                guard info?["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
                      info?["CFBundleShortVersionString"] as? String == version else {
                    throw UpdateError("The download isn't the expected version of Breather.")
                }
                try Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
                try? Self.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])
                return app
            }.value

            // Swap the bundles. The running copy keeps working until we quit.
            _ = try FileManager.default.replaceItemAt(target, withItemAt: fresh, backupItemName: nil, options: [])
            relaunch(target)
        } catch {
            try? FileManager.default.removeItem(at: work)
            fail(release, (error as? UpdateError)?.message ?? "The download failed. Check your connection and try again.")
        }
    }

    private func fail(_ release: Release, _ message: String) {
        status = .installFailed(release, message)
    }

    /// Quits (state is saved on terminate as usual), waits for this process to exit, then opens the new copy.
    private func relaunch(_ app: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$0\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, app.path]
        try? process.run()
        NSApp.terminate(nil)
    }

    // MARK: - Helpers

    struct UpdateError: Error { let message: String; init(_ m: String) { message = m } }

    /// Finds a file's hash in `shasum -a 256` output.
    nonisolated static func checksum(for file: String, in text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count == 2, parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "*")) == file {
                return parts[0].lowercased()
            }
        }
        return nil
    }

    nonisolated private static func sha256(of url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func run(_ tool: String, _ args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError(tool.hasSuffix("codesign") ? "The download's signature isn't valid." : "Couldn't unpack the download.")
        }
    }

    /// Compares dotted versions numerically: 0.10.0 is newer than 0.9.3.
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}
