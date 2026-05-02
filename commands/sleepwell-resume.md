---
description: Resumes a paused/aborted/crashed sleepwell loop.
argument-hint: "[--force] [--from-iter N]"
---

# /sleepwell:sleepwell-resume

Resumes an existing loop in any terminal state (`stopped`, `aborted`,
orphaned `running` after crash) without restarting from scratch. Reuses the
`sleepwell-loop` skill — does not create a parallel flow.

> See `lib/ritual.md` §2 (bootstrap) and §3 (iteration). This entrypoint only
> normalizes `state.json` and calls the skill at the right point.

## Arguments

```
--force                  skips AskUserQuestion in ambiguous cases (assumes safe default)
--from-iter <N>          forces re-entry at iteration N (rare; default keeps state.iteration)
```

## Preconditions

1. `.sleepwell/state.json` must exist. If it does not → error:
   "no sleepwell loop found here. Use `/sleepwell:sleepwell \"<intent>\"`."
2. Creates lock `.sleepwell/resume.lock` with `{ "ts": "<ISO>", "pid": <pid> }`
   before relaunching the skill. If the lock already exists and is recent (<5min),
   aborts with a warning ("possible orphaned wakeup; remove the lock manually if
   you know there is no other active loop"). The lock is removed by
   `sleepwell-loop` when starting the next iteration.

## Behavior by `state.status`

### `running` (mid-iter crash)
1. Assumes a crash between the iter's `started_at` and the final commit.
2. Runs `git status -s` in the worktree (or repo root if `worktree_enabled=false`).
3. If dirty → `AskUserQuestion`:
   - **rollback** → `git checkout -- .` + `git clean -fd`, decrements nothing (the iter
     had not incremented yet), and dispatches the skill at the current iter.
   - **preserve WIP** → does `git stash push -m "sleepwell-resume-wip <ISO>"`,
     records the stash in `notes.md`, and dispatches the skill.
   - **abort** → sets `status: aborted`, `abort_reason: "mid-iter crash, user aborted"`.
4. If `--force`, silently picks **rollback**.
5. Reuses `sleepwell-loop` at the **current iter without incrementing** (`iteration` stays
   as is; the skill detects resume via lock + status).

### `stopped`
1. Reverts `status` to `running`, clears `stopped_at`.
2. Appends to `notes.md`:
   ```
   ## manual resume — <ISO>
   - state reverted from "stopped" to "running"
   - next wakeup in 60s
   ```
3. Triggers `ScheduleWakeup(60s)` reusing `sleepwell-loop`.
4. Finishes (the next iter runs on the wakeup).

### `aborted`
1. Likely `consecutive_failures >= 3`. AskUserQuestion:
   - **reset counter and resume** → `consecutive_failures = 0`, `status = running`,
     records in `notes.md`, triggers `ScheduleWakeup(60s)`.
   - **inspect first** → changes nothing, suggests `/sleepwell:sleepwell-status` and `/sleepwell:sleepwell-diff`.
2. If `--force`, picks **reset and resume**.
3. If `abort_reason` indicates `cost_budget_usd` exceeded → refuses to reset the counter
   and instructs the user to relaunch with a higher `--max-cost` via a new `/sleepwell:sleepwell`.

### `done`
Error: "loop already concluded. To start another intent, use
`/sleepwell:sleepwell \"<new intent>\"` (old state will be archived)."

## `--from-iter N`
Advanced override. Sets `state.iteration = N-1` before relaunching the skill (the
skill increments to N on the next iter). Useful to repeat an iter that
passed but felt wrong. Records the override in `notes.md`.

## Anti-orphan lock

Before any `ScheduleWakeup` or direct skill invocation:

```
.sleepwell/resume.lock = { "ts": "<ISO>", "pid": <process-pid-approx> }
```

The `sleepwell-loop` skill must read this lock at boot, compare with its own
context, and remove it when starting the iter. Wakeups dispatched before `/resume`
see `status != running` and abort without work.

## Examples

```
/sleepwell:sleepwell-resume                    # common case: detects state and acts
/sleepwell:sleepwell-resume --force            # without asking, picks safe defaults
/sleepwell:sleepwell-resume --from-iter 5      # re-enters at iter 5
```
