import BreatherKit
import Charts
import SwiftUI

/// The Mac's screen habits, as an at-a-glance dashboard.
struct StatsDashboard: View {
    let model: PhoneModel

    var body: some View {
        ZStack {
            NightBackground()
            ScrollView {
                VStack(spacing: 18) {
                    header
                    if let stats = model.stats {
                        ScoreHero(stats: stats)
                        metrics(stats)
                        WeekChart(stats: stats)
                        ScoreTrend(stats: stats)
                        let apps = stats.topApps.filter { $0.seconds >= 60 }
                        let sites = stats.topSites.filter { $0.seconds >= 60 }
                        if !apps.isEmpty { UsageCard(title: "Top apps", items: apps, tint: Brand.teal) }
                        if !sites.isEmpty { UsageCard(title: "Top websites", items: sites, tint: Brand.sky) }
                        explainer
                    } else {
                        empty
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            // Content fades softly under the clock instead of colliding with it.
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Stats").font(.system(size: 30, weight: .bold))
                if let stats = model.stats {
                    Text("Today on \(stats.macName) · updated \(stats.generatedAt.formatted(.relative(presentation: .named)))")
                        .font(.footnote).foregroundStyle(BrandStyle.tertiaryText)
                }
            }
            Spacer()
        }
        .padding(.top, 8)
    }

    private func metrics(_ s: StatsSnapshot) -> some View {
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        let longTone: Color = s.longestSession > s.targetSeconds * 2 ? Brand.amber : Brand.mint
        return LazyVGrid(columns: columns, spacing: 10) {
            MetricCard(symbol: "display", tint: Brand.teal, value: hoursMinutes(s.screenSeconds), label: "Screen time")
            MetricCard(symbol: "checkmark.circle.fill", tint: Brand.mint, value: "\(s.taken)",
                       label: s.skipped == 0 ? "Breaks · none skipped" : "Breaks · \(s.skipped) skipped")
            MetricCard(symbol: "timer", tint: longTone, value: hoursMinutes(s.longestSession), label: "Longest stretch")
            MetricCard(symbol: "metronome.fill", tint: Brand.sky, value: hoursMinutes(s.medianSession),
                       label: "Typical · aim \(Int(s.targetSeconds / 60))m")
        }
    }

    private var explainer: some View {
        Text("Screen Score: up to 60 points for keeping each stretch near your rhythm, up to 40 for taking the breaks you're offered. Time away from your Mac counts as a break.")
            .font(.footnote)
            .foregroundStyle(BrandStyle.tertiaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    private var empty: some View {
        VStack(spacing: 12) {
            BrandBadge(color: Brand.sky, symbol: "chart.bar.fill", size: 56)
            Text("No stats yet").font(.headline)
            Text("They appear once your Mac sends them. Keep Breather open on your Mac and your iPhone nearby.")
                .font(.callout).foregroundStyle(BrandStyle.secondaryText).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
        .brandCard()
    }
}

// MARK: - Pieces

private func hoursMinutes(_ seconds: TimeInterval) -> String {
    let m = Int(seconds / 60)
    return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
}

private func scoreColor(_ score: Int) -> Color {
    score >= 80 ? Brand.mint : score >= 55 ? Brand.amber : Color(red: 1, green: 0.45, blue: 0.45)
}

private func weekday(_ key: String) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    guard let date = f.date(from: key) else { return key }
    f.dateFormat = "EEEEE"
    return f.string(from: date)
}

private struct ScoreHero: View {
    let stats: StatsSnapshot

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                ProgressRing(progress: Double(stats.score) / 100, color: scoreColor(stats.score), lineWidth: 12, track: .white.opacity(0.1))
                VStack(spacing: 0) {
                    Text("\(stats.score)").font(BrandStyle.numeral(40, .bold))
                    Text("of 100").font(.caption2).foregroundStyle(BrandStyle.tertiaryText)
                }
            }
            .frame(width: 120, height: 120)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Screen Score").font(.system(size: 13, weight: .semibold)).foregroundStyle(BrandStyle.secondaryText)
                    Text(verdict).font(.system(size: 16, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                }
                PartBar(label: "Rhythm", value: stats.rhythmPoints, max: 60, tint: Brand.mint)
                PartBar(label: "Breaks taken", value: stats.breakPoints, max: 40, tint: Brand.sky)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .brandCard(padding: 18, radius: 28)
    }

    private var verdict: String {
        switch stats.score {
        case 85...: "Great rhythm. Your eyes thank you."
        case 65..<85: "Good, with a few long stretches."
        case 40..<65: "Try taking breaks when they come."
        case 1..<40: "Lots of long, unbroken sessions."
        default: "Not enough screen time yet."
        }
    }
}

private struct PartBar: View {
    let label: String
    let value: Int
    let max: Int
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption).foregroundStyle(BrandStyle.secondaryText)
                Spacer()
                Text("\(value)/\(max)").font(BrandStyle.numeral(12)).foregroundStyle(BrandStyle.secondaryText)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.1))
                    Capsule().fill(tint).frame(width: geo.size.width * CGFloat(value) / CGFloat(Swift.max(max, 1)))
                }
            }
            .frame(height: 6)
        }
    }
}

private struct MetricCard: View {
    let symbol: String
    let tint: Color
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BrandBadge(color: tint, symbol: symbol, size: 32)
            Text(value).font(BrandStyle.numeral(26))
            Text(label).font(.caption).foregroundStyle(BrandStyle.secondaryText).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .brandCard(padding: 14)
    }
}

/// Screen time per day, bars coloured by that day's score; today highlighted; average line.
private struct WeekChart: View {
    let stats: StatsSnapshot

    var body: some View {
        let hours = stats.week.map { $0.screenSeconds / 3600 }
        let active = hours.filter { $0 > 0 }
        let average = active.isEmpty ? 0 : active.reduce(0, +) / Double(active.count)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("This week").font(.headline)
                Spacer()
                Text("avg \(String(format: "%.1f", average))h / day").font(.caption).foregroundStyle(BrandStyle.secondaryText)
            }
            Chart {
                ForEach(stats.week) { day in
                    BarMark(x: .value("Day", day.day), y: .value("Hours", day.screenSeconds / 3600), width: .ratio(0.55))
                        .foregroundStyle(scoreColor(day.score).opacity(day.id == stats.week.last?.id ? 1 : 0.55))
                        .cornerRadius(6)
                        .annotation(position: .top, spacing: 4) {
                            if day.screenSeconds > 0 {
                                Text("\(day.score)").font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundStyle(BrandStyle.tertiaryText)
                            }
                        }
                }
                if average > 0 {
                    RuleMark(y: .value("Average", average))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let key = value.as(String.self) { Text(weekday(key)).foregroundStyle(BrandStyle.secondaryText) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(.white.opacity(0.08))
                    AxisValueLabel {
                        if let h = value.as(Double.self) { Text("\(Int(h))h").foregroundStyle(BrandStyle.tertiaryText) }
                    }
                }
            }
            .frame(height: 170)
            HStack(spacing: 14) {
                Legend(color: Brand.mint, text: "Score 80+")
                Legend(color: Brand.amber, text: "55–79")
                Legend(color: Color(red: 1, green: 0.45, blue: 0.45), text: "Under 55")
            }
        }
        .brandCard()
    }
}

private struct Legend: View {
    let color: Color
    let text: String
    var body: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(text).font(.caption2).foregroundStyle(BrandStyle.secondaryText)
        }
    }
}

/// Score over the week, as a soft area line.
private struct ScoreTrend: View {
    let stats: StatsSnapshot

    var body: some View {
        let days = stats.week.filter { $0.screenSeconds > 0 }
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Score trend").font(.headline)
                Spacer()
                if let first = days.first, let last = days.last, days.count > 1 {
                    let delta = last.score - first.score
                    Label("\(delta >= 0 ? "+" : "")\(delta)", systemImage: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(delta >= 0 ? Brand.mint : Brand.amber)
                }
            }
            if days.count < 2 {
                Text("A trend appears after two days of use.").font(.callout).foregroundStyle(BrandStyle.secondaryText)
            } else {
                Chart(days) { day in
                    AreaMark(x: .value("Day", day.day), y: .value("Score", day.score))
                        .foregroundStyle(LinearGradient(colors: [Brand.mint.opacity(0.35), Brand.mint.opacity(0)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("Day", day.day), y: .value("Score", day.score))
                        .foregroundStyle(Brand.mint)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("Day", day.day), y: .value("Score", day.score))
                        .foregroundStyle(Brand.mint)
                        .symbolSize(30)
                }
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let key = value.as(String.self) { Text(weekday(key)).foregroundStyle(BrandStyle.secondaryText) }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 50, 100]) { _ in
                        AxisGridLine().foregroundStyle(.white.opacity(0.08))
                        AxisValueLabel().foregroundStyle(BrandStyle.tertiaryText)
                    }
                }
                .frame(height: 130)
            }
        }
        .brandCard()
    }
}

private struct UsageCard: View {
    let title: String
    let items: [StatsSnapshot.Usage]
    let tint: Color

    var body: some View {
        let top = items.first?.seconds ?? 1
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 12) {
                    Text(String(item.name.prefix(1)).uppercased())
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(tint)
                        .frame(width: 32, height: 32)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.opacity(0.16)))
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(item.name).font(.system(size: 14, weight: .medium)).lineLimit(1)
                            Spacer()
                            Text(hoursMinutes(item.seconds)).font(BrandStyle.numeral(13)).foregroundStyle(BrandStyle.secondaryText)
                        }
                        GeometryReader { geo in
                            Capsule().fill(tint.opacity(index == 0 ? 0.9 : 0.55))
                                .frame(width: max(6, geo.size.width * item.seconds / top))
                        }
                        .frame(height: 5)
                    }
                }
            }
        }
        .brandCard()
    }
}
