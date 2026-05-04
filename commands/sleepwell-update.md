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
- `--apply`: download the helper binary update automatically (via
  `scripts/install-helper.sh`) and **print to the user** the
  instruction to run `/plugin update sleepwell@sleepwell` followed by
  `/reload-plugins`. The plugin update itself is **not** executed by
  this command — only the helper binary download is automatic.
- `--plugin-only`: print plugin update guidance only.
- `--helper-only`: download/install helper binary only.

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
3. With `--apply`:
   - **Helper binary update is automatic**: invokes
     `bash scripts/install-helper.sh --version <tag>`.
   - **Plugin update is an instruction**: this command prints to the
     user the message to run `/plugin update sleepwell@sleepwell` and
     then `/reload-plugins` (or restart Claude Code) manually. Slash
     commands cannot invoke `/plugin update` from their body.

## Execution flow (for the agent)

1. Read `~/.cache/sleepwell/update.json`. If missing or older than
   `SLEEPWELL_UPDATE_TTL` seconds, run `bash hooks/check-update.sh`
   synchronously and re-read after ~3s.
2. Parse `plugin_update_available` and `helper_update_available`.
3. Print a status table (Component | Installed | Latest | Update?).
4. If `--apply` or `--helper-only` and helper update is available:
   - Run `bash scripts/install-helper.sh --version "$helper_latest"`.
   - Verify with `sleepwell-helper --version`.
5. If `--apply` or `--plugin-only` and plugin update is available:
   - **Print to user** (do not execute): "To complete the plugin
     update, run `/plugin update sleepwell@sleepwell` and then
     `/reload-plugins` (or restart Claude Code)."
6. If no updates: print "Up-to-date".

## Escape hatch

Set `SLEEPWELL_SKIP_UPDATE_CHECK=1` in your shell to disable the
SessionStart background check. Manual invocation via this command
still works.

To suppress helper-binary update notifications entirely (for users
who never want the optional helper installed):

```bash
mkdir -p ~/.config/sleepwell && touch ~/.config/sleepwell/no-helper
```

## Notes

- Cache TTL configurable via `SLEEPWELL_UPDATE_TTL` (seconds).
- Repo can be overridden via `SLEEPWELL_UPDATE_REPO=<owner>/<name>`;
  otherwise it is parsed from `.claude-plugin/plugin.json` `.repository`.
- The helper download uses the same flow as the bootstrap install
  (GitHub Releases for `bin-v*` tags, platform auto-detection).
- Plugin updates require Claude Code to reload plugins
  (`/reload-plugins` or restart) — this command will not do it for you.
