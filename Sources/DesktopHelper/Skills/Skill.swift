import AppKit

/// A self-contained behavior plugged into FocusPal at startup.
///
/// Each Skill subscribes to `AgentEvent`s, requests `FrogAction`s through its
/// `SkillContext`, and owns its own piece of menu bar UI. The registry routes
/// events to every Skill and serializes their actions through a single queue,
/// so two Skills can never produce overlapping frog behavior.
///
/// To add a new feature: drop a new file in `Skills/`, conform to `Skill`, and
/// register the instance in `AppDelegate`. See `AGENTS.md` for the full guide.
protocol Skill: AnyObject {
    var name: String { get }
    func setup(_ context: SkillContext)
    func handle(_ event: AgentEvent)
    func teardown()
}

extension Skill {
    func teardown() {}
}

// MARK: - Events (input)

/// Everything a Skill might want to react to. Skills *read* events; they
/// produce side-effects via `SkillContext`.
enum AgentEvent {
    /// Claude Code finished a response in this session.
    case taskCompleted(sessionId: String, repo: String, summary: String?)

    /// Claude Code is paused waiting for the user (permission prompt, etc).
    case awaitingInput(sessionId: String, repo: String)

    /// User submitted a new prompt — they're back at the keyboard.
    case userPrompted(sessionId: String, repo: String)

    /// A new Claude Code process appeared.
    case sessionStarted(SessionInfo)

    /// A previously-tracked Claude Code process exited.
    case sessionEnded(SessionInfo)

    /// The set of active sessions changed in some way; read `context.sessions`
    /// for the current snapshot.
    case sessionsUpdated

    /// User clicked the on-screen frog character.
    case characterClicked

    /// App-wide mode changed (e.g. Pomodoro entering/leaving focus mode).
    case modeChanged(AppMode)

    /// Periodic heartbeat. Skills do polling work here instead of owning timers.
    case tick(Date, cadence: TickCadence)
}

enum TickCadence {
    case fast   // ~1s — for things that need to feel responsive
    case slow   // ~30s — for due-date checks, file scans, AFK detection
}

enum AppMode: Equatable {
    case normal
    case focus            // Pomodoro etc. — most reminders should suppress
    case doNotDisturb     // user explicitly silenced everything
}

// MARK: - Actions (output)

/// A frog behavior a Skill wants the registry to perform.
///
/// The registry owns a single FIFO queue of `FrogAction`s and runs them one
/// at a time. Higher-priority actions cut to the front of the queue but never
/// interrupt an action already running. `coalesceKey` lets a Skill say "if
/// there is already a pending action with this key, replace it instead of
/// stacking" — important for things like health pops where you don't want to
/// queue four reminders if the frog was busy.
struct FrogAction {
    let id = UUID()
    let owner: String
    let kind: Kind
    let priority: Priority
    let coalesceKey: String?

    init(
        owner: String,
        kind: Kind,
        priority: Priority = .normal,
        coalesceKey: String? = nil
    ) {
        self.owner = owner
        self.kind = kind
        self.priority = priority
        self.coalesceKey = coalesceKey
    }

    enum Kind {
        /// Quick pop near rest position: appearing → bubble → disappearing.
        case popAndSay(message: String, duration: TimeInterval)

        /// Walk to centre, show a bubble, render `buttons` after the bubble
        /// times out (or on click). When the user picks one, `onChosen`
        /// fires with that button.
        case walkAndTalk(message: String, buttons: [BubbleButton], onChosen: (BubbleButton) -> Void)

        /// Force the frog off-screen now, cancelling any running animation.
        case sleep
    }

    enum Priority: Int { case low = 0, normal = 1, high = 2 }
}

/// A button rendered next to the frog when it's in a `walkAndTalk` action.
struct BubbleButton: Equatable {
    let id: String
    let icon: String
    let label: String
}

// MARK: - Menu sections

/// Where in the menu bar dropdown a Skill's items live. The registry inserts
/// items in section order so the menu has a stable layout regardless of
/// registration order.
enum MenuSection: Int, CaseIterable {
    case sessions   = 0   // active Claude Code sessions list
    case toggles    = 1   // on/off switches (health reminders, etc.)
    case characters = 2   // character submenu
    case debug      = 3   // demo / dev affordances
}
