#!/usr/bin/env bash
# update-plugin-cache.sh — self-update for the sleepwell plugin cache.
#
# Mirrors what `/plugin update sleepwell@sleepwell` would do, but as a
# regular shell command — so an agent (Claude Code, Codex, etc.) can
# upgrade the plugin without the user having to type a slash command.
#
# Usage:
#   bash scripts/update-plugin-cache.sh                 # resolve "latest" tag, install
#   bash scripts/update-plugin-cache.sh --version v0.7.3
#   bash scripts/update-plugin-cache.sh --version latest --dry-run
#   bash scripts/update-plugin-cache.sh --force         # re-clone even if same version
#
# Repo override: SLEEPWELL_REPO=owner/name (default FelipeOFF/sleepwell).
#
# After a successful update the user must run /reload-plugins (or
# restart Claude Code) for the new commands and skills to be picked up
# — this script never spawns Claude Code itself.
#
# Requires: bash, git, python3, and either gh or curl for tag resolution.
set -euo pipefail

PLUGINS_JSON="${HOME}/.claude/plugins/installed_plugins.json"
TARGET_VERSION="latest"
DRY_RUN=0
FORCE=0
VERBOSE=0
SLEEPWELL_REPO="${SLEEPWELL_REPO:-}"
DEFAULT_REPO="FelipeOFF/sleepwell"

log()  { echo "[sleepwell-update] $*" >&2; }
vlog() { [ "$VERBOSE" = "1" ] && echo "[sleepwell-update] (debug) $*" >&2 || true; }
err()  { echo "[sleepwell-update] error: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --version) TARGET_VERSION="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --force)   FORCE=1;   shift ;;
    --verbose) VERBOSE=1; shift ;;
    --repo)    SLEEPWELL_REPO="$2"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) err "unknown arg: $1" ;;
  esac
done

command -v git     >/dev/null 2>&1 || err "git not found in PATH"
command -v python3 >/dev/null 2>&1 || err "python3 not found in PATH"
[ -f "$PLUGINS_JSON" ] || err "installed_plugins.json not found at $PLUGINS_JSON"

# Workspace for python helpers — avoids heredocs-in-$() issues on bash 3.2.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/infer_repo.py" <<'PY'
import json, sys, re
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
except Exception:
    sys.exit(0)
for key in (d.get("plugins") or {}).keys():
    m = re.match(r"^sleepwell@([A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)?)$", key)
    if not m:
        continue
    val = m.group(1)
    # Skip marketplace-only keys (e.g. "sleepwell@sleepwell") that
    # carry no owner/repo info — fall back to default.
    if "/" not in val:
        continue
    print(val); break
PY

cat > "$WORK/dump_entry.py" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
for key, arr in (d.get("plugins") or {}).items():
    if not key.startswith("sleepwell@"):
        continue
    for entry in arr:
        print(key)
        print(entry.get("installPath", ""))
        print(entry.get("version", ""))
        print(entry.get("gitCommitSha", ""))
        sys.exit(0)
PY

cat > "$WORK/update_entry.py" <<'PY'
import json, os, sys, tempfile, time
path, key, new_path, new_ver, new_sha = sys.argv[1:]
with open(path) as f:
    d = json.load(f)
arr = d["plugins"][key]
entry = arr[0]
entry["installPath"] = new_path
entry["version"] = new_ver
entry["gitCommitSha"] = new_sha
entry["lastUpdated"] = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime())
fd, tmp = tempfile.mkstemp(prefix=".installed_plugins.", dir=os.path.dirname(path))
try:
    with os.fdopen(fd, "w") as f:
        json.dump(d, f, indent=2)
        f.write("\n")
    os.replace(tmp, path)
except Exception:
    os.unlink(tmp)
    raise
print("updated entry for", key)
PY

cat > "$WORK/parse_latest.py" <<'PY'
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for r in d:
    t = r.get("tag_name", "")
    if t.startswith("v") and not t.startswith("bin-") and not r.get("draft"):
        print(t); break
PY

# Resolve repo slug.
if [ -n "$SLEEPWELL_REPO" ]; then
  REPO_SLUG="$(echo "$SLEEPWELL_REPO" | sed -E 's#^https?://github.com/##; s#\.git$##')"
else
  REPO_SLUG="$(python3 "$WORK/infer_repo.py" "$PLUGINS_JSON" || true)"
  [ -z "$REPO_SLUG" ] && REPO_SLUG="$DEFAULT_REPO"
fi
REPO_URL="https://github.com/${REPO_SLUG}.git"
log "using repo: $REPO_SLUG"

# Resolve target tag.
if [ "$TARGET_VERSION" = "latest" ]; then
  TAG=""
  if command -v gh >/dev/null 2>&1; then
    TAG="$(gh api "repos/$REPO_SLUG/releases" \
            --jq '[.[] | select(.draft | not) | select(.tag_name | startswith("v")) | select(.tag_name | startswith("bin-") | not)][0].tag_name // empty' \
            2>/dev/null || true)"
  fi
  if [ -z "$TAG" ] && command -v curl >/dev/null 2>&1; then
    JSON_RAW="$(curl -fsSL --max-time 8 "https://api.github.com/repos/$REPO_SLUG/releases" 2>/dev/null || echo '[]')"
    TAG="$(printf '%s' "$JSON_RAW" | python3 "$WORK/parse_latest.py" 2>/dev/null || true)"
  fi
  [ -n "$TAG" ] || err "could not resolve latest v* tag from $REPO_SLUG"
else
  case "$TARGET_VERSION" in v*) TAG="$TARGET_VERSION" ;; *) TAG="v$TARGET_VERSION" ;; esac
fi

NEW_VER="${TAG#v}"
log "target version: $NEW_VER ($TAG)"

# Read current entry (4-line dump: key, installPath, version, sha).
DUMP="$(python3 "$WORK/dump_entry.py" "$PLUGINS_JSON")"
[ -z "$DUMP" ] && err "no sleepwell@* entry found in $PLUGINS_JSON"

CURRENT_KEY="$(echo     "$DUMP" | sed -n '1p')"
CURRENT_PATH="$(echo    "$DUMP" | sed -n '2p')"
CURRENT_VERSION="$(echo "$DUMP" | sed -n '3p')"

log "currently installed: $CURRENT_VERSION ($CURRENT_PATH)"

if [ "$CURRENT_VERSION" = "$NEW_VER" ] && [ "$FORCE" != "1" ]; then
  log "already at $NEW_VER — pass --force to re-clone"
  exit 0
fi

PARENT_DIR="$(dirname "$CURRENT_PATH")"
NEW_PATH="$PARENT_DIR/$NEW_VER"

if [ "$DRY_RUN" = "1" ]; then
  log "[dry-run] would clone $REPO_URL@$TAG → $NEW_PATH"
  log "[dry-run] would update installed_plugins.json: $CURRENT_VERSION → $NEW_VER"
  exit 0
fi

if [ -d "$NEW_PATH" ] && [ "$FORCE" != "1" ]; then
  vlog "$NEW_PATH already exists, reusing"
else
  rm -rf "$NEW_PATH"
  log "cloning $REPO_URL@$TAG → $NEW_PATH"
  git clone --depth 1 --branch "$TAG" "$REPO_URL" "$NEW_PATH" >/dev/null 2>&1 \
    || err "git clone failed for tag $TAG"
fi

NEW_SHA="$(git -C "$NEW_PATH" rev-parse HEAD)"

python3 "$WORK/update_entry.py" "$PLUGINS_JSON" "$CURRENT_KEY" "$NEW_PATH" "$NEW_VER" "$NEW_SHA"

# Cleanup older sibling cache directories — keep only NEW_VER and any
# .broken.* backups left by restore-plugin-cache.sh.
log "cleaning up older cache dirs in $PARENT_DIR"
for d in "$PARENT_DIR"/*; do
  [ -d "$d" ] || continue
  base="$(basename "$d")"
  case "$base" in
    "$NEW_VER")  continue ;;
    *.broken.*)  continue ;;
    *)
      vlog "removing $d"
      rm -rf "$d"
      ;;
  esac
done

# Refresh update cache so next /sleepwell:sleepwell-update sees fresh state.
rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/sleepwell/update.json"

log "done — installed sleepwell $NEW_VER at $NEW_PATH"
log "next: run /reload-plugins (or restart Claude Code) to load it"
