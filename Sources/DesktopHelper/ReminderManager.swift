import AppKit

enum SnoozeOption {
    case dismiss        // don't remind again
    case tenMinutes
    case oneHour
    case tomorrow
}

enum ReminderKind {
    case taskComplete      // Claude finished a response — maybe truly done
    case awaitingInput     // Claude is blocked waiting for approval/input
}

struct PendingReminder {
    let sessionId: String
    let repoName: String
    let summary: String
    let kind: ReminderKind
    let completedAt: Date
    var nextReminderAt: Date
    var reminderCount: Int
    var snoozedUntil: Date?
    var dismissed: Bool
}

protocol ReminderManagerDelegate: AnyObject {
    func reminderShouldFire(reminder: PendingReminder)
}

class ReminderManager {
    weak var delegate: ReminderManagerDelegate?

    private var reminders: [String: PendingReminder] = [:]  // keyed by sessionId
    private var checkTimer: Timer?

    private let terminalBundleIds: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92",
        "net.kovidgoyal.kitty",
        "co.zeit.hyper",
    ]

    /// Delay before first reminder when Claude finished a task (seconds)
    var firstReminderDelay: TimeInterval = 300   // 5 minutes

    /// Delay before first reminder when Claude is waiting for user input (seconds)
    var awaitingInputDelay: TimeInterval = 120   // 2 minutes

    /// Time after first reminder before second reminder (seconds)
    var secondReminderDelay: TimeInterval = 1800  // 30 minutes

    private var isShowingReminder = false

    init() {
        checkTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.checkReminders()
        }
    }

    func addReminder(sessionId: String, repoName: String, summary: String, kind: ReminderKind = .taskComplete) {
        let delay: TimeInterval = (kind == .awaitingInput) ? awaitingInputDelay : firstReminderDelay

        // If there's already a reminder for this session, upgrading from taskComplete
        // to awaitingInput is allowed (Claude needs input — more urgent). Otherwise keep existing.
        if let existing = reminders[sessionId] {
            if kind == .awaitingInput && existing.kind != .awaitingInput {
                // Upgrade — use shorter delay
                var updated = existing
                updated.nextReminderAt = Date().addingTimeInterval(delay)
                updated.snoozedUntil = nil
                updated.dismissed = false
                reminders[sessionId] = PendingReminder(
                    sessionId: sessionId,
                    repoName: repoName,
                    summary: summary,
                    kind: .awaitingInput,
                    completedAt: Date(),
                    nextReminderAt: Date().addingTimeInterval(delay),
                    reminderCount: existing.reminderCount,
                    snoozedUntil: nil,
                    dismissed: false
                )
                return
            }
            // Otherwise keep existing reminder in place
        }

        let reminder = PendingReminder(
            sessionId: sessionId,
            repoName: repoName,
            summary: summary,
            kind: kind,
            completedAt: Date(),
            nextReminderAt: Date().addingTimeInterval(delay),
            reminderCount: 0,
            snoozedUntil: nil,
            dismissed: false
        )
        reminders[sessionId] = reminder
    }

    func snooze(sessionId: String, option: SnoozeOption) {
        guard var reminder = reminders[sessionId] else { return }
        isShowingReminder = false

        switch option {
        case .dismiss:
            reminder.dismissed = true

        case .tenMinutes:
            reminder.snoozedUntil = Date().addingTimeInterval(600)
            reminder.nextReminderAt = Date().addingTimeInterval(600)

        case .oneHour:
            reminder.snoozedUntil = Date().addingTimeInterval(3600)
            reminder.nextReminderAt = Date().addingTimeInterval(3600)

        case .tomorrow:
            // Next day at 9 AM
            let calendar = Calendar.current
            var components = calendar.dateComponents([.year, .month, .day], from: Date())
            components.day! += 1
            components.hour = 9
            components.minute = 0
            let tomorrow = calendar.date(from: components) ?? Date().addingTimeInterval(86400)
            reminder.snoozedUntil = tomorrow
            reminder.nextReminderAt = tomorrow
        }

        reminders[sessionId] = reminder
    }

    /// Called when user interacts with a Claude Code session (starts new work)
    func sessionBecameActive(sessionId: String) {
        reminders.removeValue(forKey: sessionId)
    }

    func onReminderDismissed() {
        isShowingReminder = false
    }

    private func checkReminders() {
        guard !isShowingReminder else { return }

        let now = Date()
        let inTerminal = isTerminalFocused()
        if inTerminal { return }

        for (id, reminder) in reminders {
            if reminder.dismissed { continue }

            // Check if snoozed
            if let snoozed = reminder.snoozedUntil, now < snoozed { continue }

            // Check if it's time to fire
            if now >= reminder.nextReminderAt {
                isShowingReminder = true

                // Update for next reminder (30 min later)
                var updated = reminder
                updated.reminderCount += 1
                updated.nextReminderAt = now.addingTimeInterval(secondReminderDelay)
                updated.snoozedUntil = nil
                reminders[id] = updated

                delegate?.reminderShouldFire(reminder: updated)
                return  // one reminder at a time
            }
        }
    }

    private func isTerminalFocused() -> Bool {
        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        return terminalBundleIds.contains(bundleId)
    }

    /// The most recent reminder that was fired (for snooze actions)
    var lastFiredSessionId: String? {
        reminders.first(where: { $0.value.reminderCount > 0 && !$0.value.dismissed })?.key
    }

    var activeReminderCount: Int {
        reminders.values.filter { !$0.dismissed }.count
    }

    deinit {
        checkTimer?.invalidate()
    }
}
