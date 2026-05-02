---
description: Closes the active phase of the run, generates VERIFICATION.md, and archives.
argument-hint: "[--abandon]"
---

# /sleepwell-phase-complete

Closes the phase with `status == "active"`. Generates `VERIFICATION.md` checking
criteria from `PLAN.md` against the real state (phase commits, tests,
accumulated diff), updates `state.json`, and frees the slot for the next
phase.

See `lib/ritual.md §9`.

## Arguments

```
--abandon       marks the phase as abandoned instead of completed.
                Use when criteria were not met and you
                explicitly decide to close without verification.
```

## Prerequisites

- `.sleepwell/state.json` exists.
- Exactly one phase has `status == "active"`.

## Behavior (default mode — completed)

1. Reads active phase from `state.phases` (item with `status="active"`).
2. Reads phase's `PLAN.md` to extract acceptance criteria (list
   `- [ ] <text>`).
3. Collects evidence:
   - phase commits: `git log <started_at>..HEAD` filtered by the run's
     branch;
   - summary of `EXECUTION.md` (passes/fails);
   - accumulated diff: `git diff $(merge-base base started_at)..HEAD`.
4. Evaluates each criterion (short reasoning in the session):
   - marks `[x]` when there is clear evidence;
   - keeps `[ ]` when incomplete/ambiguous, with a note.
5. Generates `VERIFICATION.md`:
   ```markdown
   # Verification — phase <NN>-<slug>

   ## Criteria
   - [x] <criterion 1> — <evidence: short sha, file, or phrase>
   - [ ] <criterion 2> — <why not yet>

   ## Summary
   <2-3 sentences>

   ## Commits
   - <sha> <title>
   - ...

   ## Decision
   completed | partially-completed
   ```
6. Atomically updates `state.json`:
   - `status: "completed"`
   - `completed_at: "<ISO>"`
   - `verification_path: ".sleepwell/phases/<NN>-<slug>/VERIFICATION.md"`

## Behavior — `--abandon`

- Creates a minimal `VERIFICATION.md` marking "phase abandoned,
  criteria not verified".
- `state.phases[i].status = "abandoned"`, `completed_at` set.

## Output

```
phase <NN>-<slug> closed (completed | abandoned)
verification: .sleepwell/phases/<NN>-<slug>/VERIFICATION.md
criteria:     <X>/<Y> verified

next steps:
  /sleepwell-phase-start "<next>"      # start new phase
  /sleepwell-recap                      # close run
```

## Edge cases

- No active phase → "no active phase to close."
- More than one active phase (corruption) → error asking for manual
  fix to `state.json`.
- No markable criteria in `PLAN.md` → generates VERIFICATION.md with
  "no explicit criteria; status = completed by manual decision".
