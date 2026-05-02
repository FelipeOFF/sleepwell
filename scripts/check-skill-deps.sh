#!/usr/bin/env bash
# check-skill-deps.sh — lists references to external skills in the plugin and
# warns which ones are not vendored under skills/vendor/.
#
# Usage: ./scripts/check-skill-deps.sh
# Always exits 0 (informational). Use in CI as a warning, not a gate.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

echo "sleepwell — skill dependency check"
echo "=================================="

# Collect references of the form `superpowers:foo` or `everything-claude-code:bar`
# in any .md of the plugin (except vendor/ and docs/SKILLS.md which documents).
refs=$(grep -RhoE '(superpowers|everything-claude-code|obsidian-markdown):[a-zA-Z0-9_-]+' \
        --include='*.md' \
        --exclude-dir='vendor' \
        --exclude-dir='node_modules' \
        . 2>/dev/null \
        | grep -v '^docs/SKILLS.md' \
        | sort -u || true)

# obsidian-markdown may also appear as a standalone skill without prefix
extra=$(grep -RhoE '`obsidian-markdown`' \
        --include='*.md' \
        --exclude-dir='vendor' \
        . 2>/dev/null | tr -d '`' | sort -u || true)

if [ -z "$refs" ] && [ -z "$extra" ]; then
  echo "No external skills referenced."
  exit 0
fi

echo
echo "Referenced skills:"
{ echo "$refs"; echo "$extra"; } | grep -v '^$' | sort -u | sed 's/^/  - /'

echo
echo "Vendored under skills/vendor/:"
if [ -d skills/vendor ]; then
  find skills/vendor -name SKILL.md -mindepth 2 -maxdepth 2 \
    | sed 's|^|  - |'
else
  echo "  (none)"
fi

echo
echo "Status:"
missing=0
while IFS= read -r ref; do
  [ -z "$ref" ] && continue
  # E.g.: superpowers:using-git-worktrees → using-git-worktrees
  name=${ref##*:}
  # Vendor adjustment: we use simplified names (e.g., git-worktrees).
  case "$name" in
    using-git-worktrees) vendor=git-worktrees ;;
    *) vendor=$name ;;
  esac
  if [ -f "skills/vendor/$vendor/SKILL.md" ]; then
    echo "  [OK]      $ref → skills/vendor/$vendor/"
  else
    echo "  [missing] $ref (not vendored — optional or external coverage)"
    missing=$((missing + 1))
  fi
done <<< "$refs"

echo
echo "Summary: $missing reference(s) without vendor (see docs/SKILLS.md for policy)."
