---
description: Diagnoses the sleepwell environment, checks the sleepwell-helper binary, and (re)installs if necessary.
argument-hint: "[--reinstall] [--version <tag>] [--dest <dir>] [--restore-cache]"
---

# /sleepwell:sleepwell-doctor

Verifies the local environment and ensures the `sleepwell-helper` binary is
installed for the current platform.

## Steps

0. **Pre-check cache integrity**. Read
   `~/.claude/plugins/installed_plugins.json` and locate any
   `sleepwell@*` entry. For each entry verify that
   `<installPath>/.claude-plugin/plugin.json` exists and that
   `<installPath>/commands/` is non-empty. If either is missing or
   empty, the cache directory was wiped (typically by a Claude Code
   update or by a third-party tool that touches `~/.claude/plugins/`).
   Suggest re-running with `--restore-cache` (or invoking
   `bash scripts/restore-plugin-cache.sh` directly from a terminal).
1. **Detect platform** (OS + arch).
2. **Check `sleepwell-helper`** in order:
   - `$XDG_DATA_HOME/sleepwell/bin/sleepwell-helper` (Linux/macOS)
   - `~/.local/share/sleepwell/bin/sleepwell-helper`
   - `$LOCALAPPDATA/sleepwell/bin/sleepwell-helper.exe` (Windows)
   - `$PATH`
3. **If absent or `--reinstall` flag set**, runs `scripts/install-helper.sh`
   (Linux/macOS) or `scripts/install-helper.ps1` (Windows) downloading the
   binary from GitHub Releases (`FelipeOFF/sleepwell`).
4. **Smoke test**: runs `sleepwell-helper --version` and `sleepwell-helper --help`.
5. **Check external deps**: `git`, `gh` (optional), `jq` (optional for
   bash fallback).
6. **Report table** with each check and remediation hint.

## Args

- `--reinstall` — forces redownload even if binary is present.
- `--version <tag>` — installs a specific version (e.g.: `bin-v0.5.0`).
- `--dest <dir>` — alternative installation directory.
- `--restore-cache` — invokes `bash scripts/restore-plugin-cache.sh` to
  re-clone the plugin cache directory when it has been removed while
  `installed_plugins.json` still references it. Show the script output
  inline. After it completes, instruct the user to run
  `/reload-plugins` in Claude Code.

### Flag interaction: `--restore-cache` × `--reinstall`

The two flags address different artefacts and **can be combined**:

- `--restore-cache` recovers the **plugin cache directory** (skill markdown,
  commands, scripts) at `~/.claude/plugins/cache/...`. Without it the
  doctor itself may fail to reach helper scripts.
- `--reinstall` redownloads the **`sleepwell-helper` binary** under
  `~/.local/share/sleepwell/bin/` (or platform equivalent).

When both are passed, the doctor runs them in this fixed order:

1. `--restore-cache` runs **first**, before any other step, so subsequent
   logic (and any helper scripts the doctor itself loads) sees a healthy
   cache.
2. The normal pipeline then continues, and `--reinstall` re-downloads the
   helper binary on top of the now-restored cache.

Running `--reinstall` alone never touches the cache; running
`--restore-cache` alone never touches the helper binary.

## Output

```
Platform:           darwin / aarch64
cache:              ✓ valid (15 commands) at ~/.claude/plugins/cache/sleepwell/sleepwell/0.7.0
sleepwell-helper:   ✓ installed (v0.5.0) at ~/.local/share/sleepwell/bin/sleepwell-helper
git:                ✓ 2.45.1
gh:                 ✓ 2.45.0 (authenticated as user@example.com)
jq:                 ✓ 1.7
verify_cmds:        ⚠ partial — typecheck=auto, test=npm test, lint=missing
hooks:              ✓ block-push.sh, scope-guard.sh, ensure-helper.sh executable
state schema:       ✓ v3
```

When the cache is broken the line becomes:

```
cache:              ✗ broken — run /sleepwell:sleepwell-doctor --restore-cache
```

## Behavior by OS

- **macOS / Linux**: invokes `bash scripts/install-helper.sh --skip-if-present`.
- **Windows**: invokes `powershell -ExecutionPolicy Bypass -File scripts/install-helper.ps1 -SkipIfPresent`.

## When to use

- First time installing the plugin.
- After plugin upgrade (check whether there is a new binary).
- Before long runs (overnight) to ensure the environment.
- When some skill reports `sleepwell-helper not found`.

## Notes

- The `SessionStart` hook (`hooks/ensure-helper.sh`) already tries to install
  automatically in the background when a Claude Code session opens. This
  command is the explicit path when you want immediate feedback or
  forced reinstall.
- The download uses public GitHub Releases — does not require authentication.
- If no pre-built binary exists for your platform, the doctor
  suggests `cargo install --path bin/sleepwell-helper`.
