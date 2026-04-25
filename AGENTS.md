# AGENTS.md — FocusPal contributor guide for AI assistants

> If you're a Claude Code session opening this repo for the first time:
> read this end to end before changing anything. The whole point of FocusPal
> is to be **easy to extend**, and that depends on you following the
> patterns this doc describes. The complete worked example lives in
> [`Sources/FocusPal/Skills/PomodoroSkill.swift`](Sources/FocusPal/Skills/PomodoroSkill.swift).

## What this app is

FocusPal is a macOS menu-bar companion for Claude Code. A pixel-art frog
hops onto the screen when your Claude Code sessions finish, pause for
input, or when it's time to take a break. It's a single Swift Package
Manager binary — no Xcode required.

The interesting part for an AI: **every behavior is a `Skill`**. Reminders,
health breaks, the Pomodoro timer — all live as small, isolated files in
[`Sources/FocusPal/Skills/`](Sources/FocusPal/Skills/). Adding a
new feature means dropping a new `Skill` file and registering it. Nothing
else needs to change.

## Architecture map

| File | Role |
|---|---|
| `Package.swift` | Swift Package Manager manifest. Declares the executable target and bundled resources (sprites + default config). |
| `config.json` | User-editable runtime config: timings, character, messages per site/app, health-break interval. Loaded by `ConfigManager`. |
| `Sources/FocusPal/main.swift` | Entry point: `NSApplication.shared.setActivationPolicy(.accessory)` + `AppDelegate`. |
| `Sources/FocusPal/AppDelegate.swift` | App-level wiring **only**. Owns the character window, state machine, monitors, and the `SkillRegistry`. Implements `FrogActionExecutor` + `SkillMenuController` so Skills can drive the frog without touching AppKit. **Don't put feature logic here** — it goes in a Skill. |
| `Sources/FocusPal/Skills/Skill.swift` | The protocol + `AgentEvent` + `FrogAction` + `BubbleButton` + supporting enums. |
| `Sources/FocusPal/Skills/SkillContext.swift` | The only surface a Skill touches. Use `enqueue`, `emit`, `addMenuItem`, `sessions`, `config`, `storage`. |
| `Sources/FocusPal/Skills/SkillRegistry.swift` | Dispatches events to every Skill, runs one frog action at a time via a priority/coalescing queue, owns the fast (1s) / slow (30s) ticks. |
| `Sources/FocusPal/Skills/MessagePool.swift` | Rotating message catalogues for ReminderSkill. Templates use `{project}`, `{app}`, `{count}`. |
| `Sources/FocusPal/Skills/WorkActivityProbe.swift` | Detects whether the user is "actively working" (Claude session alive *or* a terminal/editor focused recently). Shared by HealthBreakSkill and ReminderSkill. |
| `Sources/FocusPal/Skills/ReminderSkill.swift` | Per-session reminder queue. Reacts to `taskCompleted` / `awaitingInput` / `userPrompted` / `sessionStarted`. Spawns a `walkAndTalk` action with snooze buttons. |
| `Sources/FocusPal/Skills/HealthBreakSkill.swift` | Periodic `popAndSay` health nudges. Suppressed during AFK or focus mode. |
| `Sources/FocusPal/Skills/PomodoroSkill.swift` | Worked example — see "How to add a Skill" below. |
| `Sources/FocusPal/CharacterStateMachine.swift` | The frog's state machine: `idle / alert / walking / talking / popAndSay / hiding / sleeping`. |
| `Sources/FocusPal/CharacterView.swift` + `CharacterWindow.swift` | The transparent floating window that draws the frog. |
| `Sources/FocusPal/SpriteAnimator.swift` | Loads PNG sprite sheets from the bundle and produces frame-by-frame `NSImage`s. |
| `Sources/FocusPal/SpeechBubbleWindow.swift` + `SpeechController.swift` | Floating speech bubble above the frog. |
| `Sources/FocusPal/ActionBubblesWindow.swift` | The 4 snooze buttons that flank the frog when it's talking. |
| `Sources/FocusPal/ScreenEdgeNavigator.swift` | Walks the frog window across the screen toward a target X. |
| `Sources/FocusPal/WindowTracker.swift` | Finds the focused window's bounds (no Accessibility permissions) so the frog can perch near it. |
| `Sources/FocusPal/SessionTracker.swift` | Polls `~/.claude/sessions/*.json` every 2s, verifies each PID with `kill(pid, 0)`. |
| `Sources/FocusPal/ClaudeCodeMonitor.swift` | Tails `~/.claude/focuspal/events.jsonl` for hook-emitted events. |
| `Sources/FocusPal/HookInstaller.swift` | On first launch, idempotently adds the required `Stop` / `Notification` / `UserPromptSubmit` hooks to `~/.claude/settings.json`. |
| `Sources/FocusPal/ConfigManager.swift` | Loads `config.json` from a few well-known paths, persists user overrides to `~/.focuspal/config.json`. |

## Glossary

### `AgentEvent` (input — Skills *react* to these)

Events flow into Skills via `Skill.handle(_ event:)`. The registry broadcasts each event to every Skill in registration order.

| Event | When it fires | Source |
|---|---|---|
| `.taskCompleted(sessionId, repo, summary)` | A `Stop` hook was written to events.jsonl. | `ClaudeCodeMonitor` |
| `.awaitingInput(sessionId, repo)` | A `Notification` hook was written — Claude is paused on a permission/clarification prompt. | `ClaudeCodeMonitor` |
| `.userPrompted(sessionId, repo)` | The user submitted a new prompt — they're actively working that session. | `ClaudeCodeMonitor` |
| `.sessionStarted(SessionInfo)` | A new Claude PID appeared in `~/.claude/sessions/`. | `SessionTracker` |
| `.sessionEnded(SessionInfo)` | A previously-tracked Claude PID died. | `SessionTracker` |
| `.sessionsUpdated` | The set of active sessions changed somehow. Read `context.sessions` for the current snapshot. | `SessionTracker` |
| `.characterClicked` | The user clicked the on-screen frog. | `CharacterView` |
| `.modeChanged(AppMode)` | App-wide mode flipped (`.normal`, `.focus`, `.doNotDisturb`). Pomodoro emits this. | Any Skill via `context.emit(...)` |
| `.tick(Date, cadence: TickCadence)` | Heartbeat. `.fast` ≈ 1s (live UI), `.slow` ≈ 30s (due-date checks, AFK). | `SkillRegistry` |

**Rule**: do polling work in `.tick(.slow)` instead of owning your own `Timer`. The registry's tick fires reliably even while the menu is open (it's added to `RunLoop.main` in `.common` mode).

### `FrogAction` (output — Skills *request* these)

Skills produce side effects exclusively by enqueueing actions:

```swift
context.enqueue(FrogAction(
    owner: name,
    kind: .popAndSay(message: "Hi!", duration: 4.0),
    priority: .low,
    coalesceKey: "my-skill"
))
```

| Field | Meaning |
|---|---|
| `kind` | `.popAndSay(message, duration)` (no walking, no buttons) / `.walkAndTalk(message, buttons, onChosen)` (walks to centre, shows snooze buttons) / `.sleep` (force frog off-screen). |
| `priority` | `.low` / `.normal` / `.high`. Higher cuts the queue but never preempts a running action. |
| `coalesceKey` | If non-nil, queueing a new action with the same key replaces any pending older one. Use this so a skill doesn't stack reminders if the frog is already busy. |
| `owner` | The Skill's `name`. Used for routing snooze callbacks back to the right skill. |

The registry runs **one action at a time**. While an action is animating, new actions wait in the queue.

### `CharacterState`

The frog's animation state machine, owned by `CharacterStateMachine`. Skills don't touch it directly — `FrogAction` is the abstraction. For reference:

`idle` (hidden) → `alert` (just appeared) → `walking(direction)` → `talking(message)` → `walking(toRest)` → `hiding` → back to `idle`.

`popAndSay(message)` is a separate fast path: appear → bubble → disappear, no walking.

## How to add a Skill

This is the canonical workflow. The full worked example is `PomodoroSkill.swift` — open it side by side with this section.

### 1. Create the file

`Sources/FocusPal/Skills/MyCoolSkill.swift`:

```swift
import AppKit

final class MyCoolSkill: Skill {
    let name = "mycool"

    private var ctx: SkillContext!
    private var menuHandle: MenuItemHandle?
    private var fired: Bool = false

    func setup(_ context: SkillContext) {
        self.ctx = context
        // Restore persisted state
        fired = context.storage.bool(for: "fired", default: false)

        menuHandle = context.addMenuItem(
            section: .toggles,
            title: "Reset MyCool",
            state: .off
        ) { [weak self] in
            self?.reset()
        }
    }

    func handle(_ event: AgentEvent) {
        switch event {
        case .taskCompleted where !fired:
            fired = true
            ctx.storage.setBool(true, for: "fired")
            ctx.enqueue(FrogAction(
                owner: name,
                kind: .popAndSay(message: "First task of the session!", duration: 4),
                priority: .normal,
                coalesceKey: "mycool-first"
            ))
        default:
            break
        }
    }

    func teardown() {
        if let handle = menuHandle { ctx.removeMenuItem(handle) }
    }

    private func reset() {
        fired = false
        ctx.storage.setBool(false, for: "fired")
    }
}
```

### 2. Register it in `AppDelegate.setupSkills()`

```swift
private func setupSkills() {
    reminderSkill = ReminderSkill()
    registry.register(reminderSkill)
    registry.register(HealthBreakSkill())
    registry.register(PomodoroSkill())
    registry.register(MyCoolSkill())     // ← new line
}
```

That is the entire integration point. No other AppDelegate edit is needed.

### 3. Build and run

```bash
swift build && swift run
```

## Conventions

### Where messages live

User-facing strings rotate through arrays so they don't get repetitive. Put new pools in `MessagePool.swift` if they're shared, or as a `private static let` array on the Skill if they're skill-local. Always provide multiple variants.

Use the `{project}`, `{app}`, `{count}` placeholders and `MessagePool.render(_:)` to interpolate.

### How to persist state

Use `context.storage` — it's a per-skill `UserDefaults` namespace:

```swift
ctx.storage.setDate(Date(), for: "lastFired")
ctx.storage.bool(for: "enabled", default: true)
```

Keys are namespaced as `focuspal.skill.<your-name>.<key>` automatically. Don't write to `UserDefaults.standard` directly.

### How to register menu items

Use `context.addMenuItem(section:title:state:action:)`. Sections (`MenuSection`) determine vertical position in the dropdown. Save the returned `MenuItemHandle` to update or remove later.

For toggle-style items, mutate via `context.updateMenuItem(handle, title: ..., state: .on/.off)` instead of recreating. Update the title to reflect live state (the Pomodoro countdown is the canonical example).

### When to use which `FrogAction.priority`

- `.high` — the user asked for this and they need to know (a real reminder firing).
- `.normal` — celebration, scheduled UX (Pomodoro end, milestone reached).
- `.low` — background nudges that can be coalesced or dropped (health breaks).

### When to use `coalesceKey`

If your Skill might enqueue multiple actions about the same thing, use a stable key so newer ones replace older queued ones. Examples in the codebase:
- `"health"` (HealthBreakSkill — only one pending health pop ever)
- `"reminder:<sessionId>"` (ReminderSkill — only one pending reminder per session)
- `"pomodoro-end"` (PomodoroSkill — only one pending end-of-block celebration)

If you don't set a key, every action queues. That's correct for genuinely unique events (e.g. "user just clicked, do this thing now") but wrong for "fire the X reminder when ready".

### When to react to `.tick(.fast)` vs `.tick(.slow)`

| Use `.fast` (1s) for… | Use `.slow` (30s) for… |
|---|---|
| Live UI: countdowns, "current time" displays | Due-date checks: "is it time to fire X?" |
| Anything the user looks at and expects to update | AFK detection: "has the terminal been idle long enough?" |
| | File scans, expensive work |

Both fire on `RunLoop.main` in `.common` mode, so they keep ticking even while the status bar menu is open.

## Lifecycle of a frog action (worked example)

User scenario: Claude finishes a task, the user is on YouTube, after 5 minutes the frog walks out. Here's every hop in order:

1. `~/.claude/focuspal/events.jsonl` gets a new line: `{"event":"Stop", ...}` (written by the hook in `~/.claude/settings.json`).
2. `ClaudeCodeMonitor` polls the file (~0.5s), parses the line, calls `delegate.claudeCodeDidComplete(...)`.
3. `AppDelegate.claudeCodeDidComplete(...)` translates it to `AgentEvent.taskCompleted(...)` and calls `registry.dispatch(event)`.
4. Every Skill's `handle(_:)` runs. `ReminderSkill` records a new `PendingReminder` with `nextReminderAt = now + 5min`.
5. Time passes. Every 30 seconds `SkillRegistry` emits `.tick(_, .slow)`. `ReminderSkill` checks its reminders, sees one is due, and (if the user isn't currently focused on a terminal) calls `ctx.enqueue(FrogAction(.walkAndTalk(...)))`.
6. `SkillRegistry.enqueue` accepts the action, calls `drainQueue`. Nothing is running, so it pops the action and calls `actionExecutor.execute(...)`.
7. `AppDelegate.execute(_:completion:)` stores `currentAction` + `completion`, then calls `stateMachine.onClaudeCodeEvent(message)`.
8. `CharacterStateMachine` runs the alert → walking → talking sequence. Each transition triggers `AppDelegate.stateDidChange(to:)` which drives the actual `CharacterView` animations.
9. `SpeechController` shows the bubble. After it times out (~3-5s) `speechDidFinish()` fires, AppDelegate shows `ActionBubblesWindow`.
10. User clicks "10 min". `ActionBubblesDelegate.actionSelected(.tenMinutes)` fires. AppDelegate maps `.tenMinutes` → button id `"10min"` → finds the matching `BubbleButton` from `currentAction.buttons` → calls `registry.bubbleButtonChosen(button)`.
11. The registry calls the running action's `onChosen` closure, which is captured inside `ReminderSkill`. The closure runs `applySnooze(sessionId:button:)`, updating `reminders[sessionId].snoozedUntil`.
12. Meanwhile AppDelegate calls `stateMachine.onFinishedTalking()` to walk the frog back home.
13. Frog reaches rest position → `.hiding` → disappear animation completes → orderOut + `stateMachine.onHideComplete()` + `finishCurrentAction()`.
14. `finishCurrentAction()` calls the stored completion, which is `registry.actionDidComplete(id)`. Registry clears `runningAction` and drains the queue (which is empty). Done.

Every numbered step happens in code that's well-named — search for the function names if you're hunting for one.

## Things to avoid

- ❌ **Don't add a feature directly to `AppDelegate`.** AppDelegate is wiring; behaviour belongs in a Skill.
- ❌ **Don't own `Timer`s in your Skill.** Use `.tick(.fast)` / `.tick(.slow)` so the registry can serialize work and your timer doesn't freeze when the menu opens.
- ❌ **Don't mutate `CharacterStateMachine` directly.** Enqueue a `FrogAction` instead.
- ❌ **Don't call `playAnimation` on the `CharacterView`.** Same reason — go through actions.
- ❌ **Don't write to `UserDefaults.standard` directly.** Use `context.storage`.
- ❌ **Don't hardcode user-facing strings.** Add a pool / config knob.
- ❌ **Don't bypass `coalesceKey` if the action is repeatable.** You will queue 17 reminders if Claude emits 17 Stop events.

## Local development

```bash
swift build               # builds debug
swift run                 # builds and runs (kills any prior instance via menu Quit)
swift test                # there are no tests yet — see roadmap
```

The character switcher in the 🐸 menu lets you preview each character without rebuilding. The "🎬 Run Demo" item triggers a synthetic reminder via `ReminderSkill.fireDemoReminder()` so you can see the full walk → talk → snooze flow without waiting.

## Roadmap (what's missing if you want to contribute)

- **AISummarySkill**: read the active session's transcript via Claude API and replace generic "Task completed" with a 1-line summary of what actually happened. Needs a `Claude API key` config knob.
- **StatsSkill**: parse `events.jsonl` + `~/.claude/history.jsonl`, render a small SwiftUI dashboard from a menu item.
- **Skill teardown on hot-reload**: today the app must restart for new skills to load. Could add a debug menu to re-register.
- **Tests**: no XCTest target yet. The Skills are pure-ish (state in instance vars, IO via context) so they're testable with a mock `SkillRegistry`.
- **Cross-platform**: AppKit-only today. SwiftUI port for iPadOS would need `CharacterView` + window code rewritten.

## When you're done

- Run `swift build` and confirm it's clean.
- Run `swift run` and exercise your new Skill manually.
- Add a line to `tasks/lessons.md` if any pattern surprised you — that's how the project gets less surprising for the next agent.

Welcome aboard.
