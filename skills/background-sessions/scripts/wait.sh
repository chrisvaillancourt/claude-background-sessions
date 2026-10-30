#!/bin/sh
# Wait until each background session stops working, then print its state and its
# latest reply, read from the session transcript (claude logs garbles text).
# Run it as a background command so its exit is the notification.
#
# Usage: sh wait.sh [--timeout SECONDS] [--after-message] ID...
#   --timeout SECONDS  give up after this long (default 3600)
#   --after-message    run right after sending each session a follow-up with SendMessage.
#                      Once a session has had a message, `state` stays "working" even
#                      while it's idle, so this mode reads the transcript instead: a
#                      session is finished when its transcript has the message (from
#                      the last 120s), an assistant entry after it, and `status` is idle.
#
# Exits 0 when every session is done, 3 when any ended blocked, failed or stopped,
# 4 when an id isn't found, 5 when --after-message found no message from the last
# 120s in a transcript after 120s of waiting, and 1 on timeout.
set -eu

timeout=3600
after_message=0
while [ $# -gt 0 ]; do
  case $1 in
    --timeout) timeout=$2; shift 2 ;;
    --after-message) after_message=1; shift ;;
    --) shift; break ;;
    -*) echo "wait.sh: unknown option $1" >&2; exit 2 ;;
    *) break ;;
  esac
done
if [ $# -lt 1 ]; then
  echo "usage: sh wait.sh [--timeout SECONDS] [--after-message] ID..." >&2
  exit 2
fi

# Prints "none" (no message since T0), "working" or "replied" for one transcript.
followup_progress() {
  jq -rs --argjson t0 "$t0" '
    def ts: ((.timestamp // "")[0:19] + "Z") | (try fromdate catch 0);
    [.[] | select(.type == "user" or .type == "assistant")] as $e
    | ([$e[] | select(.type == "user" and ((.message.content | tostring) | contains("cross-session-message"))) | ts] | max // 0) as $m
    | if $m < $t0 then "none"
      elif ($e | last | .type) == "assistant" and (($e | last | ts) >= $m) then "replied"
      else "working" end' "$1"
}

t0=$(jq -n 'now - 120 | floor')
unseen=""
elapsed=0
misses=0
while :; do
  all=$(claude agents --json --all)
  pending=0
  missing=0
  unseen=""
  for id in "$@"; do
    row=$(printf '%s' "$all" | jq -c --arg id "$id" '.[] | select(.id == $id) | {state, status, sessionId}')
    state=$(printf '%s' "$row" | jq -r '.state // empty')
    if [ -z "$state" ]; then
      missing=1
      continue
    fi
    if [ $after_message -eq 1 ]; then
      case "$state" in blocked|failed|stopped) continue ;; esac
      status=$(printf '%s' "$row" | jq -r '.status // empty')
      sid=$(printf '%s' "$row" | jq -r '.sessionId')
      progress=none
      for transcript in "$HOME"/.claude/projects/*/"$sid".jsonl; do
        [ -f "$transcript" ] && progress=$(followup_progress "$transcript")
      done
      case "$progress" in
        replied) [ "$status" = "busy" ] && pending=1 ;;
        none) pending=1; unseen="$unseen $id" ;;
        *) pending=1 ;;
      esac
    elif [ "$state" = "working" ]; then
      pending=1
    fi
  done
  if [ $missing -eq 1 ]; then
    misses=$((misses + 1))
    if [ $misses -ge 3 ]; then
      echo "wait.sh: an id isn't listed by 'claude agents --json --all'; check the ids" >&2
      exit 4
    fi
  else
    misses=0
  fi
  if [ $pending -eq 0 ] && [ $missing -eq 0 ]; then
    break
  fi
  if [ -n "$unseen" ] && [ "$elapsed" -ge 120 ]; then
    echo "wait.sh:$unseen: no follow-up message in the transcript after 120s; check whether SendMessage was held for approval" >&2
    exit 5
  fi
  if [ "$elapsed" -ge "$timeout" ]; then
    echo "wait.sh: timed out after ${timeout}s"
    for id in "$@"; do
      printf '%s' "$all" | jq -c --arg id "$id" '.[] | select(.id == $id) | {id, state}'
    done
    exit 1
  fi
  sleep 5
  elapsed=$((elapsed + 5))
done

rc=0
for id in "$@"; do
  row=$(printf '%s' "$all" | jq -c --arg id "$id" '.[] | select(.id == $id) | {id, sessionId, state, status, cwd, name}')
  printf '== %s\n' "$row"
  state=$(printf '%s' "$row" | jq -r '.state')
  case "$state" in
    done) ;;
    # After a message, a session that has replied still reports "working".
    working) [ $after_message -eq 1 ] || rc=3 ;;
    *) rc=3 ;;
  esac
  sid=$(printf '%s' "$row" | jq -r '.sessionId')
  for transcript in "$HOME"/.claude/projects/*/"$sid".jsonl; do
    [ -f "$transcript" ] || continue
    # The latest assistant text block: the final reply, without earlier turns.
    jq -rs '[.[] | select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text] | last // empty' "$transcript"
  done
done
exit $rc
