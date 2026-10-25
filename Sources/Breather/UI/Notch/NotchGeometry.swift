import AppKit

/// Where the hardware notch is on a screen, or where a pill would go on a screen without one.
struct NotchGeometry: Equatable {
    /// Notch rect in global AppKit coordinates (origin bottom-left). Zero height when there's no notch.
    var notch: CGRect
    var screenFrame: CGRect
    var menuBarHeight: CGFloat
    var hasNotch: Bool

    init(screen: NSScreen) {
        screenFrame = screen.frame
        let top = screen.safeAreaInsets.top
        if top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            hasNotch = true
            let minX = screen.frame.minX + left.width
            let maxX = screen.frame.maxX - right.width
            notch = CGRect(x: minX, y: screen.frame.maxY - top, width: maxX - minX, height: top)
            menuBarHeight = top
        } else {
            hasNotch = false
            let bar = max(24, screen.frame.maxY - screen.visibleFrame.maxY)
            notch = CGRect(x: screen.frame.midX - 100, y: screen.frame.maxY - bar, width: 200, height: 0)
            menuBarHeight = bar
        }
    }

    var centerX: CGFloat { notch.midX }

    /// Height of the band the hardware notch occupies; 0 for pill screens.
    var bandHeight: CGFloat { hasNotch ? notch.height : 0 }

    /// Where alerts go, per the user's choice; falls back to the main screen.
    @MainActor
    static func preferredScreen(_ choice: AlertDisplay = .notch) -> NSScreen? {
        switch choice {
        case .notch:
            return NSScreen.screens.first { $0.safeAreaInsets.top > 0 && $0.auxiliaryTopLeftArea != nil } ?? NSScreen.main
        case .main:
            return NSScreen.screens.first
        case .mouse:
            let point = NSEvent.mouseLocation
            return NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        }
    }
}
