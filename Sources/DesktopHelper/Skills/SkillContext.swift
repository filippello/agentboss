import AppKit

/// The only surface a Skill should touch — anything outside this is private to
/// the registry. Skills get one `SkillContext` from `setup(_:)` and keep it.
final class SkillContext {
    /// Owning registry. Used to enqueue actions, emit events, manage the menu.
    private weak var registry: SkillRegistry?

    /// Stable name for this Skill — used to namespace storage + identify
    /// action ownership in logs.
    let skillName: String

    init(skillName: String, registry: SkillRegistry) {
        self.skillName = skillName
        self.registry = registry
    }

    // MARK: - Frog actions

    /// Queue a frog behavior. Returns immediately; the registry decides when
    /// the action runs based on priority + coalesceKey + current state.
    func enqueue(_ action: FrogAction) {
        registry?.enqueue(action)
    }

    /// Push an event into the bus so other Skills can react. Use for
    /// cross-skill coordination, e.g. Pomodoro emitting `.modeChanged(.focus)`.
    func emit(_ event: AgentEvent) {
        registry?.dispatch(event)
    }

    // MARK: - Menu

    /// Add a top-level item to the menu bar dropdown. Items are grouped by
    /// `section` so layout stays stable.
    @discardableResult
    func addMenuItem(
        section: MenuSection,
        title: String,
        state: NSControl.StateValue = .off,
        action: @escaping () -> Void
    ) -> MenuItemHandle {
        registry?.addMenuItem(
            section: section,
            owner: skillName,
            title: title,
            state: state,
            action: action
        ) ?? MenuItemHandle(id: UUID())
    }

    /// Mutate an existing menu item (e.g. flip a checkbox state, change title).
    func updateMenuItem(_ handle: MenuItemHandle, title: String? = nil, state: NSControl.StateValue? = nil) {
        registry?.updateMenuItem(handle, title: title, state: state)
    }

    /// Remove an item the Skill added earlier. Called automatically on
    /// `teardown` if the Skill forgets — but explicit removal is preferred.
    func removeMenuItem(_ handle: MenuItemHandle) {
        registry?.removeMenuItem(handle)
    }

    /// Change the menu bar icon's trailing text (e.g. "🐸 3" for session count).
    /// First-come-first-serve; later writes win — only one Skill should drive this.
    func setMenuStatus(_ text: String) {
        registry?.setMenuStatus(text)
    }

    // MARK: - Read-only state

    var sessions: [SessionInfo] { registry?.sessions ?? [] }
    var config: HelperConfig { registry?.config ?? ConfigManager.shared.config }

    /// Per-skill UserDefaults namespace. Use for persistent skill-local state
    /// (last-fired timestamp, snooze schedule, etc.).
    var storage: SkillStorageBucket { SkillStorageBucket(skillName: skillName) }
}

/// Opaque handle for a menu item owned by a Skill. The registry uses the
/// internal id; Skills only pass it back when updating or removing.
struct MenuItemHandle: Equatable {
    let id: UUID
}

/// A namespaced wrapper around `UserDefaults.standard` so each Skill writes
/// into its own keyspace without collisions. Persists between launches.
struct SkillStorageBucket {
    let skillName: String
    private let defaults = UserDefaults.standard

    private func namespacedKey(_ key: String) -> String {
        "focuspal.skill.\(skillName).\(key)"
    }

    func string(for key: String) -> String? {
        defaults.string(forKey: namespacedKey(key))
    }

    func setString(_ value: String?, for key: String) {
        defaults.set(value, forKey: namespacedKey(key))
    }

    func bool(for key: String, default defaultValue: Bool = false) -> Bool {
        defaults.object(forKey: namespacedKey(key)) == nil
            ? defaultValue
            : defaults.bool(forKey: namespacedKey(key))
    }

    func setBool(_ value: Bool, for key: String) {
        defaults.set(value, forKey: namespacedKey(key))
    }

    func date(for key: String) -> Date? {
        defaults.object(forKey: namespacedKey(key)) as? Date
    }

    func setDate(_ value: Date?, for key: String) {
        defaults.set(value, forKey: namespacedKey(key))
    }
}
