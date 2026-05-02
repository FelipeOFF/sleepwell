# sleepwell — full ritual

> **Authoritative source.** This document is the canonical reference of the sleepwell flow. Skills (`sleepwell-loop`, `sleepwell-meta`) and commands (`/sleepwell:sleepwell*`) must **reference** this file (`See lib/ritual.md §<section>`) instead of duplicating logic. Flow changes start here.

Canonical documentation of the iteration ritual. The `sleepwell-loop` skill implements this flow. This page exists for humans to read.

## 1. Principles

1. **One iteration = one logical unit = one commit.** No stacking, no amend.
2. **Green before pass.** Lint + types + tests must pass to commit.
3. **Failed? Reset.** `git reset --hard HEAD && git clean -fd` discards the attempt (including untracked files created during the failed iter). The next iter restarts from the last successful iter.
4. **Always isolated branch.** Never touch main/master/develop.
5. **Append-only notes.** `notes.md` is the loop's "logbook" — it only grows.
6. **State is the source of truth.** `state.json` is what the loop consults between wakeups.

## 2. Bootstrap (iter 0)

```
[parse args]
  /sleepwell:sleepwell "<intent>" --mode refine --max-iter 20

[validations]
  ✓ git repo
  ✗ branch is main → continue (will create new branch)
  ✓ working tree clean (or auto stash with confirmation)

[branch]
  slug = kebab(intent)
  worktree path = ../<repo>-wt/sleepwell:sleepwell-<slug>
  git worktree add <path> -b sleepwell/<slug>

[adaptation]
  voice_profile = sleepwell-profile()  # if !no-voice
  calibration   = sleepwell-meta()     # if !no-meta

[state]
  write .sleepwell/state.json
  write .sleepwell/notes.md (header)
  add .sleepwell/ to .gitignore
```

## 3. Iteration N

```
[load]
  state = read .sleepwell/state.json

[abort?]
  if state.status == "stopped" → finalize("stopped")
  if state.iteration >= state.max_iter → finalize("max_iter")
  if state.consecutive_failures >= 3 → finalize("3 consecutive fails")
  if state.stop_when and evaluate(state.stop_when, notes, last_diff) → finalize("stop-when met")

[ci-monitor]
  invoke skill `sleepwell-ci-monitor`   # right after bootstrap/abort, BEFORE prompt
  → persists sentinel in .sleepwell/ci-status.json
  → verdict ∈ {no_ci, green, pending, wait_long, external_failure, fix,
                ci_attempts_exceeded, actions_minutes_exceeded,
                actions_cost_exceeded}
  → pending/wait_long: skip iter, ScheduleWakeup with longer delay
  → fix: inject .sleepwell/ci-failure-log.txt into prompt
  → ci_attempts_exceeded / actions_*_exceeded: finalize with abort_reason

[prompt]
  intent + voice_profile + calibration + mode_template + tail(notes) + git diff --stat

[execute]
  Claude reasons + edits files

[verify]
  run state.verify_cmds.lint
  run state.verify_cmds.typecheck
  run state.verify_cmds.test
  → pass | fail

[decide]
  if pass:
    if !state.dry_run:
      git add -A
      git commit -m "<conventional msg> [sleepwell-iter:N]"
    append notes.md (PASS, sha, summary)
    state.consecutive_failures = 0
    state.total_passes++
    delay = 60s
  else:
    git reset --hard HEAD
    git clean -fd                     # remove untracked files created in the iter
    append notes.md (FAIL, error)
    state.consecutive_failures++
    state.total_fails++
    delay = min(270, 60 * 2^failures)

[evaluate]
  invoke skill `sleepwell-evaluator`
  → updates state.last_eval = {rating, observation, course_correct, evaluated_at}
  → next iter injects `## Previous evaluation` into the prompt
  → 2× consecutive course_correct: escalate mode (refine→tidy) or request abort

[telemetry]
  invoke skill `sleepwell-telemetry`
  → updates state.tokens_used and state.cost_so_far_usd

[abort by cost?]
  if state.cost_budget_usd != null and
     state.cost_so_far_usd  >= state.cost_budget_usd
     → finalize("cost", abort_reason="cost budget reached")

[update]
  state.iteration++
  state.last_iter_at = now
  write state.json

[continue?]
  if next iter would abort → finalize now
  else → ScheduleWakeup(delay, prompt="continue sleepwell loop")
```

## 4. Finalize

```
state.status = "done"|"aborted"|"stopped"
state.abort_reason = "<reason>"
write notes.md final summary
write state.json

display:
  intent / mode / branch / iter / passes/fails / commits

suggest next steps:
  /sleepwell:sleepwell-diff
  git checkout main && git merge --squash <branch>
  git branch -D <branch>
```

## 5. Prompt cache

`ScheduleWakeup` with `delaySeconds` between 60-270s keeps the Anthropic prompt cache warm (TTL 5min). This means each wakeup re-enters context WITHOUT an expensive cache miss.

- 60s = next iter ready quickly (default).
- 270s = close to TTL, but still within the window.
- 300s+ = pays cache miss → avoid unless waiting on something external.

On fail backoff, the delay can exceed 270s; we accept the cache miss in exchange for spacing.

## 6. Compatibility with external skills (optional)

The core loop is **standalone** — equivalent behaviors are embedded
in the flow. If the skills below are installed in the environment,
they may be invoked for reinforcement; otherwise the loop operates
without them.

<!--
Inspirations (not required):
- superpowers:test-driven-development — mirrored by mode `build`.
- superpowers:systematic-debugging — mirrored by FAIL handling.
- superpowers:verification-before-completion — mirrored by §3 verify.
- gsd-execute-phase — replaced by internal sub-phases (§9).
- gitnexus-impact-analysis — heuristic used before `radical`.
-->

Context preserved across invocations via prompt cache.

## 7. Helpers

### 7.1 Base branch detector

Never hardcode `main`. Use the helper below to detect the correct base (`main`, `master`, `develop`) — all commands and skills must reference this logic:

```bash
# Detects the repo's base branch.
# Order: HEAD of remote origin → local main → local master → develop.
sleepwell_base_branch() {
  local base
  base=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
          | sed 's@^refs/remotes/origin/@@')
  if [ -z "$base" ]; then
    if   git rev-parse --verify --quiet main    >/dev/null; then base=main
    elif git rev-parse --verify --quiet master  >/dev/null; then base=master
    elif git rev-parse --verify --quiet develop >/dev/null; then base=develop
    fi
  fi
  echo "$base"
}
```

Use anywhere requiring `merge-base`, range `..`, exclusion `^<base>`. Already adapted: `skills/sleepwell:sleepwell-loop` (accumulated diff), `commands/sleepwell:sleepwell-status`, `commands/sleepwell:sleepwell-diff`, `skills/sleepwell:sleepwell-meta`.

### 7.2 Atomic state write

`state.json` is the source of truth — corruption breaks resumes. Always write via tmpfile + rename (atomic on the same filesystem):

```bash
tmp=$(mktemp .sleepwell/state.json.XXXXXX)
echo "$payload" > "$tmp"
mv "$tmp" .sleepwell/state.json
```

Same pattern for `notes.md` rewrites (simple appends can use `>>`).

### 7.3 Upstream guard in undo

Before checking `git log @{u}..` (detect already-pushed commits), verify upstream is configured. Without the guard, local branches without remote tracking make `git log @{u}..` fail and erroneously block undo.

```bash
if git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
  # has upstream — check @{u}..
  pushed=$(git log @{u}..)
fi
# no upstream → skip the check; undo is safe.
```

Sleepwell branches are local by default, so the guard usually skips the check.

## 8. State schema v3 — migration

`state-schema.json` was bumped to `version: 3`. The new fields (v3) are
all optional — old runs (`version: 1` or `version: 2`) remain
compatible and can be resumed without changes.

### v2 (already existing)

- `worktree_enabled` (boolean, default true) — mirrors `--no-worktree`.
- `no_voice` / `no_meta` (boolean, default false) — CLI flags persisted.
- `intent_file` (string|null) — alternative to inline intent.
- `tokens_used` `{input, output, cache_read, cache_creation}` — telemetry.
- `cost_so_far_usd` (number, default 0) — accumulated cost.
- `cost_budget_usd` (number|null) — budget via `--max-cost <USD>`.

### v3 (new)

- `last_eval` `{rating, observation, course_correct, evaluated_at}` — output
  of skill `sleepwell-evaluator`. Optional; absent in v1/v2 runs.
- `prediction_profile` `{overall, by_category, trusted, distrusted, n_runs,
  calibrated_at}` — output of `sleepwell-helper calibrate`, consumed by
  skill `sleepwell-meta`. Optional.
- `context_threshold_pct` (integer, default 80) — context pressure for
  automatic pruning.
- `phases` (array) — internal sub-phases of the run.

v2 → v3 migration: nothing to do. Old runs keep opening; the loop
adds new fields when the corresponding skills run for the first time
in the resumed run.

`verify_cmds.{lint,typecheck,test}` now explicitly accepts the literal sentinel `"auto"` (oneOf string|"auto"), in addition to a shell command.

`additionalProperties` at the root is `true` (critical sub-objects like `verify_cmds` keep `false`) — allows schema evolution without breaking parsing.

### 8.1 Cost abort gate

Add to §3 abort checks:

```
if state.cost_budget_usd != null and
   state.cost_so_far_usd  >= state.cost_budget_usd
   → finalize("cost", abort_reason="cost budget reached")
```

#### Per-iter cost guardrail

When `state.max_cost_per_iter_usd` is set (via `--max-cost-per-iter
<USD>`), we measure the **cost delta of the current iter** (difference between
`cost_so_far_usd` before and after telemetry). If the delta exceeds the limit:

```
delta = cost_so_far_usd_after - cost_so_far_usd_before
if state.max_cost_per_iter_usd != null and
   delta > state.max_cost_per_iter_usd
   → mark iter as FAIL
   → git reset --hard HEAD && git clean -fd
   → state.consecutive_failures++
   → state.total_fails++
   → exponential backoff (same formula as normal FAIL: min(270, 60*2^failures))
   → does NOT increment abort_total; the loop continues until consecutive_failures >= 3
     or any other abort gate (max_iter, cost_budget_usd, stop_when).
```

Rationale: per-iter is a **guardrail**, not a kill switch. An expensive iter shouldn't
kill the entire loop — it might be an outlier. But consecutive failures (3
expensive ones in a row) hit the `consecutive_failures >= 3` abort and cut off
naturally.

#### CI cost guardrails (v3.1)

Beyond inference cost limits, the loop respects a GitHub Actions consumption
ceiling:

- `state.max_actions_minutes_per_run` (default 60) — ceiling of Actions
  minutes aggregated across all branches of the run.
- `state.max_actions_cost_usd` (default 5.0) — USD ceiling of aggregated
  Actions consumption.
- `state.max_ci_attempts_per_branch` (default 3) — limit of fix-CI attempts
  per branch before abort.

Skill `sleepwell-ci-monitor` consolidates these metrics in
`state.ci_attempts[<branch>]`. Additional abort gates for §3:

```
if state.ci_attempts[branch].count >= state.max_ci_attempts_per_branch
   → finalize("ci_attempts_exceeded",
              abort_reason="ci_attempts_exceeded:<branch>")
if Σ state.ci_attempts[*].actions_minutes_spent >= state.max_actions_minutes_per_run
   → finalize("actions_minutes_exceeded")
if (estimated Actions cost) >= state.max_actions_cost_usd
   → finalize("actions_cost_exceeded")
```

**External failure** detection (expired/missing secret, DNS,
registry 5xx, runner offline, GitHub outage) does NOT increment
`ci_attempts[branch].count`: the monitor classifies it as
`external_failure`, logs to notes and re-schedules iter with long backoff
(600s) instead of invoking fix.

## 9. Internal sub-phases (`.sleepwell/phases/`)

A sleepwell run can be decomposed into **sub-phases** — logical blocks of
work with their own plan, execution and verification. It is a concept
**internal** to the plugin (does not depend on external skills like GSD): each phase
lives in `.sleepwell/phases/<NN>-<slug>/`.

### Layout

```
.sleepwell/phases/
├── 01-bootstrap/
│   ├── PLAN.md          # generated at the start of the phase (scope, criteria)
│   ├── EXECUTION.md     # phase iteration log (append-only)
│   └── VERIFICATION.md  # acceptance criteria verified at the end
├── 02-iteration-set-A/
│   └── ...
└── ...
```

Numbering `NN` is sequential (zero-padded, 2 digits). `slug` is kebab-case.

### state.json model

Field `phases: array` (v3, optional) with items:

```json
{
  "id": 1,
  "slug": "bootstrap",
  "status": "active|completed|abandoned",
  "started_at": "<ISO>",
  "completed_at": "<ISO|null>",
  "plan_path":         ".sleepwell/phases/01-bootstrap/PLAN.md",
  "execution_path":    ".sleepwell/phases/01-bootstrap/EXECUTION.md",
  "verification_path": ".sleepwell/phases/01-bootstrap/VERIFICATION.md"
}
```

The phase with `status == "active"` is the **phase in progress**. Only one at a time.

### Commands

- `/sleepwell:sleepwell-phase-start "<slug>" [--plan <path>]` — open a new phase.
  Creates directory, generates `PLAN.md` (inline template), empty `EXECUTION.md`,
  appends entry in `state.phases` with `status="active"`.
- `/sleepwell:sleepwell-phase-complete [--abandon]` — close the active phase.
  Generates/fills `VERIFICATION.md`, marks `completed_at`, status →
  `completed` (or `abandoned` if `--abandon`).

### Integration with the `sleepwell-loop` skill

In step 3 (build prompt), if there is an active phase (status=`active`), the skill:

- Appends the content of `<plan_path>` to the prompt (section `## Phase in progress`).
- Appends the last 30 lines of `<execution_path>`.
- After each PASS, append to `<execution_path>` the same line that goes in
  `notes.md` (local mirror of the phase).

At the end of each iter, the skill evaluates (via short reasoning over the
criteria in `PLAN.md` + accumulated phase diff) whether the phase criteria
are met. If yes:

- Presents to the user: "phase `<slug>` complete — open a new phase or
  finalize run?".
- In autonomous mode (no active user), runs
  `/sleepwell:sleepwell-phase-complete` automatically and proposes the next phase via
  `/sleepwell:sleepwell-suggest`.

### Compatibility

- Runs without `phases` (legacy v1/v2 or v3 without using phases) keep
  working exactly as before.
- Existing status/recap/diff commands don't need to change; they just
  gain extra info when `state.phases` exists.

## 10. Concurrency lockfile (`.sleepwell/ci-lock`)

To prevent two loop instances from stepping on the same `state.json`, the
bootstrap (§2) creates a `.sleepwell/ci-lock` lockfile with JSON payload:

```json
{ "pid": 12345, "started_at": "<ISO>", "hostname": "<host>" }
```

### Rules

- **Creation:** before creating the lock, check whether the file exists.
  - If it exists and contains a live `pid` (`kill -0 $pid 2>/dev/null` on unix;
    `tasklist /FI "PID eq $pid"` on windows) → refuse: message
    `lock owned by pid <X> @ <hostname> (started_at <ISO>)`.
  - If it exists and the `pid` is dead → consider lock stale and overwrite.
  - If absent → create via tmpfile + rename (atomic, see §7.2).
- **Verification by auxiliary skills.** Skills `sleepwell-evaluator`,
  `sleepwell-meta`, `sleepwell-ci-monitor` and `sleepwell-telemetry`
  check the lock before operating:
  - Lock absent → ok (invoked outside a run, or run died).
  - Live lock from another pid → refuse.
  - Live lock from current pid → ok.
- **Release.** The lock is removed in §4 finalize (success or abort)
  only by the owner (pid in the file == current pid). Late release on
  crash: the next invocation detects a dead pid and overwrites.

### Rationale

`state.json` is the source of truth; concurrency produces interleaved writes
and corruption. The lockfile is lightweight, daemonless, and degrades gracefully
on crashes (stale pid).

## 11. Catastrophic failure recovery

If the CC process is killed mid-iter:
- `state.json` is partially updated (the last write is atomic via tmpfile + rename).
- Next manual invocation of `/sleepwell:sleepwell` (no args) detects `status == "running"` and resumes.
- Working tree may be dirty if the failure happened after edit but before commit/reset → loop detects diff vs HEAD on the 1st check of the resume and offers: "rollback or recover?".
