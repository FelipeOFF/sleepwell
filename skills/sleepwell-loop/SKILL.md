---
name: sleepwell-loop
description: Use to start or continue the autonomous sleepwell loop. Implements the gnhf-style ritual (isolated branch, atomic commit, rollback on failure) with hooks for voice matching and meta-learning. Runs one iteration per invocation and uses ScheduleWakeup to relaunch itself until it finishes.
---

# sleepwell-loop

Core skill of the `sleepwell` plugin. Runs **one iteration** of the autonomous loop per invocation and decides whether to continue (via `ScheduleWakeup`) or stop.

## When to activate

- When the user invokes `/sleepwell:sleepwell "<intent>" [opts]` (1st iteration — bootstrap).
- When a scheduled `ScheduleWakeup` re-fires this skill (next iter).
- When another skill/agent explicitly requests loop continuation.

**Do not activate** if:
- User invoked `/sleepwell:sleepwell-status`, `/sleepwell:sleepwell-diff`, `/sleepwell:sleepwell-stop`, `/sleepwell:sleepwell-undo` (those have their own flows).
- `.sleepwell/state.json` does not exist AND no intent was provided (no anchor — abort).

## Prerequisites

- Repo is git (`git rev-parse --is-inside-work-tree`).
- Working tree clean OR user accepted automatic stash (ask via AskUserQuestion on 1st iter).
- Current branch != main/master/develop (if so, create a sleepwell branch before touching any file).

> **Canonical flow:** `lib/ritual.md` §1–§9 documents principles, bootstrap, iteration, finalize, helpers and migration. This SKILL implements that flow — below is only what is runtime/execution specific. Behavior changes start in `ritual.md`.

## Anatomy of an iteration

```
┌────────────────────────────────────────┐
│  load state.json                        │
│  if missing: bootstrap                  │
└─────────────┬──────────────────────────┘
              ▼
┌────────────────────────────────────────┐
│  abort checks                           │
│  - iter >= max-iter        → finalize   │
│  - failures >= 3           → abort      │
│  - stop-when met           → finalize   │
│  - sleepwell-stop sentinel → abort      │
└─────────────┬──────────────────────────┘
              ▼
┌────────────────────────────────────────┐
│  build iteration prompt                 │
│  intent + mode template + voice +       │
│  notes.md tail + last_diff + calib.     │
└─────────────┬──────────────────────────┘
              ▼
┌────────────────────────────────────────┐
│  EXECUTE — Claude edits files          │
└─────────────┬──────────────────────────┘
              ▼
┌────────────────────────────────────────┐
│  verify: lint + types + tests          │
└─────────────┬──────────────────────────┘
              ▼
        ┌─────┴─────┐
        ▼           ▼
     PASS         FAIL
       │           │
       ▼           ▼
  commit+notes  reset+clean -fd
  reset fail    failures++
  counter       backoff exp
       │           │
       └─────┬─────┘
             ▼
┌────────────────────────────────────────┐
│  update state.json                      │
└─────────────┬──────────────────────────┘
              ▼
        ┌─────┴─────┐
       done?        no
        │            │
       finalize     ScheduleWakeup
                    delay 60-270s
                    prompt: continue
```

## Detailed algorithm

### 0. Bootstrap (iter 0 only)

Detect: `.sleepwell/state.json` does not exist AND there is `--intent "<text>"` in the input.

1. Parse args of `/sleepwell:sleepwell`: intent (or `--intent-file <path>`), mode (default `refine`), max-iter (default 20), `--max-cost <USD>` (optional), stop-when, dry-run, worktree (default true), no-voice, no-meta, `--no-pr` (default false: creates PR on finalize), `--draft-pr` (creates PR as draft). All flags are **persisted in `state.json`** (fields `worktree_enabled`, `no_voice`, `no_meta`, `intent_file`, `cost_budget_usd`, `pr_mode` ∈ {`auto`,`none`,`draft`}) so that resumes via `ScheduleWakeup` preserve the setup.
2. Intent slug → short kebab-case, e.g. `refactor-auth-middleware`. Persisted in `state.slug` (separate field).
3. **Run-id:** generate unique identifier `<unix-epoch>-<rand4hex>` (e.g. `1714678920-a3f2`). Used to name the branch, avoiding collisions with duplicate slugs and ensuring PR-friendly naming.
4. **Worktree:**
   - Branch always named `sleepwell/auto/<run-id>` (no longer `sleepwell/<slug>`).
   - If `worktree=true`: create `git worktree add ../<repo>-wt/sleepwell:sleepwell-auto-<run-id> -b sleepwell/auto/<run-id>` (vendored stub in `skills/vendor/git-worktrees`).
   - Otherwise: `git checkout -b sleepwell/auto/<run-id>` (abort if branch exists — unlikely given the rand).
5. **Voice profile** (if `no-voice=false`):
   - Invoke skill `sleepwell-profile`.
   - Result in `.sleepwell/voice-profile.md`.
6. **Meta-calibration** (if `no-meta=false`):
   - Invoke skill `sleepwell-meta`.
   - Result in `.sleepwell/calibration.md`.
7. Create `.sleepwell/state.json` (schema in `lib/state-schema.json`, version `3`):
   ```json
   {
     "version": 3,
     "intent": "<user phrase>",
     "intent_file": null,
     "slug": "<kebab-case>",
     "run_id": "<unix-epoch>-<rand4hex>",
     "mode": "refine",
     "branch": "sleepwell/auto/<run-id>",
     "pr_url": null,
     "pr_mode": "auto",
     "worktree_enabled": true,
     "worktree_path": "<abs path or null>",
     "iteration": 0,
     "max_iter": 20,
     "stop_when": null,
     "dry_run": false,
     "no_voice": false,
     "no_meta": false,
     "consecutive_failures": 0,
     "total_passes": 0,
     "total_fails": 0,
     "started_at": "<ISO>",
     "last_iter_at": null,
     "status": "running",
     "verify_cmds": {
       "lint": "auto",
       "typecheck": "auto",
       "test": "auto"
     },
     "tokens_used": {
       "input": 0, "output": 0,
       "cache_read": 0, "cache_creation": 0
     },
     "cost_so_far_usd": 0,
     "cost_budget_usd": null
   }
   ```
   - `verify_cmds.lint = "auto"` → detected at runtime (npm/pnpm/bun script `lint`, `ruff`, `eslint`, `golangci-lint`, etc).
   - `cost_budget_usd` (from `--max-cost <USD>`) creates an abort gate (see `lib/ritual.md §8.1`).
8. Create `.sleepwell/notes.md` with header.
9. Add `.sleepwell/` to `.gitignore` if not already there.
10. **Concurrency lockfile (`.sleepwell/ci-lock`):** see `lib/ritual.md §10`.
    Before creating, check if the file exists:
    - If it exists: read pid; on unix `kill -0 $pid 2>/dev/null` (on windows
      `tasklist /FI "PID eq $pid"`). If alive → refuse with message
      `sleepwell-loop: lock owned by pid <X> @ <hostname> (started_at <ISO>)`.
      If pid is dead → consider lock stale, overwrite.
    - If absent: create.
    Content: `{ "pid": <int>, "started_at": "<ISO>", "hostname": "<host>" }`
    via tmpfile + rename. Lock removed on finalize (success or abort).

Skip directly to step 2 (without checking abort).

### 1. Load state

Read `.sleepwell/state.json`. If absent and no intent → error: ask for `/sleepwell:sleepwell "<intent>"` first.

### 2. Abort checks

- `state.status == "stopped"` → silent finalize.
- `state.iteration >= state.max_iter` → finalize "max iter reached".
- `state.consecutive_failures >= 3` → finalize "3 consecutive failures".
- `state.stop_when != null`:
  - Evaluate: read `notes.md` + last diff + NL condition. Decide (short reasoning) whether met. If yes → finalize "stop-when met".
- `state.cost_budget_usd != null && state.cost_so_far_usd >= state.cost_budget_usd` → finalize "cost budget reached" (see `lib/ritual.md §8.1`).

On finalize: write summary to notes.md, update `state.status = "done"|"aborted"`, show user the final status + command to review the diff.

### 3. Build iteration prompt

Compose (concatenate):

```
# Iteration ${iter+1}/${max_iter} — mode: ${mode}

## Original intent
${intent}

## Voice profile (user style)
${cat .sleepwell/voice-profile.md, if it exists}

## Calibration from previous run
${cat .sleepwell/calibration.md, if it exists}

## Mode: ${mode}
${cat sleepwell/lib/modes/${mode}.md}

## Notes from recent iterations
${tail -n 80 .sleepwell/notes.md}

## Accumulated branch diff
${BASE=$(sleepwell_base_branch); git diff --stat $(git merge-base HEAD "$BASE")..HEAD}
# `sleepwell_base_branch` detects main/master/develop — see lib/ritual.md §7.1.

## Next action
Think of a SINGLE coherent change that advances the intent. Implement it now.
Keep scope surgical — one iteration = one logical unit = one commit.
```

### 3.5 Active phase gate

Before executing (step 4), check `state.phases`:

- If there is an item with `status == "active"`:
  - Read `<plan_path>` and add section `## Phase in progress` to the prompt.
  - Read the last 30 lines of `<execution_path>` and add section
    `## Phase execution (recent)`.
  - Keep the iteration prompt focused on the phase criteria.
- No active phase: original behavior (no extra injection).

After PASS (step 6, decision), in addition to appending to `notes.md`, mirror the
same line into `<execution_path>` so the phase has its own log.

After each iter (PASS or FAIL), evaluate whether the active phase criteria
are met (short reasoning over `PLAN.md` + accumulated phase diff). If yes:

- Interactive mode: ask the user "phase complete — open a new one?".
- Autonomous mode: run `/sleepwell:sleepwell-phase-complete` automatically and
  offer next ones via `/sleepwell:sleepwell-suggest`.

See `lib/ritual.md §9`.

### 4. Execute

Do the actual work. Use Edit/Write/Bash as needed. **Stay focused**: one logical unit.

### 5. Verify

Detect stack once (cache in state.verify_cmds):
- **Node/TS:** `package.json` → `npm run lint` (if it exists), `npm run typecheck`/`tsc --noEmit`, `npm test`.
- **Python:** `pyproject.toml`/`requirements.txt` → `ruff check`, `mypy` (if configured), `pytest`.
- **Go:** `go.mod` → `go vet`, `go build`, `go test ./...`.
- **Rust:** `Cargo.toml` → `cargo clippy`, `cargo check`, `cargo test`.
- **No stack detected:** skip verify, mark in notes.md.

Per-command timeout: 5min. If hung, treat as fail.

### 6. Decision

**If PASS:**
1. If `dry_run=true`: skip commit, write notes.md "[dry-run] changes not committed".
2. Otherwise:
   - `git add -A`
   - Commit with conventional message derived from the diff:
     ```
     <type>(sleepwell): <short iter action>

     Iter ${iter+1}/${max_iter} — mode ${mode}.
     ${1-2 lines of what changed and why}

     [sleepwell-iter:${iter+1}]
     ```
3. Append to `notes.md`:
   ```
   ## Iter ${iter+1} — PASS — ${ISO}
   - <1-2 line summary>
   - commit: <sha>
   ```
4. `state.consecutive_failures = 0`, `state.total_passes++`.

**If FAIL:**
1. `git reset --hard HEAD && git clean -fd` (discards changes from this iter, including untracked files created — see `lib/ritual.md §1`).
2. Append to `notes.md`:
   ```
   ## Iter ${iter+1} — FAIL — ${ISO}
   - failed at: <lint|types|tests>
   - error summary: <100 chars>
   - rollback applied
   ```
3. `state.consecutive_failures++`, `state.total_fails++`.
4. Backoff: next wakeup with `delay = min(270, 60 * 2^failures)`.

### 6.5 Automatic context pruning

After telemetry (step 7 below), evaluate context pressure of the just-completed
iteration. Default threshold: `80%` of `model_context_window`.
Configurable via `state.context_threshold_pct` (optional v3 field).

**Context window table (inline):**

| Model             | Window (input tokens) |
|-------------------|----------------------:|
| Claude Sonnet     | 200000                |
| Claude Opus       | 200000                |
| Claude Haiku      | 200000                |
| Sonnet 1M (beta)  | 1000000               |
| Opus 1M (beta)    | 1000000               |
| Codex / GPT-5     | 200000                |

If unknown, fallback `200000`.

**Trigger:**

```
threshold_pct = state.context_threshold_pct ?? 80
window        = lookup(model_id) || 200000
limit         = window * threshold_pct / 100

if iter.tokens_used.input > limit:
  # 1. Truncate notes.md to last 20 entries (preserve header).
  header  = first lines up to the first "## Iter " (exclusive)
  entries = "## Iter ..." blocks — take the last 20
  rewrite notes.md = header + "\n\n" + last20

  # 2. last_diff cache > 5MB → remove.
  if exists(.sleepwell/last_diff) and size > 5MB:
    rm .sleepwell/last_diff

  # 3. Log the event in notes.md.
  append:
    "## Prune — <ISO ts>: context reduced (input=<N> > limit=<L>)"
```

The prune is recorded as its own entry in `notes.md` (line
`## Prune — <ts>`) for auditing — future inspections (recap, suggest)
know the history was truncated.

Idempotent: if the limit is still exceeded in subsequent iters, each
prune re-truncates to the last 20 — no perverse effect.

### 7. Update state

Write the new state.json (including `last_iter_at`, `iteration++`). Also update v2 telemetry fields: increment `tokens_used.{input,output,cache_read,cache_creation}` and recompute `cost_so_far_usd` from this iteration's consumption. Never touch the persisted flags (`worktree_enabled`, `no_voice`, `no_meta`, `intent_file`, `cost_budget_usd`) — they are immutable after bootstrap.

Use atomic write (tmpfile + rename) to avoid corrupting state on crash.

### 8. Continue or stop

- If any abort check of the next iter is already going to fire (e.g. iter+1 ≥ max), finalize now.
- Otherwise: `ScheduleWakeup`:
  - `delaySeconds`: 60 (default), 270 if a big change just landed, or backoff on fail.
  - `prompt`: `"continue sleepwell loop — invoke skill sleepwell-loop"`.
  - `reason`: `"sleepwell iter ${iter+1} → ${iter+2}, status ${PASS|FAIL}"`.

## Finalize

When aborting or concluding:

1. Update `state.status` to `"done"|"aborted"|"stopped"`.
2. Write final summary to `notes.md`.
2.5. Remove `.sleepwell/ci-lock` (only if the pid in the lock is the current pid).
2.7. **ci-mirror gate (local/CI parity):** if `sleepwell-helper` is
    available, before push/PR run
    `sleepwell-helper ci-mirror | bash` (cwd = worktree). If exit `!= 0`,
    push and PR creation are **blocked**: status changes to
    `aborted`, `abort_reason="ci_mirror_failed"`, log in notes with the
    bash output. If the helper is not in PATH, the gate is skipped with
    a warning in notes (graceful degradation). See issue #37.
3. **PR-only flow:** if `state.pr_mode != "none"` AND `state.status == "done"` AND there is ≥1 commit on the branch → invoke `/sleepwell:sleepwell-pr` to create the PR. URL is persisted in `state.pr_url`. In `"draft"` mode, creates with `--draft`. Auto-merge disabled by default; manually applying the `sleepwell-auto-merge` label enables conditional merge via a server-side Action (reference only — not implemented in this plugin).
4. Show the user:
   ```
   sleepwell finished
   ━━━━━━━━━━━━━━━━━━━━
   intent: <intent>
   mode:   <mode>
   branch: sleepwell/<slug>
   iters:  ${total_passes} pass / ${total_fails} fail
   commits: ${git log sleepwell/<slug> ^$(sleepwell_base_branch) --oneline | wc -l}
   cost:   $${cost_so_far_usd} USD${cost_budget_usd:+ / $cost_budget_usd USD budgeted}
   tokens: ${tokens_used.input} in / ${tokens_used.output} out (cache: ${tokens_used.cache_read} read, ${tokens_used.cache_creation} write)

   next steps:
   - review:  /sleepwell:sleepwell-diff
   - merge:   git checkout main && git merge --squash sleepwell/<slug>
   - discard: git branch -D sleepwell/<slug>
   ```

## Error handling

- **Dirty working tree on 1st iter:** AskUserQuestion → "auto-stash? abort?"
- **Branch sleepwell/<slug> already exists:** suffix `-2`, `-3`, ...
- **Worktree fails (space, etc):** falls back to no-worktree mode, warns user in notes.md.
- **Verify cmd not found:** mark in notes.md, treat as "skip" not fail.
- **Ctrl+C/sleepwell:sleepwell-stop:** the slash `/sleepwell:sleepwell-stop` sets `state.status = "stopped"` — abort check picks it up on the next iter.

## Composed skills (optional, source of inspiration)

The core loop is **standalone** — it does not depend on these external skills. If
they are installed in the environment, they may be invoked inside an
iteration; otherwise, equivalent behavior is already embedded here.

<!--
Inspirations (not called at runtime if missing):
- superpowers:test-driven-development — mirrors mode `build`.
- superpowers:systematic-debugging — mirrors handling of fix iters.
- superpowers:verification-before-completion — mirrored by step §5 verify.
- gsd-execute-phase — now replaced by the internal sub-phases (§9).
- gitnexus-impact-analysis — heuristic used in `refine`/`radical`.
-->


## Don't

- Do not run on `main`/`master`/`develop`.
- No `--no-verify`, no `--force-push`.
- Do not amend prior loop commits (each iter = new commit).
- Do not delete `.sleepwell/` mid-loop.
- Do not write to files outside the work repo.
