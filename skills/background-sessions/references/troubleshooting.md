# Troubleshooting background sessions

| Symptom | Cause | Fix |
|---|---|---|
| `launch.sh` exits 1 with `unknown option '…'` from `daemon.log` | An option `claude --bg` doesn't take, such as `--cwd` | Check `claude --help`, fix the options after the prompt file, and launch again |
| `launch.sh` exits 1: "not listed by 'claude agents' after 15s" | The daemon didn't register the session | Read the end of `~/.claude/daemon.log` for the id and its error |
| A hand-rolled launch prints "idle — send a prompt to start" | The prompt started with `-`, or `--add-dir` swallowed it, because there was no `--` before the prompt | Use `launch.sh`, which adds the `--` |
| "Workspace not trusted" | The repo was never opened interactively | Ask the user to run `claude` in any checkout of that repo once and accept the trust prompt. `--add-dir` grants file access, not trust |
| The launch or wait call needs approval, or auto mode denies it ("Create Unsafe Agents") | The call isn't the plain `sh <absolute path>/scripts/<name>.sh …` form, or the user hasn't added the allow rules from the README | Use the plain form with the skill directory written out. If it's still refused, tell the user; don't route around the denial |
| Edit or Write refused with "This background session hasn't isolated its changes yet. Call EnterWorktree first" | The `worktree.bgIsolation` setting defaults to `"worktree"`, which blocks edits in a main checkout | Launch into a dedicated worktree. A repo can opt out with `"worktree": {"bgIsolation": "none"}` in its `.claude/settings.json`; that's the user's call. Never have the session write around the guard with shell redirects |
| The user gets a "permission-root relocation" prompt, and the session sees an error about its current directory | The session called EnterWorktree from a worktree outside `.claude/worktrees/` | Add to the prompt: "Your cwd is your dedicated worktree; don't call EnterWorktree." |
| SendMessage reports the message is held for approval | The background session runs in a different permission mode | Tell the user to approve it there or `claude attach <id>`. Launch later sessions in this session's mode |
| SendMessage fails with "not reachable" | The finished session's process exited | Resume it: `sh <skill dir>/scripts/launch.sh <original dir> <prompt-file> --resume <full session id>` |
| `--resume` printed a new id | The session was still alive, so resume started a copy | Stop the copy and message the original with SendMessage, using its `[ref]` if names collide |
| Idle notice never arrived | The session blocked on a question; the subscription only fires on idle or exit | Keep `wait.sh` running alongside it; it exits 3 on `blocked` |
| A session is `blocked` on a permission prompt | Permission prompts need the user | Tell the user to `claude attach <id>`; SendMessage can't approve it |
| This session's working directory changed | A `cd` ran in its own Bash call, for example while checking results | `cd` back, and use absolute paths or `git -C` |
| A background shell command ran in the wrong directory | Parallel Bash calls with `cd` raced | Use absolute paths or tool flags such as `git -C` and `uv --directory` |
