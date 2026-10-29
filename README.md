# background-sessions

A Claude Code skill for starting background sessions (`claude --bg`) in a chosen directory. The session loads that directory's CLAUDE.md, AGENTS.md, rules and memory, and can run its own model and effort. The skill also covers confirming the start, waiting for the session to finish, reading its result, and following up.

The skill is model-invoked: Claude loads it when work belongs in another repo or worktree, so you don't have to spell out the launch steps.

## Install

From a checkout of this repository:

```sh
pnpm dlx skills@1.5.26 add "$PWD" --skill background-sessions --agent claude-code --global --yes
```

The installed copy is separate from the checkout: rerun the command after changing the skill.

## Recommended allow rules

So launches and status checks don't stop on permission prompts, add these to `permissions.allow` in `~/.claude/settings.json`:

```json
"Bash(claude --bg:*)",
"Bash(claude agents:*)",
"Bash(claude logs:*)",
"Bash(claude stop:*)"
```

`claude rm` is left out on purpose: it can delete a session's worktree.

## Layout

- `skills/background-sessions/SKILL.md`: the steps every launch follows.
- `skills/background-sessions/references/troubleshooting.md`: failure modes and fixes, read when something goes wrong.

Verified with Claude Code 2.1.312.
