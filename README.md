# sleepwell

> **Languages:** [English](README.md) · [Português (Brasil)](README.pt-BR.md)

Autonomous overnight loop for Claude Code. Disciplined iteration (isolated branch, atomic commit per iteration, automatic rollback on failure) combined with adaptive behavior (4 operating modes, optional voice matching, cross-run meta-learning).

Unlike external `claude -p` wrappers, sleepwell runs **inside** an active Claude Code session — keeping the prompt cache hot, MCP servers alive, and skills composable across iterations.

Language- and stack-agnostic: works with any project where lint, type-check, and tests can be invoked from the shell. Verify commands are auto-detected (Node, Python, Go, Rust, Ruby, .NET, Java, etc.) or set explicitly.

## Highlights

- **Hot prompt cache** between iterations (5-min TTL) — no cold start per loop.
- **Live MCP servers** persist across iterations.
- **Composable** with any Claude Code skill or plugin you have installed.
- **Standalone by design** — the core ritual works without external skills. See [`docs/SKILLS.md`](docs/SKILLS.md).
- **Safety first** — isolated branch, no `--no-verify`, no force-push, scope-guard hook blocks edits outside the worktree, push-guard hook blocks accidental `git push` while a loop is running.

## Install

Inside Claude Code, register the repo as a marketplace and install:

```
/plugin marketplace add FelipeOFF/sleepwell
/plugin install sleepwell@sleepwell
```

Or clone and symlink into your Claude Code plugins directory:

```bash
git clone https://github.com/FelipeOFF/sleepwell.git
ln -s "$(pwd)/sleepwell" ~/.claude/plugins/sleepwell
```

Restart Claude Code. The `/sleepwell:*` commands appear.

> **Note on namespacing.** Claude Code namespaces every plugin command
> under the plugin name. So the start command is `/sleepwell:sleepwell`,
> the status command is `/sleepwell:sleepwell-status`, etc. The bare
> `/sleepwell` (no colon) will return *Unknown command*. Use the
> namespaced form everywhere.

### Helper binary (auto-install)

The plugin uses a small Rust helper (`sleepwell-helper`) for fast JSONL
parsing, multi-LLM cost calculation, hashing, file watching, and
calibration. On first session a `SessionStart` hook
(`hooks/ensure-helper.sh`) downloads the right prebuilt binary for your
platform from GitHub Releases and installs it under
`~/.local/share/sleepwell/bin/` (or `%LOCALAPPDATA%\sleepwell\bin\` on
Windows). Already-installed binaries are kept; re-runs are a no-op.

Manual control:

```
/sleepwell:sleepwell-doctor                       # diagnose env + install if missing
/sleepwell:sleepwell-doctor --reinstall           # force redownload latest
/sleepwell:sleepwell-doctor --version bin-v0.5.0  # pin a specific version
```

Supported prebuilt targets:

| OS | Arch | Target |
|---|---|---|
| macOS | aarch64 (Apple Silicon) | `aarch64-apple-darwin` |
| Linux | x86_64 | `x86_64-unknown-linux-gnu` |
| Linux | aarch64 | `aarch64-unknown-linux-gnu` |
| Windows | x86_64 | `x86_64-pc-windows-msvc` |

If your platform isn't covered, build locally:

```bash
cargo install --path bin/sleepwell-helper
```

The helper is **optional** — every skill has a `bash`/`jq` fallback. Its
absence only reduces precision (cost telemetry, calibration), it does
not break the loop.

## Quick start

```
/sleepwell:sleepwell "extract auth middleware into its own module" --mode refine --max-iter 15
```

| Command | Purpose |
|---|---|
| `/sleepwell:sleepwell "<intent>" [opts]` | Start the loop |
| `/sleepwell:sleepwell-status` | Current iteration, branch, mode, recent commits, cost |
| `/sleepwell:sleepwell-diff` | Accumulated diff vs base branch |
| `/sleepwell:sleepwell-resume` | Resume a paused, stopped, or crashed loop |
| `/sleepwell:sleepwell-watch` | Live TUI of loop progress |
| `/sleepwell:sleepwell-recap` | Post-run narrative summary |
| `/sleepwell:sleepwell-undo` | Revert the last successful iteration |
| `/sleepwell:sleepwell-stop` | Cancel pending wakeups |

## Modes

| Mode | When to use | Behavior |
|---|---|---|
| `tidy` | Cleanup, dependencies, formatting | Mechanical changes, no behavior change |
| `refine` (default) | Incremental improvement, refactor | Refactor while keeping tests green |
| `build` | New feature end-to-end | Tests-first, ramp to working feature |
| `radical` | Subsystem rewrites | Allows breaking and rebuilding; higher risk |
| `wave` | Multi-agent collaboration (experimental) | Propose → critique → consolidate per iteration |

## Options

```
/sleepwell:sleepwell "<intent>"
  --mode tidy|refine|build|radical|wave   (default: refine)
  --max-iter <N>                          (default: 20)
  --max-cost <USD>                        (abort when total cost exceeds budget)
  --max-cost-per-iter <USD>               (per-iteration cap)
  --stop-when "<NL condition>"            (evaluated after each iter)
  --intent-file <path>                    (long intent from file)
  --no-worktree                           (default: uses git worktree)
  --dry-run                               (no commits; show diff)
  --no-voice                              (skip voice profile extraction)
  --no-meta                               (skip meta-learning calibration)
```

## Iteration anatomy

1. **Load state** from `.sleepwell/state.json`.
2. **Abort checks** — max-iter, max-cost, stop-when, ≥3 consecutive failures.
3. **Bootstrap** (first iteration only) — create `sleepwell/<slug>` branch, optional worktree, voice profile, prior calibration.
4. **Compose prompt** — intent + mode + voice + recent notes + last diff + calibration.
5. **Execute** — Claude reasons and edits files.
6. **Verify** — lint + type-check + tests (auto-detected or set in `verify_cmds`).
7. **Decision** — Pass: atomic commit + log. Fail: `git reset --hard HEAD && git clean -fd`, increment failure counter, exponential backoff.
8. **Telemetry** — accumulate token usage and cost.
9. **Schedule next** — `ScheduleWakeup(60-270s)` keeps the cache warm and relaunches the loop.

## State

```
.sleepwell/
├── state.json          # iteration, branch, mode, status, cost, tokens
├── notes.md            # appended log per iteration
├── voice-profile.md    # cached voice matching summary
├── calibration.md      # cross-run meta-learning insights
└── archive/            # previous runs
```

Add `.sleepwell/` to your project `.gitignore`.

## Verify commands

Set per project (in `state.json` or via flags). Each accepts a shell command or the literal `"auto"`:

```json
{
  "verify_cmds": {
    "lint": "auto",
    "typecheck": "auto",
    "test": "npm test"
  }
}
```

`auto` detects common toolchains: `eslint`, `ruff`, `golangci-lint`, `cargo clippy`, `rubocop`, `dotnet format`, etc.

## Cost telemetry

Detects the active runtime (Claude Code or Codex CLI), parses session JSONL, accumulates `input/output/cache_read/cache_creation` tokens per iteration, derives USD cost from a price table, and enforces the `--max-cost` budget. See [`skills/sleepwell-telemetry/SKILL.md`](skills/sleepwell-telemetry/SKILL.md).

## Safety

- Never runs on `main`/`master`/`develop` — always isolates in a `sleepwell/<slug>` branch.
- Never uses `--no-verify` or `--force-push`.
- ≥3 consecutive failures → automatic abort.
- `PreToolUse` hooks block `git push` and out-of-worktree edits during an active loop.
- `--dry-run` previews without committing.

## Troubleshooting

Common scenarios (corrupted state, orphaned worktree, runaway cost, stale voice cache, blocked push) are documented in [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) with **Symptoms / Diagnosis / Remediation**.

## Phases (internal)

A run can be broken into **internal sub-phases** living under
`.sleepwell/phases/<NN>-<slug>/`. Each phase has its own `PLAN.md`,
`EXECUTION.md`, and `VERIFICATION.md`. Tracked via `state.phases` in
`state.json`. Phases are optional — runs without phases work exactly
as before.

```
/sleepwell:sleepwell-phase-start "<slug>"          # opens a new phase (only one active at a time)
/sleepwell:sleepwell-phase-complete [--abandon]    # closes the active phase, generating VERIFICATION.md
```

When a phase is active, the loop injects its `PLAN.md` and recent
`EXECUTION.md` into each iteration prompt and evaluates acceptance
criteria after every iter. See [`lib/ritual.md` §9](lib/ritual.md).

## PR-only flow

Sleepwell runs always work on a disposable branch named
`sleepwell/auto/<run-id>` (where `run-id = <unix-epoch>-<rand4hex>`). The
human-readable slug derived from the intent is preserved separately in
`state.slug`. This guarantees branch uniqueness across parallel runs and
keeps the branch namespace tidy.

When a run finishes (`status == done`), the loop invokes
`/sleepwell:sleepwell-pr` automatically and persists the resulting PR URL into
`state.pr_url`. The PR body includes intent, mode, iteration counts,
cost in USD, latest evaluator rating, and the commit list.

```bash
/sleepwell:sleepwell "<intent>"             # default: creates PR on finish
/sleepwell:sleepwell "<intent>" --no-pr     # runs but does not create PR
/sleepwell:sleepwell "<intent>" --draft-pr  # creates PR as draft
```

Auto-merge is **disabled by default**. To enable conditional auto-merge,
manually apply the label `sleepwell-auto-merge` on the PR — a
server-side GitHub Action (not shipped with this plugin) is expected to
consume the label and run `gh pr merge --auto` once CI passes. The
plugin only documents the convention.

## Compatibility

- Claude Code (primary target).
- Codex CLI (telemetry support; loop execution may require adapter — see roadmap).
- Any language with a CLI test runner.

## Related projects

- [anthropics/claude-code](https://github.com/anthropics/claude-code) — official Claude Code CLI.
- Claude Code skill marketplaces and plugin registries — sleepwell composes with any well-formed skill or MCP server you install.

Inspired by prior overnight-agent work in the community: branch-isolated loops with atomic commits, mode-based prompting, and voice/meta adaptation.

## Architecture Decisions

See [`docs/adr/`](docs/adr/) for architecture decision records (ADRs).
Start with [ADR-001: PR-only flow e CI awareness](docs/adr/001-pr-only-ci-awareness.md).

## Contributing

Issues and pull requests welcome. The loop, schema, and ritual are documented in [`lib/ritual.md`](lib/ritual.md) (the authoritative source). Run `scripts/check-skill-deps.sh` to audit external skill references before opening a PR.

## Credits — see [NOTICE.md](NOTICE.md) and [CREDITS.md](CREDITS.md).

## License

MIT
