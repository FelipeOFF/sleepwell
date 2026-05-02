---
name: sleepwell-modes
description: Index of the 4 sleepwell operation modes (tidy, refine, build, radical). Use to pick the right mode given the intent or to load the mode template during an iteration.
---

# sleepwell-modes

Sleepwell operates in 4 modes. Each mode shapes the "rhythm" and "risk appetite" of the iterations.

| Mode | Appetite | Risk | Typical output |
|---|---|---|---|
| `tidy` | Cleanup, organization, deps | Very low | Renames, reorg, dep bumps, lint fixes |
| `refine` (default) | Incremental refactor, improvements | Low-medium | Small refactors, test coverage, naming |
| `build` | Build a new feature | Medium | TDD-first feature, new endpoints/components |
| `radical` | Rewrite subsystems | High | Replace modules, targeted stack swap |

## How to choose

- "Clean up unused imports and run prettier" -> **tidy**.
- "Refactor auth to use the new middleware without changing the API" -> **refine**.
- "Implement the /reports/csv endpoint with tests" -> **build**.
- "Rewrite the cache on top of Redis instead of in-memory" -> **radical**.

Safe default: **refine** when the intent is unclear.

## Templates

Each mode has a template that is injected into the iteration prompt. The files live in:

- `lib/modes/tidy.md`
- `lib/modes/refine.md`
- `lib/modes/build.md`
- `lib/modes/radical.md`

Load via `Read` when assembling the iteration prompt (see `sleepwell-loop`).

## Principles shared by all 4 modes

- **One iteration = one logical unit = one commit.** Do not stack.
- **Green before pass:** lint + types + tests must pass.
- **Aggressive rollback:** failed? `git reset --hard HEAD`. Do not try to "fix it again in the same iter".
- **Conventional commits.** `<type>(sleepwell): <title>` with a body explaining the why.
- **Append-only notes.** Each iter appends to `notes.md`, never rewrites.

## When to switch modes mid-loop

Allowed, but rare. Update `state.json` `mode` and the ritual continues. Cases:

- Mode `build` became `tidy` because the feature finished before max-iter (leftover: cleanup).
- Mode `refine` became `radical` because the subsystem cannot be refactored — it must be rewritten.

If you switch, record the reason in `notes.md`.
