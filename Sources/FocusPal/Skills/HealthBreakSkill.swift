import AppKit

/// Periodically reminds the user to take a break — stretch, drink water,
/// look away from the screen. Suppressed when the user is AFK or when an
/// app-wide focus mode (`AppMode.focus` / `.doNotDisturb`) is active.
///
/// This is a low-priority, coalescing skill: if the frog is busy showing
/// something else when the break is due, the registry replaces any older
/// pending health pop with the newest one rather than queueing more.
final class HealthBreakSkill: Skill {
    let name = "health"

    private var ctx: SkillContext!
    private var enabled: Bool = true
    private var suppressed: Bool = false
    private var nextDueAt: Date?
    private var intervalSeconds: TimeInterval = 7200   // 2h default
    private var menuToggle: MenuItemHandle?
    private let probe = WorkActivityProbe()

    func setup(_ context: SkillContext) {
        self.ctx = context

        let config = context.config.healthReminder ?? .default
        self.enabled = config.enabled
        self.intervalSeconds = TimeInterval(config.intervalMinutes * 60)
        self.nextDueAt = Date().addingTimeInterval(intervalSeconds)

        menuToggle = context.addMenuItem(
            section: .toggles,
            title: "Health Reminders",
            state: enabled ? .on : .off
        ) { [weak self] in
            self?.toggle()
        }
    }

    func handle(_ event: AgentEvent) {
        switch event {
        case .tick(let now, let cadence):
            // Sample focus often (fast tick), check whether to fire less often.
            if cadence == .fast {
                probe.recordCurrentFocus()
                return
            }
            maybeFire(now: now)

        case .modeChanged(let mode):
            suppressed = (mode != .normal)

        default:
            break
        }
    }

    func teardown() {
        if let handle = menuToggle { ctx.removeMenuItem(handle) }
    }

    // MARK: - Private

    private func maybeFire(now: Date) {
        guard enabled, !suppressed,
              let due = nextDueAt, now >= due
        else { return }

        let onlyWhenWorking = ctx.config.healthReminder?.onlyWhenWorking ?? true
        if onlyWhenWorking {
            let activeCount = ctx.sessions.count
            guard probe.isUserWorking(activeSessionCount: activeCount, now: now) else {
                // User AFK — defer 5 minutes and check again on next slow tick
                nextDueAt = now.addingTimeInterval(300)
                return
            }
        }

        let messages = ctx.config.healthReminder?.messages ?? ["Take a break! Stretch, drink water."]
        let message = messages.randomElement() ?? messages[0]

        ctx.enqueue(FrogAction(
            owner: name,
            kind: .popAndSay(message: message, duration: 4.0),
            priority: .low,
            coalesceKey: "health"          // never stack health pops
        ))

        nextDueAt = now.addingTimeInterval(intervalSeconds)
    }

    private func toggle() {
        enabled.toggle()
        if let handle = menuToggle {
            ctx.updateMenuItem(handle, title: nil, state: enabled ? .on : .off)
        }
        if enabled {
            // Reset the schedule so we don't fire immediately after a long pause
            nextDueAt = Date().addingTimeInterval(intervalSeconds)
        }
    }
}

// MARK: - Default config fallback

private extension HealthReminderConfig {
    static let `default` = HealthReminderConfig(
        enabled: true,
        intervalMinutes: 120,
        onlyWhenWorking: true,
        messages: [
            "Take a break! Stretch, drink water.",
            "Look away from the screen for 20 seconds.",
            "Quick PSA from your spine: please stand up.",
        ]
    )
}
