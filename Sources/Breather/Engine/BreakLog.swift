import Foundation
import Observation

/// Append-only log of break outcomes, one JSON object per line.
/// Phase 2 stats read the same file.
struct BreakLogEntry: Codable {
    enum Outcome: String, Codable { case taken, skipped, skippedInAdvance, snoozed, natural }
    var date: Date
    var outcome: Outcome
    var kind: BreakKind?
    var seconds: TimeInterval?
}

@MainActor
@Observable
final class BreakLog {
    private(set) var takenToday = 0
    private(set) var skippedToday = 0
    private(set) var advanceSkipsToday = 0

    @ObservationIgnored private let url: URL
    @ObservationIgnored private var day = Calendar.current.startOfDay(for: .now)

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Breather", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("events.jsonl")
        loadToday()
    }

    func append(_ entry: BreakLogEntry) {
        rollDay()
        count(entry)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var line = try? encoder.encode(entry) else { return }
        line.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: url)
        }
    }

    private func count(_ entry: BreakLogEntry) {
        switch entry.outcome {
        case .taken, .natural: takenToday += 1
        case .skipped: skippedToday += 1
        case .skippedInAdvance: skippedToday += 1; advanceSkipsToday += 1
        case .snoozed: break
        }
    }

    private func rollDay() {
        let today = Calendar.current.startOfDay(for: .now)
        if today != day {
            day = today
            takenToday = 0
            skippedToday = 0
            advanceSkipsToday = 0
        }
    }

    private func loadToday() {
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Only the tail can contain today's entries.
        let tail = data.suffix(256 * 1024)
        for line in tail.split(separator: 0x0A) {
            guard let entry = try? decoder.decode(BreakLogEntry.self, from: Data(line)),
                  entry.date >= day else { continue }
            count(entry)
        }
    }
}
