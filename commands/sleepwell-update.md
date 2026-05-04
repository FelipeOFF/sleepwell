---
description: Check for and apply available plugin and helper binary updates from GitHub Releases.
argument-hint: "[--check] [--apply] [--helper-only] [--plugin-only]"
---

# /sleepwell:sleepwell-update

Detects newer SleepWell plugin and helper binary releases on GitHub
and offers to apply them. Reads cached state from
`~/.cache/sleepwell/update.json` (refreshed at most every 24h by the
SessionStart `check-update.sh` hook).

## Behavior

- `--check` (default if no arg): print what is available without
  applying.
- `--apply`: apply both plugin update (instructs `/plugin update sleepwell@sleepwell`)
  and helper binary update (re-runs `scripts/install-helper.sh`).
- `--plugin-only`: only the plugin update guidance.
- `--helper-only`: only the helper binary download.

## Output (example, --check)

| Component | Installed | Latest | Update? |
|---|---|---|---|
| sleepwell plugin | v0.6.1 | v0.7.0 | yes — run /plugin update sleepwell@sleepwell |
| sleepwell-helper | bin-v0.6.0 | bin-v0.6.1 | yes — run with --apply or --helper-only |

If no updates, prints "Up-to-date" with both versions.

## How it works

1. Reads cached `~/.cache/sleepwell/update.json` written by the
   SessionStart `check-update.sh` hook (refreshed every 24h).
2. If cache is missing or stale, refreshes inline (synchronous, ~2s).
3. For `--apply`: helper update is automatic via
   `scripts/install-helper.sh --version <tag>`. Plugin update is shown
   as instruction since `/plugin update` cannot be invoked from a slash
   command body.

## Escape hatch

Set `SLEEPWELL_SKIP_UPDATE_CHECK=1` in your shell to disable the
SessionStart background check. Manual invocation via this command
still works.

## Notes

- Cache TTL configurable via `SLEEPWELL_UPDATE_TTL` (seconds).
- The helper download uses the same flow as the bootstrap install
  (GitHub Releases for `bin-v*` tags, platform auto-detection).
- Plugin updates require Claude Code to reload plugins
  (`/reload-plugins` or restart).
