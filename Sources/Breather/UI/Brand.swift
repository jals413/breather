import AppKit
import SwiftUI

/// Breather's visual identity. Everything brand-coloured in the app reads from here,
/// so a future rename/re-theme is a one-file change.
enum Brand {
    static let name = "Breather"
    static let tagline = "Rest your eyes. Keep your flow."

    /// Core palette: a calm mint that warms into ocean blue.
    static let mint = Color(red: 0.40, green: 0.91, blue: 0.76)        // #66E8C2
    static let teal = Color(red: 0.13, green: 0.71, blue: 0.69)        // #21B5B0
    static let ocean = Color(red: 0.05, green: 0.38, blue: 0.55)       // #0D618C
    static let night = Color(red: 0.03, green: 0.07, blue: 0.13)       // #081221
    static let amber = Color(red: 1.0, green: 0.72, blue: 0.33)        // heads-up / "soon"
    static let sky = Color(red: 0.45, green: 0.78, blue: 1.0)          // on hold / smart pause

    static let gradient = LinearGradient(colors: [mint, teal, ocean], startPoint: .topLeading, endPoint: .bottomTrailing)
}

extension Color {
    static let breatherMint = Brand.mint
}

/// The Breather mark: an eyelid over a rising "sun" pupil that sits on the horizon, with a
/// breath ripple below — looking far away, and breathing out. Drawn in a unit square.
struct BreatherMark: View {
    var color: Color = .white
    var rippleOpacity: Double = 0.7

    var body: some View {
        Canvas { ctx, size in
            let w = min(size.width, size.height)
            let ox = (size.width - w) / 2, oy = (size.height - w) / 2
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * w, y: oy + y * w) }
            let stroke = StrokeStyle(lineWidth: w * 0.085, lineCap: .round, lineJoin: .round)

            var lid = Path()
            lid.move(to: pt(0.08, 0.50))
            lid.addCurve(to: pt(0.92, 0.50), control1: pt(0.27, 0.10), control2: pt(0.73, 0.10))
            ctx.stroke(lid, with: .color(color), style: stroke)

            ctx.fill(Path(ellipseIn: CGRect(origin: pt(0.355, 0.335), size: CGSize(width: w * 0.29, height: w * 0.29))), with: .color(color))

            var horizon = Path()
            horizon.move(to: pt(0.12, 0.70))
            horizon.addLine(to: pt(0.88, 0.70))
            ctx.stroke(horizon, with: .color(color), style: stroke)

            var ripple = Path()
            ripple.move(to: pt(0.30, 0.86))
            ripple.addLine(to: pt(0.70, 0.86))
            ctx.stroke(ripple, with: .color(color.opacity(rippleOpacity)), style: StrokeStyle(lineWidth: w * 0.07, lineCap: .round))
        }
    }
}

/// The app icon artwork, drawn to Apple's macOS grid: an 824pt continuous-corner squircle
/// centred in a 1024pt canvas.
struct BreatherAppIcon: View {
    var body: some View {
        GeometryReader { geo in
            let canvas = geo.size.width
            let side = canvas * 824 / 1024
            let radius = side * 0.2237
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.44, green: 0.92, blue: 0.78), Color(red: 0.10, green: 0.62, blue: 0.66),
                                                  Color(red: 0.04, green: 0.30, blue: 0.48)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay {
                        // Soft top light, like light falling on glass.
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(RadialGradient(colors: [.white.opacity(0.32), .white.opacity(0)],
                                                 center: UnitPoint(x: 0.5, y: 0.0), startRadius: 0, endRadius: side * 0.7))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(.white.opacity(0.2), lineWidth: max(1, side * 0.005))
                    }
                    .frame(width: side, height: side)
                    .shadow(color: .black.opacity(0.28), radius: canvas * 0.02, y: canvas * 0.012)

                BreatherMark(color: .white)
                    .frame(width: side * 0.66, height: side * 0.66)
                    .shadow(color: Color(red: 0.02, green: 0.2, blue: 0.3).opacity(0.35), radius: side * 0.02, y: side * 0.01)
            }
            .frame(width: canvas, height: canvas)
        }
    }
}

@MainActor
enum BrandImages {
    /// Menu bar template image: the Breather mark, monochrome so macOS tints it.
    /// `dimmed` draws the ripple-less, lid-only variant used while paused.
    static func menuBarIcon(paused: Bool = false) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { rect in
            let w = rect.width
            func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * w, y: y * w) }
            NSColor.black.set()
            let lid = NSBezierPath()
            lid.move(to: pt(0.06, 0.52))
            lid.curve(to: pt(0.94, 0.52), controlPoint1: pt(0.26, 0.08), controlPoint2: pt(0.74, 0.08))
            lid.lineWidth = 1.7
            lid.lineCapStyle = .round
            lid.stroke()
            if !paused {
                NSBezierPath(ovalIn: NSRect(x: 0.33 * w, y: 0.33 * w, width: 0.34 * w, height: 0.34 * w)).fill()
            } else {
                let ring = NSBezierPath(ovalIn: NSRect(x: 0.36 * w, y: 0.36 * w, width: 0.28 * w, height: 0.28 * w))
                ring.lineWidth = 1.4
                ring.stroke()
            }
            let horizon = NSBezierPath()
            horizon.move(to: pt(0.1, 0.76))
            horizon.line(to: pt(0.9, 0.76))
            horizon.lineWidth = 1.7
            horizon.lineCapStyle = .round
            horizon.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
