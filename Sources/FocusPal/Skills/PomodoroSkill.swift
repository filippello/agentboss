import AppKit

/// 25-minute focus timer. While a focus block is running, the skill emits
/// `.modeChanged(.focus)` so other skills (ReminderSkill, HealthBreakSkill)
/// suppress their pops. When the block expires the frog hops out with a
/// short celebration + system beep.
///
/// This skill is the canonical "demo" for the Skill API: it adds a menu
/// item, owns its own state, communicates with peers via a single broadcast
/// event, and renders a frog action — all without touching `AppDelegate`.
final class PomodoroSkill: Skill {
    let name = "pomodoro"

    /// How long a focus block lasts. Hardcoded for v0.2; future config knob.
    private let focusDurationSeconds: TimeInterval = 25 * 60

    private var ctx: SkillContext!
    private var endsAt: Date?
    private var menuHandle: MenuItemHandle?

    func setup(_ context: SkillContext) {
        self.ctx = context
        menuHandle = context.addMenuItem(
            section: .toggles,
            title: idleTitle,
            state: .off
        ) { [weak self] in
            self?.toggle()
        }
    }

    func handle(_ event: AgentEvent) {
        switch event {
        case .tick(let now, let cadence):
            // Update the menu countdown on every fast tick so users see the
            // remaining minutes when they open the menu.
            if cadence == .fast {
                refreshMenuTitle(now: now)
            }
            checkExpiry(now: now)
        default:
            break
        }
    }

    func teardown() {
        if let handle = menuHandle { ctx.removeMenuItem(handle) }
    }

    // MARK: - Private

    private var idleTitle: String { "▶ Start 25-min Focus" }

    private var isFocusing: Bool { endsAt != nil }

    private func toggle() {
        if isFocusing { cancel() } else { start() }
    }

    private func start() {
        endsAt = Date().addingTimeInterval(focusDurationSeconds)
        ctx.emit(.modeChanged(.focus))
        refreshMenuTitle(now: Date())

        let message = MessagePool.pomodoroStart.randomElement() ?? "25 minutes — let's go!"
        ctx.enqueue(FrogAction(
            owner: name,
            kind: .popAndSay(message: message, duration: 4.5),
            priority: .normal,
            coalesceKey: "pomodoro-start"
        ))
    }

    /// User cancelled mid-block — no celebration, just resume normal mode.
    private func cancel() {
        endsAt = nil
        ctx.emit(.modeChanged(.normal))
        if let handle = menuHandle {
            ctx.updateMenuItem(handle, title: idleTitle, state: .off)
        }
    }

    /// Natural end-of-block — celebrate + beep + resume normal mode.
    private func checkExpiry(now: Date) {
        guard let end = endsAt, now >= end else { return }
        endsAt = nil
        ctx.emit(.modeChanged(.normal))
        if let handle = menuHandle {
            ctx.updateMenuItem(handle, title: idleTitle, state: .off)
        }

        ctx.enqueue(FrogAction(
            owner: name,
            kind: .popAndSay(
                message: "Focus block done! 25 minutes — stretch, breathe, take a sip.",
                duration: 5.0
            ),
            priority: .normal,
            coalesceKey: "pomodoro-end"
        ))
        NSSound.beep()
    }

    private func refreshMenuTitle(now: Date) {
        guard isFocusing, let end = endsAt, let handle = menuHandle else { return }
        let remaining = max(0, end.timeIntervalSince(now))
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        let title = String(format: "■ Cancel Focus (%02d:%02d)", minutes, seconds)
        ctx.updateMenuItem(handle, title: title, state: .on)
    }
}
