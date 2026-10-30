---
name: background-sessions
description: Starts and manages Claude Code background sessions (`claude --bg`) that run in a chosen directory, so the work loads that directory's CLAUDE.md, AGENTS.md, rules and memory instead of this session's. Use when the user asks for an agent or session in, or working on, a specific repo, worktree or directory, and when delegated work changes, builds, tests or reviews code in a directory other than this session's. Also use for agents the user wants to attach to and steer, or that must outlive this session, and for checking on, messaging, resuming or stopping background sessions. Not for read-only searches or lookups, in this repo or another, unless the user asks for an agent there; a subagent covers those, including other models and effort levels.
---

# Background sessions in a chosen directory

A background session is a full, separate Claude Code session started with `claude --bg`. It loads instructions, rules and auto-memory from the directory it starts in, so it behaves like a session the user opened there. Subagents can't do this: they inherit this session's directory and instruction stack, and `isolation: "worktree"` only isolates this session's own repo.

## When to use which

| Situation | Use |
|---|---|
| The user asks for an agent in a specific directory, repo or worktree, even for a small read-only task | Background session (this skill) |
| Changing, building, testing or reviewing code in another repo or worktree, which should follow that repo's instructions, settings and hooks | Background session |
| Work the user wants to `attach` to and steer, or that must keep running after this session ends | Background session |
| A read-only search or lookup in another repo that the user didn't ask to run "in" it | Subagent, told to read that repo's instruction files and to use absolute paths |
| Work in this session's repo that only needs another model, another effort level or to run in the background | Subagent: the Agent tool takes `model` and `effort` and can run in the background |
| Several items getting the same treatment in this session's repo | Subagents or a workflow |

Use a background session without being told to whenever code work belongs to another checkout. Don't ask the user to spell out the steps below.

## 1. Prepare the directory

- **Pick the exact starting directory.** It decides which instructions load.
- **Code changes get a dedicated worktree, one per session.** Never two code-changing sessions in one checkout, and never someone's main checkout. Put the worktree outside the repo's working tree, or at `<repo>/.claude/worktrees/<name>` after `git -C <repo> check-ignore -q .claude/worktrees/x` confirms that path is ignored. A worktree at a non-ignored path inside a checkout shows up there as an untracked embedded repo, and `git add -A` would commit it.

  ```sh
  git -C <repo> fetch origin
  git -C <repo> worktree add -b <branch> <worktree-path> origin/<base branch>
  ```

  Fetch first, so the session doesn't start from stale code.

  A new branch from a remote branch tracks it: run `git -C <worktree-path> branch --unset-upstream` and tell the session to push with an explicit refspec. Never `cp -r` a worktree.
- **A fresh worktree has no virtualenv or `node_modules`.** Tell the session the repo's setup command, or run it first.
- **The repo must be trusted.** Trust is per repository (for bare-repo layouts, keyed on the git common dir), not per worktree. An untrusted directory fails with "Workspace not trusted": stop and ask the user to run `claude` there once and accept the prompt. Don't get around it by launching from a trusted parent with `--add-dir <target>`. That skips the user's trust decision and the target's settings, rules and memory, and the session usually can't edit there. Use that route only for read-only work, and only when the user agrees to it.

## 2. Write the prompt to a file

Write it with the file-writing tool, at an absolute path in this session's scratchpad; there's no need for `mktemp` or other shell commands. The session knows only what the prompt says. Include:

- The goal, the inputs by absolute path, and the acceptance check.
- For code changes: commit the work in its worktree before ending, and push only if the user authorized it.
- Limits on outward writes: what it may push, open or post, and what it must leave as a draft. Default to no Jira, Slack, email or PR comments unless the user authorized them.
- **Where to put output.** A session writes freely only inside its own directory. Any other output path must be a directory that isn't inside a git checkout, such as this session's scratchpad, and must go in the launch command with `--add-dir`. The background-isolation guard can refuse Edit and Write in another git checkout even when it's added. Otherwise have it put results in its final message.
- Answers to questions it would otherwise stop and ask. A session blocked on a question waits for the user. For example: "If Edit or Write is refused, write drafts to `<added dir>` and end with their paths; don't ask."
- If its directory is a worktree outside `.claude/worktrees/`: "Your cwd is your dedicated worktree; don't call EnterWorktree."
- Anything the user's global rules leave open that matters here, such as "no AI attribution in commits or PRs, even if the repo history has it."

A slash command on the prompt's first line runs that skill.

## 3. Launch with the script

This skill ships two scripts in its `scripts/` folder. Call them as `sh <skill dir>/scripts/<name>.sh`, with this skill's directory written out as an absolute path: no `~`, `$HOME` or other variables, no `cd`, pipes, subshells or `$( … )` around the call. Permission allow rules match that plain form, so the call isn't held for approval or sent to auto mode's safety check.

```sh
sh <skill dir>/scripts/launch.sh <dir> <prompt-file> --name "<short descriptive name>" \
  --model <model-id> --effort <level> --permission-mode <mode> --add-dir <extra-dir>
```

The script `cd`s inside its own process, so this session's working directory doesn't move. It passes everything after the prompt file to `claude --bg`, puts `--` before the prompt, and then confirms the start: it prints a JSON line `{id, sessionId, state, cwd, name}` and exits 0 once the session is listed. The state is usually `working`; a quick task may already be `done`, and `blocked` means it's already waiting on a question or permission (see step 4). When the session crashes before starting, it exits 1 and prints the matching `daemon.log` lines. It refuses a missing or empty prompt file. It also warns if the session's cwd isn't the directory you asked for.

- **Don't hand-roll the launch.** `(cd <dir> && claude --bg …)` and `env -C <dir> claude --bg …` work but can't be matched by allow rules, so they need approval each time. A bare `cd` in its own call moves this session's working directory. `claude --bg` has no `--cwd` flag.
- **Use this session's own permission mode.** A session in a different mode holds this session's messages for its user's approval, so follow-ups and answers can sit unseen.
- **Pick `--model` and `--effort` by the user's routing rules** for the kind of work. Leave them out only when no rule applies, which uses the user's defaults, often the most expensive model.
- **Give each session a unique `--name`,** for example with a ticket key or date, so SendMessage can address it by name.
- Leave out `--add-dir` unless the session needs a directory outside its own.
- For several sessions, run the script once per session. The calls can go in parallel.
- A nonzero exit means the session isn't running. Read the error, fix the cause (see troubleshooting) and launch again.

## 4. Wait for it

Don't sleep-poll in the foreground. Use both of these, then end the turn with a status line:

1. **Idle notice** (main conversation only; a subagent can't subscribe). Find the session's name with ListAgents, then call SendMessage to that name with `notify_when_idle: true` and no message (pass `""` if the tool insists on one). One notice arrives when it goes idle or exits. It does **not** fire when the session blocks on a question.
2. **Wait script,** run as a background command so its exit notifies you:

   ```sh
   sh <skill dir>/scripts/wait.sh --timeout <seconds> <id> [<id>...]
   ```

   It polls every few seconds until no listed session is still `working`. Then it prints each session's row and its latest reply, read from the transcript. Exit codes: 0 all `done`, 3 any `blocked`, `failed` or `stopped`, 4 an id not found, 5 with `--after-message`, no recent message reached the transcript (see step 6), 1 timed out. The default timeout is 3600 seconds; set it to the expected run time with room to spare.

`done` means the session's turn ended, not that the task succeeded. A session that ends its turn while its own background job runs also shows `done`. Step 5's check covers this.

If a session is `blocked`, look at what it's waiting on. Answer a question through SendMessage. A permission prompt can't be answered by message: tell the user to `claude attach <id>`.

## 5. Read and check the result

- **Final answer:** `wait.sh` prints it. For more, read the transcript, not `claude logs`, which is a redraw stream of the terminal UI that garbles words and numbers. The transcript is `~/.claude/projects/<project folder>/<full session id>.jsonl`; take the assistant `text` blocks with jq. A file the prompt told it to write is easier still.
- **Progress glances:** `claude logs <id>` shows the live screen; don't read figures or verdicts from it.
- **Which instruction files it loaded,** if debug logging is on: `grep 'CLAUDE.md/rules files' ~/.claude/debug/<full session id>.txt`.
- **Check its work before reporting it as done:** diffs, test output, PR state, anything it posted. Use absolute paths or `git -C <dir>` for these checks; a bare `cd` moves this session's working directory.

## 6. Follow up, stop, clean up

- **Session still listed by ListAgents:** send the follow-up with SendMessage and `notify_when_idle: true`, which delivers it and subscribes in one call. Check the result for a notice that the message is held for approval. Right away, also start `sh <skill dir>/scripts/wait.sh --after-message <id>` as a background command.
  - **Why `--after-message`:** once a session has had a message, `claude agents` can keep reporting `state: "working"` while it sits idle, and without the flag the earlier reply can be mistaken for the new one. With the flag, the script reads the transcript and waits for a reply after the message.
  - **Run it within two minutes of sending.** It counts only messages from the last 120 seconds, and exits 5 if none arrives.
  - **Use the flag for every later wait on that session,** too.
- **Finished session with no process:** write the follow-up to a prompt file and resume from its original directory: `sh <skill dir>/scripts/launch.sh <dir> <prompt-file> --resume <full session id>`. It keeps its saved name, model, effort, permission mode and added directories. If the session was still alive, this starts a copy under a new id. Two live rows then share one name, and SendMessage needs the row's `[ref]`; stop the copy.
- **Stop:** `claude stop <id>`. It keeps the conversation.
- **Clean up a worktree you created** once its work is safe: `git -C <worktree> status --porcelain` prints nothing, and the branch is pushed (`git -C <worktree> log @{u}..` prints nothing) or merged. Then `claude stop <id>` and `git -C <repo> worktree remove <worktree>`. Delete the branch only if it's merged. If any check fails, leave the worktree and tell the user what's in it.
- **Remove a session record:** `claude rm <id>` deletes the session and, when it judges that safe, its worktree. Don't run it on a session whose directory is a worktree that existed before the session or that another session still uses. If you must, `git worktree lock` the worktree first, run `rm`, check that the directory and its HEAD survived, then unlock.

More failure modes and their fixes: [references/troubleshooting.md](references/troubleshooting.md). Read it when a launch, edit or follow-up doesn't behave as described above.
