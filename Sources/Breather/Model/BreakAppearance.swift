import SwiftUI

/// A colour that survives JSON (SwiftUI `Color` isn't Codable).
struct RGBA: Codable, Equatable, Hashable {
    var r: Double, g: Double, b: Double, a: Double = 1

    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent), Double(ns.alphaComponent))
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
    var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }

    static let white = RGBA(1, 1, 1)
    static let black = RGBA(0, 0, 0)
}

enum BreakBackground: String, Codable, CaseIterable, Identifiable {
    case aurora, gradient, solid, wallpaper, image, frosted
    var id: String { rawValue }
    var title: String {
        switch self {
        case .aurora: "Aurora (animated)"
        case .gradient: "Gradient"
        case .solid: "Solid colour"
        case .wallpaper: "Blurred wallpaper"
        case .image: "Your photo or folder"
        case .frosted: "Frosted glass"
        }
    }
}

/// Colour sets for the animated aurora (3×3 mesh, row by row).
enum AuroraPalette: String, Codable, CaseIterable, Identifiable {
    case ocean, sunset, forest, lavender, ember, mono
    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var colors: [Color] {
        let c: [(Double, Double, Double)] = switch self {
        case .ocean: [(0.04, 0.06, 0.14), (0.05, 0.18, 0.26), (0.09, 0.06, 0.20),
                      (0.06, 0.26, 0.30), (0.16, 0.42, 0.40), (0.20, 0.12, 0.36),
                      (0.03, 0.05, 0.12), (0.08, 0.14, 0.30), (0.04, 0.05, 0.12)]
        case .sunset: [(0.16, 0.05, 0.12), (0.36, 0.10, 0.18), (0.20, 0.06, 0.20),
                       (0.48, 0.18, 0.20), (0.78, 0.40, 0.28), (0.38, 0.12, 0.30),
                       (0.10, 0.03, 0.10), (0.30, 0.10, 0.22), (0.08, 0.03, 0.10)]
        case .forest: [(0.02, 0.08, 0.06), (0.05, 0.20, 0.14), (0.03, 0.10, 0.10),
                       (0.08, 0.28, 0.18), (0.24, 0.46, 0.30), (0.06, 0.20, 0.20),
                       (0.02, 0.06, 0.05), (0.06, 0.16, 0.12), (0.02, 0.05, 0.05)]
        case .lavender: [(0.10, 0.07, 0.18), (0.22, 0.16, 0.38), (0.14, 0.08, 0.26),
                         (0.30, 0.22, 0.48), (0.56, 0.46, 0.74), (0.34, 0.20, 0.50),
                         (0.08, 0.06, 0.16), (0.20, 0.14, 0.34), (0.08, 0.05, 0.14)]
        case .ember: [(0.10, 0.04, 0.02), (0.28, 0.10, 0.04), (0.14, 0.05, 0.03),
                      (0.40, 0.16, 0.05), (0.72, 0.38, 0.12), (0.30, 0.10, 0.05),
                      (0.06, 0.02, 0.02), (0.22, 0.08, 0.04), (0.06, 0.02, 0.02)]
        case .mono: [(0.04, 0.04, 0.05), (0.12, 0.12, 0.14), (0.06, 0.06, 0.07),
                     (0.16, 0.16, 0.18), (0.30, 0.30, 0.32), (0.14, 0.14, 0.16),
                     (0.03, 0.03, 0.04), (0.10, 0.10, 0.11), (0.03, 0.03, 0.04)]
        }
        return c.map { Color(red: $0.0, green: $0.1, blue: $0.2) }
    }
}

enum TimerStyle: String, Codable, CaseIterable, Identifiable {
    case ring, digits, bar, dots, hidden
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ring: "Ring"
        case .digits: "Large digits"
        case .bar: "Progress bar"
        case .dots: "Dots"
        case .hidden: "No timer"
        }
    }
}

enum TextDesign: String, Codable, CaseIterable, Identifiable {
    case standard, rounded, serif, mono
    var id: String { rawValue }
    var title: String {
        switch self {
        case .standard: "SF Pro"
        case .rounded: "SF Pro Rounded"
        case .serif: "New York"
        case .mono: "SF Mono"
        }
    }
    var design: Font.Design {
        switch self {
        case .standard: .default
        case .rounded: .rounded
        case .serif: .serif
        case .mono: .monospaced
        }
    }
}

enum TextWeight: String, Codable, CaseIterable, Identifiable {
    case ultraLight, thin, light, regular, medium, semibold, bold
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ultraLight: "Ultralight"
        case .semibold: "Semibold"
        default: rawValue.capitalized
        }
    }
    var weight: Font.Weight {
        switch self {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }
}

struct BreakAppearance: Codable, Equatable {
    // Background
    var background: BreakBackground = .aurora
    var auroraPalette: AuroraPalette = .ocean
    var animateBackground = true
    var solidColor = RGBA(0.04, 0.07, 0.12)
    var gradientTop = RGBA(0.06, 0.30, 0.40)
    var gradientBottom = RGBA(0.03, 0.05, 0.12)
    /// A file, or a folder to pick a random image from each break.
    var imagePath: String?
    var imageBlur: Double = 0
    /// Darkening over photo/wallpaper backgrounds so text stays readable.
    var dimming: Double = 0.35

    // Timer
    var timerStyle: TimerStyle = .ring
    var timerDesign: TextDesign = .rounded
    var timerWeight: TextWeight = .thin
    var timerScale: Double = 1
    var accent = RGBA.white

    // Text
    var textColor = RGBA.white
    var messageDesign: TextDesign = .standard
    var messageWeight: TextWeight = .semibold
    var messageScale: Double = 1

    // Elements
    var showKindLabel = true
    var showMessage = true
    var showBreathingHalo = true
    /// "Breathe in… breathe out" synced to the halo.
    var showBreathingCue = false
    var showClock = false
    var showHint = true

    static let `default` = BreakAppearance()
}

/// One-click looks. Applying a theme overwrites the appearance; users can tweak after.
struct BreakTheme: Identifiable {
    let id: String
    let appearance: BreakAppearance

    /// Five looks that each feel different: animated aurora, bold digits, warm gradient, black minimal, light paper.
    static let all: [BreakTheme] = [
        BreakTheme(id: "Ocean Calm", appearance: .default),
        BreakTheme(id: "Forest", appearance: {
            var a = BreakAppearance(); a.auroraPalette = .forest
            let green = RGBA(0.55, 0.97, 0.65)
            a.timerStyle = .digits; a.timerDesign = .rounded; a.timerWeight = .bold; a.timerScale = 1.3; a.accent = green
            a.textColor = green; a.messageDesign = .rounded; a.messageWeight = .bold; a.messageScale = 1.3
            a.showBreathingHalo = false; a.showBreathingCue = true; a.showClock = true; a.showHint = false
            return a
        }()),
        BreakTheme(id: "Sunset Glow", appearance: {
            var a = BreakAppearance(); a.background = .gradient
            a.gradientTop = RGBA(0.93, 0.47, 0.36); a.gradientBottom = RGBA(0.22, 0.07, 0.26)
            a.timerStyle = .dots; a.timerWeight = .semibold; a.accent = RGBA(1, 0.9, 0.78)
            a.messageDesign = .serif; a.messageWeight = .medium; a.showBreathingCue = true
            return a
        }()),
        BreakTheme(id: "Midnight Minimal", appearance: {
            var a = BreakAppearance(); a.background = .solid; a.solidColor = RGBA(0.02, 0.02, 0.03)
            a.timerStyle = .digits; a.timerDesign = .standard; a.timerWeight = .ultraLight; a.timerScale = 1.4
            a.showBreathingHalo = false; a.showKindLabel = false; a.showHint = false; return a
        }()),
        BreakTheme(id: "Paper", appearance: {
            var a = BreakAppearance(); a.background = .solid; a.solidColor = RGBA(0.96, 0.94, 0.89)
            a.textColor = RGBA(0.16, 0.14, 0.12); a.accent = RGBA(0.16, 0.14, 0.12)
            a.timerStyle = .bar; a.timerDesign = .serif; a.timerWeight = .light
            a.messageDesign = .serif; a.messageWeight = .regular; a.showBreathingHalo = false; return a
        }()),
    ]
}
