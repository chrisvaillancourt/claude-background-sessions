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

## Why scripts

The scripts work around today's permission checks.
- **Launching:** a session must start in another directory, `claude --bg` has no option for that, and every one-line command that `cd`s without moving the calling session needs approval no matter what rules exist.
- **Waiting:** waiting needs a shell loop, which no rule can match either.

[docs/why-scripts.md](docs/why-scripts.md) has the evidence, what else each script fixes, and the conditions for removing them. `sh tests/permission-forms.sh <trusted repo dir>` reruns the permission test.

## Layout

- `skills/background-sessions/SKILL.md`: the steps every launch follows.
- `skills/background-sessions/scripts/launch.sh`: starts a session in a directory and confirms it's running.
- `skills/background-sessions/scripts/wait.sh`: waits for sessions to finish and prints their final replies.
- `skills/background-sessions/references/troubleshooting.md`: failure modes and fixes, read when something goes wrong.
- `docs/why-scripts.md`: why the scripts exist and when to remove them.
- `tests/permission-forms.sh`: reruns the permission test behind the scripts.

The scripts need `sh`, `jq` and `awk`; the test also needs `timeout`.

## Testing a change

Run `tests/permission-forms.sh`, then start a fresh headless session in default permission mode with a plain request. It should load the skill and run the scripts with no `permission_denials`:

```sh
claude -p --permission-mode default --output-format json \
  "Start a Haiku agent in <trusted repo dir> to report <something in that repo>. Wait for its answer, then report it and how you started the agent."
```

Verified with Claude Code 2.1.312.
