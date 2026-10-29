# AGENTS.md

This repository is the `background-sessions` Claude Code skill: starting `claude --bg` sessions in a chosen directory and managing them.

## Where to look

| Task | Read |
|---|---|
| What the skill tells agents to do | [skills/background-sessions/SKILL.md](skills/background-sessions/SKILL.md) |
| Failure modes and fixes | [references/troubleshooting.md](skills/background-sessions/references/troubleshooting.md) |
| Install | [README.md](README.md) |

## Rules

- **The installed copy is separate.** Editing this checkout doesn't change it; rerun the README's install command after a change.
- **Verify behavior before writing it down.** Each claim about `claude --bg` should come from a run on a named Claude Code version. Update the version in the README when you re-verify.
- **Keep it generic.** No personal paths, account names, organization names or ticket keys in the skill or docs.
- **SKILL.md holds what every launch needs.** Rarer failure modes go in the troubleshooting reference.
- **Update every reference when something changes:** SKILL.md, the reference, the README and this file.

## Commits

Sentence-case imperative messages, no prefixes, no tool attribution.
