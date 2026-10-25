import SwiftUI

/// Breather's visual identity. Everything brand-coloured in the app reads from here,
/// so a future rename/re-theme is a one-file change.
public enum Brand {
    public static let name = "Breather"
    public static let tagline = "Rest your eyes. Keep your flow."

    /// Core palette: a calm mint that warms into ocean blue.
    public static let mint = Color(red: 0.40, green: 0.91, blue: 0.76)        // #66E8C2
    public static let teal = Color(red: 0.13, green: 0.71, blue: 0.69)        // #21B5B0
    public static let ocean = Color(red: 0.05, green: 0.38, blue: 0.55)       // #0D618C
    public static let night = Color(red: 0.03, green: 0.07, blue: 0.13)       // #081221
    public static let amber = Color(red: 1.0, green: 0.72, blue: 0.33)        // heads-up / "soon"
    public static let sky = Color(red: 0.45, green: 0.78, blue: 1.0)
    /// Problems: not connected, failed.
    public static let alert = Color(red: 1.0, green: 0.42, blue: 0.42)          // on hold / smart pause

    public static let gradient = LinearGradient(colors: [mint, teal, ocean], startPoint: .topLeading, endPoint: .bottomTrailing)
}

extension Color {
    public static let breatherMint = Brand.mint
}

/// The Breather mark: an eyelid over a rising "sun" pupil that sits on the horizon, with a
/// breath ripple below — looking far away, and breathing out. Built from plain shapes in a
/// unit square so it renders everywhere, including widgets and complications.
public struct BreatherMark: View {
    public var color: Color = .white
    public var rippleOpacity: Double = 0.7

    public init(color: Color = .white, rippleOpacity: Double = 0.7) {
        self.color = color
        self.rippleOpacity = rippleOpacity
    }

    public var body: some View {
        GeometryReader { geo in
            let w = min(geo.size.width, geo.size.height)
            let line = StrokeStyle(lineWidth: w * 0.085, lineCap: .round, lineJoin: .round)
            ZStack {
                MarkPart.lid.stroke(color, style: line)
                MarkPart.pupil.fill(color)
                MarkPart.horizon.stroke(color, style: line)
                MarkPart.ripple.stroke(color.opacity(rippleOpacity), style: StrokeStyle(lineWidth: w * 0.07, lineCap: .round))
            }
            .frame(width: w, height: w)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

private enum MarkPart: Shape {
    case lid, pupil, horizon, ripple

    func path(in rect: CGRect) -> Path {
        let w = min(rect.width, rect.height)
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * w, y: rect.minY + y * w) }
        var p = Path()
        switch self {
        case .lid:
            p.move(to: pt(0.08, 0.50))
            p.addCurve(to: pt(0.92, 0.50), control1: pt(0.27, 0.10), control2: pt(0.73, 0.10))
        case .pupil:
            p.addEllipse(in: CGRect(origin: pt(0.355, 0.335), size: CGSize(width: w * 0.29, height: w * 0.29)))
        case .horizon:
            p.move(to: pt(0.12, 0.70))
            p.addLine(to: pt(0.88, 0.70))
        case .ripple:
            p.move(to: pt(0.30, 0.86))
            p.addLine(to: pt(0.70, 0.86))
        }
        return p
    }
}

public struct ProgressRing: View {
    public var progress: Double
    public var color: Color
    public var lineWidth: CGFloat = 3
    public var track: Color = .white.opacity(0.16)

    public init(progress: Double, color: Color, lineWidth: CGFloat = 3, track: Color = .white.opacity(0.16)) {
        self.progress = progress
        self.color = color
        self.lineWidth = lineWidth
        self.track = track
    }

    public var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            // At zero, a round cap would still draw a dot.
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(progress > 0.005 ? 1 : 0)
        }
    }
}

