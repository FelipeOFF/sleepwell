#!/usr/bin/env bash
# test-block-push.sh — tests for the block-push.sh hook.
#
# Covers:
#   1. Global refusals (outside the loop): force-push, force-with-lease,
#      push to main, push to main via a different matcher.
#   2. Refusal during an active loop: any push.
#   3. Allows safe pushes (e.g. feature branch outside the loop).
#
# Exit 0 → all cases behaved as expected.
# Exit 1 → some case diverged.

set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
HOOK="$HERE/block-push.sh"

if [ ! -x "$HOOK" ]; then
  chmod +x "$HOOK"
fi

WORK=$(mktemp -d -t sleepwell-block-push.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

cd "$WORK" || exit 1
mkdir -p .sleepwell

pass=0
fail=0

# run_case <description> <expected_exit> <state.json content or empty> <cmd>
run_case() {
  local desc="$1" expected="$2" state="$3" cmd="$4"
  if [ -n "$state" ]; then
    printf '%s' "$state" > .sleepwell/state.json
  else
    rm -f .sleepwell/state.json
  fi
  local input
  input=$(jq -nc --arg cmd "$cmd" '{tool_name:"Bash", tool_input:{command:$cmd}}')
  local actual=0
  printf '%s' "$input" | "$HOOK" >/dev/null 2>&1 || actual=$?
  if [ "$actual" = "$expected" ]; then
    printf '  ok   %s (exit=%s)\n' "$desc" "$actual"
    pass=$((pass + 1))
  else
    printf '  FAIL %s (expected=%s actual=%s)\n' "$desc" "$expected" "$actual"
    fail=$((fail + 1))
  fi
}

STATE_RUNNING='{"status":"running","branch":"sleepwell/auto/abc"}'
STATE_DONE='{"status":"done","branch":"sleepwell/auto/abc"}'

echo "Global refusals (outside the loop):"
run_case "force-push --force"             2 "" "git push --force origin feat/x"
run_case "force-push -f"                  2 "" "git push -f origin feat/x"
run_case "force-with-lease"               2 "$STATE_DONE" "git push --force-with-lease origin feat/x"
run_case "refspec with +"                 2 "" "git push origin +feat/x:feat/x"
run_case "push to main"                   2 "" "git push origin main"
run_case "push to main with upstream -u"  2 "" "git push -u origin main"
run_case "push to master"                 2 "" "git push origin master"
run_case "push to develop"                2 "" "git push origin develop"
run_case "push to trunk"                  2 "" "git push origin trunk"

echo
echo "Active loop (status=running):"
run_case "any push during loop"           2 "$STATE_RUNNING" "git push origin sleepwell/auto/abc"

echo
echo "Allowed pushes:"
run_case "push to feature branch (no state)"     0 ""              "git push origin feat/x"
run_case "push to feature branch (loop done)"    0 "$STATE_DONE"   "git push origin feat/x"
run_case "non-bash command (no cmd)"             0 ""              ""

echo
echo "Summary: $pass passed, $fail failed"
[ "$fail" = "0" ]
