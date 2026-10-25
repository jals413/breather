import AppKit
import SwiftUI

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
