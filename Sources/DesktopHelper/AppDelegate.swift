import AppKit

/// App-level wiring. Owns:
/// - The character window + state machine + animation drivers
/// - Speech bubble + action-button window
/// - Status bar menu (base layout — Skills add their own items)
/// - The `SkillRegistry` and the long-lived monitors that feed it events
///
/// Everything *behavioural* (reminders, health breaks, future Pomodoro) lives
/// in `Skills/`. AppDelegate knows nothing about reminder timing, message
/// pools, or break intervals — it just routes events into the registry and
/// runs whatever `FrogAction`s the registry asks for. To add a new feature,
/// drop a new file in `Skills/` and register it below in `setupSkills()`.
class AppDelegate: NSObject, NSApplicationDelegate {

    // UI
    private var statusItem: NSStatusItem!
    private var characterWindow: CharacterWindow!
    private var stateMachine: CharacterStateMachine!
    private var navigator: ScreenEdgeNavigator!
    private var speechController: SpeechController!
    private var actionBubbles: ActionBubblesWindow!
    private var windowTracker: WindowTracker!
    private var restPosition: NSPoint?

    // Event sources
    private var claudeMonitor: ClaudeCodeMonitor!
    private var sessionTracker: SessionTracker!

    // Skills
    private var registry: SkillRegistry!
    private var reminderSkill: ReminderSkill!     // kept for the demo button

    // Action execution state
    private var currentAction: FrogAction?
    private var currentActionCompletion: (() -> Void)?

    // Menu state
    private var sessionMenuItems: [NSMenuItem] = []
    private let sessionsHeaderTag = 201
    private let noSessionsTag = 300
    private var skillMenuItems: [UUID: NSMenuItem] = [:]
    private var skillMenuActions: [UUID: () -> Void] = [:]

    /// Characters bundled with the app. Must match folder names under
    /// `Sources/DesktopHelper/Resources/Main Characters/`.
    static let availableCharacters = ["Ninja Frog", "Mask Dude", "Pink Man", "Virtual Guy"]

    func applicationDidFinishLaunching(_ notification: Notification) {
        let installer = HookInstaller()
        _ = installer.ensureHooksInstalled()

        setupWindowTracker()
        setupMenuBar()
        setupCharacterWindow()
        setupStateMachine()
        setupActionBubbles()
        setupClaudeCodeMonitor()
        setupSessionTracker()
        setupRegistry()
        setupSkills()
        registry.startTicking()
    }

    func applicationWillTerminate(_ notification: Notification) {
        registry?.shutdown()
    }

    // MARK: - Setup

    private func setupWindowTracker() {
        let size = CGFloat(ConfigManager.shared.config.characterSize ?? 96)
        windowTracker = WindowTracker(characterSize: size)
    }

    private func setupCharacterWindow() {
        characterWindow = CharacterWindow()
        characterWindow.orderOut(nil)
        restPosition = characterWindow.frame.origin
        characterWindow.ignoresMouseEvents = false
        characterWindow.acceptsMouseMovedEvents = true
    }

    private func setupStateMachine() {
        stateMachine = CharacterStateMachine()
        stateMachine.delegate = self
        navigator = ScreenEdgeNavigator(window: characterWindow)
        navigator.delegate = self
        characterView()?.clickDelegate = self
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

    private func setupSessionTracker() {
        sessionTracker = SessionTracker()
        sessionTracker.delegate = self
        sessionTracker.start()
    }

    private func setupRegistry() {
        registry = SkillRegistry()
        registry.actionExecutor = self
        registry.menuController = self
        registry.sessionSource = sessionTracker
    }

    private func setupSkills() {
        reminderSkill = ReminderSkill()
        registry.register(reminderSkill)
        registry.register(HealthBreakSkill())
        registry.register(PomodoroSkill())
    }

    // MARK: - Menu Bar (base layout)

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateMenuBarTitle(count: 0)

        let menu = NSMenu()
        menu.autoenablesItems = false

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
        noSessions.tag = noSessionsTag
        noSessions.isEnabled = false
        menu.addItem(noSessions)

        // Section separator before Skill items
        menu.addItem(NSMenuItem.separator())

        // Skill items (added by Skills via SkillMenuController; see addMenuItem)
        // — the registry inserts them between this separator and the character submenu.

        // Character submenu
        menu.addItem(NSMenuItem.separator())
        menu.addItem(buildCharacterSubmenuItem())

        // Demo
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

    private func buildCharacterSubmenuItem() -> NSMenuItem {
        let characterItem = NSMenuItem(title: "Character", action: nil, keyEquivalent: "")
        let characterSubmenu = NSMenu()
        let currentCharacter = ConfigManager.shared.config.characterName ?? "Ninja Frog"
        for name in Self.availableCharacters {
            let item = NSMenuItem(title: name, action: #selector(selectCharacter(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = name
            item.state = (name == currentCharacter) ? .on : .off
            characterSubmenu.addItem(item)
        }
        characterItem.submenu = characterSubmenu
        return characterItem
    }

    @objc private func selectCharacter(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        ConfigManager.shared.setCharacterName(name)
        characterView()?.reloadCharacter(named: name)
        if let submenu = sender.menu {
            for item in submenu.items {
                item.state = (item.representedObject as? String == name) ? .on : .off
            }
        }
    }

    @objc private func runDemo() {
        // Trigger a fake reminder via the ReminderSkill so the demo follows
        // the same code path as a real reminder.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.reminderSkill.fireDemoReminder()
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
        if let p = menu.item(withTag: noSessionsTag) { menu.removeItem(p) }

        guard let headerIndex = menu.items.firstIndex(where: { $0.tag == sessionsHeaderTag }) else { return }
        var insertIndex = headerIndex + 1

        if sessions.isEmpty {
            let noSessions = NSMenuItem(title: "  No active sessions", action: nil, keyEquivalent: "")
            noSessions.tag = noSessionsTag
            noSessions.isEnabled = false
            menu.insertItem(noSessions, at: insertIndex)
        } else {
            for session in sessions {
                let title = "  ⚡ \(session.repoName) — \(session.timeAgo)"
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.isEnabled = false
                item.attributedTitle = NSAttributedString(
                    string: title,
                    attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                                 .foregroundColor: NSColor.labelColor]
                )
                menu.insertItem(item, at: insertIndex)
                sessionMenuItems.append(item)
                insertIndex += 1
            }
        }

        updateMenuBarTitle(count: sessions.count)
    }

    // MARK: - Helpers

    private func characterView() -> CharacterView? {
        characterWindow.contentView as? CharacterView
    }

    private func refreshRestPosition() {
        restPosition = windowTracker.preferredRestPosition()
    }
}

// MARK: - FrogActionExecutor (registry → frog)

extension AppDelegate: FrogActionExecutor {
    func execute(_ action: FrogAction, completion: @escaping () -> Void) {
        currentAction = action
        currentActionCompletion = completion

        switch action.kind {
        case .popAndSay(let message, _):
            stateMachine.popAndSay(message: message)

        case .walkAndTalk(let message, _, _):
            stateMachine.onClaudeCodeEvent(message: message)

        case .sleep:
            // Force frog off-screen immediately and complete.
            actionBubbles.dismiss()
            characterWindow.orderOut(nil)
            finishCurrentAction()
        }
    }

    /// Called when the frog returns to .idle after running an action.
    private func finishCurrentAction() {
        let completion = currentActionCompletion
        currentAction = nil
        currentActionCompletion = nil
        completion?()
    }
}

// MARK: - SkillMenuController (registry → menu)

extension AppDelegate: SkillMenuController {
    func addMenuItem(handle: MenuItemHandle,
                     section: MenuSection,
                     title: String,
                     state: NSControl.StateValue,
                     action: @escaping () -> Void) {
        guard let menu = statusItem.menu else { return }
        let item = NSMenuItem(title: title, action: #selector(skillMenuItemFired(_:)), keyEquivalent: "")
        item.target = self
        item.state = state
        item.representedObject = handle.id

        // Insert before the character submenu (which is the first item with a submenu).
        let insertIndex = menu.items.firstIndex { $0.submenu != nil } ?? (menu.items.count - 2)
        menu.insertItem(item, at: insertIndex)

        skillMenuItems[handle.id] = item
        skillMenuActions[handle.id] = action
    }

    func updateMenuItem(_ handle: MenuItemHandle, title: String?, state: NSControl.StateValue?) {
        guard let item = skillMenuItems[handle.id] else { return }
        if let title = title { item.title = title }
        if let state = state { item.state = state }
    }

    func removeMenuItem(_ handle: MenuItemHandle) {
        guard let item = skillMenuItems.removeValue(forKey: handle.id),
              let menu = statusItem.menu else { return }
        menu.removeItem(item)
        skillMenuActions.removeValue(forKey: handle.id)
    }

    func setMenuStatus(_ text: String) {
        statusItem.button?.title = text
    }

    @objc private func skillMenuItemFired(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let action = skillMenuActions[id] else { return }
        action()
    }
}

// MARK: - CharacterStateDelegate

extension AppDelegate: CharacterStateDelegate {
    func stateDidChange(to state: CharacterState) {
        switch state {
        case .idle:
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
            if let pos = restPosition { characterWindow.setFrameOrigin(pos) }
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
            if let pos = restPosition { characterWindow.setFrameOrigin(pos) }
            characterWindow.alphaValue = 1
            characterWindow.orderFront(nil)
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
                self.finishCurrentAction()
            }
        }
    }

    func characterDidFinishTalking() {
        // The state machine is about to walk the frog back to rest position.
        // The action completion fires later in `.hiding`.
    }
}

// MARK: - ActionBubblesDelegate

extension AppDelegate: ActionBubblesDelegate {
    func actionSelected(_ option: SnoozeOption) {
        // Translate the legacy SnoozeOption into the running action's
        // matching BubbleButton and notify the registry, which routes back
        // to the Skill that emitted the walkAndTalk.
        if case .walkAndTalk(_, let buttons, _) = currentAction?.kind {
            let buttonId: String
            switch option {
            case .dismiss:     buttonId = "dismiss"
            case .tenMinutes:  buttonId = "10min"
            case .oneHour:     buttonId = "1hour"
            case .tomorrow:    buttonId = "tomorrow"
            }
            if let chosen = buttons.first(where: { $0.id == buttonId }) {
                registry.bubbleButtonChosen(chosen)
            }
        }
        // Walk the frog back home and disappear.
        stateMachine.onFinishedTalking()
    }
}

// MARK: - SessionTrackerDelegate (forward to registry)

extension AppDelegate: SessionTrackerDelegate {
    func sessionsDidUpdate(_ sessions: [SessionInfo]) {
        updateSessionsMenu(sessions)
        registry?.dispatch(.sessionsUpdated)
    }

    func sessionDidEnd(session: SessionInfo) {
        registry?.dispatch(.sessionEnded(session))
    }

    func sessionDidStart(session: SessionInfo) {
        registry?.dispatch(.sessionStarted(session))
    }
}

// MARK: - ClaudeCodeMonitorDelegate (forward to registry)

extension AppDelegate: ClaudeCodeMonitorDelegate {
    func claudeCodeDidComplete(event: ClaudeCodeEvent) {
        let sessionId = event.session ?? UUID().uuidString
        let repo = event.cwd.map { ($0 as NSString).lastPathComponent } ?? "unknown"
        registry?.dispatch(.taskCompleted(sessionId: sessionId, repo: repo, summary: event.summary))
    }

    func claudeCodeAwaitsInput(event: ClaudeCodeEvent) {
        let sessionId = event.session ?? UUID().uuidString
        let repo = event.cwd.map { ($0 as NSString).lastPathComponent } ?? "unknown"
        registry?.dispatch(.awaitingInput(sessionId: sessionId, repo: repo))
    }

    func claudeCodeUserPrompted(event: ClaudeCodeEvent) {
        guard let sessionId = event.session else { return }
        let repo = event.cwd.map { ($0 as NSString).lastPathComponent } ?? "unknown"
        registry?.dispatch(.userPrompted(sessionId: sessionId, repo: repo))
    }

    func claudeCodeStatusChanged(isRunning: Bool) {
        // Handled by SessionTracker via session events.
    }
}

// MARK: - CharacterViewDelegate

extension AppDelegate: CharacterViewDelegate {
    func characterWasClicked() {
        registry?.dispatch(.characterClicked)

        // Built-in click behavior: during a walkAndTalk action, show snooze
        // buttons immediately. During a popAndSay, dismiss.
        switch stateMachine.state {
        case .talking:
            speechController.stop()
            actionBubbles.show(around: characterWindow)
        case .popAndSay:
            speechController.stop()
            characterView()?.playAnimation(.disappearing) { [weak self] in
                guard let self = self else { return }
                self.characterWindow.orderOut(nil)
                self.characterWindow.alphaValue = 1
                self.stateMachine.onHideComplete()
                self.finishCurrentAction()
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
            // Bubble timed out without a click — show the snooze buttons.
            actionBubbles.show(around: characterWindow)

        case .popAndSay:
            // Quick pop is over — disappear, no buttons.
            characterView()?.playAnimation(.disappearing) { [weak self] in
                guard let self = self else { return }
                self.characterWindow.orderOut(nil)
                self.characterWindow.alphaValue = 1
                self.stateMachine.onHideComplete()
                self.finishCurrentAction()
            }
        default:
            break
        }
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
