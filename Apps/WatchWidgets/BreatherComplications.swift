import BreatherKit
import SwiftUI
import WidgetKit

@main
struct BreatherComplications: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BreatherNextBreak", provider: Provider()) { entry in
            ComplicationView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Next Break")
        .description("Time until your next break on your Mac.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct Entry: TimelineEntry {
    var date: Date
    var state: MacState?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now, state: .preview) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: .now, state: SharedStore.state ?? .preview))
    }

    /// The countdown text animates on its own; we only need a new entry when the break is due.
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let state = SharedStore.state
        var entries = [Entry(date: .now, state: state)]
        if let state, let due = state.mode == .onBreak ? state.breakEnd : state.nextBreakAt, due > .now {
            var after = state
            after.mode = state.mode == .onBreak ? .working : .onBreak
            entries.append(Entry(date: due, state: after))
        }
        completion(Timeline(entries: entries, policy: .never))
    }
}

struct ComplicationView: View {
    let entry: Entry
    @Environment(\.widgetFamily) private var family

    private var range: ClosedRange<Date>? { entry.state?.countdown }

    var body: some View {
        switch family {
        case .accessoryCircular:
            if let range {
                ProgressView(timerInterval: range, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    BreatherMark(color: .white, rippleOpacity: 0.6).padding(9)
                }
                .progressViewStyle(.circular)
                .tint(Brand.mint)
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    BreatherMark(color: .white, rippleOpacity: 0.6).padding(10)
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    BreatherMark(color: Brand.mint, rippleOpacity: 0.6).frame(width: 14, height: 14)
                    Text(entry.state?.headline ?? "Breather").font(.headline).widgetAccentable()
                }
                if let range {
                    Text(timerInterval: range, countsDown: true)
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                } else {
                    Text(entry.state?.detail ?? "Open Breather on iPhone").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryInline:
            if let range {
                Text("\(entry.state?.mode == .onBreak ? "Break" : "Next break") \(Text(timerInterval: range, countsDown: true))")
            } else {
                Text(entry.state?.headline ?? "Breather")
            }
        case .accessoryCorner:
            BreatherMark(color: .white, rippleOpacity: 0.6)
                .padding(6)
                .widgetLabel {
                    if let range { Text(timerInterval: range, countsDown: true) } else { Text("Breather") }
                }
        default:
            EmptyView()
        }
    }
}
