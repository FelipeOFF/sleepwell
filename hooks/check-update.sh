#!/usr/bin/env bash
# check-update.sh — SessionStart hook of the sleepwell plugin.
# Checks GitHub for newer plugin or helper releases (best-effort, in background).
# Writes a sentinel JSON cache to ~/.cache/sleepwell/update.json that
# /sleepwell:sleepwell-update reads. Never blocks the session.
set -u

# Escape hatch.
[ "${SLEEPWELL_SKIP_UPDATE_CHECK:-0}" = "1" ] && exit 0

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/sleepwell"
CACHE_FILE="$CACHE_DIR/update.json"
TTL_SECS=${SLEEPWELL_UPDATE_TTL:-86400}  # 24h default

# Skip if cache is fresh.
if [ -f "$CACHE_FILE" ]; then
  ts=$(jq -r '.checked_at_unix // 0' "$CACHE_FILE" 2>/dev/null || echo 0)
  now=$(date +%s)
  [ $((now - ts)) -lt "$TTL_SECS" ] && exit 0
fi

# Resolve plugin root and current versions.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(dirname "$HERE")"
PLUGIN_VERSION=$(jq -r .version "$ROOT/.claude-plugin/plugin.json" 2>/dev/null || echo "0.0.0")

# Resolve owner/repo: env override > plugin.json .repository > last-resort default.
REPO_FROM_ENV="${SLEEPWELL_UPDATE_REPO:-}"
if [ -n "$REPO_FROM_ENV" ]; then
  REPO_SLUG="$REPO_FROM_ENV"
else
  repo_url=$(jq -r '.repository // empty' "$ROOT/.claude-plugin/plugin.json" 2>/dev/null || echo "")
  REPO_SLUG=$(echo "$repo_url" | sed -E 's#^https?://github.com/([^/]+/[^/]+).*#\1#' | sed -E 's/\.git$//')
fi
[ -z "$REPO_SLUG" ] && REPO_SLUG="FelipeOFF/sleepwell"

# Helper opt-out: persistent sentinel suppresses helper notifications.
HELPER_OPTOUT_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/sleepwell/no-helper"

# Helper version: prefer installed binary's --version output; else "none".
HELPER_BIN_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/sleepwell/bin"
HELPER_BIN="$HELPER_BIN_DIR/sleepwell-helper"
if [ -f "$HELPER_OPTOUT_FILE" ]; then
  HELPER_VERSION="opted-out"
else
  [ -x "$HELPER_BIN" ] && HELPER_VERSION=$("$HELPER_BIN" --version 2>/dev/null | awk '{print $2}') || HELPER_VERSION="none"
fi

# Background fetch — never blocks startup.
(
  # Guard: jq is required for the JSON parsing below.
  command -v jq >/dev/null || exit 0

  mkdir -p "$CACHE_DIR"
  latest_plugin=""
  latest_helper=""
  if command -v gh >/dev/null 2>&1; then
    latest_plugin=$(timeout 8 gh api "repos/$REPO_SLUG/releases" --jq '[.[] | select(.tag_name | startswith("v"))][0].tag_name // empty' 2>/dev/null || true)
    latest_helper=$(timeout 8 gh api "repos/$REPO_SLUG/releases" --jq '[.[] | select(.tag_name | startswith("bin-v"))][0].tag_name // empty' 2>/dev/null || true)
  elif command -v curl >/dev/null 2>&1; then
    json=$(curl -fsSL --max-time 8 "https://api.github.com/repos/$REPO_SLUG/releases" 2>/dev/null || echo "[]")
    latest_plugin=$(printf '%s' "$json" | jq -r '[.[] | select(.tag_name | startswith("v"))][0].tag_name // empty' 2>/dev/null || true)
    latest_helper=$(printf '%s' "$json" | jq -r '[.[] | select(.tag_name | startswith("bin-v"))][0].tag_name // empty' 2>/dev/null || true)
  fi

  # Fallback: plugin tag may not exist (repo only tags helper as bin-v*).
  # Read .claude-plugin/plugin.json from default branch via raw GitHub.
  if [ -z "$latest_plugin" ]; then
    raw_json=""
    if command -v gh >/dev/null 2>&1; then
      raw_json=$(timeout 8 gh api "repos/$REPO_SLUG/contents/.claude-plugin/plugin.json" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null || true)
    fi
    if [ -z "$raw_json" ] && command -v curl >/dev/null 2>&1; then
      for branch in main master; do
        raw_json=$(curl -fsSL --max-time 8 "https://raw.githubusercontent.com/$REPO_SLUG/$branch/.claude-plugin/plugin.json" 2>/dev/null || echo "")
        [ -n "$raw_json" ] && break
      done
    fi
    if [ -n "$raw_json" ]; then
      remote_ver=$(printf '%s' "$raw_json" | jq -r '.version // empty' 2>/dev/null || true)
      [ -n "$remote_ver" ] && latest_plugin="v$remote_ver"
    fi
  fi

  # Strip prefixes for comparison.
  lp=${latest_plugin#v}
  lh=${latest_helper#bin-v}

  # Decide if updates are available (semver-ish lex compare).
  semver_gt() {
    # returns 0 if $1 > $2 by semver
    [ "$1" = "$2" ] && return 1
    higher=$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)
    [ "$higher" = "$1" ]
  }

  plugin_update=false
  [ -n "$lp" ] && semver_gt "$lp" "$PLUGIN_VERSION" && plugin_update=true

  helper_update=false
  if [ "$HELPER_VERSION" = "opted-out" ]; then
    helper_update=false
  elif [ -n "$lh" ] && [ "$HELPER_VERSION" != "none" ]; then
    semver_gt "$lh" "$HELPER_VERSION" && helper_update=true
  elif [ -n "$lh" ] && [ "$HELPER_VERSION" = "none" ]; then
    helper_update=true
  fi

  tmp="$CACHE_FILE.$$.tmp"
  cat > "$tmp" <<JSON
{
  "plugin_installed": "$PLUGIN_VERSION",
  "plugin_latest": "${latest_plugin:-unknown}",
  "plugin_update_available": $plugin_update,
  "helper_installed": "$HELPER_VERSION",
  "helper_latest": "${latest_helper:-unknown}",
  "helper_update_available": $helper_update,
  "checked_at_unix": $(date +%s),
  "checked_at_iso": "$(date -u +%FT%TZ)"
}
JSON
  mv "$tmp" "$CACHE_FILE"
) >/dev/null 2>&1 &
disown 2>/dev/null || true
exit 0
