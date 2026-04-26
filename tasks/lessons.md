# Lessons

> Append a new entry every time a correction lands. Re-read at session start.

## 2026-04-25 — Apply orchestration skill end-to-end

**Mistake:** I drifted into ad-hoc work without using the orchestration workflow even though the skill was loaded — making plans only in `~/.claude/plans/`, calling `TaskCreate` rarely, no `tasks/` directory in the repo, no subagents for exploration.

**Rule:**
- Every project: `tasks/todo.md` + `tasks/lessons.md` in the repo root.
- Mirror plans as checkable items; mark them done in real time.
- Use Plan/Explore subagents before non-trivial refactors — don't refactor blind from main context.
- Verification is a gate, not a habit: every task must show evidence (build output, observed behavior, demo) before being marked complete.

**How to apply:** at the start of any session in this repo, read `tasks/todo.md` and `tasks/lessons.md`. If a `tasks/` dir doesn't exist yet, create it before doing anything else.

## 2026-04-26 — LSUIElement agents need explicit termination opt-out

**Mistake:** Shipped v0.2.0 as a packaged `.app` with `LSUIElement=true` but no termination opt-outs. macOS silently auto-terminated the menu-bar agent within ~30s of idle, the user's frog "just disappeared". The system log showed `_kLSApplicationWouldBeTerminatedByTALKey=1` — AppKit's TAL (Automatic Termination) machinery decided FocusPal was inactive.

**Rule for menu-bar / LSUIElement apps:** belt and suspenders both —
1. Info.plist: `NSSupportsAutomaticTermination=false`, `NSSupportsSuddenTermination=false`.
2. At startup: `ProcessInfo.processInfo.disableAutomaticTermination(...)` + `disableSuddenTermination()`.

The plist alone isn't enough when running unbundled (`swift run`); the programmatic call alone isn't enough on cold-launch from `/Applications`. Apply both.

**How to apply:** any time you set an app's activation policy to `.accessory` or set `LSUIElement` true, add the four termination opt-outs in the same change. There's no scenario where a menu-bar agent wants to be auto-terminated.

## 2026-04-26 — Don't trust enum-based event upgrades without timing windows

**Mistake:** ReminderSkill upgraded `.taskComplete` → `.awaitingInput` whenever a Notification event arrived for a session that already had a reminder, on the assumption that Notification meant "Claude is blocked". The user reported every reminder showing the "waiting for input" message instead of the friendly "task done" one. Inspection of `events.jsonl` revealed Claude Code emits Stop+Notification *as a pair* every time it finishes — the Notification is the auto-ping, not a block signal.

**Rule:**
- For events that arrive in fixed-order pairs from external systems, don't infer semantics from the second event alone — check the time delta from the first.
- When integrating with a black-box upstream (Claude Code hooks), tail the raw event log before designing logic on top of it. The shape of the stream surprises you.
- Concretely: fixed by ignoring `.awaitingInput` if it arrives within 5s of an existing `.taskComplete` reminder for the same session.

**How to apply:** before writing branch logic on event-stream upgrades, dump 30 seconds of real events to a file and look at the actual order/spacing.
