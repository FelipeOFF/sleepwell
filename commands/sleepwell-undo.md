---
description: Reverts the last successful iteration of the sleepwell loop (git reset --hard HEAD~1 on the sleepwell branch).
argument-hint: [--n N] [--keep-changes]
---

# /sleepwell:sleepwell-undo

Reverts the last successful iteration of the sleepwell branch.

## Arguments

- `--n N` — reverts the last N iterations (default: 1).
- `--keep-changes` — uses `git reset --soft` (keeps changes staged) instead of `--hard`.

## Behavior

1. Reads `.sleepwell/state.json`. If absent → error.
2. Confirms with the user via AskUserQuestion (showing the commits to be discarded):
   ```
   I'll revert the last N commits on branch <state.branch>:
   - <sha> <msg>
   - <sha> <msg>

   ⚠️  This is destructive (--hard). Continue?
   [confirm / cancel]
   ```
3. If confirmed:
   - Verifies that the current branch is `state.branch`. If not → checkout to it first.
   - `git reset --hard HEAD~N` (or `--soft` with `--keep-changes`).
   - Decrements `state.iteration` and `state.total_passes` in `.sleepwell/state.json`.
   - Appends to `notes.md`:
     ```
     ## manual undo — <ISO>
     - reverted N commits via /sleepwell:sleepwell-undo
     - new HEAD: <sha>
     ```
4. Shows post-undo state (calls `/sleepwell:sleepwell-status` logic at the end).

## Safeguards

- **Never** runs on main/master/develop — aborts with an error.
- **Never** discards commits that have already been pushed. Before the `git log @{u}..` check, validate upstream — without configured upstream, skips the check (does not block undo):
  ```bash
  if git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
    pushed=$(git log @{u}..)
    # if there are pushed commits in the range to be reverted → abort with error
  fi
  # without upstream → local branch; undo is safe. See lib/ritual.md §7.3.
  ```
- If the loop is in `status == "running"`, also suggests `/sleepwell:sleepwell-stop` before undo (to avoid conflicting with the next wakeup).
