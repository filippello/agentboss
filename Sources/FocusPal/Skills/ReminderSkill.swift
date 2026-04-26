import AppKit

// MARK: - Public types reused from the old ReminderManager

enum ReminderKind {
    case taskComplete       // Claude finished a response
    case awaitingInput      // Claude is blocked waiting on the user
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

// MARK: - Skill

/// The core feature: when Claude Code finishes a task or pauses for input,
/// queue a reminder. After a delay, if the user isn't already at the
/// terminal, walk the frog to centre and show a snooze bubble.
///
/// Replaces the old `ReminderManager` + the message pool that lived in
/// `AppDelegate`. State is per-session so multiple repos can have
/// independent reminders + snoozes.
final class ReminderSkill: Skill {
    let name = "reminders"

    private var ctx: SkillContext!
    private var reminders: [String: PendingReminder] = [:]   // keyed by sessionId
    private var probe = WorkActivityProbe()
    private var suppressed = false                           // .focus / .doNotDisturb

    private var firstReminderDelay: TimeInterval = 300       // 5 min
    private var awaitingInputDelay: TimeInterval = 120       // 2 min
    private var secondReminderDelay: TimeInterval = 1800     // 30 min

    /// Snooze buttons shown when the frog walks-and-talks. `BubbleButton.id`
    /// is the wire-level key the executor uses to translate clicks back here.
    private static let snoozeButtons: [BubbleButton] = [
        BubbleButton(id: "dismiss",  icon: "👍", label: "OK"),
        BubbleButton(id: "10min",    icon: "🕐", label: "10 min"),
        BubbleButton(id: "1hour",    icon: "🕐", label: "1 hour"),
        BubbleButton(id: "tomorrow", icon: "🌙", label: "Tomorrow"),
    ]

    func setup(_ context: SkillContext) {
        self.ctx = context

        if let timing = context.config.reminderTiming {
            firstReminderDelay = TimeInterval(timing.firstDelayMinutes * 60)
            secondReminderDelay = TimeInterval(timing.secondDelayMinutes * 60)
            if let awaiting = timing.awaitingInputDelayMinutes {
                awaitingInputDelay = TimeInterval(awaiting * 60)
            }
        }
    }

    func handle(_ event: AgentEvent) {
        switch event {
        case .taskCompleted(let sessionId, let repo, let summary):
            addReminder(sessionId: sessionId, repoName: repo, summary: summary ?? "Task complete", kind: .taskComplete)

        case .awaitingInput(let sessionId, let repo):
            addReminder(sessionId: sessionId, repoName: repo, summary: "Waiting for input", kind: .awaitingInput)

        case .userPrompted(let sessionId, _):
            // User is back at the keyboard for this session — drop reminder
            reminders.removeValue(forKey: sessionId)

        case .sessionStarted(let session):
            // Starting a new session counts as activity for that session id
            reminders.removeValue(forKey: session.sessionId)

        case .tick(let now, let cadence):
            if cadence == .fast {
                probe.recordCurrentFocus()
                return
            }
            checkDueReminders(now: now)

        case .modeChanged(let mode):
            suppressed = (mode != .normal)

        default:
            break
        }
    }

    // MARK: - Demo hook (used by AppDelegate's debug menu)

    /// Triggered manually by the demo button. Skips the timing pipeline and
    /// fires a reminder immediately for a fake "solana integration" session
    /// in the spicy "repeat" voice. Kept here so the demo is consistent with
    /// the real reminder flow.
    func fireDemoReminder() {
        let demoId = "demo-\(Int(Date().timeIntervalSince1970))"
        let reminder = PendingReminder(
            sessionId: demoId,
            repoName: "solana integration",
            summary: "10 minutes idle",
            kind: .taskComplete,
            completedAt: Date().addingTimeInterval(-600),
            nextReminderAt: Date(),
            reminderCount: 2,                 // triggers spicier "repeat" message
            snoozedUntil: nil,
            dismissed: false
        )
        reminders[demoId] = reminder
        emit(reminder)
    }

    // MARK: - Private

    private func addReminder(sessionId: String, repoName: String, summary: String, kind: ReminderKind) {
        let delay = (kind == .awaitingInput) ? awaitingInputDelay : firstReminderDelay

        // Claude Code's Notification hook fires automatically right after every
        // Stop hook (it's how the auto "I'm done" sound is triggered). So a
        // .awaitingInput event arriving within a few seconds of an existing
        // .taskComplete is almost always that auto-ping — NOT a genuine "I'm
        // blocked waiting for permission" signal. Treat it as noise and keep
        // the .taskComplete reminder intact.
        //
        // If the .awaitingInput arrives well after the Stop (or with no Stop
        // at all), it's a real block — upgrade the reminder.
        let autoNotificationWindow: TimeInterval = 5
        if let existing = reminders[sessionId],
           kind == .awaitingInput,
           existing.kind != .awaitingInput {
            let elapsed = Date().timeIntervalSince(existing.completedAt)
            if elapsed < autoNotificationWindow {
                // Auto-ping after Stop — ignore it, keep the existing reminder.
                return
            }
            // Standalone Notification → real block, upgrade.
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

        // Otherwise: keep an existing reminder (don't reset its timer if
        // Claude emits the same kind of event repeatedly — common for Stop).
        guard reminders[sessionId] == nil else { return }

        reminders[sessionId] = PendingReminder(
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
    }

    private func checkDueReminders(now: Date) {
        guard !suppressed else { return }

        // If the user is currently at the terminal we don't interrupt them —
        // wait until they tab away.
        guard !probe.isTerminalFocused else { return }

        for (id, reminder) in reminders {
            if reminder.dismissed { continue }
            if let snoozed = reminder.snoozedUntil, now < snoozed { continue }
            guard now >= reminder.nextReminderAt else { continue }

            // Advance the schedule before firing so a slow executor doesn't
            // cause double-fires.
            var updated = reminder
            updated.reminderCount += 1
            updated.nextReminderAt = now.addingTimeInterval(secondReminderDelay)
            updated.snoozedUntil = nil
            reminders[id] = updated

            emit(updated)
            return     // fire one at a time — the rest will catch up next tick
        }
    }

    /// Build the message + enqueue the action. Runs both for naturally-due
    /// reminders and for the demo button.
    private func emit(_ reminder: PendingReminder) {
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "that app"
        let pool = (reminder.kind == .awaitingInput) ? MessagePool.awaitingInput : MessagePool.taskComplete
        let pair = pool.randomElement() ?? pool[0]
        let template = (reminder.reminderCount <= 1) ? pair.first : pair.repeat_
        let message = MessagePool.render(
            template,
            project: reminder.repoName,
            app: appName,
            count: reminder.reminderCount
        )

        let sessionId = reminder.sessionId
        ctx.enqueue(FrogAction(
            owner: name,
            kind: .walkAndTalk(
                message: message,
                buttons: Self.snoozeButtons,
                onChosen: { [weak self] button in
                    self?.applySnooze(sessionId: sessionId, button: button)
                }
            ),
            priority: .high,
            coalesceKey: "reminder:\(sessionId)"
        ))
    }

    private func applySnooze(sessionId: String, button: BubbleButton) {
        guard var reminder = reminders[sessionId] else { return }

        switch button.id {
        case "dismiss":
            reminder.dismissed = true

        case "10min":
            let until = Date().addingTimeInterval(600)
            reminder.snoozedUntil = until
            reminder.nextReminderAt = until

        case "1hour":
            let until = Date().addingTimeInterval(3600)
            reminder.snoozedUntil = until
            reminder.nextReminderAt = until

        case "tomorrow":
            let calendar = Calendar.current
            var components = calendar.dateComponents([.year, .month, .day], from: Date())
            components.day! += 1
            components.hour = 9
            components.minute = 0
            let tomorrow = calendar.date(from: components) ?? Date().addingTimeInterval(86400)
            reminder.snoozedUntil = tomorrow
            reminder.nextReminderAt = tomorrow

        default:
            return
        }

        reminders[sessionId] = reminder
    }
}
