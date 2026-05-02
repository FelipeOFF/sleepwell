---
description: Stops the sleepwell loop. Marks state as "stopped" so future wakeups abort on the first check.
---

# /sleepwell:sleepwell-stop

Stops the loop. Destroys nothing — only sets the stop flag.

## Behavior

1. Reads `.sleepwell/state.json`. If absent → error: "no active loop".
2. If `status != "running"` → shows "loop is already in status <X>, nothing to do".
3. Updates `.sleepwell/state.json`:
   ```json
   {
     ...
     "status": "stopped",
     "stopped_at": "<ISO now>"
   }
   ```
4. Appends to `notes.md`:
   ```
   ## manual stop — <ISO>
   - user invoked /sleepwell:sleepwell-stop
   - next wakeup will abort on the 1st check
   ```
5. (Optional) tries to cancel scheduled wakeups — there is no direct cancel API, but `sleepwell-loop` on the next wake checks `status == "stopped"` and finishes.
6. Shows:
   ```
   sleepwell stopped.
   next automatic action: none.
   to resume: /sleepwell:sleepwell (no args, will detect state and ask)
   to finalize and merge: /sleepwell:sleepwell-diff && git checkout main && git merge --squash <branch>
   ```

## No destructive side effects

`sleepwell-stop` does not touch commits, does not change branch. It only marks the state. It is reversible: `/sleepwell:sleepwell` (no args) can resume.
