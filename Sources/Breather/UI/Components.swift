import SwiftUI

enum Format {
    /// "12m", "45s", "1h 05m".
    static func short(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        if s < 60 { return "\(s)s" }
        let m = Int((Double(s) / 60).rounded(.up))
        if m < 60 { return "\(m)m" }
        return String(format: "%dh %02dm", m / 60, m % 60)
    }

    /// "12:04", "0:45".
    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// "20 seconds", "5 minutes".
    static func spoken(_ seconds: TimeInterval) -> String {
        let f = DateComponentsFormatter()
        f.unitsStyle = .full
        f.allowedUnits = seconds >= 3600 ? [.hour, .minute] : seconds >= 60 ? [.minute] : [.second]
        f.maximumUnitCount = 2
        return f.string(from: seconds.rounded()) ?? ""
    }
}

struct ProgressRing: View {
    var progress: Double
    var color: Color
    var lineWidth: CGFloat = 3
    var track: Color = .white.opacity(0.16)

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// Small capsule button used on the island's black surface.
struct IslandButton: View {
    enum Style { case primary, normal, subtle }
    var title: String
    var symbol: String? = nil
    var style: Style = .normal
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)) }
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .foregroundStyle(style == .primary ? Color.black : .white.opacity(style == .subtle ? 0.6 : 0.95))
            .background(
                Capsule().fill(background.opacity(hovering ? 1 : 0.85))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var background: Color {
        switch style {
        case .primary: .mint
        case .normal: .white.opacity(0.14)
        case .subtle: .white.opacity(0.06)
        }
    }
}

extension Color {
    static let breatherMint = Color(red: 0.42, green: 0.93, blue: 0.75)
}
