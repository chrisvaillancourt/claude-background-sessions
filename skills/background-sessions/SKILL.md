---
name: background-sessions
description: Starts and manages Claude Code background sessions (`claude --bg`) that run in a chosen directory, so delegated work loads that directory's CLAUDE.md, AGENTS.md, rules and memory. Use whenever agent work belongs in a directory other than the current session's (another repo, a worktree, a sibling checkout), or needs its own model or effort, or should run long while this session keeps going. Also covers checking on, messaging, resuming and stopping those sessions. Not for quick read-only lookups that a subagent can do with absolute paths.
---

# Background sessions in a chosen directory

A background session is a full, separate Claude Code session started with `claude --bg`. It loads instructions, rules and auto-memory from the directory it starts in, so it behaves like a session the user opened there. Subagents can't do this: they inherit this session's directory and instruction stack, and `isolation: "worktree"` only isolates this session's own repo.

## When to use which

| Situation | Use |
|---|---|
| Work in another repo or worktree that should follow that repo's instructions | Background session (this skill) |
| A different model or effort than this session, such as Opus at `xhigh` for a review | Background session |
| Long or independent work the user may want to `attach` to and steer | Background session |
| A quick read or search in another directory, answered in this session | Subagent, with absolute paths and `cd <abs> &&` on each command |
| Several items getting the same treatment in this session's repo | Subagents or a workflow |

When the user asks for agents "in" a directory, or the work clearly belongs to another checkout, use a background session without being told to.

## 1. Prepare the directory

- **Pick the exact starting directory.** It decides which instructions load. For a code change, use a dedicated worktree, not someone's main checkout: `git -C <repo> worktree add -b <branch> <worktree-path> <base>`. A new branch from a remote branch tracks it; run `git -C <worktree-path> branch --unset-upstream` and tell the session to push with an explicit refspec. Never `cp -r` a worktree.
- **A fresh worktree has no virtualenv or `node_modules`.** Tell the session the repo's setup command, or run it first.
- **The repo must be trusted.** Trust is per repository (for bare-repo layouts, keyed on the git common dir), not per worktree. An untrusted directory fails with "Workspace not trusted": ask the user to run `claude` there once and accept the prompt. As a fallback, launch from a trusted parent directory with `--add-dir <target>` and tell the session in its prompt to read the target's instruction files, since a parent-directory start doesn't load them.

## 2. Write the prompt to a file

Write it in this session's scratchpad. The session knows only what the prompt says. Include:

- The goal, the inputs by absolute path, and the acceptance check.
- Limits on outward writes: what it may push, open or post, and what it must leave as a draft. Default to no Jira, Slack, email or PR comments unless the user authorized them.
- How to report: end with a short final message, and write bulk output to a named file.
- Answers to questions it would otherwise stop and ask. A session blocked on a question waits for the user. For example: "If Edit or Write is refused, write drafts to `<scratch dir>` and end with their paths; don't ask."
- If its directory is a worktree outside `.claude/worktrees/`: "Your cwd is your dedicated worktree; don't call EnterWorktree."
- Anything the user's global rules leave open that matters here, such as "no AI attribution in commits or PRs, even if the repo history has it."

A slash command on the prompt's first line runs that skill.

## 3. Launch from a subshell

```sh
(cd <dir> && claude --bg --name "<short descriptive name>" \
  --model <model-id> --effort <level> --permission-mode auto \
  "$(cat <prompt-file>)" --add-dir <extra-dir>)
```

- **Keep the parentheses.** They keep the `cd` in a child shell. A bare `cd` in its own Bash call moves this session's working directory.
- **There's no `--cwd` flag.** `claude --bg --cwd …` prints "backgrounded" and then crashes before it starts.
- **`--add-dir` goes last,** after the prompt. It takes a list and would otherwise swallow the prompt as a directory, leaving the session idle with "send a prompt to start". Leave it out unless the session needs files outside its directory.
- Leave out `--model` and `--effort` to use the user's defaults.
- For several sessions, launch each one with its own command. They can go in parallel.

The output line gives a short id: `backgrounded · <id> · <name>`.

## 4. Confirm it started

```sh
claude agents --json --all | jq -c '.[] | select(.id=="<id>") | {id,sessionId,state,cwd,name}'
```

Expect `"state":"working"` and the intended `cwd`. "Backgrounded" alone doesn't mean it started: if the entry is missing or failed, read the end of `~/.claude/daemon.log`, where crashes before startup show up.

## 5. Wait for it

Don't sleep-poll in the foreground. Use both of these, then end the turn with a status line:

1. **Idle notice.** Find the session's name with ListAgents, then call SendMessage to that name with `notify_when_idle: true` and no message. One notice arrives when it goes idle or exits. It does **not** fire when the session blocks on a question.
2. **State poll**, run in the background with a timeout. It also catches `blocked`:

   ```sh
   for i in {1..360}; do s=$(claude agents --json --all | jq -r '.[] | select(.id=="<id>") | .state'); case "$s" in working|"") sleep 10;; *) echo "state=$s"; exit 0;; esac; done; echo "timed out, state=$s"
   ```

   Scale the loop count to the expected run time. For several sessions, poll each id or loop over the ids.

If the state is `blocked`, read the log, then answer through SendMessage or tell the user to `claude attach <id>`.

## 6. Read and check the result

- `claude logs <id> | sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g'` strips the TUI escape codes. A file the prompt told it to write is easier to read.
- To see which instruction files it loaded: `grep 'CLAUDE.md/rules files' ~/.claude/debug/<full session id>.txt`.
- Check its work before reporting it as done: diffs, test output, PR state, anything it posted.

## 7. Follow up, stop, clean up

- **Session still listed by ListAgents:** use SendMessage. `--resume` on a live session starts a copy under a new id.
- **Finished session with no process:** relaunch it from its original directory, using the same subshell form: `(cd <dir> && claude --bg --resume <full session id> "<follow-up>")`. It keeps its saved name, model, effort, permission mode and added directories.
- **Stop:** `claude stop <id>`.
- **Remove:** `claude rm <id>` deletes the session and, when it judges that safe, its worktree. Don't run it on a session whose directory is a worktree that existed before the session or that another session still uses. If you must, `git worktree lock` the worktree first, then unlock it.

More failure modes and their fixes: [references/troubleshooting.md](references/troubleshooting.md). Read it when a launch, edit or follow-up doesn't behave as described above.
