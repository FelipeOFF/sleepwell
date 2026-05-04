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
# Repo selection (for forks/mirrors):
#   1. SLEEPWELL_REPO env var (e.g. "myorg/sleepwell" or full https URL).
#   2. Inferred from `installed_plugins.json` entries `sleepwell@<owner>/<repo>`
#      when they encode the source repo.
#   3. Fallback: FelipeOFF/sleepwell.
#
# Backup retention:
#   Old `.broken.<ts>` directories left from previous restores are pruned
#   automatically after a successful run. Default TTL: 7 days. Override with
#   SLEEPWELL_BROKEN_TTL_DAYS=<n> (set to 0 to disable cleanup).
#
# Designed to run **without** the plugin being loaded. Standalone — usable via:
#   bash <(curl -fsSL https://raw.githubusercontent.com/FelipeOFF/sleepwell/main/scripts/restore-plugin-cache.sh)
#
# Requires: bash, git, python3 (universal on macOS/Linux dev boxes).
set -euo pipefail

PLUGINS_JSON="${HOME}/.claude/plugins/installed_plugins.json"
DRY_RUN=0
FORCE=0
VERBOSE=0
SLEEPWELL_REPO="${SLEEPWELL_REPO:-}"
SLEEPWELL_BROKEN_TTL_DAYS="${SLEEPWELL_BROKEN_TTL_DAYS:-7}"
DEFAULT_REPO="FelipeOFF/sleepwell"

log()  { echo "[sleepwell-restore] $*" >&2; }
vlog() { [ "$VERBOSE" = "1" ] && echo "[sleepwell-restore] (debug) $*" >&2 || true; }
err()  { echo "[sleepwell-restore] error: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --force)   FORCE=1;   shift ;;
    --verbose) VERBOSE=1; shift ;;
    --repo)    SLEEPWELL_REPO="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,28p' "$0"
      exit 0
      ;;
    *) err "unknown arg: $1" ;;
  esac
done

command -v git     >/dev/null 2>&1 || err "git not found in PATH"
command -v python3 >/dev/null 2>&1 || err "python3 not found in PATH"

[ -f "$PLUGINS_JSON" ] || err "installed_plugins.json not found at $PLUGINS_JSON"

# Resolve REPO_URL from (1) override, (2) inference from installed_plugins.json
# entries shaped `sleepwell@<owner>/<repo>`, (3) DEFAULT_REPO fallback.
resolve_repo_url() {
  if [ -n "$SLEEPWELL_REPO" ]; then
    case "$SLEEPWELL_REPO" in
      http*|git@*) echo "$SLEEPWELL_REPO" ;;
      *)           echo "https://github.com/${SLEEPWELL_REPO}.git" ;;
    esac
    return 0
  fi
  local inferred
  inferred="$(python3 - "$PLUGINS_JSON" <<'PY'
import json, sys, re
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
except Exception:
    sys.exit(0)
for key in (data.get("plugins") or {}).keys():
    # accept patterns like "sleepwell@owner/repo" or "sleepwell@owner"
    m = re.match(r"^sleepwell@([A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)?)$", key)
    if not m:
        continue
    val = m.group(1)
    if "/" not in val:
        # owner only — pair with repo name "sleepwell"
        val = f"{val}/sleepwell"
    print(val)
    break
PY
)"
  if [ -n "$inferred" ]; then
    echo "https://github.com/${inferred}.git"
  else
    echo "https://github.com/${DEFAULT_REPO}.git"
  fi
}

REPO_URL="$(resolve_repo_url)"
log "using repo: $REPO_URL"

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

# Detect default branch of REPO_URL (some forks use "master" instead of "main").
detect_default_branch() {
  local repo_path="$1"
  local b
  b="$(git -C "$repo_path" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null \
       | sed 's|^origin/||' || true)"
  if [ -z "$b" ]; then
    # remotes/origin/HEAD missing — try to set it, then reread.
    git -C "$repo_path" remote set-head origin --auto >/dev/null 2>&1 || true
    b="$(git -C "$repo_path" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null \
         | sed 's|^origin/||' || true)"
  fi
  [ -n "$b" ] || b="main"
  echo "$b"
}

# Prune `.broken.<ts>` siblings older than SLEEPWELL_BROKEN_TTL_DAYS.
prune_old_backups() {
  local install_path="$1"
  [ "${SLEEPWELL_BROKEN_TTL_DAYS:-0}" -gt 0 ] || return 0
  local parent base
  parent="$(dirname "$install_path")"
  base="$(basename "$install_path")"
  [ -d "$parent" ] || return 0
  find "$parent" -maxdepth 1 -type d -name "${base}.broken.*" \
    -mtime "+${SLEEPWELL_BROKEN_TTL_DAYS}" 2>/dev/null | while read -r old; do
      vlog "pruning old backup: $old"
      rm -rf "$old"
    done
}

restore_entry() {
  local install_path="$1" sha="$2" version="$3"
  local parent
  parent="$(dirname "$install_path")"

  if [ "$DRY_RUN" = "1" ]; then
    log "[dry-run] would clone $REPO_URL → $install_path (sha=${sha:-<default-branch>})"
    return 0
  fi

  mkdir -p "$parent"

  # Backup existing dir if any (kept for SLEEPWELL_BROKEN_TTL_DAYS, then pruned).
  if [ -e "$install_path" ]; then
    local backup="${install_path}.broken.$(date +%s)"
    vlog "moving existing $install_path → $backup"
    mv "$install_path" "$backup"
  fi

  # Clone into a `.partial` and rename on success so an interrupted clone never
  # leaves a half-baked dir at the canonical path.
  local partial="${install_path}.partial.$$"
  trap 'rm -rf "$partial"' EXIT INT TERM

  log "cloning $REPO_URL → $install_path"
  git clone --quiet "$REPO_URL" "$partial" || err "git clone failed"
  mv "$partial" "$install_path"
  trap - EXIT INT TERM

  local default_branch
  default_branch="$(detect_default_branch "$install_path")"

  local new_sha=""
  if [ -n "$sha" ]; then
    if git -C "$install_path" cat-file -e "$sha^{commit}" 2>/dev/null; then
      vlog "checking out recorded sha $sha"
      git -C "$install_path" checkout --quiet "$sha"
      new_sha="$sha"
    else
      log "recorded sha $sha not reachable; falling back to $default_branch"
      git -C "$install_path" checkout --quiet "$default_branch"
      new_sha="$(git -C "$install_path" rev-parse HEAD 2>/dev/null)"
    fi
  else
    git -C "$install_path" checkout --quiet "$default_branch"
    new_sha="$(git -C "$install_path" rev-parse HEAD 2>/dev/null)"
  fi

  # Persist the resolved sha to a sibling tmp file (avoids stdout coupling).
  printf '%s\n' "$new_sha" > "${install_path}.last_sha"
}

update_json() {
  local key="$1" install_path="$2" new_sha="$3"
  python3 - "$PLUGINS_JSON" "$key" "$install_path" "$new_sha" <<'PY'
import json, os, sys, datetime
path, key, install_path, new_sha = sys.argv[1:5]
with open(path) as f:
    data = json.load(f)
arr = (data.get("plugins") or {}).get(key, [])
# Single timestamp source — datetime.now(UTC) replaces deprecated utcnow.
now_dt = datetime.datetime.now(datetime.timezone.utc)
now = now_dt.strftime("%Y-%m-%dT%H:%M:%S.") + f"{now_dt.microsecond // 1000:03d}Z"
for entry in arr:
    if entry.get("installPath") == install_path:
        entry["gitCommitSha"] = new_sha
        entry["lastUpdated"] = now
# Atomic write: tmp file + os.replace prevents corruption on crash/SIGINT.
tmp = path + ".tmp." + str(os.getpid())
with open(tmp, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
os.replace(tmp, path)
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
    restore_entry "$IPATH" "$SHA" "$VER"
    continue
  fi

  restore_entry "$IPATH" "$SHA" "$VER"
  NEW_SHA=""
  if [ -f "${IPATH}.last_sha" ]; then
    NEW_SHA="$(cat "${IPATH}.last_sha")"
    rm -f "${IPATH}.last_sha"
  fi
  update_json "$KEY" "$IPATH" "$NEW_SHA"

  if is_broken "$IPATH"; then
    err "post-restore integrity check FAILED for $IPATH"
  fi
  LOCAL_COUNT="$(count_commands "$IPATH")"
  log "  ✓ restored ($LOCAL_COUNT commands) at sha=$NEW_SHA"
  ANY_RESTORED=1

  # Restore succeeded — prune old `.broken.*` siblings beyond TTL.
  prune_old_backups "$IPATH"
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
