# AGENTS.md

This repository is the `background-sessions` Claude Code skill: starting `claude --bg` sessions in a chosen directory and managing them.

## Where to look

| Task | Read |
|---|---|
| What the skill tells agents to do | [skills/background-sessions/SKILL.md](skills/background-sessions/SKILL.md) |
| How a session is launched and confirmed | [scripts/launch.sh](skills/background-sessions/scripts/launch.sh) |
| How sessions are waited on and results read | [scripts/wait.sh](skills/background-sessions/scripts/wait.sh) |
| Failure modes and fixes | [references/troubleshooting.md](skills/background-sessions/references/troubleshooting.md) |
| Allow rules and why the scripts exist | [README.md](README.md) |
| Install | [README.md](README.md) |

## Rules

- **The installed copy is separate.** Editing this checkout doesn't change it; rerun the README's install command after a change.
- **Verify behavior before writing it down.** Each claim about `claude --bg` should come from a run on a named Claude Code version. Update the version in the README when you re-verify.
- **Keep it generic.** No personal paths, account names, organization names or ticket keys in the skill or docs.
- **Every command the skill tells agents to run must be matchable by an allow rule:** a plain `sh <absolute path>/scripts/<name>.sh …` or a plain `claude <subcommand> …`, with no `cd`, subshell, pipe, variable or `$( … )`. Logic that needs those goes in a script. Test a new form with a headless session in default permission mode (a refused command shows up in `permission_denials`).
- **Scripts stay POSIX `sh`** plus `jq` and `awk`. Test the failure paths too: a bad option, a missing id.
- **SKILL.md holds what every launch needs.** Rarer failure modes go in the troubleshooting reference.
- **Update every reference when something changes:** SKILL.md, the reference, the README and this file.

## Commits

Sentence-case imperative messages, no prefixes, no tool attribution.
