#!/bin/sh
# Wait until each background session stops working, then print its state and the
# end of its final reply, read from the session transcript (claude logs garbles text).
# Run it as a background command so its exit is the notification.
#
# Usage: sh wait.sh [--timeout SECONDS] ID...   (short ids from launch.sh; default timeout 3600)
#
# Exits 0 when every session is done, 3 when any ended blocked, failed or stopped,
# 4 when an id isn't found, and 1 on timeout.
set -eu

timeout=3600
if [ "${1:-}" = "--timeout" ]; then
  timeout=$2
  shift 2
fi
if [ $# -lt 1 ]; then
  echo "usage: sh wait.sh [--timeout SECONDS] ID..." >&2
  exit 2
fi

elapsed=0
misses=0
while :; do
  all=$(claude agents --json --all)
  pending=0
  missing=0
  for id in "$@"; do
    state=$(printf '%s' "$all" | jq -r --arg id "$id" '.[] | select(.id == $id) | .state')
    case "$state" in
      working) pending=1 ;;
      "") missing=1 ;;
    esac
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
  if [ "$elapsed" -ge "$timeout" ]; then
    echo "wait.sh: timed out after ${timeout}s"
    for id in "$@"; do
      printf '%s' "$all" | jq -c --arg id "$id" '.[] | select(.id == $id) | {id, state}'
    done
    exit 1
  fi
  sleep 10
  elapsed=$((elapsed + 10))
done

rc=0
for id in "$@"; do
  row=$(printf '%s' "$all" | jq -c --arg id "$id" '.[] | select(.id == $id) | {id, sessionId, state, cwd, name}')
  printf '== %s\n' "$row"
  state=$(printf '%s' "$row" | jq -r '.state')
  [ "$state" = "done" ] || rc=3
  sid=$(printf '%s' "$row" | jq -r '.sessionId')
  for transcript in "$HOME"/.claude/projects/*/"$sid".jsonl; do
    [ -f "$transcript" ] || continue
    jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text' "$transcript" | tail -n 40
  done
done
exit $rc
