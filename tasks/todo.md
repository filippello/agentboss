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

### B1. Rename to FocusPal  ✅ (mostly — see manual steps)
- [x] `Package.swift` — `name: "FocusPal"`, `path: "Sources/FocusPal"`
- [x] Source directory: `git mv Sources/DesktopHelper Sources/FocusPal`
- [x] Comments + paths in `AppDelegate`, `ConfigManager`, `HookInstaller`, `ClaudeCodeMonitor`
- [x] Runtime paths: `~/.claude/desktophelper/` → `~/.claude/focuspal/`, `~/.desktophelper/config.json` → `~/.focuspal/config.json`
- [x] HookInstaller adds **legacy cleanup**: removes any old `desktophelper/events.jsonl` hooks before installing new ones
- [x] `README.md`, `AGENTS.md`, `.gitignore` updated
- [x] Verify: `swift build` clean, `swift run` produces a binary called `FocusPal`, hook migration tested (legacy desktophelper hooks removed, new focuspal hooks installed)
- [ ] **MANUAL**: GitHub repo rename `agentboss` → `focuspal` (in repo Settings)
- [ ] **MANUAL**: `git remote set-url origin https://github.com/filippello/focuspal.git`
- [ ] **MANUAL**: rename local working directory `desktophelper` → `focuspal` (close any Claude Code sessions in this dir first, then `mv ~/Projects/tools/desktophelper ~/Projects/tools/focuspal`)

### B2. .app bundle script  ✅
- [x] `scripts/build-app.sh` produces `dist/FocusPal.app` (744K) with `LSUIElement=true`, `com.filippello.focuspal` bundle id, signed-off via `xattr -cr`. Reads from `swift build -c release`.
- [x] Verified locally: double-click on `dist/FocusPal.app` launches and shows menu bar 🐸.

### B3. GitHub Releases automation  ✅
- [x] `.github/workflows/release.yml` on macos-14 (arm64). Builds + zips + uploads zip + sha256 file.
- [x] Verified end-to-end: `git tag v0.2.0 && git push origin v0.2.0` triggered the workflow → release published with both assets → re-downloaded zip + verified sha256 matches.

### B4. Homebrew tap  ✅ (formula ready, manual tap repo creation pending)
- [x] `homebrew/Casks/focuspal.rb` with version `0.2.0`, SHA-256 from the published release, `app "FocusPal.app"`, `zap` cleanup of `~/.focuspal` + `~/.claude/focuspal` + plist.
- [x] `homebrew/README.md` documents: create `homebrew-tap` repo, copy formula, push, instructions for bumping version on each release.
- [x] README updated with three install paths.
- [ ] **MANUAL**: create `https://github.com/filippello/homebrew-tap` (public), copy `homebrew/Casks/focuspal.rb` → `Casks/focuspal.rb` in that repo, push.
- [ ] **MANUAL verify**: `brew tap filippello/tap && brew install --cask focuspal` installs FocusPal.app to `/Applications`.

## Out of scope (v0.3)
- AISummarySkill (lee transcripts + Claude API)
- StatsSkill (dashboard SwiftUI)
- Capa agéntica (skills emiten `AgenticAction`)
- Codesign + notarización
- Auto-update

## Order of operations
A0 → A1 → A2 → A3 → A4 → B1 → B2 → B3 → B4

## Review — v0.2 milestone

**Shipped:**

1. **Skill framework**: `Skill` protocol + `SkillContext` + `SkillRegistry` with priority/coalescing action queue, fast/slow tick events, mode-change broadcast, per-skill UserDefaults storage, and a single menu surface. AppDelegate is now wiring + UI only — adding a new behavior is one `register()` call.
2. **3 example skills**: `ReminderSkill` (replaces ad-hoc ReminderManager), `HealthBreakSkill` (replaces HealthReminder), and the demo `PomodoroSkill` with a fully interactive multi-step flow. Conversational `walkAndTalk` → `askFollowUp` chain keeps the frog on screen across questions.
3. **Bug fixes during the refactor**: stuck disappearing frame (cleared layer.contents), Stop+Notification double-firing causing every reminder to read as "awaiting input" (5s window check), button mapping for arbitrary `BubbleButton` lists (was hardcoded 4 snooze options).
4. **AGENTS.md** at repo root (symlinked from CLAUDE.md): architecture map, full glossary, "How to add a Skill" walkthrough with a copy-pasteable template, conventions, and a 14-step lifecycle trace from event hook → frog disappearing.
5. **Distribution path**: `scripts/build-app.sh` produces a 744K `.app`, `.github/workflows/release.yml` auto-publishes a GitHub Release on tag pushes (verified end-to-end with v0.2.0), `homebrew/Casks/focuspal.rb` ready to drop into a `homebrew-tap` repo for `brew install --cask filippello/tap/focuspal`.
6. **Project rename** AgentBoss → FocusPal across code, runtime paths (`~/.focuspal/`, `~/.claude/focuspal/`), and docs. HookInstaller migrates legacy hooks automatically.

**Manual follow-ups left for the user (non-blocking):**

- Rename GitHub repo `agentboss` → `focuspal` (Settings → Rename), update local `git remote set-url`.
- Rename local working dir `desktophelper` → `focuspal`.
- Create `https://github.com/filippello/homebrew-tap` (public) and push `homebrew/Casks/focuspal.rb` into it.

**What I'd revisit if doing it again:**

- Used a 3-arg python3 script bundled at runtime for the Claude Code hook payload — the current bash one-liner can't capture `session_id` from stdin JSON, so all events share an empty session id. Reminders end up clobbering one another across repos. Working as intended for a single-session use, but worth a follow-up.
- Could have written one or two unit tests around `ReminderSkill.addReminder` (kinds, upgrade rules, snooze) — the framework is pure-ish, the tests would have caught the auto-Notification upgrade bug before the user did.

**Out of scope, deferred to v0.3:**

- AISummarySkill (read transcripts via Claude API, render 1-line task summaries)
- StatsSkill (SwiftUI dashboard from events.jsonl + history.jsonl)
- Agentic layer (skills that emit `AgenticAction`s — spawn Claude sessions, run commands)
- Codesigning + notarization (need Apple Developer ID, $99/year)
- Auto-update mechanism
- Per-session reminders fix (needs hook payload parsing — see "What I'd revisit")
