# Troubleshooting background sessions

| Symptom | Cause | Fix |
|---|---|---|
| Launch prints "idle — send a prompt to start", and the session's state is `failed`; `daemon.log` shows `unknown option '<prompt text>'` | The prompt starts with `-` and there was no `--` before it | Put `--` right before the prompt |
| Launch prints "idle — send a prompt to start", and `daemon.log` shows no crash | `--add-dir` came after the options with no `--`, and took the prompt as a directory | Put `--` right before the prompt |
| Launch prints "backgrounded", then the session is listed as `failed`, or `claude logs` fails with `connect ENOENT …control.sock` | It crashed before startup, for example from an unknown flag such as `--cwd` | Read the end of `~/.claude/daemon.log` for `settled <id> (crashed)` and its error, fix the command, and launch again |
| "Workspace not trusted" | The repo was never opened interactively | Ask the user to run `claude` in any checkout of that repo once and accept the trust prompt. `--add-dir` grants file access, not trust |
| Edit or Write refused with "This background session hasn't isolated its changes yet. Call EnterWorktree first" | The `worktree.bgIsolation` setting defaults to `"worktree"`, which blocks edits in a main checkout | Launch into a dedicated worktree. A repo can opt out with `"worktree": {"bgIsolation": "none"}` in its `.claude/settings.json`; that's the user's call. Never have the session write around the guard with shell redirects |
| The user gets a "permission-root relocation" prompt, and the session sees an error about its current directory | The session called EnterWorktree from a worktree outside `.claude/worktrees/` | Add to the prompt: "Your cwd is your dedicated worktree; don't call EnterWorktree." |
| Auto mode denies the launch ("Create Unsafe Agents") | No allow rule or classifier decision let it through | Tell the user; they can approve the denied call or add allow rules. Prefix rules such as `Bash(claude --bg:*)` may not match the `( cd … && claude --bg … )` form; that's unverified. Don't route around the denial |
| SendMessage reports the message is held for approval | The background session runs in a different permission mode | Tell the user to approve it there or `claude attach <id>`. Launch later sessions in this session's mode |
| SendMessage fails with "not reachable" | The finished session's process exited | Resume it with `claude --bg --resume <full session id> -- "<prompt>"` from its original directory, in a subshell |
| `--resume` printed a new id | The session was still alive, so resume started a copy | Stop the copy and message the original with SendMessage, using its `[ref]` if names collide |
| Idle notice never arrived | The session blocked on a question; the subscription only fires on idle or exit | Keep the background state poll running alongside it; it reports `blocked` |
| A session is `blocked` on a permission prompt | Permission prompts need the user | Tell the user to `claude attach <id>`; SendMessage can't approve it |
| This session's working directory changed after the launch | The `cd` ran in its own Bash call instead of a subshell | `cd` back, and use the `( … )` form next time |
| A background shell command ran in the wrong directory | Parallel Bash calls with `cd` raced | Use absolute paths or tool flags such as `git -C` and `uv --directory` |
