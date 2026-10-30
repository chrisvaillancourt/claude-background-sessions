---
name: background-sessions
description: Starts and manages Claude Code background sessions (`claude --bg`) that run in a chosen directory, so the work loads that directory's CLAUDE.md, AGENTS.md, rules and memory instead of this session's. Use when the user asks for an agent or session in, or working on, a specific repo, worktree or directory, and whenever delegated work belongs in a directory other than this session's. Also use for agents the user wants to attach to and steer, or that must outlive this session, and for checking on, messaging, resuming or stopping background sessions. Not for lookups in this session's own repo; a subagent covers those, including other models and effort levels.
---

# Background sessions in a chosen directory

A background session is a full, separate Claude Code session started with `claude --bg`. It loads instructions, rules and auto-memory from the directory it starts in, so it behaves like a session the user opened there. Subagents can't do this: they inherit this session's directory and instruction stack, and `isolation: "worktree"` only isolates this session's own repo.

## When to use which

| Situation | Use |
|---|---|
| The user asks for an agent in a specific directory, repo or worktree, even for a small read-only task | Background session (this skill) |
| Work in another repo or worktree that should follow that repo's instructions | Background session |
| Work the user wants to `attach` to and steer, or that must keep running after this session ends | Background session |
| Work in this session's repo that only needs another model, another effort level or to run in the background | Subagent: the Agent tool takes `model` and `effort` and can run in the background |
| Several items getting the same treatment in this session's repo | Subagents or a workflow |

Use a background session without being told to whenever the work belongs to another checkout. Don't ask the user to spell out the steps below.

## 1. Prepare the directory

- **Pick the exact starting directory.** It decides which instructions load.
- **Code changes get a dedicated worktree, one per session.** Never two code-changing sessions in one checkout, and never someone's main checkout. Put the worktree outside the repo's working tree, or at `<repo>/.claude/worktrees/<name>` after `git -C <repo> check-ignore -q .claude/worktrees/x` confirms that path is ignored. A worktree at a non-ignored path inside a checkout shows up there as an untracked embedded repo, and `git add -A` would commit it.

  ```sh
  git -C <repo> worktree add -b <branch> <worktree-path> <base>
  ```

  A new branch from a remote branch tracks it: run `git -C <worktree-path> branch --unset-upstream` and tell the session to push with an explicit refspec. Never `cp -r` a worktree.
- **A fresh worktree has no virtualenv or `node_modules`.** Tell the session the repo's setup command, or run it first.
- **The repo must be trusted.** Trust is per repository (for bare-repo layouts, keyed on the git common dir), not per worktree. An untrusted directory fails with "Workspace not trusted": ask the user to run `claude` there once and accept the prompt. As a fallback, launch from a trusted parent directory with `--add-dir <target>`, and tell the session in its prompt to read the target's instruction files, since a parent-directory start doesn't load them.

## 2. Write the prompt to a file

Write it in this session's scratchpad. The session knows only what the prompt says. Include:

- The goal, the inputs by absolute path, and the acceptance check.
- Limits on outward writes: what it may push, open or post, and what it must leave as a draft. Default to no Jira, Slack, email or PR comments unless the user authorized them.
- **Where to put output.** A session writes freely only inside its own directory. Any other output path must be a directory that isn't inside a git checkout, such as this session's scratchpad, and must go in the launch command with `--add-dir`. The background-isolation guard can refuse Edit and Write in another git checkout even when it's added. Otherwise have it put results in its final message.
- Answers to questions it would otherwise stop and ask. A session blocked on a question waits for the user. For example: "If Edit or Write is refused, write drafts to `<added dir>` and end with their paths; don't ask."
- If its directory is a worktree outside `.claude/worktrees/`: "Your cwd is your dedicated worktree; don't call EnterWorktree."
- Anything the user's global rules leave open that matters here, such as "no AI attribution in commits or PRs, even if the repo history has it."

A slash command on the prompt's first line runs that skill.

## 3. Launch from a subshell

```sh
(cd <dir> && claude --bg --name "<short descriptive name>" \
  --model <model-id> --effort <level> --permission-mode <mode> \
  --add-dir <extra-dir> -- "$(cat <prompt-file>)")
```

- **Keep the parentheses.** They keep the `cd` in a child shell. A bare `cd` in its own Bash call moves this session's working directory.
- **Keep the `--` before the prompt.** Without it, a prompt that starts with `-` (a bullet or front matter) is parsed as an unknown option, and the session crashes before it starts. `--` also stops `--add-dir`, which takes a list, from swallowing the prompt.
- **There's no `--cwd` flag.** `claude --bg --cwd …` prints "backgrounded" and then crashes before it starts.
- **Use this session's own permission mode.** A session in a different mode holds this session's messages for its user's approval, so follow-ups and answers can sit unseen.
- Leave out `--add-dir` unless the session needs a directory outside its own. Leave out `--model` and `--effort` to use the user's defaults.
- For several sessions, launch each one with its own command. They can go in parallel.

The output line gives a short id: `backgrounded · <id> · <name>`. If it adds "idle — send a prompt to start", the prompt didn't arrive; see troubleshooting.

## 4. Confirm it started

```sh
claude agents --json --all | jq -c '.[] | select(.id=="<id>") | {id,sessionId,state,cwd,name}'
```

Expect `"state":"working"` and the intended `cwd`. "Backgrounded" alone doesn't mean it started. If the state is `failed`, read the end of `~/.claude/daemon.log`, where a crash before startup shows up as `settled <id> (crashed)` with the error.

## 5. Wait for it

Don't sleep-poll in the foreground. Use both of these, then end the turn with a status line:

1. **Idle notice** (main conversation only; a subagent can't subscribe). Find the session's name with ListAgents, then call SendMessage to that name with `notify_when_idle: true` and no message. One notice arrives when it goes idle or exits. It does **not** fire when the session blocks on a question.
2. **State poll**, run in the background with a timeout. It also catches `blocked`, and gives up early if the id is wrong:

   ```sh
   miss=0; for i in {1..360}; do s=$(claude agents --json --all | jq -r '.[] | select(.id=="<id>") | .state'); case "$s" in working) miss=0; sleep 10;; "") miss=$((miss+1)); [ $miss -ge 3 ] && { echo "id not found"; exit 1; }; sleep 10;; *) echo "state=$s"; exit 0;; esac; done; echo "timed out, state=$s"
   ```

   Scale the loop count to the expected run time. For several sessions, poll each id or loop over the ids.

If the state is `blocked`, look at what it's waiting on. Answer a question through SendMessage. A permission prompt can't be answered by message: tell the user to `claude attach <id>`.

## 6. Read and check the result

- **Final answer:** read it from the transcript, not from `claude logs`, which is a redraw stream of the terminal UI that garbles words and numbers.

  ```sh
  jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' ~/.claude/projects/*/<full session id>.jsonl | tail -n 40
  ```

  A file the prompt told it to write is easier still.
- **Progress glances:** `claude logs <id> | sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g'`.
- **Which instruction files it loaded,** if debug logging is on: `grep 'CLAUDE.md/rules files' ~/.claude/debug/<full session id>.txt`.
- **Check its work before reporting it as done:** diffs, test output, PR state, anything it posted. Use absolute paths or `git -C <dir>` for these checks; a bare `cd` moves this session's working directory.

## 7. Follow up, stop, clean up

- **Session still listed by ListAgents:** use SendMessage. Check the result for a notice that the message is held for approval.
- **Finished session with no process:** relaunch it from its original directory with the same subshell form: `(cd <dir> && claude --bg --resume <full session id> -- "<follow-up>")`. It keeps its saved name, model, effort, permission mode and added directories. If the session was still alive, this starts a copy under a new id. Two live rows then share one name, and SendMessage needs the row's `[ref]`; stop the copy.
- **Stop:** `claude stop <id>`. It keeps the conversation.
- **Remove:** `claude rm <id>` deletes the session and, when it judges that safe, its worktree. Don't run it on a session whose directory is a worktree that existed before the session or that another session still uses. If you must, `git worktree lock` the worktree first, run `rm`, check that the directory and its HEAD survived, then unlock.

More failure modes and their fixes: [references/troubleshooting.md](references/troubleshooting.md). Read it when a launch, edit or follow-up doesn't behave as described above.
