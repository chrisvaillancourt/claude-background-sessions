# AGENTS.md

This repository is the `background-sessions` Claude Code skill: starting `claude --bg` sessions in a chosen directory and managing them. The README explains the problem it solves.

## Where to look

| Task | Read |
|---|---|
| Why the skill does something the way it does, before changing it | [docs/decisions.md](docs/decisions.md) |
| What the skill tells agents to do | [skills/background-sessions/SKILL.md](skills/background-sessions/SKILL.md) |
| How a session is launched and confirmed | [scripts/launch.sh](skills/background-sessions/scripts/launch.sh) |
| How sessions are waited on and results read | [scripts/wait.sh](skills/background-sessions/scripts/wait.sh) |
| Failure modes and fixes | [references/troubleshooting.md](skills/background-sessions/references/troubleshooting.md) |
| Allow rules | [README.md](README.md) |
| Why the scripts exist, and when to remove them | [docs/why-scripts.md](docs/why-scripts.md) |
| Re-check which command forms permissions allow | [tests/permission-forms.sh](tests/permission-forms.sh) |
| Install | [README.md](README.md) |

## Rules

- **The installed copy is separate.** Editing this checkout doesn't change it; rerun the README's install command after a change.
- **Verify behavior before writing it down.** Each claim about `claude --bg` should come from a run on a named Claude Code version. Update the version in the README when you re-verify.
- **Keep it generic.** No personal paths, account names, organization names or ticket keys in the skill or docs.
- **Every command the skill tells agents to run must be matchable by an allow rule:** a plain `sh <absolute path>/scripts/<name>.sh …` or a plain `claude <subcommand> …`, with no `cd`, subshell, pipe, variable or `$( … )`. Logic that needs those goes in a script. Test a new form with a headless session in default permission mode (a refused command shows up in `permission_denials`); `tests/permission-forms.sh` does this for the known forms. Don't remove or bypass a script without meeting the conditions in `docs/why-scripts.md`.
- **Scripts stay POSIX `sh`** plus `jq` and `awk`. Test the failure paths too: a bad option, a missing id.
- **SKILL.md holds what every launch needs.** Rarer failure modes go in the troubleshooting reference.
- **Don't reverse a decision silently.** If a change contradicts [docs/decisions.md](docs/decisions.md), update that entry with what changed and why, and record new decisions there with their evidence. Move an item out of "Not verified" when you verify it.
- **Update every reference when something changes:** SKILL.md, the reference, the README, the docs and this file.

## Commits

Sentence-case imperative messages, no prefixes, no tool attribution.
