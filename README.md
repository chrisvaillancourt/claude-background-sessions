# claude-background-sessions

A Claude Code skill for starting background sessions (`claude --bg`) in a chosen directory. The session loads that directory's CLAUDE.md, AGENTS.md, rules and memory, and can run its own model and effort. The skill also covers confirming the start, waiting for the session to finish, reading its result, and following up.

The skill is model-invoked: Claude loads it when work belongs in another repo or worktree, so you don't have to spell out the launch steps.

## Install

From a checkout of this repository:

```sh
sfw pnpm dlx skills@1.5.26 add "$PWD" --skill background-sessions --agent claude-code --global --yes
```

`sfw` is Socket Firewall; drop it if you don't use it.

The installed copy is separate from the checkout: rerun the command after changing the skill.

## Recommended allow rules

So launches and waits don't stop on permission prompts or auto mode's safety check, add these to `permissions.allow` in `~/.claude/settings.json`. Replace `<home>` with your home directory written out: rules match the command text literally, so `~` and `$HOME` don't work.

```json
"Bash(sh <home>/.claude/skills/background-sessions/scripts/launch.sh:*)",
"Bash(sh <home>/.claude/skills/background-sessions/scripts/wait.sh:*)",
"Bash(claude --bg:*)",
"Bash(claude agents:*)",
"Bash(claude logs:*)",
"Bash(claude stop:*)"
```

The two script rules cover what the skill runs. The `claude` rules cover direct status checks and stops. `claude rm` is left out on purpose: it can delete a session's worktree.

Why scripts: launching in another directory needs a `cd`, and every one-line form that keeps the caller's directory in place needs approval no matter what rules exist. Tested with headless sessions in default permission mode on Claude Code 2.1.312:

| Command | Result |
|---|---|
| `claude --bg …` | Allowed by `Bash(claude --bg:*)` |
| `(cd <dir> && claude --bg …)` | Refused: "This command uses shell operators that require approval for safety" |
| `env -C <dir> claude --bg …` | Refused: "'env -C' can't be checked before it runs" |

## Layout

- `skills/background-sessions/SKILL.md`: the steps every launch follows.
- `skills/background-sessions/scripts/launch.sh`: starts a session in a directory and confirms it's running.
- `skills/background-sessions/scripts/wait.sh`: waits for sessions to finish and prints their final replies.
- `skills/background-sessions/references/troubleshooting.md`: failure modes and fixes, read when something goes wrong.

The scripts need `sh`, `jq` and `awk`.

Verified with Claude Code 2.1.312.
