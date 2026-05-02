---
description: Live TUI showing the status of an in-progress sleepwell loop.
argument-hint: "[--interval 3] [--tail 15]"
---

# /sleepwell:sleepwell-watch

Shows a live TUI dashboard with the state of the sleepwell loop. Blocks the
terminal until `Ctrl+C`. Read-only — does not change `state.json` nor trigger the skill.

## Arguments

```
--interval <seconds>    interval between refreshes (default: 3)
--tail <N>              final lines of notes.md to show (default: 15)
```

## What it shows

On each refresh:

- summary line: `iter X/Y  pass=P fail=F  status=<S>  cost=$<USD>`
- separator
- last N lines of `.sleepwell/notes.md`
- separator
- last 5 commits of the branch (`git log --oneline <branch>`)

## Implementation

Spawns a blocking Bash. Uses `watch(1)` if available; otherwise falls back to `while
true`. Handles missing state without crashing.

```bash
INTERVAL=${1:-3}
TAIL=${2:-15}

if command -v watch >/dev/null; then
  watch -n "$INTERVAL" -c bash -c '
    [ -f .sleepwell/state.json ] || { echo "no active loop"; exit 0; }
    jq -r "\"iter \(.iteration)/\(.max_iter)  pass=\(.total_passes) fail=\(.total_fails)  status=\(.status)  cost=\$\(.cost_so_far_usd // 0)\"" .sleepwell/state.json
    echo "---"
    tail -n '"$TAIL"' .sleepwell/notes.md 2>/dev/null
    echo "---"
    B=$(jq -r .branch .sleepwell/state.json)
    git log --oneline "$B" 2>/dev/null | head -5
  '
else
  while true; do
    clear
    if [ ! -f .sleepwell/state.json ]; then
      echo "no active loop"
    else
      jq -r '"iter \(.iteration)/\(.max_iter)  pass=\(.total_passes) fail=\(.total_fails)  status=\(.status)  cost=$\(.cost_so_far_usd // 0)"' .sleepwell/state.json
      echo "---"
      tail -n "$TAIL" .sleepwell/notes.md 2>/dev/null
      echo "---"
      B=$(jq -r .branch .sleepwell/state.json)
      git log --oneline "$B" 2>/dev/null | head -5
    fi
    sleep "$INTERVAL"
  done
fi
```

## Exit

`Ctrl+C` exits. Since the command is read-only, exiting at any time is
safe — it does not leave the loop in an inconsistent state.

## Edge cases

- `.sleepwell/state.json` missing → shows "no active loop" (does not fail).
- `notes.md` missing → silent tail (no stderr).
- `jq` not installed → recommend installing it; `watch` uses `jq` to format.
- sleepwell branch removed (after merge) → `git log` returns empty, does not
  break the refresh.

## When to use

- Track an overnight loop in another terminal/tab.
- Confirm progress without running `/sleepwell:sleepwell-status` repeatedly.
- Detect hangs: if `iter` doesn't change across several refreshes and `status =
  running`, consider `/sleepwell:sleepwell-resume`.
