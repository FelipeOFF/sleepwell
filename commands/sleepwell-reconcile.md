---
description: Reconciles outcomes from previous runs (merged/partial/discarded) via git branch --merged.
---

# /sleepwell:sleepwell-reconcile

Retroactively marks the **outcome** of each archived sleepwell run by
inspecting whether the branch `sleepwell/<slug>` was actually integrated into the base.

Idempotent: can be run as many times as needed; only overwrites the
`outcome` field in the archived `state.json`.

## Outcomes

- **merged** — all commits of the branch appear in the base (fully
  integrated). Detected via `git branch --merged $(sleepwell_base_branch)`.
- **partial** — at least one commit was cherry-picked (but the branch as a
  whole is not merged). Detected via `git cherry <base> <branch>`: lines
  starting with `+` indicate commits NOT present in the base; lines with `-`
  indicate commits present (cherry-picked). `partial` when there is at least one
  `-` but not all.
- **discarded** — no commit absorbed (all `+` in `git cherry`, and
  branch is not in `--merged`).

## Behavior

1. Detects the base via the `lib/ritual.md §7.1` helper (`sleepwell_base_branch`).
2. Lists candidates:
   - local branches matching `sleepwell/*` (`git branch --list 'sleepwell/*'`);
   - subdirectories of `.sleepwell/archive/<run-id>/` that contain `state.json`.
3. For each archived run:
   - Reads `.sleepwell/archive/<run-id>/state.json` (fields `branch`, `mode`,
     `iteration`, `cost_so_far_usd`).
   - If the branch no longer exists locally:
     - No refs → `outcome = "discarded"` (no way to infer cherry-pick).
   - If the branch exists:
     - `git branch --merged "$BASE" | grep -qx "  $branch"` → `merged`.
     - Otherwise, `git cherry "$BASE" "$branch"`:
       - all lines start with `+` → `discarded`;
       - mix of `+` and `-` → `partial`;
       - all with `-` but branch is not in `--merged` (rare) → `partial`.
4. Atomically updates (`tmpfile + mv`) the archived `state.json` adding:
   ```json
   {
     "outcome": "merged|partial|discarded",
     "outcome_reconciled_at": "<ISO>"
   }
   ```
5. Prints markdown table:

```
| Branch                       | Category  | Outcome   | Iters | Cost     |
|------------------------------|-----------|-----------|-------|----------|
| sleepwell/extract-auth       | refine    | merged    | 12    | $0.84    |
| sleepwell/rewrite-pipeline   | radical   | partial   | 18    | $2.10    |
| sleepwell/cleanup-deps       | tidy      | discarded | 4     | $0.12    |
```

`Category` = `state.mode`. `Cost` = `state.cost_so_far_usd` formatted in
USD (2 decimals).

## Idempotency

- Runs read-only on git (no branch modifications).
- The only side-effect is rewriting the `outcome` field in archived JSON
  files (`.sleepwell/archive/<run-id>/state.json`). Overwriting with the
  same value is a semantic no-op.
- Can be invoked N times; each call recomputes based on the current
  git state.

## Edge cases

- `.sleepwell/archive/` missing → message: "no archived runs to
  reconcile."
- archived `state.json` corrupted → skips with warning, continues.
- Base branch not detectable (repo without main/master/develop) → explanatory
  error, abort.
- Run whose branch was deleted **and** rebase/squash erased the original SHAs
  → `discarded` (no anchor to infer cherry-pick).

## No destructive side effects

Never deletes branch, never runs `git gc`, never moves a file. Only
**reads git** and **writes the `outcome` field** to the archived JSON.

## Post-execution

Suggests:
```
to audit discarded runs:
  ls .sleepwell/archive/

to clean up already-merged branches:
  git branch --merged $(sleepwell_base_branch) | grep '^  sleepwell/' | xargs -r git branch -d
```
