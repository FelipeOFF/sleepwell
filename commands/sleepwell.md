---
description: Starts (or resumes) the autonomous sleepwell loop. Combines gnhf discipline (isolated branch, atomic commit, rollback on fail) with overnight adaptation (voice matching, modes, meta-learning). Runs inside the CC session with a warm cache between iterations.
argument-hint: "<intent>" [--mode tidy|refine|build|radical] [--max-iter N] [--max-cost USD] [--max-cost-per-iter USD] [--stop-when "<condition>"] [--dry-run] [--no-worktree] [--no-voice] [--no-meta] [--intent-file <path>] [--no-pr] [--draft-pr]
---

# /sleepwell:sleepwell

Starts or resumes the autonomous loop. Use the `sleepwell-loop` skill as the entrypoint — it bootstraps state, creates the isolated branch, extracts the voice profile, reads calibration, and runs the first iteration.

> **Canonical flow:** see `lib/ritual.md` §2 (bootstrap) and §3 (iteration). This file only covers CLI args and dispatching to the skill — no duplicated steps.

## Parsed arguments

```
<intent>                              first quoted string — required at bootstrap
--intent-file <path>                  optional, alternative for long intent (reads file)
--mode tidy|refine|build|radical      default: refine
--max-iter <N>                        default: 20
--max-cost <USD>                      optional, total max budget in USD (abort gate)
--max-cost-per-iter <USD>             optional, per-iter guardrail (an iter that exceeds aborts as FAIL and enters backoff; does not count as a total abort — see lib/ritual.md §8.1)
--stop-when "<NL condition>"          optional
--dry-run                             optional (does not commit)
--no-worktree                         optional (default: uses worktree)
--no-voice                            optional
--no-meta                             optional
--no-pr                               optional (default: creates PR at end of run)
--draft-pr                            optional (creates PR as draft)
```

> **PR-only flow:** at the end of a run with `status == done`, the loop invokes
> `/sleepwell:sleepwell-pr` automatically (unless `--no-pr` was passed).
> Auto-merge is disabled by default. See `commands/sleepwell:sleepwell-pr.md`.

All flags are **persisted in `state.json`** at bootstrap (`worktree_enabled`,
`no_voice`, `no_meta`, `intent_file`, `cost_budget_usd`,
`max_cost_per_iter_usd`) — so resumes via
`ScheduleWakeup` preserve the chosen setup. See `lib/state-schema.json` (v2)
and `lib/ritual.md §8`.

## Behavior

1. If `.sleepwell/state.json` **does not exist** and there is `<intent>` → full bootstrap.
2. If `.sleepwell/state.json` **exists** and `status == "running"` → resumes from where it stopped (relaunches the `sleepwell-loop` skill).
3. If `.sleepwell/state.json` **exists** and `status == "done"|"aborted"|"stopped"`:
   - If `<intent>` was passed → fresh bootstrap (moves old state to `.sleepwell/archive/<timestamp>/`).
   - Otherwise → shows final status and suggests `/sleepwell:sleepwell-status`/`/sleepwell:sleepwell-diff`.

## Validations before bootstrapping

- Is the repo a git repo? If not → error: "sleepwell requires git. Run `git init`."
- Is current branch `main`/`master`/`develop`? OK — we'll create a new branch.
- Working tree clean? If not → AskUserQuestion: auto stash? abort?

## Invocation

Now invoke the `sleepwell-loop` skill with the input `${ARGUMENTS}`.

The skill takes care of:
- Argument parsing
- Bootstrap (if applicable)
- Iteration execution
- ScheduleWakeup for the next iteration

Do not perform work outside it — only dispatching here.
