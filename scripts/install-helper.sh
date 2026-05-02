#!/usr/bin/env bash
# Detect platform and install sleepwell-helper from GitHub Releases.
# Usage:
#   scripts/install-helper.sh                    # latest release
#   scripts/install-helper.sh --version v0.5.0   # specific tag (without bin- prefix)
#   scripts/install-helper.sh --dest <dir>       # custom install dir
#   scripts/install-helper.sh --quiet            # only print errors
#   scripts/install-helper.sh --skip-if-present  # no-op if binary already runnable
set -euo pipefail

REPO="FelipeOFF/sleepwell"
DEFAULT_DEST="${XDG_DATA_HOME:-$HOME/.local/share}/sleepwell/bin"
VERSION=""
DEST="$DEFAULT_DEST"
QUIET=0
SKIP_IF_PRESENT=0

log()  { [ "$QUIET" = "1" ] || echo "[sleepwell-install] $*" >&2; }
err()  { echo "[sleepwell-install] error: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --dest) DEST="$2"; shift 2 ;;
    --quiet) QUIET=1; shift ;;
    --skip-if-present) SKIP_IF_PRESENT=1; shift ;;
    -h|--help)
      sed -n '2,9p' "$0"
      exit 0
      ;;
    *) err "unknown arg: $1" ;;
  esac
done

# Detect OS
case "$(uname -s)" in
  Darwin) OS="darwin" ;;
  Linux)  OS="linux"  ;;
  MINGW*|MSYS*|CYGWIN*) OS="windows" ;;
  *) err "unsupported OS: $(uname -s)" ;;
esac

# Detect arch
case "$(uname -m)" in
  arm64|aarch64) ARCH="aarch64" ;;
  x86_64|amd64)  ARCH="x86_64"  ;;
  *) err "unsupported arch: $(uname -m)" ;;
esac

# Map to Rust target triple
case "$OS-$ARCH" in
  darwin-aarch64)  TARGET="aarch64-apple-darwin" ;;
  linux-x86_64)    TARGET="x86_64-unknown-linux-gnu" ;;
  linux-aarch64)   TARGET="aarch64-unknown-linux-gnu" ;;
  windows-x86_64)  TARGET="x86_64-pc-windows-msvc" ;;
  *) err "no prebuilt binary for $OS-$ARCH (try cargo install --path bin/sleepwell-helper)" ;;
esac

EXT="tar.gz"
[ "$OS" = "windows" ] && EXT="zip"

# Resolve version
if [ -z "$VERSION" ]; then
  log "resolving latest bin-v* release"
  if command -v gh >/dev/null 2>&1; then
    VERSION="$(gh release list --repo "$REPO" --limit 30 --json tagName --jq '[.[] | select(.tagName | startswith("bin-v"))][0].tagName' 2>/dev/null || true)"
  fi
  if [ -z "$VERSION" ]; then
    # fallback to GitHub API without auth
    VERSION="$(curl -fsSL "https://api.github.com/repos/$REPO/releases" 2>/dev/null \
      | grep -oE '"tag_name":\s*"bin-v[^"]+"' | head -1 | sed -E 's/.*"(bin-v[^"]+)".*/\1/' || true)"
  fi
  [ -n "$VERSION" ] || err "could not resolve latest release. Pass --version <tag>."
fi

[[ "$VERSION" == bin-v* ]] || VERSION="bin-v${VERSION#v}"

ASSET="sleepwell-helper-${TARGET}.${EXT}"
URL="https://github.com/$REPO/releases/download/$VERSION/$ASSET"

# Skip if present and runnable
mkdir -p "$DEST"
BIN_NAME="sleepwell-helper"
[ "$OS" = "windows" ] && BIN_NAME="sleepwell-helper.exe"
INSTALLED="$DEST/$BIN_NAME"
if [ "$SKIP_IF_PRESENT" = "1" ] && [ -x "$INSTALLED" ]; then
  log "binary already present: $INSTALLED"
  exit 0
fi

log "downloading $ASSET ($VERSION) → $DEST"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if command -v curl >/dev/null 2>&1; then
  curl -fL --progress-bar "$URL" -o "$TMP/$ASSET" \
    || err "download failed: $URL"
elif command -v wget >/dev/null 2>&1; then
  wget -q --show-progress -O "$TMP/$ASSET" "$URL" \
    || err "download failed: $URL"
else
  err "neither curl nor wget found"
fi

# Extract
cd "$TMP"
if [ "$EXT" = "zip" ]; then
  command -v unzip >/dev/null 2>&1 || err "unzip not found"
  unzip -q "$ASSET"
else
  tar xzf "$ASSET"
fi

# Find the binary
SRC="$(find . -name "$BIN_NAME" -type f | head -1)"
[ -n "$SRC" ] || err "binary $BIN_NAME not found in archive"

install -m 0755 "$SRC" "$INSTALLED" 2>/dev/null || cp -f "$SRC" "$INSTALLED" && chmod +x "$INSTALLED"

# Verify
if "$INSTALLED" --version >/dev/null 2>&1; then
  log "installed: $INSTALLED"
  log "version: $($INSTALLED --version 2>/dev/null || echo unknown)"
else
  err "installed but failed to run: $INSTALLED"
fi

# Hint about PATH
case ":$PATH:" in
  *":$DEST:"*) ;;
  *) log "tip: add $DEST to PATH for direct invocation" ;;
esac
