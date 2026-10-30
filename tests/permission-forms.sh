#!/bin/sh
# Check which launch command forms Claude Code's permission rules let through.
# This is the evidence for the skill's scripts: if the one-line forms start
# passing, the scripts may no longer be needed (see docs/why-scripts.md).
#
# Usage: sh tests/permission-forms.sh TARGET_DIR
#   TARGET_DIR: a trusted repo directory to launch the test sessions in.
#   Run it from a trusted directory; the headless sessions start there.
#
# Each case runs a headless Haiku session in default permission mode that runs one
# exact command. Headless sessions can't ask, so a command no allow rule matches is
# refused and counted in permission_denials. Allowed launches start a Haiku session
# that replies "OK" and finishes. Costs a few cents per case.
set -eu

[ $# -eq 1 ] || { echo "usage: sh tests/permission-forms.sh TARGET_DIR" >&2; exit 2; }
dir=$(cd "$1" && pwd)
skill="$HOME/.claude/skills/background-sessions/scripts"
work=$(mktemp -d)
prompt_file="$work/prompt.md"
printf '%s\n' '- Reply with the single word OK. Do not use any tools.' > "$prompt_file"
p='Reply with the single word OK. Do not use any tools.'

run_case() {
  name=$1
  cmd=$2
  timeout 300 claude -p --permission-mode default --model haiku --effort low --output-format json \
    "Run exactly this one Bash command, unchanged, then reply with its output verbatim. Don't run any other command, and don't retry another way if it's refused; just say it was refused.

$cmd" > "$work/$name.json" 2> "$work/$name.err" || true
}

run_case plain-control "claude --bg --name \"perm test plain\" --model haiku --effort low -- \"$p\"" &
run_case subshell "(cd $dir && claude --bg --name \"perm test subshell\" --model haiku --effort low -- \"$p\")" &
run_case env-C "env -C $dir claude --bg --name \"perm test env-C\" --model haiku --effort low -- \"$p\"" &
run_case launch-script "sh $skill/launch.sh $dir $prompt_file --name \"perm test launch.sh\" --model haiku --effort low" &
run_case wait-script "sh $skill/wait.sh --timeout 30 00000000" &
run_case negative-control "(cd $dir && claude rm no-such-session-id)" &
wait

printf '%-18s %-8s %s\n' CASE DENIED EXPECTED
for name in plain-control subshell env-C launch-script wait-script negative-control; do
  case $name in
    plain-control|launch-script|wait-script) expected=0 ;;
    *) expected=1 ;;
  esac
  denied=$(jq -r 'if type == "array" then .[] | select(.type == "result") else . end | .permission_denials | length' "$work/$name.json" 2>/dev/null || echo "?")
  printf '%-18s %-8s %s\n' "$name" "$denied" "$expected"
  # Remove the headless session's transcript so it doesn't clutter session history.
  sid=$(jq -r 'if type == "array" then .[] | select(.type == "result") else . end | .session_id' "$work/$name.json" 2>/dev/null || true)
  if [ -n "$sid" ]; then
    rm -f "$HOME"/.claude/projects/*/"$sid".jsonl
  fi
done
echo "Raw results: $work"
echo "If subshell or env-C now shows 0 denied, see docs/why-scripts.md before removing anything."
