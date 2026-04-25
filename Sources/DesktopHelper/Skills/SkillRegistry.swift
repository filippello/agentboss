import AppKit

/// Bridge between Skills and the rest of the app.
///
/// The registry has three jobs:
/// 1. **Lifecycle** — register / setup / teardown Skills.
/// 2. **Event dispatch** — broadcast `AgentEvent`s to every Skill in registration order.
/// 3. **Action queue** — accept `FrogAction`s from Skills, serialize them so only
///    one runs at a time, and hand each off to a `FrogActionExecutor` (AppDelegate).
///
/// The registry is intentionally Cocoa-light: it doesn't know how to draw a
/// frog or render a menu. It calls into protocol-bound delegates so the
/// existing UI code in AppDelegate stays the only place that touches AppKit.
final class SkillRegistry {

    // MARK: - Configuration

    /// Where the registry hands off concrete frog behavior. Owned by AppDelegate.
    weak var actionExecutor: FrogActionExecutor?

    /// Where the registry hands off concrete menu mutations. Owned by AppDelegate.
    weak var menuController: SkillMenuController?

    /// Source of session info — registry forwards via `SkillContext.sessions`.
    weak var sessionSource: SessionSource?

    // MARK: - Internal state

    private var skills: [Skill] = []
    private var contexts: [String: SkillContext] = [:]   // by skill name

    private var actionQueue: [FrogAction] = []
    private var runningAction: FrogAction?

    private var fastTickTimer: Timer?
    private var slowTickTimer: Timer?

    // MARK: - Lifecycle

    /// Register a Skill. Calls its `setup(_:)` synchronously.
    /// Skill names must be unique — duplicates are silently ignored.
    func register(_ skill: Skill) {
        guard contexts[skill.name] == nil else {
            print("[SkillRegistry] Skill '\(skill.name)' already registered, skipping")
            return
        }
        let context = SkillContext(skillName: skill.name, registry: self)
        contexts[skill.name] = context
        skills.append(skill)
        skill.setup(context)
    }

    /// Tear down all registered Skills (drops menu items, cancels timers).
    /// Called on app termination.
    func shutdown() {
        for skill in skills.reversed() {
            skill.teardown()
        }
        skills.removeAll()
        contexts.removeAll()
        fastTickTimer?.invalidate()
        slowTickTimer?.invalidate()
    }

    /// Start the periodic tick events. Call once after all Skills are registered.
    func startTicking() {
        fastTickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.dispatch(.tick(Date(), cadence: .fast))
        }
        slowTickTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.dispatch(.tick(Date(), cadence: .slow))
        }
    }

    // MARK: - Event dispatch

    /// Broadcast an event to every Skill in registration order.
    func dispatch(_ event: AgentEvent) {
        for skill in skills {
            skill.handle(event)
        }
    }

    // MARK: - Action queue (called by SkillContext.enqueue)

    func enqueue(_ action: FrogAction) {
        // Coalesce: if a pending action already shares this key, drop the
        // older one and keep the newer (a fresher health-pop message wins
        // over a stale one).
        if let key = action.coalesceKey {
            actionQueue.removeAll { $0.coalesceKey == key }
        }

        // Insert by priority — higher first, FIFO within same priority.
        if let firstLowerIndex = actionQueue.firstIndex(where: { $0.priority.rawValue < action.priority.rawValue }) {
            actionQueue.insert(action, at: firstLowerIndex)
        } else {
            actionQueue.append(action)
        }

        drainQueue()
    }

    /// Called by the executor when the running action's animation finishes.
    /// Triggers the next action in the queue, if any.
    func actionDidComplete(_ id: UUID) {
        if runningAction?.id == id {
            runningAction = nil
        }
        drainQueue()
    }

    /// Look up the running action's bubble-button callback. Used by the
    /// menu/UI layer to route a click on a bubble button back to the right Skill.
    func bubbleButtonChosen(_ button: BubbleButton) {
        guard let action = runningAction else { return }
        if case .walkAndTalk(_, _, let onChosen) = action.kind {
            onChosen(button)
        }
    }

    private func drainQueue() {
        guard runningAction == nil, !actionQueue.isEmpty else { return }
        let next = actionQueue.removeFirst()
        runningAction = next

        guard let executor = actionExecutor else {
            // No executor wired yet — drop on the floor and clear running so
            // the queue keeps draining. Useful during early bring-up.
            runningAction = nil
            return
        }

        executor.execute(next) { [weak self] in
            self?.actionDidComplete(next.id)
        }
    }

    // MARK: - Menu (called by SkillContext)

    func addMenuItem(
        section: MenuSection,
        owner: String,
        title: String,
        state: NSControl.StateValue,
        action: @escaping () -> Void
    ) -> MenuItemHandle {
        let handle = MenuItemHandle(id: UUID())
        menuController?.addMenuItem(
            handle: handle,
            section: section,
            title: title,
            state: state,
            action: action
        )
        return handle
    }

    func updateMenuItem(_ handle: MenuItemHandle, title: String?, state: NSControl.StateValue?) {
        menuController?.updateMenuItem(handle, title: title, state: state)
    }

    func removeMenuItem(_ handle: MenuItemHandle) {
        menuController?.removeMenuItem(handle)
    }

    func setMenuStatus(_ text: String) {
        menuController?.setMenuStatus(text)
    }

    // MARK: - Read-only state for SkillContext

    var sessions: [SessionInfo] { sessionSource?.activeSessions ?? [] }
    var config: HelperConfig { ConfigManager.shared.config }
}

// MARK: - Delegate protocols (implemented by AppDelegate)

/// What the registry hands actions off to. AppDelegate implements this and
/// drives the existing CharacterStateMachine + SpeechController + ActionBubbles
/// based on the action kind.
protocol FrogActionExecutor: AnyObject {
    /// Execute the given action. Must call `completion` exactly once when the
    /// frog is done (animation finished, user dismissed, etc.).
    func execute(_ action: FrogAction, completion: @escaping () -> Void)
}

/// What the registry hands menu mutations off to. AppDelegate implements this
/// using the existing `NSStatusItem.menu`.
protocol SkillMenuController: AnyObject {
    func addMenuItem(handle: MenuItemHandle,
                     section: MenuSection,
                     title: String,
                     state: NSControl.StateValue,
                     action: @escaping () -> Void)
    func updateMenuItem(_ handle: MenuItemHandle, title: String?, state: NSControl.StateValue?)
    func removeMenuItem(_ handle: MenuItemHandle)
    func setMenuStatus(_ text: String)
}

/// Where the registry reads the current set of active Claude Code sessions.
/// Today the implementer is `SessionTracker`.
protocol SessionSource: AnyObject {
    var activeSessions: [SessionInfo] { get }
}
