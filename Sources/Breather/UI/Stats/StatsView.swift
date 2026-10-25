import AppKit
import Charts
import SwiftUI

/// Stats pages, in the same sidebar-and-cards layout as Settings.
enum StatsPane: String, CaseIterable, Identifiable, SidebarItem {
    case today, week, apps, websites
    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .week: "This Week"
        case .apps: "Apps"
        case .websites: "Websites"
        }
    }

    var symbol: String {
        switch self {
        case .today: "gauge.with.needle.fill"
        case .week: "chart.bar.fill"
        case .apps: "square.grid.2x2.fill"
        case .websites: "globe"
        }
    }

    var tint: Color {
        switch self {
        case .today: Brand.teal
        case .week: .indigo
        case .apps: .blue
        case .websites: .orange
        }
    }

    var summary: String {
        switch self {
        case .today: "Your Screen Score and how today's screen time went."
        case .week: "Screen time and score over the last seven days."
        case .apps: "Where your screen time went, by app."
        case .websites: "Where your browser time went, by site."
        }
    }

    static let groups: [SidebarGroup<StatsPane>] = [
        SidebarGroup(title: nil, items: [.today, .week]),
        SidebarGroup(title: "Usage", items: [.apps, .websites]),
    ]
}

struct StatsView: View {
    let app: AppModel
    @State private var pane: StatsPane = .today

    var body: some View {
        SidebarWindow(selection: $pane, groups: StatsPane.groups) {
            switch pane {
            case .today: TodayPage(app: app)
            case .week: WeekPage(app: app)
            case .apps: UsagePage(app: app, pane: .apps)
            case .websites: UsagePage(app: app, pane: .websites)
            }
        }
    }
}

private func header(_ pane: StatsPane) -> HeaderCard {
    HeaderCard(symbol: pane.symbol, tint: pane.tint, title: pane.title, summary: pane.summary)
}

private func scoreColor(_ score: Int) -> Color {
    score >= 80 ? Brand.mint : score >= 55 ? Brand.amber : Brand.alert
}

// MARK: - Today

private struct TodayPage: View {
    let app: AppModel

    var body: some View {
        let usage = app.usage
        let today = usage.today
        let parts = today.scoreParts(includingCurrent: usage.currentSession)
        Form {
            header(.today)
            Section {
                HStack(spacing: 22) {
                    ZStack {
                        ProgressRing(progress: Double(usage.score) / 100, color: scoreColor(usage.score), lineWidth: 11,
                                     track: .secondary.opacity(0.15))
                        VStack(spacing: 0) {
                            Text("\(usage.score)").font(.system(size: 38, weight: .bold, design: .rounded))
                            Text("of 100").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 118, height: 118)
                    .padding(.leading, 6)
                    VStack(alignment: .leading, spacing: 12) {
                        Text(verdict(usage.score)).font(.headline)
                        ScoreBar(label: "Rhythm", value: parts.rhythm, max: 60, tint: Brand.mint)
                        ScoreBar(label: "Breaks taken", value: parts.breaks, max: 40, tint: Brand.sky)
                    }
                }
                .padding(.vertical, 12)
                .padding(.trailing, 4)
            } header: {
                Text("Screen Score")
            } footer: {
                Text("Up to 60 points for keeping each stretch near your rhythm, up to 40 for taking the breaks you're offered. Time away from your Mac counts as a break.")
            }

            Section("Today") {
                StatRow(symbol: "display", tint: Brand.teal, title: "Screen time", value: Format.hoursMinutes(today.screenSeconds))
                StatRow(symbol: "checkmark.circle.fill", tint: Brand.mint, title: "Breaks taken", value: "\(today.taken)")
                StatRow(symbol: "forward.end.fill", tint: Brand.amber, title: "Breaks skipped", value: "\(today.skipped)")
                StatRow(symbol: "timer", tint: .orange, title: "Longest stretch without a real break",
                        value: Format.hoursMinutes(max(today.longestSession, usage.currentSession)))
                StatRow(symbol: "metronome.fill", tint: .indigo, title: "Typical stretch",
                        value: "\(Format.hoursMinutes(today.medianSession)) · aim \(Format.compact(today.targetSeconds))")
            }
        }
    }

    private func verdict(_ score: Int) -> String {
        switch score {
        case 85...: "Great rhythm. Your eyes thank you."
        case 65..<85: "Good, with a few long stretches."
        case 40..<65: "Try taking breaks when they come."
        case 1..<40: "Lots of long, unbroken sessions."
        default: "Not enough screen time yet."
        }
    }
}

private struct ScoreBar: View {
    let label: String
    let value: Int
    let max: Int
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Text("\(value)/\(max)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.secondary.opacity(0.15))
                    Capsule().fill(tint).frame(width: geo.size.width * CGFloat(value) / CGFloat(Swift.max(max, 1)))
                }
            }
            .frame(height: 6)
        }
    }
}

private struct StatRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            SettingsBadge(symbol: symbol, tint: tint)
            Text(title)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(.secondary)
        }
    }
}

// MARK: - Week

private struct WeekPage: View {
    let app: AppModel

    var body: some View {
        let days = app.usage.history(days: 7)
        let hours = days.map { $0.screenSeconds / 3600 }.filter { $0 > 0 }
        let average = hours.isEmpty ? 0 : hours.reduce(0, +) / Double(hours.count)
        Form {
            header(.week)
            Section {
                Chart {
                    ForEach(days, id: \.day) { day in
                        BarMark(x: .value("Day", weekday(day.day)), y: .value("Hours", day.screenSeconds / 3600), width: .ratio(0.55))
                            .foregroundStyle(scoreColor(score(day)).opacity(day.day == days.last?.day ? 1 : 0.6))
                            .cornerRadius(5)
                            .annotation(position: .top, spacing: 3) {
                                if day.screenSeconds > 0 {
                                    Text("\(score(day))").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                                }
                            }
                    }
                    if average > 0 {
                        RuleMark(y: .value("Average", average))
                            .foregroundStyle(.secondary.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                }
                .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let h = v.as(Double.self) { Text("\(Int(h))h") } } } }
                .frame(height: 200)
                .padding(.vertical, 6)
            } header: {
                Text("Screen time")
            } footer: {
                Text("Bars are coloured by that day's Screen Score: mint 80+, amber 55–79, red under 55. The dashed line is your daily average (\(String(format: "%.1f", average))h).")
            }

            Section("Day by day") {
                ForEach(days.reversed(), id: \.day) { day in
                    HStack {
                        Text(longDay(day.day))
                        Spacer()
                        Text(Format.hoursMinutes(day.screenSeconds)).monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 70, alignment: .trailing)
                        Text(day.screenSeconds > 0 ? "\(score(day))" : "–")
                            .font(.callout.weight(.semibold).monospacedDigit())
                            .foregroundStyle(day.screenSeconds > 0 ? scoreColor(score(day)) : .secondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func score(_ day: DailyStats) -> Int {
        day.day == app.usage.today.day ? app.usage.score : day.score()
    }

    private func weekday(_ key: String) -> String { format(key, "EEE") }
    private func longDay(_ key: String) -> String { key == app.usage.today.day ? "Today" : format(key, "EEEE") }

    private func format(_ key: String, _ pattern: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: key) else { return key }
        f.dateFormat = pattern
        return f.string(from: date)
    }
}

// MARK: - Apps & websites

private struct UsagePage: View {
    let app: AppModel
    let pane: StatsPane
    @State private var range: Range = .today

    enum Range: String, CaseIterable, Identifiable {
        case today = "Today", week = "Last 7 Days"
        var id: String { rawValue }
    }

    var body: some View {
        let stats = range == .today ? app.usage.today : combine(app.usage.history(days: 7))
        let dict = pane == .apps ? stats.appSeconds : stats.siteSeconds
        let items = dict.sorted { $0.value > $1.value }.prefix(15).filter { $0.value >= 60 }
        let top = items.first?.value ?? 1
        Form {
            header(pane)
            Section {
                Picker("Show", selection: $range) {
                    ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            if pane == .websites && !app.store.settings.trackWebsites {
                Section {
                    Text("See which sites you spend time on in Safari, Chrome, Arc, Brave, Edge, Vivaldi and Opera. macOS asks once per browser; nothing leaves your Mac.")
                        .foregroundStyle(.secondary)
                    HStack {
                        Spacer()
                        Button("Turn On Website Tracking") { app.store.settings.trackWebsites = true }
                    }
                }
            } else if items.isEmpty {
                Section { Text("Nothing yet.").foregroundStyle(.secondary) }
            } else {
                Section {
                    ForEach(Array(items), id: \.key) { id, seconds in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 10) {
                                if pane == .apps {
                                    AppIcon(bundleID: id).frame(width: 22, height: 22)
                                } else {
                                    SettingsBadge(symbol: "globe", tint: .orange)
                                }
                                Text(pane == .apps ? (stats.appNames[id] ?? id) : id).lineLimit(1)
                                Spacer()
                                Text(Format.hoursMinutes(seconds)).monospacedDigit().foregroundStyle(.secondary)
                            }
                            GeometryReader { geo in
                                Capsule().fill(pane.tint.opacity(0.7)).frame(width: max(4, geo.size.width * seconds / top))
                            }
                            .frame(height: 4)
                            .padding(.leading, 32)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private func combine(_ days: [DailyStats]) -> DailyStats {
        var out = DailyStats(day: "week")
        for d in days {
            d.appSeconds.forEach { out.appSeconds[$0.key, default: 0] += $0.value }
            d.siteSeconds.forEach { out.siteSeconds[$0.key, default: 0] += $0.value }
            d.appNames.forEach { out.appNames[$0.key] = $0.value }
        }
        return out
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
            window.titleVisibility = .hidden
            window.setContentSize(NSSize(width: 820, height: 640))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
