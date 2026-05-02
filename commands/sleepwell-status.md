---
description: Shows the current state of the sleepwell loop — iteration, mode, branch, commits, failures, next scheduled wakeup.
---

# /sleepwell:sleepwell-status

Inspects `.sleepwell/state.json` (if present) and presents a readable snapshot of the loop.

## Behavior

1. Looks for `.sleepwell/state.json` in the cwd.
   - Not found → shows "no active sleepwell loop here. Use `/sleepwell:sleepwell \"<intent>\"` to start."
2. Reads the JSON and formats:

```
sleepwell — status
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
intent:   <state.intent>
mode:     <state.mode>
branch:   <state.branch>  (worktree: <path or "—">)
status:   <running|done|aborted|stopped>
iter:     <state.iteration> / <state.max_iter>
passes:   <state.total_passes>
fails:    <state.total_fails> (consecutive: <state.consecutive_failures>)
started:  <state.started_at>
last:     <state.last_iter_at>
stop-when: <state.stop_when or "—">

# Telemetry (if present in state.json — see sleepwell-telemetry skill).
cost:     <state.cost_so_far_usd> USD (budget: <state.cost_budget_usd or "—">)
tokens:   in=<state.tokens_used.input> out=<state.tokens_used.output>
          cache_read=<state.tokens_used.cache_read>
          cache_creation=<state.tokens_used.cache_creation>

# Calibration (if present — see sleepwell-meta skill v2).
overall:    <state.prediction_profile.overall * 100>% (n=<state.prediction_profile.n_runs>)
trusted:    <state.prediction_profile.trusted | join(", ") or "—">
distrusted: <state.prediction_profile.distrusted | join(", ") or "—">

last commits on the branch:
$(BASE=$(sleepwell_base_branch); git log --oneline -5 <state.branch> ^"$BASE" 2>/dev/null)
# `sleepwell_base_branch` detects main/master/develop — see lib/ritual.md §7.1.

last lines of notes.md:
$(tail -n 20 .sleepwell/notes.md 2>/dev/null)
```

3. If `status == "running"`, suggests:
   - `/sleepwell:sleepwell-stop` to stop.
   - `/sleepwell:sleepwell-diff` to view diff.
   - `/sleepwell:sleepwell-undo` to revert the last iter.

4. If `status != "running"`, shows final summary + commands to merge/discard.

## No side effects

`/sleepwell:sleepwell-status` is **read-only**. It does not modify state.json, does not create commits, does not trigger the loop.
