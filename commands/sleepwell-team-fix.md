---
description: Multi-agent coordinated workflow — implement, open PR, dispatch reviewer + fixer agents, wait CI, merge, optional post-merge actions.
argument-hint: "<intent> [--mode <m>] [--max-iter <N>] [--no-review] [--no-fix] [--max-review-rounds <N>] [--ci-timeout <minutes>] [--no-merge] [--post-merge <action>] [--config <path>]"
---

# /sleepwell:sleepwell-team-fix

Coordinates a **team of agents** end-to-end: an Implementer runs the standard
sleepwell loop, a Reviewer inspects the resulting PR with line-level comments,
a Fixer applies the requested changes, a CI-Watcher waits for green, and an
optional Post-Merge step ships the change forward (release, downstream
dispatch, custom command, or no-op).

> **Canonical flow:** see `lib/team-workflow.md`. This file only covers CLI
> args and dispatching to the `sleepwell-team` skill — no duplicated logic.

## Parsed arguments

```
<intent>                              first quoted string — required
--mode tidy|refine|build|radical      forwarded to sleepwell-loop (default: refine)
--max-iter <N>                        forwarded to sleepwell-loop (default: 20)
--no-review                           skip the reviewer phase entirely
--no-fix                              run reviewer but skip fixer (only annotate the PR)
--max-review-rounds <N>               max reviewer→fixer rounds (default: 2)
--ci-timeout <minutes>                max minutes waiting for CI (default: 30)
--no-merge                            stop after CI is green; do not merge
--post-merge none|release|<custom>    post-merge action (default: from config)
--config <path>                       alternative path for team.config.yaml
```

All flags override values from `.sleepwell/team.config.yaml` (or the file
provided via `--config`). When neither flag nor config define a value, the
defaults shipped in `team.config.example.yaml` apply.

## Behavior

1. Validate args; load `.sleepwell/team.config.yaml` (or `--config`).
2. Persist the resolved configuration into `.sleepwell/team-state.json`
   (`run_id`, `intent`, `mode`, `max_review_rounds`, `ci_timeout_minutes`,
   `post_merge_action`, `current_round = 0`, `phase = "implement"`).
3. Invoke the `sleepwell-team` skill with the parsed arguments. The skill
   coordinates each phase, calling other sleepwell skills/commands as
   building blocks (`sleepwell-loop`, `sleepwell-pr`) and using
   `gh` for review threads, replies and CI polling.

## Validations before dispatch

- Repo is git? (else error: "sleepwell-team-fix requires git.")
- `gh` CLI authenticated? (else error: "Run `gh auth login`.")
- `.sleepwell/state.json` does not point to a different running loop —
  if it does, refuse and suggest `/sleepwell:sleepwell-status`.

## Invocation

Now invoke the `sleepwell-team` skill with the input `${ARGUMENTS}`.

The skill takes care of:

- Argument and config parsing
- Implementer phase (delegates to `sleepwell-loop`)
- PR creation (delegates to `/sleepwell:sleepwell-pr`)
- Reviewer + Fixer rounds (line-level comments via `gh api`)
- CI-Watcher poll (`gh pr checks --watch`)
- Merge + optional post-merge dispatch
- Persistence of `.sleepwell/team-state.json`

Do not perform work outside it — only dispatching here.
