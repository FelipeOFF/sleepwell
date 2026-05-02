#!/usr/bin/env bash
# scope-guard.sh — PreToolUse hook do plugin sleepwell.
#
# Quando o loop sleepwell está em `status: running` e tem `worktree_path`
# definido, qualquer Edit/Write/MultiEdit/NotebookEdit fora desse worktree
# é recusado. Garante que o loop autônomo não vaze edições para outros
# projetos/diretórios.

set -euo pipefail

input=$(cat || true)

tool_name=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null || true)
case "$tool_name" in
  Edit|Write|MultiEdit|NotebookEdit) ;;
  *) exit 0 ;;
esac

state_file=".sleepwell/state.json"
[ -f "$state_file" ] || exit 0

status=$(jq -r '.status // empty' "$state_file" 2>/dev/null || true)
[ "$status" = "running" ] || exit 0

worktree_path=$(jq -r '.worktree_path // empty' "$state_file" 2>/dev/null || true)
[ -n "$worktree_path" ] || exit 0

# Resolve caminho canônico do worktree.
wt_real=$(realpath "$worktree_path" 2>/dev/null || echo "$worktree_path")

# Tools usam `file_path` (Edit/Write/MultiEdit) e `notebook_path` (NotebookEdit).
target=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null || true)
[ -n "$target" ] || exit 0

# Resolve target — pode não existir ainda (Write de arquivo novo); cai para o pai.
if target_real=$(realpath "$target" 2>/dev/null); then
  :
elif parent_real=$(realpath "$(dirname "$target")" 2>/dev/null); then
  target_real="$parent_real/$(basename "$target")"
else
  target_real="$target"
fi

case "$target_real" in
  "$wt_real"|"$wt_real"/*)
    exit 0
    ;;
esac

cat >&2 <<EOF
sleepwell: edição fora do worktree bloqueada.

  tool:    $tool_name
  target:  $target_real
  scope:   $wt_real

Durante um loop sleepwell em execução só é permitido editar dentro do
worktree isolado. Se você precisa mudar algo fora, pare o loop com
/sleepwell-stop e edite manualmente.
EOF
exit 2
