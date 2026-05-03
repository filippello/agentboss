---
description: Control FocusPal from any Claude Code session — toggle the frog, run a Pomodoro, demo the rest party, or import a pet from petdex.
disable-model-invocation: true
allowed-tools: Bash(echo *), Bash(mkdir *), Bash(date *)
---

!`mkdir -p ~/.claude/focuspal && a="$ARGUMENTS" && cmd="${a%% *}" && rest="${a#"$cmd"}" && rest="${rest# }" && echo "{\"command\":\"$cmd\",\"args\":\"$rest\",\"ts\":$(date +%s)}" >> ~/.claude/focuspal/commands.jsonl`

FocusPal: $ARGUMENTS

## Sub-commands

- `/focuspal` — toggle the frog (or dismiss whatever it's doing right now)
- `/focuspal pomodoro` — start the conversational Pomodoro flow
- `/focuspal demo` — kick off the rest-party demo
- `/focuspal health` — toggle hourly health-break reminders
- `/focuspal show` / `/focuspal hide` — explicit visibility
- `/focuspal petdex <name>` — import a pet from https://petdex.crafter.run/ (e.g. `/focuspal petdex boba`)

The slash command writes the request to `~/.claude/focuspal/commands.jsonl`.
The FocusPal app polls that file every 0.5s and acts accordingly. Make sure
FocusPal is running (`brew install --cask filippello/tap/focuspal`).
