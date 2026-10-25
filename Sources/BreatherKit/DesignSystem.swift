import SwiftUI

// Breather's design system. Every surface — the Mac notch island, menu bar, break screen,
// iPhone app, Live Activity and Apple Watch — is built from these pieces, so the brand looks
// the same everywhere: dark "night" surfaces, soft glass cards, a mint→ocean aurora, the
// eyelid-and-horizon mark, rounded numerals, and one status colour language.

/// What a status colour means. One meaning, one colour, on every device.
public enum BrandTone: Sendable {
    /// Counting toward a break.
    case focus
    /// A break is close (under a minute).
    case soon
    /// A break is waiting on a call, video, typing…
    case hold
    /// On a break.
    case rest
    /// Paused, away, off hours.
    case idle

    public var color: Color {
        switch self {
        case .focus: Brand.mint
        case .soon: Brand.amber
        case .hold: Brand.sky
        case .rest: Brand.mint
        case .idle: .white.opacity(0.45)
        }
    }
}

public enum BrandStyle {
    public static let primaryText = Color.white
    public static let secondaryText = Color.white.opacity(0.62)
    public static let tertiaryText = Color.white.opacity(0.4)
    public static let cardFill = Color.white.opacity(0.075)
    public static let cardFillHover = Color.white.opacity(0.12)
    public static let cardStroke = Color.white.opacity(0.07)
    public static let iconWell = Color.white.opacity(0.12)
    public static let cardRadius: CGFloat = 22
    public static let tileRadius: CGFloat = 18

    /// Countdown and stat numerals: SF Pro Rounded, tabular.
    public static func numeral(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }

    /// Ocean aurora, row by row for a 3×3 mesh.
    public static let auroraOcean: [Color] = [
        (0.04, 0.06, 0.14), (0.05, 0.18, 0.26), (0.09, 0.06, 0.20),
        (0.06, 0.26, 0.30), (0.16, 0.42, 0.40), (0.20, 0.12, 0.36),
        (0.03, 0.05, 0.12), (0.08, 0.14, 0.30), (0.04, 0.05, 0.12),
    ].map { Color(red: $0.0, green: $0.1, blue: $0.2) }

    /// The calm app background: night with a faint aurora glow at the top.
    public static let nightGradient = LinearGradient(
        colors: [Color(red: 0.05, green: 0.13, blue: 0.19), Brand.night, Color(red: 0.02, green: 0.04, blue: 0.08)],
        startPoint: .top, endPoint: .bottom)
}

// MARK: - Backgrounds

/// The signature animated mesh. Used behind breaks on every device.
public struct AuroraBackground: View {
    public var colors: [Color]
    public var animated: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(colors: [Color] = BrandStyle.auroraOcean, animated: Bool = true) {
        self.colors = colors
        self.animated = animated
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || !animated)) { context in
            let t = (reduceMotion || !animated) ? 0 : context.date.timeIntervalSinceReferenceDate
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [Float(0.5 + 0.18 * sin(t * 0.21)), Float(0.5 + 0.14 * cos(t * 0.17))], [1, 0.5],
                    [0, 1], [Float(0.5 + 0.2 * cos(t * 0.13)), 1], [1, 1],
                ],
                colors: colors.count == 9 ? colors : BrandStyle.auroraOcean
            )
        }
        .ignoresSafeArea()
    }
}

/// Night background with a soft aurora glow, for app screens (not breaks).
public struct NightBackground: View {
    public init() {}
    public var body: some View {
        ZStack {
            BrandStyle.nightGradient
            RadialGradient(colors: [Brand.teal.opacity(0.28), .clear], center: .top, startRadius: 0, endRadius: 420)
        }
        .ignoresSafeArea()
    }
}

/// 8-second breath: 4s in, 4s out. Shared so halos and cues stay in sync across devices.
public enum BreathCycle {
    public static let period: TimeInterval = 8
    /// 0 → fully exhaled, 1 → fully inhaled.
    public static func level(at date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
        return 0.5 - 0.5 * cos(2 * .pi * t)
    }
    public static func inhaling(at date: Date) -> Bool {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) < period / 2
    }
}

public struct BreathingHalo: View {
    public var color: Color
    public var reduceMotion: Bool

    public init(color: Color = .white, reduceMotion: Bool = false) {
        self.color = color
        self.reduceMotion = reduceMotion
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let level = reduceMotion ? 0.5 : BreathCycle.level(at: context.date)
            GeometryReader { geo in
                Circle()
                    .fill(RadialGradient(colors: [color.opacity(0.2), color.opacity(0)], center: .center,
                                         startRadius: 4, endRadius: geo.size.width / 2))
                    .scaleEffect(0.78 + 0.4 * level)
            }
        }
    }
}

// MARK: - Status

/// The Breather ring: progress around, a countdown or the mark in the middle, a caption below.
public struct StatusRing<Center: View>: View {
    public var progress: Double
    public var tone: BrandTone
    public var lineWidth: CGFloat
    public var center: Center

    public init(progress: Double, tone: BrandTone, lineWidth: CGFloat = 8, @ViewBuilder center: () -> Center) {
        self.progress = progress
        self.tone = tone
        self.lineWidth = lineWidth
        self.center = center()
    }

    public var body: some View {
        ZStack {
            ProgressRing(progress: progress, color: tone.color, lineWidth: lineWidth, track: .white.opacity(0.12))
            center
        }
    }
}

/// The mark in a tinted circle; leads headers, toasts and Live Activities.
public struct BrandBadge: View {
    public var color: Color
    public var symbol: String?
    public var size: CGFloat

    public init(tone: BrandTone = .focus, symbol: String? = nil, size: CGFloat = 36) {
        self.init(color: tone.color, symbol: symbol, size: size)
    }

    public init(color: Color, symbol: String? = nil, size: CGFloat = 36) {
        self.color = color
        self.symbol = symbol
        self.size = size
    }

    public var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.18))
            if let symbol {
                Image(systemName: symbol).font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(color)
            } else {
                BreatherMark(color: color, rippleOpacity: 0.6).frame(width: size * 0.56, height: size * 0.56)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Controls

/// Control Center–style tile: an icon well on a glass card, with an optional label.
public struct ActionTile: View {
    public var title: String
    public var symbol: String
    public var tint: Color
    public var active: Bool
    public var action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.actionTileTitles) private var showsTitle

    public init(_ title: String, symbol: String, tint: Color = Brand.mint, active: Bool = false,
                action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.active = active
        self.action = action
    }

    public var body: some View {
        Button(action: action) { label }
            .buttonStyle(.plain)
            #if os(macOS)
            .onHover { hovering = $0 }
            .pointerStyle(.link)
            // Icon-only tiles name themselves instantly on hover.
            .hoverLabel(showsTitle ? nil : title, visible: hovering && isEnabled)
            #endif
            .accessibilityLabel(title)
            .opacity(isEnabled ? 1 : 0.4)
    }

    /// The tile's look on its own, e.g. as a Menu label.
    public var label: ActionTileLabel {
        ActionTileLabel(title: title, symbol: symbol, tint: tint, active: active, hovering: hovering)
    }
}

public struct ActionTileLabel: View {
    public var title: String
    public var symbol: String
    public var tint: Color
    public var active: Bool
    public var hovering: Bool
    @Environment(\.actionTileTitles) private var showsTitle

    public var body: some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(active ? Brand.night : tint)
                .frame(width: 38, height: 38)
                .background(Circle().fill(active ? tint : BrandStyle.iconWell))
            if showsTitle {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(BrandStyle.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, showsTitle ? 12 : 9)
        .background(RoundedRectangle(cornerRadius: BrandStyle.tileRadius, style: .continuous)
            .fill(hovering ? BrandStyle.cardFillHover : BrandStyle.cardFill))
        .contentShape(RoundedRectangle(cornerRadius: BrandStyle.tileRadius, style: .continuous))
    }
}

public extension EnvironmentValues {
    @Entry var actionTileTitles: Bool = true
}

public extension View {
    func actionTileTitles(_ show: Bool) -> some View { environment(\.actionTileTitles, show) }
}

/// Capsule button: primary (mint), normal (glass), subtle.
public struct PillButton: View {
    public enum Style: Sendable { case primary, normal, subtle }
    public var title: String
    public var symbol: String?
    public var style: Style
    /// Share a row's width equally with its neighbours.
    public var stretch: Bool
    public var fontSize: CGFloat
    /// Shown above the button on hover (for icon-only pills).
    public var hint: String?
    public var tint: Color?
    public var action: () -> Void
    @State private var hovering = false

    public init(_ title: String, symbol: String? = nil, style: Style = .normal, stretch: Bool = false,
                fontSize: CGFloat = 13, hint: String? = nil, tint: Color? = nil, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.style = style
        self.stretch = stretch
        self.fontSize = fontSize
        self.hint = hint
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.system(size: fontSize - 1, weight: .semibold)) }
                if !title.isEmpty {
                    Text(title).font(.system(size: fontSize, weight: .semibold)).lineLimit(1).fixedSize()
                }
            }
            .padding(.horizontal, title.isEmpty ? 10 : 12)
            .padding(.vertical, 7)
            .frame(maxWidth: stretch ? .infinity : nil)
            .foregroundStyle(tint ?? (style == .primary ? Brand.night : .white.opacity(style == .subtle ? 0.62 : 0.95)))
            .background(Capsule().fill(hovering ? hoverBackground : background))
            .contentShape(Capsule())
            .scaleEffect(hovering ? 1.04 : 1)
            .animation(.easeOut(duration: 0.15), value: hovering)
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .onHover { hovering = $0 }
        .pointerStyle(.link)
        .hoverLabel(hint, visible: hovering)
        #endif
    }

    private var background: Color {
        switch style {
        case .primary: Brand.mint
        case .normal: .white.opacity(0.13)
        case .subtle: .white.opacity(0.07)
        }
    }

    private var hoverBackground: Color {
        switch style {
        case .primary: Brand.mint.opacity(0.85)
        case .normal: .white.opacity(0.24)
        case .subtle: .white.opacity(0.16)
        }
    }
}

// MARK: - Hover labels

/// A small dark label that appears above a control while hovered — instant, unlike system tooltips.
public struct HoverLabel: View {
    public var text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color(white: 0.06).opacity(0.94)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.14)))
            .fixedSize()
    }
}

public extension View {
    /// Floats `text` just above the view while `visible`; nil shows nothing.
    func hoverLabel(_ text: String?, visible: Bool) -> some View {
        self
            .overlay(alignment: .top) {
                if let text, visible {
                    HoverLabel(text)
                        .offset(y: -28)
                        .transition(.opacity.combined(with: .offset(y: 3)))
                        .allowsHitTesting(false)
                }
            }
            .zIndex(visible ? 10 : 0)
            .animation(.easeOut(duration: 0.12), value: visible)
    }
}

// MARK: - Cards & text

public extension View {
    /// A glass card on the night background.
    func brandCard(padding: CGFloat = 16, radius: CGFloat = BrandStyle.cardRadius) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(BrandStyle.cardFill)
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(BrandStyle.cardStroke))
            )
    }
}

/// Small caps section label used above cards.
public struct BrandSectionLabel: View {
    public var text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(BrandStyle.tertiaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
    }
}

/// Big number with a caption, for "breaks today" / "score".
public struct BrandStat: View {
    public var value: String
    public var label: String
    public var tint: Color
    public init(_ value: String, label: String, tint: Color = .white) {
        self.value = value
        self.label = label
        self.tint = tint
    }
    /// Numbers get the big rounded numeral; words (a profile name) a calmer weight.
    private var isNumber: Bool { Double(value) != nil }
    public var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(isNumber ? BrandStyle.numeral(24) : .system(size: 17, weight: .semibold))
                .frame(height: 30)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(tint)
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(BrandStyle.tertiaryText)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Shared status mapping

public extension MacState.Mode {
    var tone: BrandTone {
        switch self {
        case .working: .focus
        case .onHold: .hold
        case .onBreak: .rest
        case .paused, .away, .offHours: .idle
        }
    }
}

public extension MacState {
    /// Tone that also turns amber in the last minute before a break.
    func tone(at date: Date) -> BrandTone {
        if mode == .working, let next = nextBreakAt, next.timeIntervalSince(date) < 60 { return .soon }
        return mode.tone
    }
}
