# FocusPal v0.2 — Hackable Framework + Distribution

> Mirror of the approved plan at `~/.claude/plans/sharded-foraging-sunbeam.md`. Mark items as you complete them.

## Phase A — Foundation

### A0. Pre-work (before touching code)
- [x] Run an Explore subagent to map current event flow: who emits each event today, who reacts, where the wiring lives in `AppDelegate`
  - _Result_: 12 event sources identified. **10 coupling risks** — biggest: state machine silently drops events when busy, `currentSessionId` is a scalar (collisions), no central event queue, shared animation state.
- [x] Run a Plan subagent to validate the `Skill` protocol shape against the 10 risks
  - _Result_: refined API below addresses risks #1, #2, #3, #5, #7, #9. Key changes vs original draft:
    - **`FrogAction` with priority + `coalesceKey`** → registry has a single FIFO queue. `popAndSay`/`walkAndTalk` are `FrogAction.Kind` cases, not direct methods. Eliminates dropped events.
    - **`onChosen: (BubbleButton) -> Void`** closure on `walkAndTalk` action → no more `AppDelegate.currentSessionId` global. Registry routes the callback when buttons are clicked.
    - **`tick(Date, cadence: TickCadence)`** with `.fast` (1s) / `.slow` (30s) → one timer in registry, no per-Skill `Timer.scheduledTimer`.
    - **`modeChanged(AppMode)`** event for focus/DND → Pomodoro emits, other Skills filter. Decoupled silencing.
    - **`teardown()`** on Skill protocol → no leaked menu items / observers on hot-reload.
    - **`MenuItemHandle` + sections** in `SkillContext` → Skills own their menu items, no AppDelegate edits to add a feature.
    - **Per-skill `SkillStorageBucket`** for UserDefaults.
    - Drop `SessionInfo` payloads from session events (use `context.sessions` to avoid two sources of truth).

#### Refined API (final draft):

```swift
protocol Skill: AnyObject {
    var name: String { get }
    func setup(_ context: SkillContext)
    func handle(_ event: AgentEvent)
    func teardown()
}

enum AgentEvent {
    case taskCompleted(sessionId: String, repo: String, summary: String?)
    case awaitingInput(sessionId: String, repo: String)
    case userPrompted(sessionId: String, repo: String)
    case sessionStarted(SessionInfo)
    case sessionEnded(SessionInfo)
    case sessionsUpdated
    case characterClicked
    case modeChanged(AppMode)
    case tick(Date, cadence: TickCadence)
}

enum TickCadence { case fast, slow }
enum AppMode { case normal, focus, doNotDisturb }

struct FrogAction {
    let id = UUID()
    let owner: String
    let kind: Kind
    let priority: Priority
    let coalesceKey: String?
    enum Kind {
        case popAndSay(message: String, duration: TimeInterval)
        case walkAndTalk(message: String, buttons: [BubbleButton], onChosen: (BubbleButton) -> Void)
        case sleep
    }
    enum Priority: Int { case low, normal, high }
}

struct BubbleButton { let id: String; let icon: String; let label: String }

final class SkillContext {
    func enqueue(_ action: FrogAction)
    func emit(_ event: AgentEvent)
    func setMenuStatus(_ text: String)
    func addMenuItem(section: MenuSection, title: String,
                     state: NSControl.StateValue,
                     action: @escaping () -> Void) -> MenuItemHandle
    func updateMenuItem(_ h: MenuItemHandle, title: String?, state: NSControl.StateValue?)
    func removeMenuItem(_ h: MenuItemHandle)
    var sessions: [SessionInfo] { get }
    var config: HelperConfig { get }
    var storage: SkillStorageBucket
}
```

### A1. Skill protocol + dispatcher  ✅
- [x] Create `Sources/DesktopHelper/Skills/Skill.swift` (protocol, `AgentEvent`, `FrogAction`, `BubbleButton`, `AppMode`, `TickCadence`, `MenuSection`)
- [x] Create `Sources/DesktopHelper/Skills/SkillContext.swift` (the only surface a Skill touches: enqueue / emit / addMenuItem / sessions / config / per-skill storage bucket)
- [x] Create `Sources/DesktopHelper/Skills/SkillRegistry.swift` (dispatcher + priority/coalescing action queue + fast/slow tick timer + delegate protocols `FrogActionExecutor`, `SkillMenuController`, `SessionSource`)
- [x] Verify: `swift build` clean, `swift run` shows menu bar 🐸 with no behavior change (existing AppDelegate untouched, registry unused yet)
- _Wiring to AppDelegate moves to A2._

### A2. Refactor existing features into Skills  ✅
- [x] `HealthBreakSkill` (replaces `HealthReminder.swift`, deleted)
- [x] `ReminderSkill` (replaces `ReminderManager.swift`, deleted) — funny-message pool extracted to `MessagePool.swift`, `WorkActivityProbe.swift` shared between skills
- [x] AppDelegate slimmed: now FrogActionExecutor + SkillMenuController + event-translation only. No more reminder timing, no more `currentSessionId` scalar, no more hardcoded message arrays.
- [x] Regression: user confirmed Run Demo, sessions list, Health toggle, character switcher all work identically to pre-refactor.

### A3. PomodoroSkill (demo)  ✅
- [x] `Sources/DesktopHelper/Skills/PomodoroSkill.swift` — adds menu item "▶ Start 25-min Focus", on click emits `.modeChanged(.focus)` (silences Reminder + HealthBreak via their existing `suppressed` flag), tracks countdown via `.tick(.fast)`, on expiry emits `.modeChanged(.normal)` + `popAndSay` + `NSSound.beep()`. Mid-focus click cancels without celebration.
- [x] `SkillRegistry.startTicking` updated to use `RunLoop.main.add(timer, forMode: .common)` so the live countdown ticks while the menu is open.
- [x] Registered in `AppDelegate.setupSkills()` — zero changes to AppDelegate's existing wiring beyond the one register call.
- [x] User-verified: frog pop + beep at end, suppression during focus.

### A4. AGENTS.md (root)  ✅
- [x] Architecture map — every file in the repo with a one-line role
- [x] Glossary — full `AgentEvent` table, `FrogAction` semantics (priority/coalesceKey), `CharacterState`, lifecycle of a frog action (14-step worked example)
- [x] "How to add a Skill" walkthrough — full `MyCoolSkill` template + integration (one-line `register` call)
- [x] Conventions — message pools, persistence via `context.storage`, menu items, priority/coalesceKey choice, fast vs slow tick
- [x] "Things to avoid" anti-patterns
- [x] Symlink `CLAUDE.md → AGENTS.md`
- [ ] Qualitative verification (run after commit): open a fresh Claude Code in this repo, ask it to add a "good morning" skill. Track whether it succeeds reading only `AGENTS.md` + `PomodoroSkill.swift`. Append findings to `tasks/lessons.md`.

## Phase B — Distribution

### B1. Rename to FocusPal
- [ ] `Package.swift` — `name: "FocusPal"`, target name + paths
- [ ] All Swift sources — references to `DesktopHelper` / `AgentBoss` → `FocusPal`
- [ ] `README.md`, `AGENTS.md` — name, badges, repo URLs
- [ ] Local directory rename: `desktophelper` → `focuspal` (verify SPM still builds after rename)
- [ ] GitHub repo rename: `agentboss` → `focuspal` (manual, in repo settings)
- [ ] Update local git remote: `git remote set-url origin https://github.com/filippello/focuspal.git`
- [ ] Verify: `swift build && swift run` works, `git push` works to new remote

### B2. .app bundle script
- [ ] Create `scripts/build-app.sh`:
  - `swift build -c release`
  - Build `FocusPal.app/Contents/{MacOS,Resources}` structure
  - Copy binary + Resources (sprites, config.default.json)
  - Generate `Info.plist` with `LSUIElement=true`
  - Output to `dist/FocusPal.app`
- [ ] Verify: `./scripts/build-app.sh` produces a working `.app` you can double-click

### B3. GitHub Releases automation
- [ ] `.github/workflows/release.yml`
  - Trigger: tags `v*`
  - macos-14 (arm64) runner
  - Steps: build → run script → zip the `.app` → upload as release asset
- [ ] Verify: `git tag v0.2.0-rc.1 && git push --tags` produces a Release with `FocusPal.app.zip`

### B4. Homebrew tap
- [ ] Create separate repo: `filippello/homebrew-tap` (public)
- [ ] Add `Casks/focuspal.rb` Cask formula referencing the GitHub release URL + sha256
- [ ] Update `README.md` install instructions: `brew install --cask filippello/tap/focuspal`
- [ ] Verify: `brew tap filippello/tap && brew install --cask focuspal` puts FocusPal.app in `/Applications` and it runs

## Out of scope (v0.3)
- AISummarySkill (lee transcripts + Claude API)
- StatsSkill (dashboard SwiftUI)
- Capa agéntica (skills emiten `AgenticAction`)
- Codesign + notarización
- Auto-update

## Order of operations
A0 → A1 → A2 → A3 → A4 → B1 → B2 → B3 → B4

## Review (fill in when done)

_To be added at end of milestone._
