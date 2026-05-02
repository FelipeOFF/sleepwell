#!/usr/bin/env bash
# block-push.sh — PreToolUse hook do plugin sleepwell.
#
# Recusas:
#   1. Sempre (mesmo fora do loop): force-push e push direto em base
#      branches (main/master/develop/trunk).
#   2. Durante loop sleepwell ativo (status=running em
#      .sleepwell/state.json): qualquer `git push` é bloqueado — push
#      deve ser uma decisão humana explícita após /sleepwell-stop ou
#      finalize natural do loop.
#
# Protocolo Claude Code PreToolUse:
#   - input: JSON via stdin (tool_name, tool_input, ...).
#   - exit 0  → permite a tool call.
#   - exit 2  → recusa e a stderr é mostrada ao modelo/usuário.

set -euo pipefail

input=$(cat || true)

# Só nos importamos com Bash.
tool_name=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null || true)
if [ "$tool_name" != "Bash" ]; then
  exit 0
fi

# Comando que o agente quer rodar.
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
if [ -z "$cmd" ]; then
  exit 0
fi

# Detecta `git push` (com flags, subcomandos compostos, pipes, etc).
is_git_push=0
if printf '%s' "$cmd" | grep -Eq '(^|[;&|[:space:]])git([[:space:]]+-[^[:space:]]+)*[[:space:]]+push([[:space:]]|$)'; then
  is_git_push=1
fi

# 1. Recusas globais (independem do estado do loop).
if [ "$is_git_push" = "1" ]; then
  # Force-push: --force, -f isolado, ou refspec com `+`.
  if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+push[^|;&]*([[:space:]]--force(-with-lease|-if-includes)?([[:space:]]|=|$)|[[:space:]]-f([[:space:]]|$)|[[:space:]]\+[A-Za-z0-9_./-]+:)'; then
    cat >&2 <<EOF
sleepwell: force-push bloqueado.

Push direto em base branch ou force-push bloqueado. Use /sleepwell-pr
para criar PR. Se for absolutamente necessário, peça ao usuário humano
para executar manualmente fora do agent.
EOF
    exit 2
  fi

  # Push direto em base branch (main/master/develop/trunk) — match em
  # qualquer ocorrência da palavra após `git push`.
  if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+push[^|;&]*[[:space:]](main|master|develop|trunk)([[:space:]]|$|:)'; then
    cat >&2 <<EOF
sleepwell: push em base branch bloqueado.

Push direto em base branch ou force-push bloqueado. Use /sleepwell-pr
para criar PR.
EOF
    exit 2
  fi
fi

# 2. Bloqueio durante loop ativo (comportamento original).
state_file=".sleepwell/state.json"
if [ ! -f "$state_file" ]; then
  exit 0
fi

status=$(jq -r '.status // empty' "$state_file" 2>/dev/null || true)
if [ "$status" != "running" ]; then
  exit 0
fi

if [ "$is_git_push" = "1" ]; then
  cat >&2 <<EOF
sleepwell: git push bloqueado.

Loop sleepwell está em status=running (branch=$(jq -r '.branch // "?"' "$state_file" 2>/dev/null)).
Pushar no meio do loop pode publicar commits que ainda serão revertidos.

Pare o loop antes:
  /sleepwell-stop
e revise com:
  /sleepwell-diff
Depois você pode pushar manualmente — ou use /sleepwell-pr.
EOF
  exit 2
fi

exit 0
