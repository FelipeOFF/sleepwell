---
description: Suggests 3 ranked overnight plans based on the workspace, TODOs, status, and calibration.
---

# /sleepwell:sleepwell-suggest

Inspects the current workspace and proposes **3 overnight plans** ordered by
confidence, derived from statistical calibration of previous runs.

## Inputs read

1. **Workspace dirty:** `git status -s` — modified/staged files
   suggest in-progress work suitable for "polish/refine".
2. **TODOs/FIXMEs:** `grep -rE "TODO|FIXME" --include="*.{md,ts,tsx,js,jsx,py,rs,go,rb,java,cs}"`
   limited to the first 50 occurrences (head -n 50).
3. **Current state** (if present): `.sleepwell/state.json` — current intent,
   mode, status. Avoids suggesting what is already running.
4. **Calibration:** `.sleepwell/calibration.md` (output of the
   `sleepwell-meta` skill) and, if present, the `prediction_profile` field in
   `state.json` (or `.sleepwell/prediction_profile.json`) with shape:
   ```json
   {
     "by_category": {
       "tidy":    { "merge_rate": 0.85, "avg_cost_usd": 0.30, "avg_iters": 6 },
       "refine":  { "merge_rate": 0.70, "avg_cost_usd": 0.90, "avg_iters": 12 },
       "build":   { "merge_rate": 0.55, "avg_cost_usd": 1.80, "avg_iters": 18 },
       "radical": { "merge_rate": 0.30, "avg_cost_usd": 2.50, "avg_iters": 20 }
     }
   }
   ```
   - `Confidence` (0-100) = `merge_rate * 100`. If `prediction_profile`
     is missing, heuristic fallback: tidy=80, refine=65, build=50,
     radical=35, wave=40.

## Flow

1. Collects the inputs above in the current session (no external call).
2. **Composes a prompt for Claude itself** (same session) with:
   - list of TODOs/FIXMEs (with path:line);
   - summary of `git status -s`;
   - intent/mode of the in-progress run (if any);
   - `by_category` table from calibration.
3. Asks Claude to rank 3 diverse plans, each with:
   - **Intent** (short imperative phrase, PT-BR);
   - **Mode** (tidy/refine/build/radical/wave);
   - **Suggested max-iter** (aligned with `avg_iters` of the category);
   - **Expected cost** (aligned with `avg_cost_usd`);
   - **Confidence** (from `prediction_profile.by_category[mode].merge_rate`,
     or heuristic fallback if missing);
   - **Justification** — 1 phrase explaining why this plan now.
4. Sorts by `Confidence` desc.

## Output

Markdown table:

```
| # | Intent                                | Mode    | Max-iter | Expected cost | Confidence |
|---|---------------------------------------|---------|----------|---------------|------------|
| 1 | Clean unused deps and format          | tidy    | 6        | ~$0.30        | 85%        |
| 2 | Extrair middleware de auth            | refine  | 12       | ~$0.90        | 70%        |
| 3 | Adicionar endpoint /metrics com tests | build   | 18       | ~$1.80        | 55%        |
```

Below the table, for each row, 1 justification phrase:

```
1. tidy — Clean unused deps and format
   There are 14 TODOs in JS files and clean working tree: ideal night for
   low-risk mechanical hygiene.

2. refine — Extrair middleware de auth
   `src/auth/*` appears in 8 recent commits; refine has high historical
   merge_rate (70%) in this category.

3. build — Adicionar endpoint /metrics com tests
   Clear TODO in `server/routes.ts:42`; build mode with TDD fits.
```

## Edge cases

- No TODOs and clean working tree → suggests plans based on
  generic calibration (refactor of `git log --stat` hot-spots).
- No calibration → heuristic fallback for Confidence; footer note:
  "Confidence based on heuristic (no prediction_profile)."
- Active run in progress → does not suggest the same intent; may suggest
  parallel tidy/refine on another branch.
- Malformed `prediction_profile` → ignored, uses fallback.

## No side effects

`/sleepwell:sleepwell-suggest` is **read-only**. Does not create branch, does not write to
`.sleepwell/`, does not trigger loop. Only prints the table.

## Post-execution

```
to start plan #1:
  /sleepwell:sleepwell "<intent>" --mode <mode> --max-iter <N>
```
