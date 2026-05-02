#!/usr/bin/env bash
# scope-guard.sh — PreToolUse hook for the sleepwell plugin.
#
# When the sleepwell loop is in `status: running` and has `worktree_path`
# defined, any Edit/Write/MultiEdit/NotebookEdit outside that worktree
# is refused. Ensures the autonomous loop does not leak edits to other
# projects/directories.

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

# Resolve canonical worktree path.
wt_real=$(realpath "$worktree_path" 2>/dev/null || echo "$worktree_path")

# Tools use `file_path` (Edit/Write/MultiEdit) and `notebook_path` (NotebookEdit).
target=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null || true)
[ -n "$target" ] || exit 0

# Resolve target — may not exist yet (Write of a new file); fall back to the parent.
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
sleepwell: edit outside the worktree blocked.

  tool:    $tool_name
  target:  $target_real
  scope:   $wt_real

While a sleepwell loop is running, edits are only allowed inside the
isolated worktree. If you need to change something outside, stop the
loop with /sleepwell-stop and edit manually.
EOF
exit 2
