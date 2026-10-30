#!/bin/sh
# Start a Claude Code background session in DIR with the prompt in PROMPT_FILE,
# then confirm it started. The cd happens in this script's own process, so the
# calling session's working directory doesn't move.
#
# Usage: sh launch.sh DIR PROMPT_FILE [claude --bg options...]
#   e.g. sh launch.sh /abs/repo /abs/prompt.md --name "fix flaky test" --model opus --effort high
#   Resume a finished session: sh launch.sh DIR PROMPT_FILE --resume <full session id>
#
# Prints the launch output, then one JSON line {id,sessionId,state,cwd,name}.
# Exits 0 once the session is running (or already finished), 1 if it failed to start.
set -eu

if [ $# -lt 2 ]; then
  echo "usage: sh launch.sh DIR PROMPT_FILE [claude --bg options...]" >&2
  exit 2
fi
dir=$1
prompt_file=$2
shift 2
[ -d "$dir" ] || { echo "launch.sh: no such directory: $dir" >&2; exit 2; }
[ -s "$prompt_file" ] || { echo "launch.sh: prompt file missing or empty: $prompt_file" >&2; exit 2; }
dir=$(cd "$dir" && pwd)
prompt=$(cat "$prompt_file")

# "--" ends option parsing, so a prompt that starts with "-" isn't read as an option
# and a list option such as --add-dir can't swallow it.
if ! out=$(cd "$dir" && claude --bg "$@" -- "$prompt" 2>&1); then
  printf '%s\n' "$out" >&2
  exit 1
fi
printf '%s\n' "$out"

id=$(printf '%s\n' "$out" | awk '$1 == "backgrounded" { print $3; exit }')
if [ -z "$id" ]; then
  echo "launch.sh: no session id in the launch output" >&2
  exit 1
fi

# "backgrounded" doesn't mean it started: a crash before init shows up as state "failed".
i=0
while [ $i -lt 15 ]; do
  row=$(claude agents --json --all | jq -c --arg id "$id" '.[] | select(.id == $id) | {id, sessionId, state, cwd, name}')
  state=$(printf '%s' "$row" | jq -r '.state // empty')
  case "$state" in
    failed)
      printf '%s\n' "$row"
      echo "launch.sh: session $id failed to start. daemon.log says:" >&2
      grep -F "$id" "$HOME/.claude/daemon.log" 2>/dev/null | tail -n 3 >&2 || true
      exit 1
      ;;
    "")
      ;;
    *)
      printf '%s\n' "$row"
      cwd=$(printf '%s' "$row" | jq -r '.cwd // empty')
      if [ "$cwd" != "$dir" ]; then
        echo "launch.sh: warning: session cwd is $cwd, expected $dir" >&2
      fi
      exit 0
      ;;
  esac
  i=$((i + 1))
  sleep 1
done
echo "launch.sh: session $id not listed by 'claude agents' after 15s; check ~/.claude/daemon.log" >&2
exit 1
