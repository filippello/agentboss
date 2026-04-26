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

## 2026-04-26 — Test the distribution path before tagging

**Mistake:** Tagged v0.2.0 → v0.2.1 → v0.2.2 → v0.2.3 in rapid succession because each release surfaced a different distribution-only bug that I never could have hit running `swift run` locally:
- v0.2.0: macOS auto-terminated `LSUIElement` agents via TAL
- v0.2.1: `.app` bundle was internally inconsistent because `swift build` embeds an ad-hoc signature in the binary but the bundle had no `_CodeSignature/` dir → spctl rejected, launch died
- v0.2.2: Gatekeeper quarantine on the unzipped Cask download blocked launch even after codesign was fixed
- v0.2.3: Swift Package Manager's auto-generated `resource_bundle_accessor.swift` resolves `Bundle.module` via `Bundle.main.bundleURL.appendingPathComponent("X_X.bundle")` — i.e. at the `.app`'s **root**, not inside `Contents/Resources/`. Putting the bundle in the conventional Cocoa location made `Bundle.module` fatalError on launch.

**Rule:** before tagging a release, build the distribution artifact (`scripts/build-app.sh`), zip it, extract it to a different directory, and double-click. Don't trust `swift run` as proof the binary works in production.

**How to apply:** add a manual smoke-test step to the release runbook — `(cd /tmp && rm -rf st && mkdir st && cd st && cp /repo/dist/X.zip . && unzip X.zip && open X.app && sleep 60 && pgrep X)`. If that fails, the release isn't ready.

## 2026-04-26 — Bundle.module looks at .app root, not Contents/Resources

**Specific symptom:** the `swift build`-bundled SPM target produces an auto-generated `resource_bundle_accessor.swift` that does:

```swift
let mainPath = Bundle.main.bundleURL
    .appendingPathComponent("FocusPal_FocusPal.bundle").path
```

`Bundle.main.bundleURL` is the `.app` itself. Resources expected at the **`.app` root**, not at `Contents/Resources/<bundle>`. Putting the bundle in the conventional Cocoa location makes the app `fatalError` on the first call to `Bundle.module`.

**Rule:** when manually packaging an SPM-built executable into a `.app`, mirror the resource bundle into the `.app` root. Optionally also mirror it into `Contents/Resources/` so `codesign --deep` stays happy and the bundle structure looks conventional, but the root copy is the load-bearing one.

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
