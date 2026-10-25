import AppKit
import Charts
import SwiftUI

struct StatsView: View {
    let app: AppModel
    /// Snapshot rendering can't draw inside a ScrollView.
    var scrolls = true
    @State private var range: Range = .today

    enum Range: String, CaseIterable, Identifiable {
        case today = "Today", week = "Last 7 Days"
        var id: String { rawValue }
    }

    private var usage: UsageTracker { app.usage }

    var body: some View {
        Group {
            if scrolls { ScrollView { content } } else { content }
        }
        .frame(minWidth: 760, minHeight: 620)
    }

    private var content: some View {
        let history = usage.history(days: 7)
        let stats = range == .today ? usage.today : Self.combine(history)
        return VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Picker("", selection: $range) {
                        ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 260)
                    Spacer()
                }

                HStack(alignment: .top, spacing: 14) {
                    ScoreCard(score: range == .today ? usage.score : Self.averageScore(history), isAverage: range == .week)
                    VStack(spacing: 14) {
                        HStack(spacing: 14) {
                            MetricCard(title: "Screen time", value: Format.hoursMinutes(stats.screenSeconds), symbol: "display", tint: Brand.teal)
                            MetricCard(title: "Breaks taken", value: "\(stats.taken)", detail: stats.skipped > 0 ? "\(stats.skipped) skipped" : "None skipped",
                                       symbol: "checkmark.circle.fill", tint: Brand.mint)
                        }
                        HStack(spacing: 14) {
                            MetricCard(title: "Longest stretch", value: Format.hoursMinutes(max(stats.longestSession, range == .today ? usage.currentSession : 0)),
                                       detail: "without a real break", symbol: "timer", tint: Brand.amber)
                            MetricCard(title: "Typical stretch", value: Format.hoursMinutes(stats.medianSession),
                                       detail: "target \(Format.compact(stats.targetSeconds))", symbol: "chart.bar.fill", tint: .indigo)
                        }
                    }
                }

                if range == .week {
                    Card(title: "Screen time by day") {
                        Chart(history, id: \.day) { day in
                            BarMark(x: .value("Day", Self.weekday(day.day)), y: .value("Hours", day.screenSeconds / 3600))
                                .foregroundStyle(Brand.gradient)
                                .cornerRadius(6)
                                .annotation(position: .top) {
                                    if day.screenSeconds > 0 {
                                        Text("\(day.score())").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                                    }
                                }
                        }
                        .chartYAxis { AxisMarks { AxisValueLabel(format: FloatingPointFormatStyle<Double>().precision(.fractionLength(0))); AxisGridLine() } }
                        .frame(height: 180)
                        Text("Numbers above the bars are each day's Screen Score.").font(.caption).foregroundStyle(.secondary)
                    }
                }

                HStack(alignment: .top, spacing: 14) {
                    Card(title: "Apps") {
                        UsageList(items: Self.top(stats.appSeconds, 8), total: stats.screenSeconds) { id in
                            AnyView(HStack(spacing: 8) { AppIcon(bundleID: id); Text(stats.appNames[id] ?? id).lineLimit(1) })
                        }
                        if !app.store.settings.trackAppUsage {
                            Text("App tracking is off in Settings → Stats & Privacy.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Card(title: "Websites") {
                        if app.store.settings.trackWebsites {
                            UsageList(items: Self.top(stats.siteSeconds, 8), total: stats.siteSeconds.values.reduce(0, +)) { host in
                                AnyView(HStack(spacing: 8) {
                                    Image(systemName: "globe").foregroundStyle(.secondary).frame(width: 18)
                                    Text(host).lineLimit(1)
                                })
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("See which sites you spend time on in Safari, Chrome, Arc, Brave, Edge, Vivaldi and Opera.")
                                    .font(.callout).foregroundStyle(.secondary)
                                Button("Turn On Website Tracking") { app.store.settings.trackWebsites = true }
                                Text("macOS will ask once per browser. Nothing leaves your Mac.").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                ScoreExplainer()
            }
            .padding(24)
    }

    // MARK: Helpers

    static func top(_ dict: [String: TimeInterval], _ n: Int) -> [(String, TimeInterval)] {
        dict.sorted { $0.value > $1.value }.prefix(n).map { ($0.key, $0.value) }
    }

    static func combine(_ days: [DailyStats]) -> DailyStats {
        var out = DailyStats(day: "week")
        for d in days {
            out.screenSeconds += d.screenSeconds
            out.sessions += d.sessions
            out.taken += d.taken
            out.skipped += d.skipped
            out.targetSeconds = d.targetSeconds
            d.appSeconds.forEach { out.appSeconds[$0.key, default: 0] += $0.value }
            d.siteSeconds.forEach { out.siteSeconds[$0.key, default: 0] += $0.value }
            d.appNames.forEach { out.appNames[$0.key] = $0.value }
        }
        return out
    }

    static func averageScore(_ days: [DailyStats]) -> Int {
        let active = days.filter { $0.screenSeconds > 300 }
        guard !active.isEmpty else { return 0 }
        return active.map { $0.score() }.reduce(0, +) / active.count
    }

    static func weekday(_ key: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: key) else { return key }
        f.dateFormat = "EEE"
        return f.string(from: date)
    }
}

private struct Card<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.quaternary.opacity(0.45)))
    }
}

private struct ScoreCard: View {
    var score: Int
    var isAverage: Bool

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                ProgressRing(progress: Double(score) / 100, color: color, lineWidth: 12, track: .secondary.opacity(0.15))
                VStack(spacing: 0) {
                    Text("\(score)").font(.system(size: 44, weight: .bold, design: .rounded)).contentTransition(.numericText())
                    Text("of 100").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 140, height: 140)
            Text(isAverage ? "Average Screen Score" : "Screen Score").font(.headline)
            Text(verdict).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(width: 210)
        .padding(.vertical, 18)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.quaternary.opacity(0.45)))
    }

    private var color: Color { score >= 80 ? Brand.mint : score >= 55 ? Brand.amber : .red }
    private var verdict: String {
        switch score {
        case 85...: "Great rhythm. Your eyes thank you."
        case 65..<85: "Good. A few long stretches."
        case 40..<65: "Try taking breaks when they come."
        case 1..<40: "Lots of long, unbroken sessions."
        default: "Not enough screen time yet."
        }
    }
}

private struct MetricCard: View {
    var title: String
    var value: String
    var detail: String? = nil
    var symbol: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.caption.weight(.medium)).foregroundStyle(tint)
            Text(value).font(.system(size: 26, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
            Text(detail ?? " ").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.quaternary.opacity(0.45)))
    }
}

private struct UsageList: View {
    var items: [(String, TimeInterval)]
    var total: TimeInterval
    var label: (String) -> AnyView

    var body: some View {
        if items.isEmpty {
            Text("Nothing yet today.").font(.callout).foregroundStyle(.secondary)
        } else {
            let maxValue = items.first?.1 ?? 1
            VStack(spacing: 10) {
                ForEach(items, id: \.0) { id, seconds in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            label(id)
                            Spacer()
                            Text(Format.hoursMinutes(seconds)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .font(.callout)
                        GeometryReader { geo in
                            Capsule().fill(Brand.teal.opacity(0.7)).frame(width: max(4, geo.size.width * seconds / maxValue))
                        }
                        .frame(height: 4)
                    }
                }
            }
        }
    }
}

private struct ScoreExplainer: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("How Screen Score works").font(.subheadline.weight(.semibold))
            Text("Up to 60 points for keeping each stretch of work near your rhythm. Up to 40 for taking the breaks you're offered. Time away from your Mac counts as a break.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

extension Format {
    /// "3h 12m", "42m", "0m".
    static func hoursMinutes(_ seconds: TimeInterval) -> String {
        let m = Int(seconds / 60)
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }
}

@MainActor
final class StatsWindowController {
    private var window: NSWindow?

    func show(app: AppModel) {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: StatsView(app: app)))
            window.title = "Breather Stats"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.setContentSize(NSSize(width: 820, height: 700))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
