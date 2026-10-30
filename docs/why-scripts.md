# Why the skill uses scripts, and when to remove them

The skill could tell agents to run `claude --bg` directly. It ships `launch.sh` and `wait.sh` instead because of how Claude Code's permission checks work today, not because the logic is complicated. If those checks change, the scripts may be unnecessary. This page records what forced each script, the evidence, and how to tell when it no longer applies.

Recorded 2026-10-29 on Claude Code 2.1.312.

## The constraint

A background session loads instructions, rules and memory from the directory it starts in, and `claude --bg` has no option to choose that directory. So something has to `cd` first, and the calling session's own working directory must not move.

Every command the skill gives agents also has to be one that a permission allow rule can match. If it isn't, it needs approval each time. Under auto mode, an unmatched command goes to the safety classifier, which has denied background launches before ("Create Unsafe Agents") and can't be counted on.

## What was tested

These are headless sessions in default permission mode, with allow rules `Bash(claude --bg:*)` and the two script rules from the README. A headless session can't ask, so an unmatched command is refused and listed in `permission_denials`. `tests/permission-forms.sh` reruns this.

| Command | Result | Problem |
|---|---|---|
| `cd <dir>` as its own call, then `claude --bg …` | Runs | The `cd` moves the calling session's working directory; the harness announced a new primary working directory |
| `(cd <dir> && claude --bg …)` | Refused | "This command uses shell operators that require approval for safety." No rule can match it |
| `env -C <dir> claude --bg …` | Refused | "'env -C' can't be checked before it runs" |
| `claude --bg --cwd <dir> …` | Prints "backgrounded", then crashes | No such option: `daemon.log` shows `unknown option '--cwd'` |
| `claude --bg …` with no `cd` | Allowed | Starts in the wrong directory |
| `sh <home>/.claude/skills/background-sessions/scripts/launch.sh …` | Allowed | None |
| `sh <home>/.claude/skills/background-sessions/scripts/wait.sh …` | Allowed | None |

The `(cd …)` form did run in auto mode in earlier tests, but only because the classifier approved it each time.

## Why `launch.sh`

It exists to change directory without moving the caller and without a command form the rules can't match. It also does three things the old instructions asked agents to do by hand, and that went wrong in testing:

- **Puts `--` before the prompt.** A prompt starting with `-` (a Markdown bullet or front matter) was parsed as an unknown option and the session crashed before starting (probe `bfc74573`). `--` also stops `--add-dir`, which takes a list, from swallowing the prompt.
- **Reads the prompt from a file.** `"$(cat file)"` in the agent's own command is command substitution, which is another form rules can't match.
- **Confirms the start.** "backgrounded" prints even when the session crashes before it starts. The script checks `claude agents` for `failed` and prints the `daemon.log` error.

## Why `wait.sh`

It exists because waiting needs a loop (`for`, `case`, `$( … )`), and a loop typed into the Bash tool can't be matched by a rule either. It also:

- **Reads the final reply from the transcript.** `claude logs` is a redraw of the terminal screen; after stripping escape codes, words and numbers were garbled.
- **Catches `blocked`.** The built-in idle subscription (SendMessage `notify_when_idle`) doesn't fire when a session stops to ask a question; observed 2026-10-16.
- **Waits correctly after a follow-up** (`--after-message`). Once a session has had a SendMessage message, `claude agents` reported `state: "working"` with `status: "idle"` for minutes after it had replied (session `efe9bef0`, 2026-10-29). A wait on `state` alone hung. The session also replied within a second, so "wait until it's seen working again" would miss the busy period. The script instead reads the transcript for a reply after the message.
- **Waits for a session's own next turn** (`--next-turn`). A session idle until its own background job notifies it gets no message, and an idle subscription fires at once for the turn that already ended. The script records the transcript's length and waits for a reply after it (decision 16 in [decisions.md](decisions.md)).

## When to remove them

Rerun `sh tests/permission-forms.sh <trusted repo dir>` after Claude Code updates that touch permissions or background sessions, and check `claude --help`.

- **Remove `launch.sh`** when any of these holds, and the replacement form is in SKILL.md with the `--` before the prompt:
  - `claude --bg` gains an option to set the starting directory, such as `--cwd` (check `claude --help`);
  - the subshell or `env -C` case in the test shows 0 denied with an allow rule that names only `claude --bg`;
  - Claude Code adds a supported way to start a background session in a chosen directory from a tool call.

  The start check would then go back into SKILL.md as a `claude agents --json --all` step, or into a smaller script if that command itself can't be matched.
- **Remove `wait.sh`** when both of these hold:
  - a plain command or built-in notification reports a session's end, including `blocked`, without a shell loop;
  - there's a plain way to read the final reply that isn't garbled, such as a `claude logs` option for plain text or the final message.

  `--after-message` can go once `state` reliably reports idle after a message, or once the idle notice is reliable enough to use alone. `--next-turn` can go once an idle notice requested while a session is already idle waits for its next turn.

  Without both, keep it or replace only the half that changed.

After removing either, update the README's allow rules, SKILL.md steps 3 to 5, the troubleshooting rows that name the scripts, and `AGENTS.md`. Then rerun the headless test from the README.
