---
description: Shows the accumulated diff of the sleepwell branch against the base (main by default).
argument-hint: [--base <branch>] [--stat]
---

# /sleepwell:sleepwell-diff

Shows what the sleepwell loop has produced so far.

## Behavior

1. Reads `.sleepwell/state.json` to discover `branch`. If absent → error: "no sleepwell loop here".
2. Determines base:
   - `--base <branch>` if passed.
   - Otherwise uses the `sleepwell_base_branch` helper (detects `main` / `master` / `develop` in order; see `lib/ritual.md §7.1`).
3. Runs:
   ```bash
   # commit count
   git log --oneline <base>..<state.branch>

   # full diff OR just stat
   git diff <base>...<state.branch>           # default
   git diff --stat <base>...<state.branch>    # if --stat
   ```
4. Shows:
   - List of commits on the branch (with `[sleepwell-iter:N]`).
   - Summary stat always (changed files / +N -M).
   - Full diff if `--stat` was not requested.

## No side effects

Read-only. Does not modify anything. Can run while the loop is active (does not interfere with `ScheduleWakeup`).
