import AppKit

/// Conversational Pomodoro: clicking the menu item summons the frog, who
/// asks (1) how long the focus block should be, (2) how long the rest is.
/// Once focus starts the frog vanishes and other skills are silenced via
/// `.modeChanged(.focus)`. At the end of focus the frog comes back to
/// celebrate, a small countdown widget shows the remaining rest, and when
/// rest expires the frog asks "another round?".
///
/// This skill is the canonical demo of the framework: it owns its own
/// state machine and a single auxiliary widget (`PomodoroCountdownWindow`),
/// drives the frog purely through `FrogAction`s, and registers / updates a
/// menu item via `SkillContext`.
final class PomodoroSkill: Skill {
    let name = "pomodoro"

    // MARK: - State

    private enum State {
        case idle
        case askingFocus
        case askingRest(focusMinutes: Int)
        case focusing(focusMinutes: Int, restMinutes: Int, endsAt: Date)
        case resting(focusMinutes: Int, restMinutes: Int, endsAt: Date)
        case askingNext(focusMinutes: Int, restMinutes: Int)
    }

    private var ctx: SkillContext!
    private var state: State = .idle
    private var menuHandle: MenuItemHandle?
    private var restWindow: PomodoroCountdownWindow?
    private var restParty: RestPartyOrchestrator?

    // MARK: - Choice tables (kept short so the 4-button layout fits)

    private static let focusChoices: [(minutes: Int, button: BubbleButton)] = [
        (15, BubbleButton(id: "focus-15", icon: "⚡", label: "15 min")),
        (25, BubbleButton(id: "focus-25", icon: "⏱", label: "25 min")),
        (45, BubbleButton(id: "focus-45", icon: "🔥", label: "45 min")),
        (60, BubbleButton(id: "focus-60", icon: "🚀", label: "60 min")),
    ]

    private static let restChoices: [(minutes: Int, button: BubbleButton)] = [
        ( 5, BubbleButton(id: "rest-5",  icon: "☕", label: "5 min")),
        (10, BubbleButton(id: "rest-10", icon: "🧘", label: "10 min")),
        (15, BubbleButton(id: "rest-15", icon: "🌳", label: "15 min")),
    ]

    private static let nextChoices: [BubbleButton] = [
        BubbleButton(id: "again", icon: "🔁", label: "Same again"),
        BubbleButton(id: "new",   icon: "✨", label: "New round"),
        BubbleButton(id: "done",  icon: "✅", label: "Done"),
    ]

    // MARK: - Skill conformance

    func setup(_ context: SkillContext) {
        self.ctx = context
        menuHandle = context.addMenuItem(
            section: .toggles,
            title: idleTitle,
            state: .off
        ) { [weak self] in
            self?.menuClicked()
        }
    }

    func handle(_ event: AgentEvent) {
        switch event {
        case .tick(let now, let cadence):
            if cadence == .fast {
                refreshMenuTitle(now: now)
            }
            checkExpiry(now: now)

        case .frogArrivedAtCentre(let owner) where owner == name:
            // The frog has just finished walking to centre for our rest
            // walkAndTalk. Spawn the chaos right now (party + countdown)
            // so the user reads it as a single coordinated moment.
            spawnRestChaosIfNeeded()

        default:
            break
        }
    }

    /// Spawn fruits + countdown widget for the in-progress rest, if not
    /// already running. Idempotent — safe to call from frogArrivedAtCentre.
    private func spawnRestChaosIfNeeded() {
        guard case .resting(_, _, let endsAt) = state, restParty == nil else { return }

        let restSeconds = endsAt.timeIntervalSinceNow
        let party = RestPartyOrchestrator()
        party.start(restSeconds: max(restSeconds, 30))
        restParty = party

        let win = restWindow ?? PomodoroCountdownWindow()
        win.onSkip = { [weak self] in self?.skipRest() }
        win.onExpire = { [weak self] in self?.handleRestExpired() }
        win.start(prefix: "Rest", endsAt: endsAt, anchorTopLeft: belowFrogAnchor())
        restWindow = win
    }

    func teardown() {
        if let handle = menuHandle { ctx.removeMenuItem(handle) }
        restWindow?.stop()
        restParty?.stop()
        restParty = nil
    }

    // MARK: - Menu

    private var idleTitle: String { "🍅 Pomodoro" }

    private func menuClicked() {
        switch state {
        case .idle, .askingNext:
            startConversation()
        case .askingFocus, .askingRest:
            // User clicked again mid-question — abort the conversation.
            state = .idle
            updateMenuTitle()
        case .focusing, .resting:
            cancelEverything()
        }
    }

    private func startConversation() {
        state = .askingFocus
        updateMenuTitle()
        ctx.enqueue(FrogAction(
            owner: name,
            kind: .walkAndTalk(
                message: "Pomodoro time! How long do you want to focus?",
                buttons: Self.focusChoices.map { $0.button },
                onChosen: { [weak self] button in
                    self?.handleFocusChoice(button)
                }
            ),
            priority: .high,
            coalesceKey: "pomodoro-ask-focus"
        ))
    }

    private func cancelEverything() {
        restWindow?.stop()
        restWindow = nil
        restParty?.stop()
        restParty = nil
        let wasResting: Bool
        if case .resting = state { wasResting = true } else { wasResting = false }
        state = .idle
        ctx.emit(.modeChanged(.normal))
        updateMenuTitle()
        // If the frog was standing at centre during rest, walk it home now.
        if wasResting {
            ctx.dismissRunningAction()
        }
    }

    // MARK: - Conversation handlers

    private func handleFocusChoice(_ button: BubbleButton) {
        guard let choice = Self.focusChoices.first(where: { $0.button.id == button.id }) else {
            state = .idle
            updateMenuTitle()
            return
        }
        state = .askingRest(focusMinutes: choice.minutes)
        updateMenuTitle()

        // .askFollowUp keeps the frog standing — bubble swaps in place.
        ctx.enqueue(FrogAction(
            owner: name,
            kind: .askFollowUp(
                message: "\(choice.minutes) minutes of focus, got it. And how long for the rest after?",
                buttons: Self.restChoices.map { $0.button },
                onChosen: { [weak self] btn in
                    self?.handleRestChoice(btn)
                }
            ),
            priority: .high,
            coalesceKey: "pomodoro-ask-rest"
        ))
    }

    private func handleRestChoice(_ button: BubbleButton) {
        guard case .askingRest(let focusMinutes) = state,
              let choice = Self.restChoices.first(where: { $0.button.id == button.id })
        else {
            state = .idle
            updateMenuTitle()
            return
        }
        startFocus(focusMinutes: focusMinutes, restMinutes: choice.minutes)
    }

    private func handleNextChoice(_ button: BubbleButton) {
        guard case .askingNext(let focusMinutes, let restMinutes) = state else {
            state = .idle
            updateMenuTitle()
            return
        }
        switch button.id {
        case "again":
            startFocus(focusMinutes: focusMinutes, restMinutes: restMinutes)
        case "new":
            startConversation()
        default:
            state = .idle
            ctx.emit(.modeChanged(.normal))
            updateMenuTitle()
        }
    }

    // MARK: - Demo entry point (used by the menu bar's "Demo Rest Party" item)

    /// Skip the asking phase and jump straight into a rest cycle of the
    /// requested length (seconds). Same flow as `startRest` — the chaos
    /// spawns when the frog arrives at centre via `.frogArrivedAtCentre`.
    /// Default 300 = 5 min (real Pomodoro break duration, good for video
    /// recording).
    func runRestDemo(restSeconds: Int = 300) {
        let endsAt = Date().addingTimeInterval(TimeInterval(restSeconds))
        let restMinutes = max(1, restSeconds / 60)
        state = .resting(focusMinutes: 25, restMinutes: restMinutes, endsAt: endsAt)
        updateMenuTitle()
        NSSound.beep()

        ctx.enqueue(FrogAction(
            owner: name,
            kind: .walkAndTalk(
                message: "What a mess in here! Go rest, the crew will tidy up. \(restMinutes) min.",
                buttons: [],
                onChosen: { _ in }
            ),
            priority: .high,
            coalesceKey: "pomodoro-rest"
        ))
    }

    // MARK: - Phase transitions

    private func startFocus(focusMinutes: Int, restMinutes: Int) {
        let endsAt = Date().addingTimeInterval(TimeInterval(focusMinutes * 60))
        state = .focusing(focusMinutes: focusMinutes, restMinutes: restMinutes, endsAt: endsAt)
        ctx.emit(.modeChanged(.focus))
        updateMenuTitle()

        let pep = MessagePool.pomodoroStart.randomElement() ?? "\(focusMinutes) min — let's go!"
        ctx.enqueue(FrogAction(
            owner: name,
            kind: .popAndSay(
                message: "\(pep) (\(focusMinutes) min focus, \(restMinutes) min rest)",
                duration: 4.5
            ),
            priority: .normal,
            coalesceKey: "pomodoro-start"
        ))
    }

    private func startRest(focusMinutes: Int, restMinutes: Int) {
        let endsAt = Date().addingTimeInterval(TimeInterval(restMinutes * 60))
        state = .resting(focusMinutes: focusMinutes, restMinutes: restMinutes, endsAt: endsAt)
        updateMenuTitle()
        NSSound.beep()

        // Walk the frog out to centre and KEEP it standing there for the
        // whole rest. The chaos (party + countdown) is spawned by the
        // `.frogArrivedAtCentre` event handler the instant the frog stops
        // walking — see `spawnRestChaosIfNeeded`.
        ctx.enqueue(FrogAction(
            owner: name,
            kind: .walkAndTalk(
                message: "What a mess in here! Go rest, the crew will tidy up. \(restMinutes) min.",
                buttons: [],
                onChosen: { _ in /* no buttons during rest */ }
            ),
            priority: .high,
            coalesceKey: "pomodoro-rest"
        ))
    }

    /// Where to put the rest countdown widget — just below the frog at
    /// screen centre, since the frog walks to centre at the start of rest.
    private func belowFrogAnchor() -> NSPoint {
        guard let screen = NSScreen.main else { return NSPoint(x: 100, y: 100) }
        let visible = screen.visibleFrame
        return NSPoint(
            x: visible.midX - 80,
            y: visible.midY - 56
        )
    }

    private func skipRest() {
        guard case .resting(let focusMinutes, let restMinutes, _) = state else { return }
        restWindow?.stop()
        restWindow = nil
        finishRest(focusMinutes: focusMinutes, restMinutes: restMinutes)
    }

    private func handleRestExpired() {
        guard case .resting(let focusMinutes, let restMinutes, _) = state else { return }
        restWindow = nil
        finishRest(focusMinutes: focusMinutes, restMinutes: restMinutes)
    }

    private func finishRest(focusMinutes: Int, restMinutes: Int) {
        // Tear down the rest party — fruits and harvesters all go home.
        restParty?.stop()
        restParty = nil
        restWindow?.stop()
        restWindow = nil

        state = .askingNext(focusMinutes: focusMinutes, restMinutes: restMinutes)
        ctx.emit(.modeChanged(.normal))
        updateMenuTitle()

        // The frog has been standing at centre for the whole rest — pivot
        // its current walkAndTalk to the next-round question in place. No
        // walking home and back; the bubble + buttons just swap.
        ctx.swapToFollowUp(
            message: "Break's done! Want another \(focusMinutes)-min round?",
            buttons: Self.nextChoices,
            onChosen: { [weak self] btn in
                self?.handleNextChoice(btn)
            }
        )
    }

    // MARK: - Tick driven

    private func checkExpiry(now: Date) {
        if case .focusing(let focusMinutes, let restMinutes, let endsAt) = state, now >= endsAt {
            startRest(focusMinutes: focusMinutes, restMinutes: restMinutes)
        }
        // .resting expiry is driven by PomodoroCountdownWindow.onExpire (1s tick).
    }

    // MARK: - Menu title

    private func refreshMenuTitle(now: Date) {
        switch state {
        case .focusing(_, _, let endsAt):
            updateMenuTitle(remaining: endsAt.timeIntervalSince(now), prefix: "■ Cancel Focus")
        case .resting(_, _, let endsAt):
            updateMenuTitle(remaining: endsAt.timeIntervalSince(now), prefix: "☕ Rest")
        default:
            break
        }
    }

    private func updateMenuTitle() {
        guard let handle = menuHandle else { return }
        let title: String
        let menuState: NSControl.StateValue
        switch self.state {
        case .idle:
            title = idleTitle
            menuState = .off
        case .askingFocus, .askingRest:
            title = "🍅 Pomodoro (asking…)"
            menuState = .mixed
        case .focusing(_, _, let endsAt):
            title = formatTitle(prefix: "■ Cancel Focus", remaining: endsAt.timeIntervalSinceNow)
            menuState = .on
        case .resting(_, _, let endsAt):
            title = formatTitle(prefix: "☕ Rest", remaining: endsAt.timeIntervalSinceNow)
            menuState = .on
        case .askingNext:
            title = "🍅 Pomodoro (next?)"
            menuState = .mixed
        }
        ctx.updateMenuItem(handle, title: title, state: menuState)
    }

    private func updateMenuTitle(remaining: TimeInterval, prefix: String) {
        guard let handle = menuHandle else { return }
        ctx.updateMenuItem(handle, title: formatTitle(prefix: prefix, remaining: remaining), state: .on)
    }

    private func formatTitle(prefix: String, remaining: TimeInterval) -> String {
        let secs = max(0, Int(remaining))
        return String(format: "%@ (%02d:%02d)", prefix, secs / 60, secs % 60)
    }
}
