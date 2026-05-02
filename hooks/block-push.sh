#!/usr/bin/env bash
# block-push.sh — PreToolUse hook do plugin sleepwell.
#
# Bloqueia comandos `git push` enquanto o loop sleepwell estiver com
# `status: running` em `.sleepwell/state.json`. Push deve ser uma decisão
# humana explícita após /sleepwell-stop ou finalize natural do loop.
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

# Estado precisa existir e ter status "running".
state_file=".sleepwell/state.json"
if [ ! -f "$state_file" ]; then
  exit 0
fi

status=$(jq -r '.status // empty' "$state_file" 2>/dev/null || true)
if [ "$status" != "running" ]; then
  exit 0
fi

# Comando que o agente quer rodar.
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
if [ -z "$cmd" ]; then
  exit 0
fi

# Detecta `git push` (com flags, subcomandos compostos, pipes, etc).
# Casa "git" seguido (com flags arbitrárias) de "push".
if printf '%s' "$cmd" | grep -Eq '(^|[;&|[:space:]])git([[:space:]]+-[^[:space:]]+)*[[:space:]]+push([[:space:]]|$)'; then
  cat >&2 <<EOF
sleepwell: git push bloqueado.

Loop sleepwell está em status=running (branch=$(jq -r '.branch // "?"' "$state_file" 2>/dev/null)).
Pushar no meio do loop pode publicar commits que ainda serão revertidos.

Pare o loop antes:
  /sleepwell-stop
e revise com:
  /sleepwell-diff
Depois você pode pushar manualmente.
EOF
  exit 2
fi

exit 0
