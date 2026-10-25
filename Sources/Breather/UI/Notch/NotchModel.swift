import SwiftUI
import Observation

struct NotchToast: Equatable, Identifiable {
    enum Action: Equatable { case undoNaturalBreak, resume }
    var id = UUID()
    var symbol: String
    var tint: Color
    var title: String
    var subtitle: String?
    var action: Action?
    var actionTitle: String?
}

enum NotchContent: Equatable {
    case resting
    case expanded
    case headsUp(BreakKind)
    case countdown
    case toast(NotchToast)
    /// During a break the overlay owns the screen.
    case hidden
}

/// Decides what the island shows. Higher-priority content wins:
/// countdown → heads-up → toast → hover dashboard → resting.
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
    @ObservationIgnored var animation: Animation? = .spring(response: 0.42, dampingFraction: 0.8)

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

        let next: NotchContent
        if engine?.isOnBreak == true {
            next = .hidden
            headsUpUntil = nil
        } else if engine?.isInFinalCountdown == true {
            next = .countdown
            headsUpUntil = nil
        } else if headsUpUntil != nil, engine?.phase == .working {
            next = .headsUp(headsUpKind)
        } else if let toast {
            next = .toast(toast)
        } else if isHovering {
            next = .expanded
        } else {
            next = .resting
        }
        if next != content {
            withAnimation(animation) { content = next }
        }
    }
}

/// Island sizes for each state. `notch` is the hardware notch (or a nominal size for pills).
enum NotchLayout {
    static let shoulder: CGFloat = 8
    static let earWidth: CGFloat = 46

    static func size(for content: NotchContent, notch: CGSize, liveActivity: Bool) -> CGSize {
        let band = notch.height
        switch content {
        case .hidden: return CGSize(width: notch.width, height: band)
        case .resting:
            return liveActivity ? CGSize(width: notch.width + 2 * earWidth, height: band) : CGSize(width: notch.width, height: band)
        case .countdown: return CGSize(width: max(notch.width + 2 * 70, 320), height: band + 64)
        case .headsUp: return CGSize(width: max(notch.width + 180, 400), height: band + 92)
        case .toast(let toast): return CGSize(width: max(notch.width + 160, toast.action == nil ? 360 : 400), height: band + 56)
        case .expanded: return CGSize(width: max(notch.width + 260, 460), height: band + 168)
        }
    }

    static func bottomRadius(for content: NotchContent) -> CGFloat {
        switch content {
        case .resting, .hidden: 10
        case .countdown, .toast: 22
        case .headsUp, .expanded: 28
        }
    }
}
