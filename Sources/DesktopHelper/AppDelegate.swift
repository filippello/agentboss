import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var characterWindow: CharacterWindow!
    private var stateMachine: CharacterStateMachine!
    private var navigator: ScreenEdgeNavigator!
    private var claudeMonitor: ClaudeCodeMonitor!
    private var sessionTracker: SessionTracker!
    private var reminderManager: ReminderManager!
    private var healthReminder: HealthReminder!
    private var windowTracker: WindowTracker!
    private var speechController: SpeechController!
    private var actionBubbles: ActionBubblesWindow!
    private var pendingMessage: String?
    private var restPosition: NSPoint?
    private var currentSessionId: String?

    // Menu
    private var sessionMenuItems: [NSMenuItem] = []
    private let sessionsHeaderTag = 201
    private let healthToggleTag = 202

    /// Characters bundled with the app. Must match folder names under
    /// `Sources/DesktopHelper/Resources/Main Characters/`.
    static let availableCharacters = ["Ninja Frog", "Mask Dude", "Pink Man", "Virtual Guy"]

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Auto-install Claude Code hooks on first run
        let installer = HookInstaller()
        _ = installer.ensureHooksInstalled()

        setupWindowTracker()
        setupMenuBar()
        setupCharacterWindow()
        setupStateMachine()
        setupActionBubbles()
        setupClaudeCodeMonitor()
        setupReminderManager()
        setupSessionTracker()
        setupHealthReminder()
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateMenuBarTitle(count: 0)

        let menu = NSMenu()

        let header = NSMenuItem(title: "Claude Code Sessions", action: nil, keyEquivalent: "")
        header.tag = sessionsHeaderTag
        header.isEnabled = false
        header.attributedTitle = NSAttributedString(
            string: "Claude Code Sessions",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 12), .foregroundColor: NSColor.labelColor]
        )
        menu.addItem(header)
        menu.addItem(NSMenuItem.separator())

        let noSessions = NSMenuItem(title: "  No active sessions", action: nil, keyEquivalent: "")
        noSessions.tag = 300
        noSessions.isEnabled = false
        menu.addItem(noSessions)

        menu.addItem(NSMenuItem.separator())

        let healthToggle = NSMenuItem(
            title: "Health Reminders",
            action: #selector(toggleHealthReminders),
            keyEquivalent: ""
        )
        healthToggle.tag = healthToggleTag
        healthToggle.target = self
        // Check state reflects enabled status — set after config loads in setupHealthReminder
        healthToggle.state = .on
        menu.addItem(healthToggle)

        // Character submenu
        let characterItem = NSMenuItem(title: "Character", action: nil, keyEquivalent: "")
        let characterSubmenu = NSMenu()
        let currentCharacter = ConfigManager.shared.config.characterName ?? "Ninja Frog"
        for name in Self.availableCharacters {
            let item = NSMenuItem(
                title: name,
                action: #selector(selectCharacter(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = name
            item.state = (name == currentCharacter) ? .on : .off
            characterSubmenu.addItem(item)
        }
        characterItem.submenu = characterSubmenu
        menu.addItem(characterItem)

        menu.addItem(NSMenuItem.separator())

        let demoItem = NSMenuItem(
            title: "🎬 Run Demo (solana integration)",
            action: #selector(runDemo),
            keyEquivalent: "d"
        )
        demoItem.target = self
        menu.addItem(demoItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    @objc private func selectCharacter(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }

        // Persist selection to user override config
        ConfigManager.shared.setCharacterName(name)

        // Hot-swap sprites on the live CharacterView
        characterView()?.reloadCharacter(named: name)

        // Update menu checkmarks
        if let submenu = sender.menu {
            for item in submenu.items {
                item.state = (item.representedObject as? String == name) ? .on : .off
            }
        }
    }

    @objc private func runDemo() {
        // Fire a fake "task complete" reminder 5 seconds from now
        // with project "solana integration" and a repeat-count high enough
        // to use the spicier repeat message ("has been done for a while now").
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self = self else { return }
            let fakeReminder = PendingReminder(
                sessionId: "demo-\(Int(Date().timeIntervalSince1970))",
                repoName: "solana integration",
                summary: "10 minutes idle",
                kind: .taskComplete,
                completedAt: Date().addingTimeInterval(-600),   // 10 min ago
                nextReminderAt: Date(),
                reminderCount: 2,                               // triggers "repeat" variant
                snoozedUntil: nil,
                dismissed: false
            )
            self.reminderShouldFire(reminder: fakeReminder)
        }
    }

    @objc private func toggleHealthReminders() {
        guard healthReminder != nil else { return }
        healthReminder.enabled.toggle()
        if let item = statusItem.menu?.item(withTag: healthToggleTag) {
            item.state = healthReminder.enabled ? .on : .off
        }
    }

    private func updateMenuBarTitle(count: Int) {
        if let button = statusItem.button {
            button.title = count > 0 ? "🐸 \(count)" : "🐸"
        }
    }

    private func updateSessionsMenu(_ sessions: [SessionInfo]) {
        guard let menu = statusItem.menu else { return }

        for item in sessionMenuItems { menu.removeItem(item) }
        sessionMenuItems.removeAll()
        if let p = menu.item(withTag: 300) { menu.removeItem(p) }

        guard let headerIndex = menu.items.firstIndex(where: { $0.tag == sessionsHeaderTag }) else { return }
        var insertIndex = headerIndex + 1

        if sessions.isEmpty {
            let noSessions = NSMenuItem(title: "  No active sessions", action: nil, keyEquivalent: "")
            noSessions.tag = 300
            noSessions.isEnabled = false
            menu.insertItem(noSessions, at: insertIndex)
        } else {
            for session in sessions {
                let title = "  ⚡ \(session.repoName) — \(session.timeAgo)"
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.isEnabled = false
                item.attributedTitle = NSAttributedString(
                    string: title,
                    attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.labelColor]
                )
                menu.insertItem(item, at: insertIndex)
                sessionMenuItems.append(item)
                insertIndex += 1
            }
        }

        updateMenuBarTitle(count: sessions.count)
    }

    // MARK: - Setup

    private func setupCharacterWindow() {
        characterWindow = CharacterWindow()
        characterWindow.orderOut(nil)
        restPosition = characterWindow.frame.origin

        // Make character clickable — shows action bubbles
        characterWindow.ignoresMouseEvents = false
        characterWindow.acceptsMouseMovedEvents = true
    }

    private func setupStateMachine() {
        stateMachine = CharacterStateMachine()
        stateMachine.delegate = self
        navigator = ScreenEdgeNavigator(window: characterWindow)
        navigator.delegate = self

        // Set up click handler on character
        if let view = characterView() {
            view.clickDelegate = self
        }
    }

    private func setupActionBubbles() {
        actionBubbles = ActionBubblesWindow()
        actionBubbles.actionDelegate = self
    }

    private func setupClaudeCodeMonitor() {
        claudeMonitor = ClaudeCodeMonitor()
        claudeMonitor.delegate = self

        speechController = SpeechController()
        speechController.delegate = self
    }

    private func setupReminderManager() {
        reminderManager = ReminderManager()
        reminderManager.delegate = self

        if let timing = ConfigManager.shared.config.reminderTiming {
            reminderManager.firstReminderDelay = TimeInterval(timing.firstDelayMinutes * 60)
            reminderManager.secondReminderDelay = TimeInterval(timing.secondDelayMinutes * 60)
            if let awaiting = timing.awaitingInputDelayMinutes {
                reminderManager.awaitingInputDelay = TimeInterval(awaiting * 60)
            }
        }
    }

    private func setupSessionTracker() {
        sessionTracker = SessionTracker()
        sessionTracker.delegate = self
        sessionTracker.start()
    }

    private func setupWindowTracker() {
        let size = CGFloat(ConfigManager.shared.config.characterSize ?? 96)
        windowTracker = WindowTracker(characterSize: size)
    }

    private func setupHealthReminder() {
        let cfg = ConfigManager.shared.config.healthReminder ?? HealthReminderConfig(
            enabled: true,
            intervalMinutes: 60,
            onlyWhenWorking: true,
            messages: ["Take a break! Stretch, drink water."]
        )
        healthReminder = HealthReminder(config: cfg, sessionTracker: sessionTracker)
        healthReminder.delegate = self

        // Sync menu toggle state
        if let item = statusItem.menu?.item(withTag: healthToggleTag) {
            item.state = healthReminder.enabled ? .on : .off
        }
    }

    /// Recompute where the frog should rest based on current window/screen state.
    /// Call before each appear to follow the focused window.
    private func refreshRestPosition() {
        restPosition = windowTracker.preferredRestPosition()
    }

    // MARK: - Character Show/Hide

    private func showCharacter() {
        refreshRestPosition()
        if let pos = restPosition {
            characterWindow.setFrameOrigin(pos)
        }
        characterWindow.alphaValue = 1
        characterWindow.orderFront(nil)
        characterView()?.playAnimation(.appearing) { [weak self] in
            self?.characterView()?.playAnimation(.idle)
        }
    }

    private func hideCharacter() {
        restPosition = characterWindow.frame.origin
        actionBubbles.dismiss()
        characterView()?.playAnimation(.disappearing) { [weak self] in
            guard let self = self else { return }
            self.characterWindow.orderOut(nil)
            self.characterWindow.alphaValue = 1  // reset for next show
        }
    }

    private func characterView() -> CharacterView? {
        characterWindow.contentView as? CharacterView
    }
}

// MARK: - CharacterStateDelegate
extension AppDelegate: CharacterStateDelegate {
    func stateDidChange(to state: CharacterState) {
        switch state {
        case .idle:
            // Hidden state — ensure window is off screen
            navigator.stopWalking()

        case .walking(let direction):
            switch direction {
            case .left:
                characterView()?.playAnimation(.run, mirrored: true)
            case .right:
                characterView()?.playAnimation(.run)
            case .toPoint(let targetX):
                let goingRight = targetX > characterWindow.frame.midX
                characterView()?.playAnimation(.run, mirrored: !goingRight)
            }
            navigator.startWalking(direction: direction)

        case .alert:
            navigator.stopWalking()
            refreshRestPosition()
            if let pos = restPosition {
                characterWindow.setFrameOrigin(pos)
            }
            characterWindow.alphaValue = 1
            characterWindow.orderFront(nil)
            characterView()?.playAnimation(.appearing) { [weak self] in
                self?.characterView()?.playAnimation(.doubleJump) { [weak self] in
                    self?.characterView()?.playAnimation(.idle)
                }
            }

        case .talking(let message):
            characterView()?.playAnimation(.idle)
            speechController.speak(message: message, above: characterWindow)

        case .popAndSay(let message):
            navigator.stopWalking()
            refreshRestPosition()
            if let pos = restPosition {
                characterWindow.setFrameOrigin(pos)
            }
            characterWindow.alphaValue = 1
            characterWindow.orderFront(nil)
            // Appear, show bubble for ~4s, then disappear. No walking, no buttons.
            characterView()?.playAnimation(.appearing) { [weak self] in
                guard let self = self else { return }
                self.characterView()?.playAnimation(.idle)
                self.speechController.speak(message: message, above: self.characterWindow)
            }

        case .sleeping:
            navigator.stopWalking()

        case .hiding:
            navigator.stopWalking()
            actionBubbles.dismiss()
            characterView()?.playAnimation(.disappearing) { [weak self] in
                guard let self = self else { return }
                self.characterWindow.orderOut(nil)
                self.characterWindow.alphaValue = 1
                self.stateMachine.onHideComplete()
            }
        }
    }

    func characterDidFinishTalking() {
        pendingMessage = nil
    }
}

// MARK: - ActionBubblesDelegate
extension AppDelegate: ActionBubblesDelegate {
    func actionSelected(_ option: SnoozeOption) {
        if let sessionId = currentSessionId {
            reminderManager.snooze(sessionId: sessionId, option: option)
        }
        // Frog walks back and disappears
        stateMachine.onFinishedTalking()
    }
}

// MARK: - ReminderManagerDelegate
extension AppDelegate: ReminderManagerDelegate {
    private static let funnyMessages: [(first: String, repeat_: String)] = [
        (
            "Yo! {project} is done. Get back to work, {app} isn't paying your bills!",
            "Still on {app}? {project} has been waiting for you. Let's go!"
        ),
        (
            "Hey! {project} finished while you were doom scrolling {app}. Time to review!",
            "{project} is gathering dust while you're on {app}. Come on!"
        ),
        (
            "Breaking news: {project} is done! Unlike {app}, it actually needs you.",
            "Plot twist: {project} is STILL done and you're STILL on {app}!"
        ),
        (
            "{project} just dropped. Stop wasting time on {app} and go ship it!",
            "Reminder #{count}: {project} is done. {app} will survive without you."
        ),
        (
            "Your code in {project} is ready! {app} can wait, your deadline can't.",
            "Hey! {project} called, it wants its developer back from {app}."
        ),
        (
            "Task complete in {project}! Close {app} and go be productive!",
            "You've been on {app} long enough. {project} misses you!"
        ),
        (
            "{project} is cooked! Stop scrolling {app} and go check it out!",
            "Earth to developer! {project} is done. {app} is not your job."
        ),
        (
            "Ding! {project} is ready for you. {app}? Not so much. Let's move!",
            "Fun fact: {project} finished ages ago. Less {app}, more coding!"
        ),
        (
            "{project} wrapped up! Your future self will thank you for leaving {app} now.",
            "Still here on {app}? {project} is getting lonely. Go review your code!"
        ),
        (
            "Alert: {project} is done and you're still on {app}. Priorities, friend!",
            "{project} has been done for a while. {app} isn't going anywhere, but your deadline is."
        ),
    ]

    private static let awaitingInputMessages: [(first: String, repeat_: String)] = [
        (
            "Hey! I'm waiting for you to continue in {project}.",
            "Still here! {project} is blocked waiting on you."
        ),
        (
            "{project} needs your input to keep going!",
            "Hello? {project} is still frozen waiting for you."
        ),
        (
            "Yo, {project} is waiting on your approval to move on.",
            "Reminder #{count}: {project} is stuck, needs your go-ahead."
        ),
        (
            "Psst — {project} is paused waiting for you to answer.",
            "Knock knock. {project} is still waiting for your call."
        ),
        (
            "Claude is waiting for you in {project}. Quick review?",
            "{project} has been on hold for a while now. Come unblock it!"
        ),
    ]

    func reminderShouldFire(reminder: PendingReminder) {
        currentSessionId = reminder.sessionId

        let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "that app"

        let pair: (first: String, repeat_: String)
        switch reminder.kind {
        case .awaitingInput:
            pair = Self.awaitingInputMessages[Int.random(in: 0..<Self.awaitingInputMessages.count)]
        case .taskComplete:
            pair = Self.funnyMessages[Int.random(in: 0..<Self.funnyMessages.count)]
        }

        let template = reminder.reminderCount <= 1 ? pair.first : pair.repeat_
        let message = template
            .replacingOccurrences(of: "{project}", with: reminder.repoName)
            .replacingOccurrences(of: "{app}", with: appName)
            .replacingOccurrences(of: "{count}", with: "\(reminder.reminderCount)")

        pendingMessage = message
        stateMachine.onClaudeCodeEvent(message: message)
    }
}

// MARK: - SessionTrackerDelegate
extension AppDelegate: SessionTrackerDelegate {
    func sessionsDidUpdate(_ sessions: [SessionInfo]) {
        updateSessionsMenu(sessions)
    }

    func sessionDidEnd(session: SessionInfo) {
        // Don't notify on session end — we use the event hooks for that
    }

    func sessionDidStart(session: SessionInfo) {
        // User started new work on this session — cancel reminders
        reminderManager.sessionBecameActive(sessionId: session.sessionId)
    }
}

// MARK: - ClaudeCodeMonitorDelegate
extension AppDelegate: ClaudeCodeMonitorDelegate {
    func claudeCodeDidComplete(event: ClaudeCodeEvent) {
        let summary = event.summary ?? "Task complete"
        let sessionId = event.session ?? UUID().uuidString
        let repoName = event.cwd.map { ($0 as NSString).lastPathComponent } ?? "unknown"

        reminderManager.addReminder(
            sessionId: sessionId,
            repoName: repoName,
            summary: summary,
            kind: .taskComplete
        )
    }

    func claudeCodeAwaitsInput(event: ClaudeCodeEvent) {
        let sessionId = event.session ?? UUID().uuidString
        let repoName = event.cwd.map { ($0 as NSString).lastPathComponent } ?? "unknown"

        reminderManager.addReminder(
            sessionId: sessionId,
            repoName: repoName,
            summary: "Waiting for input",
            kind: .awaitingInput
        )
    }

    func claudeCodeUserPrompted(event: ClaudeCodeEvent) {
        // User submitted a prompt — they're actively working on this session, cancel reminders
        if let sessionId = event.session {
            reminderManager.sessionBecameActive(sessionId: sessionId)
        }
    }

    func claudeCodeStatusChanged(isRunning: Bool) {
        // Handled by SessionTracker
    }
}

// MARK: - CharacterViewDelegate (click on frog)
extension AppDelegate: CharacterViewDelegate {
    func characterWasClicked() {
        // Only show snooze buttons during Claude Code reminders (.talking state).
        // For .popAndSay (health) just dismiss the bubble.
        switch stateMachine.state {
        case .talking:
            speechController.stop()
            actionBubbles.show(around: characterWindow)
        case .popAndSay:
            speechController.stop()
            // speechDidFinish will be called by stop() indirectly — but actually stop() doesn't fire the delegate
            // Manually trigger disappearing
            characterView()?.playAnimation(.disappearing) { [weak self] in
                guard let self = self else { return }
                self.characterWindow.orderOut(nil)
                self.characterWindow.alphaValue = 1
                self.stateMachine.onHideComplete()
            }
        default:
            break
        }
    }
}

// MARK: - SpeechControllerDelegate
extension AppDelegate: SpeechControllerDelegate {
    func speechDidFinish() {
        switch stateMachine.state {
        case .talking:
            // Bubble timed out without click — show buttons anyway
            actionBubbles.show(around: characterWindow)

        case .popAndSay:
            // Quick pop — disappear right away, no buttons
            characterView()?.playAnimation(.disappearing) { [weak self] in
                guard let self = self else { return }
                self.characterWindow.orderOut(nil)
                self.characterWindow.alphaValue = 1
                self.stateMachine.onHideComplete()
                self.healthReminder.didFinishShowing()
            }

        default:
            break
        }
    }
}

// MARK: - HealthReminderDelegate
extension AppDelegate: HealthReminderDelegate {
    func healthReminderShouldFire(message: String) {
        stateMachine.popAndSay(message: message)
    }
}

// MARK: - ScreenEdgeNavigatorDelegate
extension AppDelegate: ScreenEdgeNavigatorDelegate {
    func navigatorDidReachTarget() {
        stateMachine.onReachedTarget()
    }

    func navigatorDidReachEdge() {
        stateMachine.onReachedTarget()
    }
}
