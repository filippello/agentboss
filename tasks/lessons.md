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
