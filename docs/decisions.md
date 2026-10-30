# Decisions

Each entry records what was decided, why, and the evidence. Read the matching entry before changing behavior it covers. If you reverse a decision, update its entry and say what changed. Dates are when the evidence was gathered; everything was tested on Claude Code 2.1.312 unless noted.

## 1. Use background sessions for work in another directory, not subagents

**Decision:** code work in a directory other than the coordinating session's (changing, building, testing or reviewing code) runs in a `claude --bg` background session started in that directory.

**Why:** a session loads CLAUDE.md, AGENTS.md, `.claude/rules`, settings, hooks and auto-memory from the directory it starts in. Agent-tool subagents inherit the parent session's working directory and instruction stack instead. Each workaround on the subagent side failed or fell short:

- **Wrong instructions:** a subagent delegated from a notes repository into a code repo follows the notes repo's rules. Telling it to read the target's instruction files covers those files but not the target's settings, hooks or memory.
- **Constant `cd`:** every command needs `cd <abs path> &&` or absolute paths, and a forgotten one runs in the wrong repo.
- **`isolation: "worktree"` isolates the wrong repo:** it makes a worktree of the parent's repo, not the target's. In one run (2026-10-22), agents launched this way got unused worktrees of the parent repo. They created their own worktrees in the target and worked there. The harness then deleted the unchanged parent-repo worktrees, and every later shell call failed with "working directory … no longer exists". Three of four agents stopped partway.

A background session avoids all three, and the user can `claude attach` to watch or steer it.

## 2. Keep subagents for read-only lookups in other repos

**Decision:** read-only searches and lookups go to an ordinary subagent unless the user asks for an agent "in" a directory. Model and effort follow the user's routing rules, and are left out only when no rule applies.

**Why:** a background session is a full session. With no model flag it runs the user's default model, often the most expensive. For a lookup, a subagent with absolute paths is cheaper and returns its answer straight into the calling session. The second review flagged that the earlier description pulled almost every cross-repo lookup into a full default-model session.

**Evidence:** the first headless test asked "Start a Haiku agent in <repo> to report …". The skill's description at the time excluded "quick read-only lookups", so the session used a subagent instead of the skill. The description now triggers on an explicit request for an agent in a directory, even for read-only work. With that wording, two later headless tests loaded the skill unprompted.

## 3. Never move the calling session's working directory

**Decision:** the `cd` into the target happens in a child process, never in the coordinator's own shell.

**Why:** a `cd` in its own Bash call carries over to the session's next calls. When the target was inside the session's working directories, the harness announced "Primary working directory: <target>" and treated the target as the session's worktree. Every later relative path and git command then ran in the wrong repo.

**History:** the first fix was a subshell, `(cd <dir> && claude --bg …)`, which kept the coordinator in place. Decision 4 replaced it.

## 4. Launch and wait through scripts that allow rules can match

**Decision:** agents run `sh <absolute skill dir>/scripts/launch.sh …` and `… /wait.sh …`, never a hand-written launch or polling loop. The README lists allow rules for both.

**Why:** there are two reasons.
- **No one-line form can be allowed:** `claude --bg` has no directory option, and the one-line forms that change directory without moving the caller can't be matched by any allow rule. In default mode they need approval every time.
- **Auto mode isn't reliable either:** an unmatched command goes to the safety classifier, which has denied background launches before ("Create Unsafe Agents").

A plain `sh <absolute path> …` call matches a prefix rule, so it skips both.

**Evidence:** [why-scripts.md](why-scripts.md) has the test table and the conditions for removing the scripts. `tests/permission-forms.sh` reruns the test.

## 5. Put `--` before the prompt

**Decision:** `launch.sh` always passes `claude --bg <options> -- "<prompt>"`.

**Why:** without `--`, the CLI's option parser reads a prompt starting with `-` as an unknown option. That covers a Markdown bullet or a `---` front-matter line. The session crashes before it starts, but the launch still prints "backgrounded … (idle — send a prompt to start)". `--add-dir` takes a list, so without `--` it also swallowed a prompt placed after it.

**Evidence:** the first review's probe: `daemon.log` recorded `settled <id> (crashed): exit 1 before init — error: unknown option '- Reply with …'`. The same prompt with `--` ran normally.

## 6. Confirm the start; "backgrounded" isn't proof

**Decision:** `launch.sh` checks `claude agents --json --all` after launching. It exits 1 on `failed` and prints the matching `daemon.log` lines. It refuses a missing or empty prompt file.

**Why:** "backgrounded · <id>" prints before the session initializes, so a crash afterwards looks like success. `claude --bg --cwd <dir>` printed "backgrounded", then died on `unknown option '--cwd'`. An empty prompt, from a relative path resolved after a `cd`, launched an idle session and still exited 0 in the second review's probe.

## 7. Wait with the idle notice and `wait.sh`, not either alone

**Decision:** in the main conversation, subscribe with SendMessage `notify_when_idle: true`, and also run `wait.sh` as a background command.

**Why:** the idle notice doesn't fire when a session stops on a question. It was observed missing a `blocked` session on 2026-10-16, and it's only available from the main conversation. `wait.sh` exits on `blocked`, `failed` and `stopped` too, and its exit wakes the caller. Neither needs foreground sleeps.

## 8. Read results from the transcript, not `claude logs`

**Decision:** `wait.sh` prints the latest assistant text from `~/.claude/projects/<project>/<session id>.jsonl`. `claude logs` is for glances only.

**Why:** `claude logs` replays the terminal UI's redraw stream. Even after stripping escape codes, words and numbers came out mangled ("↓ 1.3ktkens", "thoughtfor s"), so figures or verdicts read from it can be wrong. Printing only the latest text block stops earlier turns from mixing into a follow-up's answer.

## 9. Wait for follow-ups through the transcript (`--after-message`)

**Decision:** after sending a session a follow-up with SendMessage, wait with `wait.sh --after-message`. It treats the session as finished once three things hold:
- the transcript has a cross-session message from the last 120 seconds;
- there's an assistant entry after that message;
- `claude agents` reports `status` as anything but `busy`.

**Why:** once a session had received a message, `claude agents` kept reporting `state: "working"` with `status: "idle"` for minutes after it replied, so a wait on `state` hung until its timeout. The second review proposed "wait until it's seen working again", but the session replied in under a second, well inside one polling interval. The transcript is the only signal that held up.

**Evidence (2026-10-29):** a session answered a follow-up in about 0.5 seconds. `state` stayed `working` for over 3 minutes. The transcript-based wait returned the new reply. With no recent message, it exits 5 after 120 seconds.

## 10. Launch with the coordinator's permission mode

**Decision:** pass `--permission-mode` matching the calling session.

**Why:** the SendMessage tool documents that a session in a different permission mode holds cross-session messages for its user's approval and may let them expire. The send still reports success, so follow-ups and answers can sit unseen. Not reproduced here; taken from the tool's documentation.

## 11. Output stays inside the session's directory, or an added non-repo directory

**Decision:** the prompt has to name where output goes. It's either inside the session's own directory, or a directory outside any git checkout that's passed with `--add-dir`. Otherwise the result goes in the final message.

**Why:** background sessions run under the `worktree.bgIsolation` guard. Its default `"worktree"` refuses Edit and Write in a main checkout until the session calls EnterWorktree. An earlier session refused this way in a git checkout passed with `--add-dir` got around it by making its own worktree and pushing from there; the result was fine, but it skipped the guard. Don't route around the guard with shell redirects.

## 12. Worktrees: one per code-changing session, fetched fresh, cleaned up only when safe

**Decisions and reasons:**
- **One worktree per code-changing session:** two sessions editing one checkout collide.
- **Placement:** outside the repo, or under `.claude/worktrees/` only after `git check-ignore` confirms the path is ignored. A worktree at a non-ignored path inside a checkout shows up as an untracked embedded repo, and `git add -A` would commit it.
- **`git fetch` first:** otherwise the session starts from whatever was last fetched.
- **The session commits before it ends.** The coordinator removes the worktree only when `status --porcelain` is empty and the branch is pushed or merged. Otherwise it leaves the worktree and reports what's in it.
- **No `claude rm` on a pre-existing or shared worktree:** `claude rm` deletes the session's worktree "when safe", and the session list doesn't show which worktree a session owns.

## 13. Untrusted repos: ask the user; don't route around trust

**Decision:** on "Workspace not trusted", stop and ask the user to run `claude` there once and accept trust. Launch from a trusted parent with `--add-dir` only for read-only work, and only with the user's OK.

**Why:** the parent-directory route skips the user's trust decision. It also loses the point of the skill, since the target's settings, rules and memory don't load, and edits there are usually refused anyway. The second review raised this.

## 14. Packaging

**Decisions:**
- **Repo name `claude-background-sessions`, skill name `background-sessions`:** the repo name says it's Claude Code-specific. Inside Claude Code, a "claude" prefix on the skill name would be redundant.
- **Installed with the skills CLI for the `claude-code` agent only:** the skill depends on `claude --bg`, SendMessage and ListAgents, so other harnesses can't use it.
- **The installed copy is separate from the checkout.** Rerun the install after every change.
- **Allow rules name the installed script paths.** Rules match command text literally, so `~` and `$HOME` don't work. Moving the install means updating the rules.

## 15. How it was reviewed and tested (2026-10-29)

- **Live probes:** Haiku sessions at low effort with trivial prompts, in a trusted repo, covering:
  - the working directory and which instruction files loaded (the session's debug log lists them);
  - subshell launches, prompts starting with `-`, `--resume` with `--`, and crashes before startup;
  - `launch.sh` success and failure paths;
  - `wait.sh` in normal mode, `--after-message` with a real follow-up, a missing id (exit 4) and no message (exit 5).
- **Permission test:** headless sessions in default permission mode, where an unmatched command is refused instead of prompting. This is `tests/permission-forms.sh`.
- **Trigger tests:** a fresh headless session given a plain request, "Start a Haiku agent in <repo> to report …":
  - Test 1 (auto mode, original description): used a subagent; see decision 2.
  - Test 2 (auto mode, revised description): loaded the skill, launched from a subshell, waited and checked the answer. It then used a bare `cd` to spot-check, which moved its own working directory; SKILL.md now says to check results with absolute paths or `git -C`.
  - Test 3 (default mode, scripts): loaded the skill and ran `launch.sh` and `wait.sh` with no permission denials. Its only denial was a `mktemp -d` it chose itself for the prompt file; SKILL.md now says to write the prompt with the file-writing tool.
  - Test 4 (default mode, after the second review's changes): loaded the skill, gave the session a unique dated name, and ran `launch.sh` and `wait.sh` with no denials. Its only denials were `printenv TMPDIR` probes while it looked for a place to write the prompt file. SKILL.md now names a fallback location and says not to probe with shell commands.
- **Adversarial reviews:** two Opus reviews, each in a fresh context, at a "personal tooling used regularly by agents" bar.
  - First review: one blocker (decision 5) and six should-fix items (decisions 6 to 12, and the allow-rule question that led to decision 4). All fixed.
  - Second review: no blockers. Its top finding (empty or relative prompt files) was already fixed by `launch.sh`. Its other findings led to decisions 2, 9, 12 and 13 and some smaller wording fixes.

## Not verified

These rest on observation elsewhere or on documentation, not on a test in this repo:

- The idle notice missing a session blocked on a question: observed once, 2026-10-16.
- SendMessage holding messages across permission modes (decision 10).
- That SendMessage can answer a question a session is blocked on.
- `claude rm` deleting a pre-existing worktree, and the lock-then-remove workaround.
- Trust being keyed on the git common dir for bare-repo layouts.
- The "permission-root relocation" prompt when a session calls EnterWorktree outside `.claude/worktrees/`.
- The idle subscription expiring after 12 hours.
