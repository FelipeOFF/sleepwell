#!/usr/bin/env bash
# test-block-push.sh — testes do hook block-push.sh.
#
# Cobre:
#   1. Recusas globais (fora do loop): force-push, force-with-lease,
#      push em main, push em main por matcher diferente.
#   2. Recusa durante loop ativo: qualquer push.
#   3. Permite pushes seguros (ex: feature branch fora do loop).
#
# Saída 0 → todos os casos reagiram corretamente.
# Saída 1 → algum caso divergiu.

set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
HOOK="$HERE/block-push.sh"

if [ ! -x "$HOOK" ]; then
  chmod +x "$HOOK"
fi

WORK=$(mktemp -d -t sleepwell-block-push.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

cd "$WORK"
mkdir -p .sleepwell

pass=0
fail=0

# run_case <descrição> <expected_exit> <state.json content or empty> <cmd>
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

echo "Recusas globais (fora do loop):"
run_case "force-push --force"           2 "" "git push --force origin feat/x"
run_case "force-push -f"                2 "" "git push -f origin feat/x"
run_case "force-with-lease"             2 "$STATE_DONE" "git push --force-with-lease origin feat/x"
run_case "refspec com +"                2 "" "git push origin +feat/x:feat/x"
run_case "push em main"                 2 "" "git push origin main"
run_case "push em main com upstream -u" 2 "" "git push -u origin main"
run_case "push em master"               2 "" "git push origin master"
run_case "push em develop"              2 "" "git push origin develop"
run_case "push em trunk"                2 "" "git push origin trunk"

echo
echo "Loop ativo (status=running):"
run_case "qualquer push em loop"        2 "$STATE_RUNNING" "git push origin sleepwell/auto/abc"

echo
echo "Pushes permitidos:"
run_case "push em feature branch (sem state)"     0 ""              "git push origin feat/x"
run_case "push em feature branch (loop done)"     0 "$STATE_DONE"   "git push origin feat/x"
run_case "comando não-bash (sem cmd)"             0 ""              ""

echo
echo "Resumo: $pass passou, $fail falhou"
[ "$fail" = "0" ]
