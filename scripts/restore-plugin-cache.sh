#!/usr/bin/env bash
# restore-plugin-cache.sh — standalone recovery for sleepwell plugin cache.
#
# Reads ~/.claude/plugins/installed_plugins.json, finds sleepwell entries,
# detects broken cache directories (missing or empty .claude-plugin/plugin.json
# or commands/), and restores them via `git clone` from the upstream repo.
#
# Usage:
#   bash scripts/restore-plugin-cache.sh                # auto-detect and fix
#   bash scripts/restore-plugin-cache.sh --dry-run      # report only
#   bash scripts/restore-plugin-cache.sh --force        # re-clone even if ok
#   bash scripts/restore-plugin-cache.sh --verbose      # extra logging
#
# Designed to run **without** the plugin being loaded. Standalone — usable via:
#   bash <(curl -fsSL https://raw.githubusercontent.com/FelipeOFF/sleepwell/main/scripts/restore-plugin-cache.sh)
#
# Requires: bash, git, python3 (universal on macOS/Linux dev boxes).
set -euo pipefail

REPO_URL="https://github.com/FelipeOFF/sleepwell.git"
PLUGINS_JSON="${HOME}/.claude/plugins/installed_plugins.json"
DRY_RUN=0
FORCE=0
VERBOSE=0

log()  { echo "[sleepwell-restore] $*" >&2; }
vlog() { [ "$VERBOSE" = "1" ] && echo "[sleepwell-restore] (debug) $*" >&2 || true; }
err()  { echo "[sleepwell-restore] error: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --force)   FORCE=1;   shift ;;
    --verbose) VERBOSE=1; shift ;;
    -h|--help)
      sed -n '2,18p' "$0"
      exit 0
      ;;
    *) err "unknown arg: $1" ;;
  esac
done

command -v git     >/dev/null 2>&1 || err "git not found in PATH"
command -v python3 >/dev/null 2>&1 || err "python3 not found in PATH"

[ -f "$PLUGINS_JSON" ] || err "installed_plugins.json not found at $PLUGINS_JSON"

# Extract sleepwell entries: lines of "<key>\t<installPath>\t<sha>\t<version>".
ENTRIES="$(python3 - "$PLUGINS_JSON" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as f:
    data = json.load(f)
for key, arr in (data.get("plugins") or {}).items():
    if not key.startswith("sleepwell@"):
        continue
    for entry in arr:
        ip = entry.get("installPath", "")
        sha = entry.get("gitCommitSha", "") or ""
        ver = entry.get("version", "") or ""
        print(f"{key}\t{ip}\t{sha}\t{ver}")
PY
)"

if [ -z "$ENTRIES" ]; then
  log "no sleepwell@* entries found in installed_plugins.json — nothing to do."
  exit 0
fi

is_broken() {
  local p="$1"
  [ -d "$p" ] || return 0
  [ -f "$p/.claude-plugin/plugin.json" ] || return 0
  # commands/ must exist and contain at least one .md
  [ -d "$p/commands" ] || return 0
  local n
  n="$(find "$p/commands" -maxdepth 1 -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')"
  [ "${n:-0}" -gt 0 ] || return 0
  return 1
}

count_commands() {
  local p="$1"
  if [ -d "$p/commands" ]; then
    find "$p/commands" -maxdepth 1 -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' '
  else
    echo 0
  fi
}

restore_entry() {
  local install_path="$1" sha="$2" version="$3"
  local parent
  parent="$(dirname "$install_path")"

  if [ "$DRY_RUN" = "1" ]; then
    log "[dry-run] would clone $REPO_URL → $install_path (sha=${sha:-main})"
    return 0
  fi

  mkdir -p "$parent"

  # Backup existing dir if any
  if [ -e "$install_path" ]; then
    local backup="${install_path}.broken.$(date +%s)"
    vlog "moving existing $install_path → $backup"
    mv "$install_path" "$backup"
  fi

  log "cloning $REPO_URL → $install_path"
  git clone --quiet "$REPO_URL" "$install_path" || err "git clone failed"

  local new_sha=""
  if [ -n "$sha" ]; then
    if git -C "$install_path" cat-file -e "$sha^{commit}" 2>/dev/null; then
      vlog "checking out recorded sha $sha"
      git -C "$install_path" checkout --quiet "$sha"
      new_sha="$sha"
    else
      log "recorded sha $sha not reachable; falling back to main"
      git -C "$install_path" checkout --quiet main
      new_sha="$(git -C "$install_path" rev-parse HEAD 2>/dev/null)"
    fi
  else
    git -C "$install_path" checkout --quiet main
    new_sha="$(git -C "$install_path" rev-parse HEAD 2>/dev/null)"
  fi

  printf '%s\n' "$new_sha"
}

update_json() {
  local key="$1" install_path="$2" new_sha="$3"
  python3 - "$PLUGINS_JSON" "$key" "$install_path" "$new_sha" <<'PY'
import json, sys, datetime
path, key, install_path, new_sha = sys.argv[1:5]
with open(path) as f:
    data = json.load(f)
arr = (data.get("plugins") or {}).get(key, [])
now = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%S.") + \
      f"{datetime.datetime.utcnow().microsecond // 1000:03d}Z"
for entry in arr:
    if entry.get("installPath") == install_path:
        entry["gitCommitSha"] = new_sha
        entry["lastUpdated"] = now
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
}

ANY_BROKEN=0
ANY_RESTORED=0

# IFS-safe iteration over tab-separated lines.
while IFS=$'\t' read -r KEY IPATH SHA VER; do
  [ -n "$KEY" ] || continue
  log "checking $KEY @ $IPATH (version=$VER)"
  if is_broken "$IPATH"; then
    ANY_BROKEN=1
    log "  → broken cache detected"
  elif [ "$FORCE" = "1" ]; then
    log "  → cache valid (--force, re-cloning anyway)"
  else
    LOCAL_COUNT="$(count_commands "$IPATH")"
    log "  ✓ cache valid ($LOCAL_COUNT commands), no action needed"
    continue
  fi

  if [ "$DRY_RUN" = "1" ]; then
    restore_entry "$IPATH" "$SHA" "$VER" >/dev/null
    continue
  fi

  NEW_SHA="$(restore_entry "$IPATH" "$SHA" "$VER" | tail -n1)"
  update_json "$KEY" "$IPATH" "$NEW_SHA"

  if is_broken "$IPATH"; then
    err "post-restore integrity check FAILED for $IPATH"
  fi
  LOCAL_COUNT="$(count_commands "$IPATH")"
  log "  ✓ restored ($LOCAL_COUNT commands) at sha=$NEW_SHA"
  ANY_RESTORED=1
done <<< "$ENTRIES"

if [ "$DRY_RUN" = "1" ]; then
  log "dry-run complete."
  exit 0
fi

if [ "$ANY_RESTORED" = "1" ]; then
  log "done. Run /reload-plugins in Claude Code to apply."
elif [ "$ANY_BROKEN" = "0" ]; then
  log "all sleepwell caches healthy — nothing to do."
fi
