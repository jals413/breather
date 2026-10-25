import Foundation
import Observation

/// Checks GitHub Releases for a newer Breather. No data is sent beyond the request itself.
@MainActor
@Observable
final class UpdateChecker {
    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, page: URL)
        case failed
    }

    private(set) var status: Status = .idle
    @ObservationIgnored var onNewVersion: ((String, URL) -> Void)?

    private static let api = URL(string: "https://api.github.com/repos/jals413/breather/releases/latest")!
    private static let lastCheckKey = "updates.lastCheck"
    private static let announcedKey = "updates.announced"

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
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
        struct Release: Decodable { let tag_name: String; let html_url: URL; let draft: Bool?; let prerelease: Bool? }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { status = .failed; return }
            let release = try JSONDecoder().decode(Release.self, from: data)
            let latest = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
            guard Self.isNewer(latest, than: currentVersion) else {
                status = .upToDate
                return
            }
            status = .available(version: latest, page: release.html_url)
            // Mention each new version once, not every day.
            if UserDefaults.standard.string(forKey: Self.announcedKey) != latest {
                UserDefaults.standard.set(latest, forKey: Self.announcedKey)
                onNewVersion?(latest, release.html_url)
            }
        } catch {
            status = .failed
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
