import AppKit

protocol HealthReminderDelegate: AnyObject {
    func healthReminderShouldFire(message: String)
}

/// Fires a brief "take a break" reminder at a configurable interval.
/// Uses the same character (Ninja Frog) in .popAndSay mode — no walking, no buttons.
class HealthReminder {
    weak var delegate: HealthReminderDelegate?

    /// Master on/off switch. Starts from config, can be toggled via menu bar.
    var enabled: Bool {
        didSet {
            if enabled { scheduleNext() } else { timer?.invalidate() }
        }
    }

    /// Only fire when there's sign of active work: a Claude session is alive
    /// OR a terminal/editor was focused within the last 5 min.
    var onlyWhenWorking: Bool = true

    private let intervalSeconds: TimeInterval
    private let messages: [String]
    private var sessionTracker: SessionTracker?
    private var timer: Timer?
    private var lastTerminalFocusAt: Date?
    private var focusCheckTimer: Timer?

    private let workAppBundleIds: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92",
        "net.kovidgoyal.kitty",
        "co.zeit.hyper",
    ]

    init(config: HealthReminderConfig, sessionTracker: SessionTracker?) {
        self.enabled = config.enabled
        self.intervalSeconds = TimeInterval(config.intervalMinutes * 60)
        self.messages = config.messages.isEmpty ? ["Take a break! Stretch, drink water."] : config.messages
        self.onlyWhenWorking = config.onlyWhenWorking ?? true
        self.sessionTracker = sessionTracker

        // Track last time user was in a terminal/editor
        focusCheckTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.recordFocusIfWorking()
        }
        recordFocusIfWorking()

        if enabled { scheduleNext() }
    }

    private func scheduleNext() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: false) { [weak self] _ in
            self?.maybeFire()
        }
    }

    private func maybeFire() {
        guard enabled else { return }

        if onlyWhenWorking && !isUserWorking() {
            // Not working right now — defer; check again in 5 min
            timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { [weak self] _ in
                self?.maybeFire()
            }
            return
        }

        let message = messages.randomElement() ?? messages[0]
        delegate?.healthReminderShouldFire(message: message)

        // Schedule next one
        scheduleNext()
    }

    /// Called by AppDelegate after the pop animation is done (so reminders don't stack).
    func didFinishShowing() {
        // Already rescheduled in maybeFire — nothing to do
    }

    private func recordFocusIfWorking() {
        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        if workAppBundleIds.contains(bundleId) {
            lastTerminalFocusAt = Date()
        }
    }

    private func isUserWorking() -> Bool {
        // Any Claude session alive?
        if let tracker = sessionTracker, tracker.activeCount > 0 {
            return true
        }
        // Terminal focused recently?
        if let lastFocus = lastTerminalFocusAt,
           Date().timeIntervalSince(lastFocus) < 300 {
            return true
        }
        return false
    }

    deinit {
        timer?.invalidate()
        focusCheckTimer?.invalidate()
    }
}
