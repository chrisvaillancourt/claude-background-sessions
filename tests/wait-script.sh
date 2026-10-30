#!/bin/sh
# Offline tests for scripts/wait.sh. A fake `claude` on PATH serves `claude agents`
# from a file, and a temporary HOME holds a fake transcript, so the cases can change
# a session's state and transcript while wait.sh polls. No sessions are started.
#
# Usage: sh tests/wait-script.sh
# Takes about a minute: wait.sh polls every 5 seconds.
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
script="$repo/skills/background-sessions/scripts/wait.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/home/.claude/projects/p"
cat > "$work/bin/claude" <<'EOF'
#!/bin/sh
echo "$*" >> "$FAKE_DIR/calls"
cat "$FAKE_DIR/agents.json"
EOF
chmod +x "$work/bin/claude"
export FAKE_DIR="$work" HOME="$work/home" PATH="$work/bin:$PATH"

id=abcd1234
sid=abcd1234-0000-0000-0000-000000000000
transcript="$work/home/.claude/projects/p/$sid.jsonl"
failures=0

set_agent() { # STATE STATUS
  printf '[{"id":"%s","sessionId":"%s","state":"%s","status":%s,"cwd":"/x","name":"t"}]\n' \
    "$id" "$sid" "$1" "$2" > "$work/agents.json"
}
entry() { # TYPE TEXT
  ts=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
  if [ "$1" = assistant ]; then
    jq -cn --arg t "$2" --arg ts "$ts" '{type: "assistant", timestamp: $ts, message: {content: [{type: "text", text: $t}]}}'
  else
    jq -cn --arg t "$2" --arg ts "$ts" '{type: "user", timestamp: $ts, message: {content: $t}}'
  fi >> "$transcript"
}
reset() {
  : > "$work/calls"
  : > "$transcript"
  entry user "start the build"
  entry assistant "The build is running in the background; I'll pick up when it finishes."
  set_agent done null
}
# Start wait.sh in the background; its output goes to $work/out, its exit code to $work/rc.
start_wait() {
  rm -f "$work/rc"
  { rc=0; sh "$script" "$@" > "$work/out" 2>&1 || rc=$?; echo "$rc" > "$work/rc"; } &
}
# Wait until wait.sh has polled claude agents at least N times, or it has exited.
polls_at_least() {
  i=0
  while [ "$(wc -l < "$work/calls" | tr -d ' ')" -lt "$1" ] && [ ! -f "$work/rc" ] && [ $i -lt 60 ]; do
    sleep 1; i=$((i + 1))
  done
}
finish() { # seconds to wait for wait.sh to exit; prints its exit code, or "running"
  i=0
  while [ ! -f "$work/rc" ] && [ $i -lt "$1" ]; do sleep 1; i=$((i + 1)); done
  if [ -f "$work/rc" ]; then cat "$work/rc"; else echo running; fi
}
check() { # NAME CONDITION DETAIL: passes when the shell condition CONDITION is true
  if eval "$2"; then
    echo "ok   $1"
  else
    echo "FAIL $1: $3"
    failures=$((failures + 1))
  fi
}

# Plain wait returns at once for a session that's already done: the problem --next-turn fixes.
reset
start_wait --timeout 30 "$id"
rc=$(finish 10)
check "plain wait returns at once for a done session" '[ "$rc" = 0 ]' "exit $rc"

# --next-turn ignores the turn that already ended, keeps waiting while the next turn
# runs, and returns that turn's reply once the session is idle again.
reset
start_wait --next-turn --timeout 120 "$id"
polls_at_least 2
check "next-turn keeps waiting on an idle session" '[ ! -f "$work/rc" ]' "exited $(cat "$work/rc" 2>/dev/null) with: $(cat "$work/out")"
entry user "<task-notification>build finished</task-notification>"
set_agent working '"busy"'
polls_at_least 4
check "next-turn keeps waiting while the next turn runs" '[ ! -f "$work/rc" ]' "exited $(cat "$work/rc" 2>/dev/null)"
entry assistant "Build finished: all green."
set_agent done null
rc=$(finish 20)
check "next-turn exits 0 after the next turn" '[ "$rc" = 0 ]' "exit $rc: $(cat "$work/out")"
check "next-turn prints the new reply" 'grep -q "Build finished: all green." "$work/out"' "$(cat "$work/out")"
check "next-turn doesn't print the earlier reply" '! grep -q "pick up when it finishes" "$work/out"' "$(cat "$work/out")"

# A reply written while claude agents still reports the session busy isn't the end yet.
reset
start_wait --next-turn --timeout 120 "$id"
polls_at_least 2
set_agent working '"busy"'
entry user "<task-notification>build finished</task-notification>"
entry assistant "Build finished: all green."
polls_at_least 4
check "next-turn waits until the session isn't busy" '[ ! -f "$work/rc" ]' "exited $(cat "$work/rc" 2>/dev/null)"
set_agent working '"idle"'
rc=$(finish 20)
check "next-turn accepts working/idle after a reply" '[ "$rc" = 0 ]' "exit $rc"

# A reply still being written when the wait starts belongs to the old turn.
reset
jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" '{type: "assistant", timestamp: $ts, message: {content: [{type: "text", text: "Old reply, half written."}]}}' | tr -d '\n' >> "$transcript"
start_wait --next-turn --timeout 15 "$id"
polls_at_least 2
printf '\n' >> "$transcript"
rc=$(finish 40)
check "next-turn skips a line half written when it started" '[ "$rc" = 1 ]' "exit $rc: $(cat "$work/out")"

# A session that blocks on its next turn ends the wait with exit 3.
reset
start_wait --next-turn --timeout 120 "$id"
polls_at_least 2
set_agent blocked '"idle"'
rc=$(finish 20)
check "next-turn exits 3 on blocked" '[ "$rc" = 3 ]' "exit $rc"

# No new turn: time out with exit 1.
reset
start_wait --next-turn --timeout 5 "$id"
rc=$(finish 30)
check "next-turn times out with exit 1" '[ "$rc" = 1 ]' "exit $rc"

# Option errors.
reset
start_wait --next-turn --after-message "$id"
rc=$(finish 10)
check "next-turn with after-message is refused" '[ "$rc" = 2 ]' "exit $rc"

echo
if [ $failures -eq 0 ]; then
  echo "All wait.sh tests passed."
else
  echo "$failures wait.sh test(s) failed."
  exit 1
fi
