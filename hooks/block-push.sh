#!/usr/bin/env bash
# block-push.sh — PreToolUse hook for the sleepwell plugin.
#
# Refusals:
#   1. Always (even outside the loop): force-push and direct push to base
#      branches (main/master/develop/trunk).
#   2. During an active sleepwell loop (status=running in
#      .sleepwell/state.json): any `git push` is blocked — push
#      must be an explicit human decision after /sleepwell-stop or
#      natural loop finalize.
#
# Claude Code PreToolUse protocol:
#   - input: JSON via stdin (tool_name, tool_input, ...).
#   - exit 0  → allows the tool call.
#   - exit 2  → refuses and stderr is shown to the model/user.

set -euo pipefail

input=$(cat || true)

# Escape hatch: explicit override (used for plugin self-development /
# emergency manual operation). Set SLEEPWELL_ALLOW_PUSH=1 to bypass.
if [ "${SLEEPWELL_ALLOW_PUSH:-0}" = "1" ]; then
  exit 0
fi

# We only care about Bash.
tool_name=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null || true)
if [ "$tool_name" != "Bash" ]; then
  exit 0
fi

# Command the agent wants to run.
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
if [ -z "$cmd" ]; then
  exit 0
fi

# Detect `git push` (with flags, compound subcommands, pipes, etc).
is_git_push=0
if printf '%s' "$cmd" | grep -Eq '(^|[;&|[:space:]])git([[:space:]]+-[^[:space:]]+)*[[:space:]]+push([[:space:]]|$)'; then
  is_git_push=1
fi

# 1. Force-push is always blocked (regardless of active loop) — dangerous
# in any context and should never be done by an automated agent.
if [ "$is_git_push" = "1" ]; then
  if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+push[^|;&]*([[:space:]]--force(-with-lease|-if-includes)?([[:space:]]|=|$)|[[:space:]]-f([[:space:]]|$)|[[:space:]]\+[A-Za-z0-9_./-]+:)'; then
    cat >&2 <<EOF
sleepwell: force-push blocked.

Force-push may rewrite published history. If absolutely necessary,
ask the human user to run it manually outside the agent, or export
SLEEPWELL_ALLOW_PUSH=1.
EOF
    exit 2
  fi
fi

# 2. Block during active loop. No state.json → no loop, let it
# through (including push to base branches — that's the host repo, not
# the hook's job to police outside the loop).
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
sleepwell: git push blocked.

Sleepwell loop is in status=running (branch=$(jq -r '.branch // "?"' "$state_file" 2>/dev/null)).
Pushing mid-loop may publish commits that will still be reverted.

Stop the loop first:
  /sleepwell-stop
and review with:
  /sleepwell-diff
Then you can push manually — or use /sleepwell-pr.
EOF
  exit 2
fi

exit 0
