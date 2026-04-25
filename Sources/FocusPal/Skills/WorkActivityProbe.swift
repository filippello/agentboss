import AppKit

/// Detects whether the user is "actively working" — i.e. has a Claude Code
/// session alive **or** has touched a terminal/editor recently.
///
/// Shared by HealthBreakSkill (decides whether to fire a break pop) and
/// ReminderSkill (decides whether to suppress a reminder when the user is
/// already at the keyboard). Centralised so the bundle ID list is in one place.
final class WorkActivityProbe {
    private let workAppBundleIds: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92",
        "net.kovidgoyal.kitty",
        "co.zeit.hyper",
    ]

    /// Most recent moment a terminal/editor was the frontmost app.
    /// Updated by callers via `recordCurrentFocus()` (typically on a tick).
    private(set) var lastTerminalFocusAt: Date?

    /// Was the frontmost app a terminal/editor *right now*?
    var isTerminalFocused: Bool {
        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        return workAppBundleIds.contains(bundleId)
    }

    /// Take a sample. If the frontmost app is a terminal/editor, stamp
    /// `lastTerminalFocusAt` with the current time.
    func recordCurrentFocus() {
        if isTerminalFocused {
            lastTerminalFocusAt = Date()
        }
    }

    /// "Working" = a Claude session is alive, or the user touched a
    /// terminal/editor in the last 5 minutes.
    func isUserWorking(activeSessionCount: Int, now: Date = Date()) -> Bool {
        if activeSessionCount > 0 { return true }
        if let last = lastTerminalFocusAt, now.timeIntervalSince(last) < 300 { return true }
        return false
    }
}
