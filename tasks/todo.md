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

### A2. Refactor existing features into Skills
- [ ] `HealthBreakSkill` (move from `HealthReminder.swift`)
- [ ] `ReminderSkill` (move from `ReminderManager.swift` + the funny-message pool that lives in `AppDelegate`)
- [ ] Slim down `AppDelegate` to wiring + character window + base menu bar
- [ ] Verify: regression test — task complete reminder fires at 5 min (use demo button), health pop fires when interval hits, character switcher still works

### A3. PomodoroSkill (demo)
- [ ] Add menu bar item "Start 25-min Focus" via `context.addMenuItem`
- [ ] During focus block: pause `ReminderSkill` and `HealthBreakSkill` (registry-level pause flag)
- [ ] On block end: `popAndSay("Focus done!") + NSSound.beep()`
- [ ] Verify: start block → trigger Stop event manually → no reminder fires → after 25 min (or short test interval) → frog pops + sound plays

### A4. AGENTS.md (root)
- [ ] Architecture map — what each file does (table format, scannable)
- [ ] Glossary — `AgentEvent`, `CharacterState`, frog lifecycle
- [ ] "How to add a Skill" walkthrough — copy-paste of `PomodoroSkill` with explanation
- [ ] Convention notes — where messages live, where config is, naming
- [ ] Symlink `CLAUDE.md → AGENTS.md`
- [ ] Verify (qualitative): open a fresh Claude Code session in the repo, ask it to add a trivial new skill ("good morning skill that fires once on first event of the day"). It should succeed reading only `AGENTS.md` + `PomodoroSkill.swift`.

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
