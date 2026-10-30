# claude-background-sessions

A Claude Code skill that lets an agent hand work to another agent running in the right directory: another repo, or a git worktree. The new agent is a separate background session (`claude --bg`) started in that directory. It follows that directory's own instructions, settings, hooks and memory, and the session that started it stays where it was.

## The problem

You often coordinate from one place (a notes repository, a main checkout) while the work belongs somewhere else, such as a fix in another repo or a review in a worktree. Claude Code's built-in way to delegate is the Agent tool, and its subagents can't run "over there":

- **They inherit the caller's directory and instructions.** A subagent sent from a notes repo into a code repo follows the notes repo's CLAUDE.md, rules and memory, not the code repo's. Telling it to read the target's instruction files doesn't bring in the target's settings, hooks or memory.
- **Every command needs a `cd` or absolute paths.** One slip and it runs in the wrong repo.
- **Worktree isolation isolates the wrong repo.** `isolation: "worktree"` makes a worktree of the caller's repo, not the target's. In one run, the harness deleted those unused worktrees mid-task and the agents' shells died.

A background session started in the target directory has none of these problems. Starting and managing one well is fiddly, though, and every one of these traps showed up in testing:

- **No directory option:** `claude --bg` can't be told where to start, and the obvious ways to change directory either move the calling session or need a permission approval every time.
- **A dropped prompt that looks fine:** a prompt starting with `-` is read as an option, and the session dies before it starts while the launch still prints "backgrounded".
- **Waiting is unreliable:** the built-in idle notice misses a session stuck on a question. After a follow-up message, the session list can report a finished session as still working.
- **Garbled output:** `claude logs` mangles words and numbers.
- **Repo setup:** worktree placement, trust, the background edit guard, permission modes and cleanup all need care.

This skill gives agents one tested way through all of that. It's model-invoked: when you ask for an agent in a directory, or when code work belongs to another checkout, Claude loads it on its own, so you don't have to spell out the steps.

## What it does

1. **Prepares the directory:** a dedicated, freshly fetched worktree for code changes, and a trust check.
2. **Writes the agent's prompt to a file,** covering its goal, limits on outward writes, where output goes, and answers to questions it might otherwise stop and ask.
3. **Launches with `scripts/launch.sh`,** which starts the session in the target directory without moving the caller and confirms it's actually running.
4. **Waits with `scripts/wait.sh`** plus the built-in idle notice. The script prints the session's final reply from its transcript, and has a mode for waiting on follow-up messages.
5. **Checks the work, follows up, and cleans up** worktrees only when their work is committed and pushed or merged.

Background on every choice, with evidence: [docs/decisions.md](docs/decisions.md).

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
- `docs/decisions.md`: each design decision, why it was made, the evidence, and what's still unverified.
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
