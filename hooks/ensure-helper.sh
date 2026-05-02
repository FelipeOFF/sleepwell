#!/usr/bin/env bash
# SessionStart hook: ensure sleepwell-helper binary is installed for the
# current platform. Best-effort — never blocks the session, never errors out.
# Runs install-helper.sh with --skip-if-present --quiet so it's a no-op
# after the first session.
set -u

# Resolve plugin root (this hook lives at <root>/hooks/ensure-helper.sh)
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(dirname "$HERE")"

INSTALL_SH="$ROOT/scripts/install-helper.sh"
[ -x "$INSTALL_SH" ] || [ -f "$INSTALL_SH" ] || exit 0

# Run install in skip-if-present mode; swallow all output. Don't block.
(
  bash "$INSTALL_SH" --skip-if-present --quiet
) >/dev/null 2>&1 &

# Detach. SessionStart should not delay startup.
disown 2>/dev/null || true
exit 0
