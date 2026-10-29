# Troubleshooting background sessions

| Symptom | Cause | Fix |
|---|---|---|
| Launch prints "backgrounded", then the session isn't listed or `claude logs` fails with `connect ENOENT …control.sock` | It crashed before startup, for example from an unknown flag such as `--cwd` | Read the end of `~/.claude/daemon.log` for `settled <id> (crashed)` and its error, fix the command, and launch again |
| Session sits idle with "send a prompt to start" | `--add-dir` came before the prompt and took it as a directory | Put `--add-dir` last |
| "Workspace not trusted" | The repo was never opened interactively | Ask the user to run `claude` in any checkout of that repo once and accept the trust prompt. `--add-dir` grants file access, not trust |
| Edit or Write refused with "This background session hasn't isolated its changes yet. Call EnterWorktree first" | The `worktree.bgIsolation` setting defaults to `"worktree"`, which blocks edits in a main checkout | Launch into a dedicated worktree. A repo can opt out with `"worktree": {"bgIsolation": "none"}` in its `.claude/settings.json`; that's the user's call. Never have the session write around the guard with shell redirects |
| The user gets a "permission-root relocation" prompt, and the session sees an error about its current directory | The session called EnterWorktree from a worktree outside `.claude/worktrees/` | Add to the prompt: "Your cwd is your dedicated worktree; don't call EnterWorktree." |
| Auto mode denies the launch ("Create Unsafe Agents") | No allow rule matches the command | The user can add allow rules `Bash(claude --bg:*)`, `Bash(claude agents:*)`, `Bash(claude logs:*)` and `Bash(claude stop:*)`, or approve the denied call. Don't route around the denial |
| SendMessage fails with "not reachable" | The finished session's process exited | Resume it with `claude --bg --resume <full session id> "<prompt>"` from its original directory, in a subshell |
| `--resume` printed a new id | The session was still alive, so resume started a copy | Stop the copy and message the original with SendMessage |
| Idle notice never arrived | The session blocked on a question; the subscription only fires on idle or exit | Keep the background state poll running alongside it; it reports `blocked` |
| This session's working directory changed after the launch | The `cd` ran in its own Bash call instead of a subshell | `cd` back, and use the `( … )` form next time |
| A background shell command ran in the wrong directory | Parallel Bash calls with `cd` raced | Use absolute paths or tool flags such as `git -C` and `uv --directory` |
