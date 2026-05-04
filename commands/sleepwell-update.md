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
- `--apply`: install **both** the helper binary AND the plugin cache
  automatically. After applying, the user only has to run
  `/reload-plugins` (or restart Claude Code) for the new commands and
  skills to be picked up — Claude Code does not expose a tool that
  can run `/reload-plugins` from a command body.
- `--plugin-only`: install plugin cache only (no helper change).
- `--helper-only`: install helper binary only (no plugin change).

## Output (example, --check)

| Component | Installed | Latest | Update? |
|---|---|---|---|
| sleepwell plugin | 0.7.0 | v0.7.3 | yes — run with --apply or --plugin-only |
| sleepwell-helper | bin-v0.6.0 | bin-v0.7.3 | yes — run with --apply or --helper-only |

If no updates, prints "Up-to-date" with both versions.

## How it works

1. Reads cached `~/.cache/sleepwell/update.json` written by the
   SessionStart `check-update.sh` hook (refreshed every 24h).
2. If cache is missing or stale, refreshes inline (synchronous, ~2s).
3. With `--apply`:
   - **Helper binary** → `bash $CLAUDE_PLUGIN_ROOT/scripts/install-helper.sh --version <tag>`
   - **Plugin cache** → `bash $CLAUDE_PLUGIN_ROOT/scripts/update-plugin-cache.sh --version <tag>`
     - Clones the new release into `~/.claude/plugins/cache/sleepwell/sleepwell/<X.Y.Z>`,
       atomically rewrites `installed_plugins.json` to point to it, and
       prunes older sibling cache directories (keeps `.broken.*`
       backups intact).
   - **Final step** is reload — the command prints the reminder to
     run `/reload-plugins` (or restart Claude Code).

## Execution flow (for the agent)

1. Read `~/.cache/sleepwell/update.json`. If missing or older than
   `SLEEPWELL_UPDATE_TTL` seconds, run
   `bash $CLAUDE_PLUGIN_ROOT/hooks/check-update.sh` synchronously and
   re-read after ~3s.
2. Parse `plugin_update_available` and `helper_update_available`.
3. Print a status table (Component | Installed | Latest | Update?).
4. If `--apply` or `--helper-only` and helper update is available:
   - Run `bash $CLAUDE_PLUGIN_ROOT/scripts/install-helper.sh --version "$helper_latest"`.
   - Verify with `sleepwell-helper --version`.
5. If `--apply` or `--plugin-only` and plugin update is available:
   - Run `bash $CLAUDE_PLUGIN_ROOT/scripts/update-plugin-cache.sh --version "$plugin_latest"`.
   - Print: "Plugin cache updated to <ver>. Run `/reload-plugins` (or
     restart Claude Code) to load the new commands and skills."
6. If no updates: print "Up-to-date".

> **Note on `${CLAUDE_PLUGIN_ROOT}`:** Claude Code injects this env
> var into command/hook execution contexts. When the agent runs the
> scripts, prefer the env-var path — falls back to discovery via
> `installed_plugins.json` if unset.

## Escape hatch

Set `SLEEPWELL_SKIP_UPDATE_CHECK=1` in your shell to disable the
SessionStart background check. Manual invocation via this command
still works.

To suppress helper-binary update notifications entirely (for users
who never want the optional helper installed):

```bash
mkdir -p ~/.config/sleepwell && touch ~/.config/sleepwell/no-helper
```

To roll back a plugin upgrade after `--apply`, reuse the recovery
flow:

```bash
bash $CLAUDE_PLUGIN_ROOT/scripts/update-plugin-cache.sh --version v<previous>
```

## Notes

- Cache TTL configurable via `SLEEPWELL_UPDATE_TTL` (seconds).
- Repo can be overridden via `SLEEPWELL_UPDATE_REPO=<owner>/<name>`
  (or `SLEEPWELL_REPO=<owner>/<name>` for the install/update scripts);
  otherwise it is parsed from `.claude-plugin/plugin.json` `.repository`
  or inferred from the `installed_plugins.json` key.
- The helper download uses the same flow as the bootstrap install
  (GitHub Releases for `bin-v*` tags, platform auto-detection).
- Plugin updates still require `/reload-plugins` (or a Claude Code
  restart) — `/plugin` slash commands cannot be triggered from inside
  another command body.
