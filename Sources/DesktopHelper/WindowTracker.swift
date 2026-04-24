import AppKit
import CoreGraphics

/// Finds the bounds of the focused window using CGWindowList (no Accessibility permissions needed).
/// Used to position the frog over the focused window instead of always at the main screen's corner.
class WindowTracker {
    private let characterSize: CGFloat
    private let minWindowWidth: CGFloat = 300
    private let minWindowHeight: CGFloat = 200

    init(characterSize: CGFloat) {
        self.characterSize = characterSize
    }

    /// Returns where the frog should sit at rest.
    /// Top-right of the focused window if it's large enough; otherwise bottom-right of main screen.
    func preferredRestPosition() -> NSPoint {
        if let windowBounds = focusedWindowBounds(),
           windowBounds.width >= minWindowWidth,
           windowBounds.height >= minWindowHeight {
            return topRightOfWindow(windowBounds)
        }
        return bottomRightOfMainScreen()
    }

    /// Get bounds of the focused window (frontmost app's top window at layer 0).
    /// Returns bounds in AppKit coordinates (origin bottom-left).
    private func focusedWindowBounds() -> NSRect? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let frontPID = frontApp.processIdentifier

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for info in windowList {
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32, pid == frontPID else { continue }
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any] else { continue }

            let cgRect = CGRect(
                x: boundsDict["X"] as? CGFloat ?? 0,
                y: boundsDict["Y"] as? CGFloat ?? 0,
                width: boundsDict["Width"] as? CGFloat ?? 0,
                height: boundsDict["Height"] as? CGFloat ?? 0
            )

            // CGWindowBounds uses top-left origin with Y flipped relative to AppKit.
            // Convert to AppKit coordinates using the screen that contains the window.
            return convertToAppKit(cgRect: cgRect)
        }

        return nil
    }

    /// Convert CGWindowList rect (top-left origin) to AppKit rect (bottom-left origin).
    /// AppKit's Y increases upward; the global "main screen" defines the coordinate origin.
    private func convertToAppKit(cgRect: CGRect) -> NSRect {
        // Total height spans all screens; but AppKit global origin is at the bottom of the primary screen.
        // To flip correctly across multi-monitor, we use the primary screen's frame as reference.
        guard let primaryScreen = NSScreen.screens.first else {
            return NSRect(origin: .zero, size: cgRect.size)
        }
        let primaryHeight = primaryScreen.frame.height

        return NSRect(
            x: cgRect.origin.x,
            y: primaryHeight - cgRect.origin.y - cgRect.height,
            width: cgRect.width,
            height: cgRect.height
        )
    }

    /// Top-right-ish corner of the window, inset so the frog stays comfortably visible.
    private func topRightOfWindow(_ windowRect: NSRect) -> NSPoint {
        let offsetX: CGFloat = 140  // inset from right edge
        let offsetY: CGFloat = 60   // below top edge (avoid title bar + menu bar)

        var pos = NSPoint(
            x: windowRect.maxX - characterSize - offsetX,
            y: windowRect.maxY - characterSize - offsetY
        )

        // Clamp to the visibleFrame of the screen that contains the window,
        // so the frog never ends up behind the menu bar or off-screen.
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(windowRect) }) ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let maxX = visible.maxX - characterSize - 4
            let maxY = visible.maxY - characterSize - 4
            let minX = visible.minX + 4
            let minY = visible.minY + 4
            pos.x = max(minX, min(pos.x, maxX))
            pos.y = max(minY, min(pos.y, maxY))
        }

        return pos
    }

    /// Fallback: bottom-right of the main screen, above the dock.
    private func bottomRightOfMainScreen() -> NSPoint {
        guard let screen = NSScreen.main else { return NSPoint(x: 100, y: 100) }
        let visible = screen.visibleFrame
        return NSPoint(
            x: visible.maxX - characterSize - 20,
            y: visible.minY + 10
        )
    }
}
