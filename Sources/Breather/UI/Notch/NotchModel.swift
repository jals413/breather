import SwiftUI
import Observation

struct NotchToast: Equatable, Identifiable {
    enum Action: Equatable {
        case undoNaturalBreak, resume
        case reminderDone(UUID), reminderLater(UUID)
        case startPlanned(UUID), skipPlanned, breakNow
        case openURL(URL)
    }
    var id = UUID()
    var symbol: String
    var tint: Color
    var title: String
    var subtitle: String?
    var action: Action?
    var actionTitle: String?
    var secondaryAction: Action? = nil
    var secondaryTitle: String? = nil
}

enum NotchContent: Equatable {
    /// Invisible: the island is exactly the hardware notch.
    case resting
    /// Countdown "ears" flanking the notch.
    case peek
    case expanded
    case headsUp(BreakKind)
    case countdown
    case toast(NotchToast)
    /// During a break the overlay owns the screen.
    case hidden

    /// How "open" the island is; opening and closing use different springs.
    var openness: Int {
        switch self {
        case .hidden, .resting: 0
        case .peek: 1
        case .toast, .countdown: 2
        case .headsUp: 3
        case .expanded: 4
        }
    }

    var key: String {
        switch self {
        case .resting: "resting"
        case .peek: "peek"
        case .expanded: "expanded"
        case .headsUp: "headsUp"
        case .countdown: "countdown"
        case .toast(let t): "toast-\(t.id)"
        case .hidden: "hidden"
        }
    }
}

/// Decides what the island shows. Higher-priority content wins:
/// countdown → heads-up → toast → hover dashboard → peek → resting.
@MainActor
@Observable
final class NotchModel {
    private(set) var content: NotchContent = .resting
    var isHovering = false { didSet { if oldValue != isHovering { recompute() } } }

    @ObservationIgnored private var headsUpUntil: Date?
    @ObservationIgnored private var headsUpKind: BreakKind = .short
    @ObservationIgnored private var toast: NotchToast?
    @ObservationIgnored private var toastUntil: Date?
    @ObservationIgnored private weak var engine: BreakEngine?
    @ObservationIgnored var reduceMotion = false

    func attach(_ engine: BreakEngine) { self.engine = engine }

    func showHeadsUp(_ kind: BreakKind, for seconds: TimeInterval = 10) {
        headsUpKind = kind
        headsUpUntil = .now.addingTimeInterval(seconds)
        recompute()
    }

    func dismissHeadsUp() {
        headsUpUntil = nil
        recompute()
    }

    func show(_ toast: NotchToast, for seconds: TimeInterval = 6) {
        self.toast = toast
        toastUntil = .now.addingTimeInterval(seconds)
        recompute()
    }

    func dismissToast() {
        toast = nil
        toastUntil = nil
        recompute()
    }

    func recompute(now: Date = .now) {
        if let until = headsUpUntil, now >= until { headsUpUntil = nil }
        if let until = toastUntil, now >= until { toast = nil; toastUntil = nil }
        guard let engine else { return }

        let next: NotchContent
        if engine.isOnBreak {
            next = .hidden
            headsUpUntil = nil
        } else if engine.isInFinalCountdown {
            next = .countdown
            headsUpUntil = nil
        } else if headsUpUntil != nil, engine.phase == .working {
            next = .headsUp(headsUpKind)
        } else if let toast {
            next = .toast(toast)
        } else if isHovering {
            next = .expanded
        } else if shouldPeek(engine) {
            next = .peek
        } else {
            next = .resting
        }
        guard next != content else { return }
        withAnimation(Self.animation(from: content, to: next, reduceMotion: reduceMotion)) { content = next }
    }

    private func shouldPeek(_ engine: BreakEngine) -> Bool {
        let s = engine.settings
        guard s.notchLiveActivity else { return false }
        switch engine.phase {
        case .holding: return true
        case .working, .smartPaused:
            return s.notchRevealSeconds <= 0 || engine.timeUntilBreak <= s.notchRevealSeconds
        case .paused, .away, .offHours, .onBreak: return s.notchRevealSeconds <= 0
        }
    }

    /// Opening is lively; closing settles without overshoot so the island never
    /// "pops" past the hardware notch on its way back in.
    static func animation(from old: NotchContent, to new: NotchContent, reduceMotion: Bool) -> Animation {
        if reduceMotion { return .easeInOut(duration: 0.18) }
        if new == .hidden { return .easeIn(duration: 0.25) }
        return new.openness >= old.openness
            ? .spring(response: 0.46, dampingFraction: 0.74)
            : .spring(response: 0.36, dampingFraction: 1.0)
    }
}

/// Island sizes for each state. `notch` is the hardware notch (zero for pill screens).
enum NotchLayout {
    static let shoulder: CGFloat = 8
    static let earWidth: CGFloat = 44
    static let pillMinHeight: CGFloat = 52

    static func size(for content: NotchContent, notch: CGSize) -> CGSize {
        let band = notch.height
        switch content {
        case .hidden, .resting: return CGSize(width: notch.width, height: band)
        case .peek: return CGSize(width: notch.width + 2 * earWidth, height: band)
        case .countdown: return CGSize(width: max(notch.width + 150, 340), height: band + 62)
        case .headsUp: return CGSize(width: max(notch.width + 200, 410), height: band + 104)
        case .toast(let toast):
            let width: CGFloat = toast.secondaryAction != nil ? 450 : toast.action != nil ? 410 : 360
            return CGSize(width: max(notch.width + 170, width), height: band + 58)
        case .expanded: return CGSize(width: max(notch.width + 270, 470), height: band + 158)
        }
    }

    /// Size of the content area below the hardware band.
    static func contentSize(for content: NotchContent, notch: CGSize) -> CGSize {
        let s = size(for: content, notch: notch)
        return CGSize(width: s.width, height: max(0, s.height - notch.height))
    }

    static func bottomRadius(for content: NotchContent) -> CGFloat {
        switch content {
        case .resting, .hidden, .peek: 10
        case .countdown, .toast: 24
        case .headsUp, .expanded: 30
        }
    }
}
