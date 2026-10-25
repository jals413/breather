import ActivityKit
import BreatherKit
import SwiftUI
import WidgetKit

@main
struct BreatherWidgets: WidgetBundle {
    var body: some Widget {
        BreatherLiveActivity()
    }
}

struct BreatherLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BreatherActivityAttributes.self) { context in
            LockScreenView(state: context.state, macName: context.attributes.macName, isStale: context.isStale)
                .activityBackgroundTint(Brand.night.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Badge(state: state).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(state: state)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(activityTint(state))
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(state.title).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        Text(state.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                            .multilineTextAlignment(.center)
                        ProgressBar(state: state)
                    }
                    .padding(.horizontal, 8)
                }
            } compactLeading: {
                BreatherMark(color: activityTint(state), rippleOpacity: 0.6).frame(width: 18, height: 18)
            } compactTrailing: {
                Countdown(state: state)
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .foregroundStyle(activityTint(state))
                    .frame(maxWidth: 44)
            } minimal: {
                BreatherMark(color: activityTint(state), rippleOpacity: 0.6).frame(width: 16, height: 16)
            }
            .keylineTint(activityTint(state))
        }
        // Mirrors to the Apple Watch Smart Stack (and CarPlay).
        .supplementalActivityFamilies([.small, .medium])
    }
}

private func activityTint(_ state: BreatherActivityAttributes.ContentState) -> Color {
    switch state.mode {
    case .onBreak: Brand.mint
    case .working: .white
    case .onHold: Brand.sky
    case .paused: .gray
    }
}

private struct LockScreenView: View {
    let state: BreatherActivityAttributes.ContentState
    let macName: String
    let isStale: Bool
    @Environment(\.activityFamily) private var family

    var body: some View {
        if family == .small {
            // Apple Watch Smart Stack.
            HStack(spacing: 8) {
                BreatherMark(color: activityTint(state), rippleOpacity: 0.6).frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text(state.title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    Countdown(state: state).font(.system(.title3, design: .rounded).weight(.semibold))
                }
            }
            .padding(10)
        } else {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Badge(state: state)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.title).font(.headline)
                        Text(isStale ? "Out of range of \(macName)" : state.subtitle)
                            .font(.subheadline).foregroundStyle(.white.opacity(0.7)).lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    Countdown(state: state)
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(activityTint(state))
                }
                ProgressBar(state: state)
            }
            .padding(16)
            .foregroundStyle(.white)
        }
    }
}

private struct Badge: View {
    let state: BreatherActivityAttributes.ContentState

    var body: some View {
        ZStack {
            Circle().fill(activityTint(state).opacity(0.2))
            BreatherMark(color: activityTint(state), rippleOpacity: 0.6).frame(width: 24, height: 24)
        }
        .frame(width: 44, height: 44)
    }
}

/// Counts down on its own; no updates needed from the Mac every second.
private struct Countdown: View {
    let state: BreatherActivityAttributes.ContentState

    var body: some View {
        if let target = state.target, target > .now {
            Text(timerInterval: (state.from ?? .now)...target, countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        } else {
            Image(systemName: state.mode == .onHold ? "hourglass" : state.mode == .paused ? "pause.fill" : "checkmark")
        }
    }
}

private struct ProgressBar: View {
    let state: BreatherActivityAttributes.ContentState

    var body: some View {
        if let target = state.target, let from = state.from, target > from {
            ProgressView(timerInterval: from...target, countsDown: state.mode == .onBreak) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(activityTint(state))
        }
    }
}
