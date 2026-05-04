#!/usr/bin/env bash
# generate-changelog.sh — render a Conventional Commits changelog section.
#
# Usage:
#   scripts/generate-changelog.sh <new_version> [from_ref] [to_ref]
#
# Defaults:
#   from_ref → previous v* plugin tag (or empty if none)
#   to_ref   → HEAD
#
# Emits markdown to stdout suitable for prepending to CHANGELOG.md and
# also for use as a GitHub Release body. Compatible with bash 3.2+.
set -euo pipefail

NEW="${1:?missing new version (e.g. 0.7.3)}"
FROM="${2:-}"
TO="${3:-HEAD}"

if [ -z "$FROM" ]; then
  FROM=$(git tag --list 'v*' --sort=-v:refname \
         | grep -vE '^v[0-9]+\.[0-9]+\.[0-9]+-' \
         | head -1 || true)
fi

if [ -z "$FROM" ]; then
  RANGE="$TO"
else
  RANGE="$FROM..$TO"
fi

DATE=$(date -u +%Y-%m-%d)

# Output buckets stored in tempfiles to stay portable across bash versions.
TMPDIR_OUT=$(mktemp -d 2>/dev/null || mktemp -d -t cl)
trap 'rm -rf "$TMPDIR_OUT"' EXIT

bucket_label() {
  case "$1" in
    feat)     printf '### Features' ;;
    fix)      printf '### Bug fixes' ;;
    perf)     printf '### Performance' ;;
    refactor) printf '### Refactor' ;;
    docs)     printf '### Documentation' ;;
    test)     printf '### Tests' ;;
    build)    printf '### Build' ;;
    ci)       printf '### CI' ;;
    chore)    printf '### Chore' ;;
    style)    printf '### Style' ;;
    hotfix)   printf '### Hotfix' ;;
    other)    printf '### Other' ;;
    *) return 1 ;;
  esac
}
ORDER="feat fix perf refactor docs test build ci chore style hotfix other"

# Process commits via process substitution (POSIX-friendly while read).
git log "$RANGE" --no-merges --pretty=tformat:'%h%x09%s' \
  | while IFS=$'\t' read -r sha subject || [ -n "$sha" ]; do
      [ -z "$sha" ] && continue
      type=""
      title="$subject"

      # Match `type(scope)?: subject` (banged or not). Use grep -E for portability.
      head_part="${subject%%:*}"
      rest_part="${subject#*: }"
      cleaned_head=$(printf '%s' "$head_part" | sed -E 's/!$//' | sed -E 's/\(.+\)$//')
      if printf '%s' "$cleaned_head" | grep -Eq '^[a-z]+$' && [ "$head_part" != "$subject" ]; then
        type="$cleaned_head"
        title="$rest_part"
      fi

      # Skip release chores entirely — they are noise.
      case "$subject" in
        chore\(release\)*) continue ;;
      esac

      if [ -n "$type" ] && bucket_label "$type" >/dev/null 2>&1; then
        printf -- '- %s (%s)\n' "$title" "$sha" >> "$TMPDIR_OUT/$type"
      else
        printf -- '- %s (%s)\n' "$subject" "$sha" >> "$TMPDIR_OUT/other"
      fi
    done

REPO_URL=$(git config --get remote.origin.url 2>/dev/null \
  | sed -E 's#(git@|https://)github.com[:/]([^/]+)/([^/.]+)(\.git)?#https://github.com/\2/\3#' || true)

{
  printf '## v%s — %s\n\n' "$NEW" "$DATE"
  if [ -n "$FROM" ] && [ -n "$REPO_URL" ]; then
    printf '_Compare: [`%s…v%s`](%s/compare/%s...v%s)_\n\n' \
      "$FROM" "$NEW" "$REPO_URL" "$FROM" "$NEW"
  fi

  emitted=0
  for type in $ORDER; do
    if [ -s "$TMPDIR_OUT/$type" ]; then
      bucket_label "$type"
      printf '\n\n'
      cat "$TMPDIR_OUT/$type"
      printf '\n'
      emitted=1
    fi
  done

  if [ "$emitted" = "0" ]; then
    if [ -n "$FROM" ]; then
      printf '_No user-facing changes since %s._\n\n' "$FROM"
    else
      printf '_Initial release._\n\n'
    fi
  fi
}
