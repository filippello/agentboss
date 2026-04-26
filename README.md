# FocusPal

A playful desktop companion for **Claude Code** on macOS. A pixel‑art character (Ninja Frog by default) lives in your menu bar and occasionally hops onto the screen to let you know when your Claude Code sessions finish, need your input, or when it's time to take a break.

> _"Hey! solana-integration has been done for a while. Chrome isn't going anywhere, but your deadline is."_

![Hero placeholder — replace with a screenshot of the frog on your desktop](docs/hero.png)

---

## Why

If you run multiple Claude Code sessions in parallel, it's easy to wander off into Twitter/YouTube/Slack while agents finish their work in the background. FocusPal watches every active Claude Code session and a tiny character gently nags you back — funny, non‑disruptive, and context‑aware.

## Features

- **🐸 Menu‑bar command center** — see every active Claude Code session with its repo name and how long it's been running.
- **⚡ Reminders when tasks finish** — the frog walks into the middle of your screen and tells you, only if you've drifted away from the terminal.
- **⏸ "Waiting for you" detection** — when Claude Code pauses for a permission prompt (`Notification` hook), the frog appears sooner (2 min) with a different message.
- **😴 Snooze options** — click the frog: dismiss, 10 minutes, 1 hour, or tomorrow. Snoozes are per‑session, so other repos keep reminding you.
- **🧘 Hourly health nudges** — every 2 hours the frog does a quick "stand up, drink water, look away from the screen" pop — only when you're actually working.
- **🪟 Window aware** — the frog appears near the top‑right of whichever window is focused, on whichever monitor it lives on.
- **⚙️ Config‑driven** — tune delays, messages, sites that count as distractions, and more in `config.json` without rebuilding.

## Preview

| Character | Sprite |
|---|---|
| Ninja Frog (default) | ![](Sources/FocusPal/Resources/Main%20Characters/Ninja%20Frog/Idle%20%2832x32%29.png) |
| Mask Dude | ![](Sources/FocusPal/Resources/Main%20Characters/Mask%20Dude/Idle%20%2832x32%29.png) |
| Pink Man | ![](Sources/FocusPal/Resources/Main%20Characters/Pink%20Man/Idle%20%2832x32%29.png) |
| Virtual Guy | ![](Sources/FocusPal/Resources/Main%20Characters/Virtual%20Guy/Idle%20%2832x32%29.png) |

_Sprites from the excellent [Pixel Adventure 1](https://pixelfrog-assets.itch.io/pixel-adventure-1) pack by Pixel Frog (free for commercial use)._

## Architecture

```
┌──────────────────────┐     ┌───────────────────────────┐
│  ~/.claude/hooks     │     │  ~/.claude/sessions/*.json │
│  Stop / Notification │     │  (auto‑discovered PIDs)   │
│  UserPromptSubmit    │     └───────────────────────────┘
└──────────┬───────────┘                  │
           │                              │
           ▼                              ▼
┌────────────────────────┐     ┌────────────────────────┐
│ ClaudeCodeMonitor      │     │ SessionTracker         │
│ (events.jsonl watcher) │     │ (PID liveness poll)    │
└──────────┬─────────────┘     └──────────┬─────────────┘
           │                              │
           ▼                              ▼
       ┌─────────────────────────────────────┐
       │         ReminderManager             │
       │  (per‑session delays, snooze)       │
       └──────────────────┬──────────────────┘
                          │
                          ▼
       ┌─────────────────────────────────────┐
       │  CharacterStateMachine (Ninja Frog) │
       │  idle → alert → run → talk → hide   │
       │            └→ popAndSay (health)    │
       └─────────────────────────────────────┘
```

### Key modules

| File | Role |
|---|---|
| `main.swift` / `AppDelegate.swift` | NSApplication bootstrap, wiring, menu bar. |
| `SessionTracker.swift` | Polls `~/.claude/sessions/*.json`, verifies each PID with `kill(pid, 0)`. |
| `ClaudeCodeMonitor.swift` | Tails `~/.claude/focuspal/events.jsonl` for Stop / Notification / UserPromptSubmit hooks. |
| `HookInstaller.swift` | On first launch, adds the required hook lines to `~/.claude/settings.json` (non‑destructive — preserves existing hooks). |
| `ReminderManager.swift` | Per‑session reminder queue, snooze logic, upgrade from `taskComplete` → `awaitingInput`. |
| `HealthReminder.swift` | Hourly break nudge, skipped when the user is idle / AFK. |
| `WindowTracker.swift` | Finds the focused window via `CGWindowListCopyWindowInfo` (no Accessibility permissions needed). |
| `CharacterStateMachine.swift` + `CharacterView.swift` + `SpriteAnimator.swift` | Idle / run / talk / appear / disappear sprite animations. |
| `SpeechBubbleWindow.swift` / `ActionBubblesWindow.swift` | The speech bubble and the 4 snooze buttons that flank the frog when you click it. |

## Requirements

- macOS **13+** (Ventura or later)
- Swift **5.9+** (comes with Xcode Command Line Tools — full Xcode is **not** required)
- Claude Code installed and at least one session open

Check with:

```bash
swift --version   # expect: 5.9+
```

## Getting started

### Option A — download the .app (Apple Silicon only, for now)

1. Grab the latest `FocusPal-vX.Y.Z-arm64.zip` from [Releases](https://github.com/filippello/agentboss/releases).
2. Unzip and drag `FocusPal.app` to `/Applications`.
3. **First launch:** the app is unsigned, so right-click `FocusPal.app` → **Open** (Apple won't let you open it by double-click the first time).
4. Subsequent launches work normally.

### Option B — Homebrew (once the tap is published)

```bash
brew install --cask filippello/tap/focuspal
```

(See `homebrew/README.md` in the repo for tap publishing instructions.)

### Option C — build from source

```bash
git clone https://github.com/<you>/focuspal.git
cd focuspal
swift run                  # for development
scripts/build-app.sh       # to produce dist/FocusPal.app
```

On first launch the app will:

1. Show a 🐸 icon in the macOS menu bar (the app has no Dock icon).
2. Install the required Claude Code hooks in `~/.claude/settings.json` (preserving any existing hooks you have).
3. Start watching every active Claude Code session.

> **Restart any already‑open Claude Code sessions** so they pick up the newly installed hooks. Sessions started _after_ FocusPal is running already have them.

### Try the demo

Click the 🐸 menu bar icon → **🎬 Run Demo (solana integration)**. After 5 seconds the frog will hop out with a sample reminder so you can see the full flow without waiting for real events.

## Usage

### Menu bar

Click the 🐸 icon to see:

- The list of every active Claude Code session with its repo name and age (`⚡ focuspal — 3m ago`).
- **Health Reminders** toggle (on by default).
- **🎬 Run Demo** (⌘D) — triggers a sample reminder immediately.
- **Quit**.

### When a reminder fires

1. The frog _appears_ near the focused window, does a little jump, and runs to the middle of the screen.
2. A speech bubble shows a rotating funny message, e.g. _"{project} just dropped. Stop wasting time on {app} and go ship it!"_.
3. **Click the frog** → four snooze buttons flank it:
   - 👍 **OK** — dismiss, don't remind me again for this session.
   - 🕐 **10 min** — remind me in 10.
   - 🕐 **1 hour** — remind me in an hour.
   - 🌙 **Tomorrow** — remind me at 9 AM tomorrow.
4. The frog runs back and _disappears_ with a pixel animation.

### Health nudges

Every 2 hours (configurable), the frog does a quick pop — no walking, no buttons, just a message like _"Hour's up! Roll your shoulders, unclench your jaw, take a breath."_ and vanishes. Skipped when you've been AFK.

## Configuration

All behaviour lives in `config.json` in the project root. No rebuild needed — edit and relaunch.

```jsonc
{
  "characterName": "Ninja Frog",  // "Mask Dude" | "Pink Man" | "Virtual Guy"
  "characterSize": 96,

  "reminderTiming": {
    "firstDelayMinutes": 5,            // task completed → first nudge
    "secondDelayMinutes": 30,          // follow‑up if still ignored
    "awaitingInputDelayMinutes": 2     // Claude blocked on you → shorter nudge
  },

  "healthReminder": {
    "enabled": true,
    "intervalMinutes": 120,
    "onlyWhenWorking": true,
    "messages": [
      "Hour's up! Roll your shoulders, unclench your jaw, take a breath.",
      "Hydration check! When did you last drink water? Go get some."
    ]
  },

  "sites": {
    "youtube": {
      "keywords": ["youtube"],
      "message": "Your task is done! Stop watching YouTube and come check it out!",
      "thresholdSeconds": 45
    }
  },

  "apps": {
    "slack": {
      "bundleIds": ["com.tinyspeck.slackmacgap"],
      "message": "Task complete! Finish your chat and come check the code!",
      "thresholdSeconds": 120
    }
  }
}
```

### Personal overrides

Drop a file at `~/.focuspal/config.json` — it takes precedence over the repo's `config.json`. Handy for keeping your personal tweaks out of the repo.

## How the Claude Code integration works

FocusPal installs three hooks in `~/.claude/settings.json`:

| Hook | When it fires | What FocusPal does |
|---|---|---|
| `Stop` | Claude finishes its response | Queues a reminder (5 min default). |
| `Notification` | Claude is paused waiting for your approval | Queues a shorter reminder (2 min) — it's blocking you. |
| `UserPromptSubmit` | You submit a new prompt | Cancels any pending reminder for that session. |

Each hook appends a JSON line to `~/.claude/focuspal/events.jsonl`:

```json
{"event":"Stop","session":"<id>","cwd":"/path/to/repo","summary":"Task completed"}
```

If you already had hooks configured (e.g. Peon sounds from Warcraft — the author definitely doesn't do that), they're left untouched and ours are appended.

### Live session discovery

Independently of hooks, FocusPal polls `~/.claude/sessions/*.json` every 2 seconds. Each file is named after a PID, so liveness is verified with `kill(pid, 0)`. This is how the menu bar stays up to date with active sessions, even before any hook fires.

## Privacy

- **No network I/O.** Everything stays on your machine.
- **No telemetry.** The app never phones home.
- **No Accessibility permissions required.** Window tracking uses `CGWindowListCopyWindowInfo`, which doesn't need Accessibility.
- **Reads only from your home directory** (`~/.claude/` and `~/.focuspal/`). Writes only to `~/.claude/focuspal/events.jsonl` and (once, to install hooks) `~/.claude/settings.json`.

## Known limitations

- **Browser tab title detection** requires Automation permissions to AppleScript, which is disabled by default — the distraction context defaults to the app name. You can enable it in your code if you want richer messages.
- **macOS only.** The app is built on AppKit.
- **PID‑based session tracking** relies on Claude Code continuing to expose `~/.claude/sessions/*.json`. If Anthropic changes that layout, the tracker will need updating.

## Roadmap

Ideas floating around (PRs welcome):

- Drag the frog to reposition it; remember the chosen anchor per app.
- Per‑app perching (top of VS Code title bar, bottom of a browser tab bar).
- A tiny stats view: how long each session ran, how many tasks finished today.
- Optional `NSSpeechSynthesizer` TTS when the frog talks.
- More characters.

## Credits

- Character sprites: [Pixel Adventure 1](https://pixelfrog-assets.itch.io/pixel-adventure-1) by **Pixel Frog**.
- Built with Swift + AppKit. No frameworks, no dependencies.

## License

[MIT](LICENSE) — do whatever you want.
