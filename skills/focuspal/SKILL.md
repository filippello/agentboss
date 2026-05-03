---
description: Control FocusPal from any Claude Code session — toggle the frog, run a Pomodoro, demo the rest party, or import a pet from petdex.
disable-model-invocation: true
allowed-tools: Bash(mkdir *), Bash(echo *)
---

!`mkdir -p ~/.claude/focuspal`

!`echo '{"raw":"$ARGUMENTS"}' >> ~/.claude/focuspal/commands.jsonl`

FocusPal: $ARGUMENTS

## Sub-commands

- `/focuspal` — toggle the frog (or dismiss whatever it's doing right now)
- `/focuspal pomodoro` — start the conversational Pomodoro flow
- `/focuspal demo` — kick off the rest-party demo
- `/focuspal health` — toggle hourly health-break reminders
- `/focuspal show` / `/focuspal hide` — explicit visibility
- `/focuspal petdex <name>` — import a pet from https://petdex.crafter.run/ (e.g. `/focuspal petdex boba`)

The slash command writes the raw `$ARGUMENTS` line to `~/.claude/focuspal/commands.jsonl`.
FocusPal polls that file every 0.5s and parses the command itself (splitting
the first whitespace into subcommand + args). The bash here is intentionally
trivial — Claude Code rejects SKILL.md scripts that contain parameter
expansion (`${...}`, `$(...)`).

Make sure FocusPal is running (`brew install --cask filippello/tap/focuspal`).
