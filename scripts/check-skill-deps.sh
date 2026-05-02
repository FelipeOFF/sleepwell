#!/usr/bin/env bash
# check-skill-deps.sh — lista referências a skills externas no plugin e
# avisa quais não estão vendoradas em skills/vendor/.
#
# Uso: ./scripts/check-skill-deps.sh
# Exit 0 sempre (informativo). Use em CI como aviso, não como gate.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

echo "sleepwell — skill dependency check"
echo "=================================="

# Coleta referências do tipo `superpowers:foo` ou `everything-claude-code:bar`
# em qualquer .md do plugin (exceto vendor/ e docs/SKILLS.md que documenta).
refs=$(grep -RhoE '(superpowers|everything-claude-code|obsidian-markdown):[a-zA-Z0-9_-]+' \
        --include='*.md' \
        --exclude-dir='vendor' \
        --exclude-dir='node_modules' \
        . 2>/dev/null \
        | grep -v '^docs/SKILLS.md' \
        | sort -u || true)

# obsidian-markdown também pode aparecer como skill standalone sem prefixo
extra=$(grep -RhoE '`obsidian-markdown`' \
        --include='*.md' \
        --exclude-dir='vendor' \
        . 2>/dev/null | tr -d '`' | sort -u || true)

if [ -z "$refs" ] && [ -z "$extra" ]; then
  echo "Nenhuma skill externa referenciada."
  exit 0
fi

echo
echo "Skills referenciadas:"
{ echo "$refs"; echo "$extra"; } | grep -v '^$' | sort -u | sed 's/^/  - /'

echo
echo "Vendoradas em skills/vendor/:"
if [ -d skills/vendor ]; then
  find skills/vendor -name SKILL.md -mindepth 2 -maxdepth 2 \
    | sed 's|^|  - |'
else
  echo "  (nenhuma)"
fi

echo
echo "Status:"
missing=0
while IFS= read -r ref; do
  [ -z "$ref" ] && continue
  # Ex.: superpowers:using-git-worktrees → using-git-worktrees
  name=${ref##*:}
  # Ajuste para vendor: usamos nomes simplificados (ex.: git-worktrees).
  case "$name" in
    using-git-worktrees) vendor=git-worktrees ;;
    *) vendor=$name ;;
  esac
  if [ -f "skills/vendor/$vendor/SKILL.md" ]; then
    echo "  [OK]      $ref → skills/vendor/$vendor/"
  else
    echo "  [missing] $ref (não vendorado — opcional ou cobertura externa)"
    missing=$((missing + 1))
  fi
done <<< "$refs"

echo
echo "Sumário: $missing referência(s) sem vendor (consulte docs/SKILLS.md para política)."
