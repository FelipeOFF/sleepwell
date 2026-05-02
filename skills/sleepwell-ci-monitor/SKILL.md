---
name: sleepwell-ci-monitor
description: Checks CI status at the start of each wake and persists a sentinel in .sleepwell/ci-status.json. Classifies failures (own vs. external), acts as a circuit breaker for the fix-CI feedback loop and enforces guardrails (max_ci_attempts_per_branch, max_actions_minutes_per_run, max_actions_cost_usd).
---

# sleepwell-ci-monitor

Skill invoked **right after bootstrap and before compose-prompt** in each
`sleepwell-loop` iteration (see `lib/ritual.md §3`). Checks CI status of
the current branch, classifies failures, persists a sentinel and decides
whether the loop should invoke fix-CI, wait, or abort.

## 1. Trigger

- Invoked by `sleepwell-loop` at the start of each wake, after bootstrap and
  before prompt composition.
- May also be invoked manually via `/sleepwell:sleepwell-ci-status`.

## 2. Precondition

`state.pr_url` exists OR the sleepwell branch has been pushed (recorded in
`state.last_push_sha`). If neither is true, the skill has nothing to
monitor and returns `no_ci`.

## 3. Lockfile

Before operating, this skill **respects** the `.sleepwell/ci-lock` lockfile
created by `sleepwell-loop`. If the lock exists and contains a live pid
DIFFERENT from the current pid → refuse to run (message: "ci-monitor: lock owned
by pid <X>, aborting"). If absent or pid is dead → ok. See
`lib/ritual.md §10`.

## 4. Collection

```bash
gh run list --branch "$BRANCH" --limit 5 --json \
  status,conclusion,headSha,databaseId,createdAt,workflowName \
  --jq '.[0]' > .sleepwell/ci-run-latest.json
```

Picks the most recent run. If no run exists yet → status `pending`
(branch was pushed but the workflow hasn't started yet).

### 4.1 SHA validation

```
latest = read .sleepwell/ci-run-latest.json
if latest.headSha != state.last_push_sha:
  status = "pending"   # push recorded but run not started yet
                       # OR run points to a previous commit
```

Only runs whose `headSha == state.last_push_sha` count toward the decision.

### 4.2 Atomic sentinel

Persist to `.sleepwell/ci-status.json` via tmpfile + rename:

```json
{
  "branch": "sleepwell/auto/<run-id>",
  "head_sha": "<sha>",
  "run_id": <databaseId>,
  "status": "in_progress|completed|pending",
  "conclusion": "success|failure|cancelled|null",
  "workflow": "<name>",
  "checked_at": "<ISO>",
  "verdict": "green|pending|fix|external_failure|ci_attempts_exceeded|no_ci"
}
```

```bash
tmp=$(mktemp .sleepwell/ci-status.json.XXXXXX)
echo "$payload" > "$tmp"
mv "$tmp" .sleepwell/ci-status.json
```

## 5. Decision

```
if no_ci (sem PR e sem last_push_sha):
  return "no_ci"

if status == "in_progress" or pending:
  state.ci_waiting_iters++
  if state.ci_waiting_iters > 5:
    return "wait_long"   # backoff passivo, sleep maior no ScheduleWakeup
  return "pending"

if conclusion == "success":
  state.ci_green = true
  state.ci_waiting_iters = 0
  reset state.ci_attempts[branch].count = 0
  return "green"

if conclusion == "failure":
  # Capture log of the failed job.
  gh run view "$RUN_ID" --log-failed > .sleepwell/ci-failure-log.txt
  # Cap at 100KB (truncate head if needed).
  truncate --size=100K .sleepwell/ci-failure-log.txt 2>/dev/null \
    || head -c 102400 .sleepwell/ci-failure-log.txt > .sleepwell/ci-failure-log.txt.tmp \
    && mv .sleepwell/ci-failure-log.txt.tmp .sleepwell/ci-failure-log.txt

  ext = match_external_failure(.sleepwell/ci-failure-log.txt)
  if ext:
    log notes.md ("external_failure: <signal>")
    return "external_failure"   # does NOT increment count, backoff 600s
  else:
    state.ci_attempts[branch].count++
    state.ci_attempts[branch].last_run_id = RUN_ID
    state.ci_attempts[branch].actions_minutes_spent += <duration>
    # Inject the log into the next iter (see §6).
    if state.ci_attempts[branch].count >= state.max_ci_attempts_per_branch:
      return "ci_attempts_exceeded"
    return "fix"
```

## 6. Log injection into the next prompt

When the skill returns `fix`, the content of `.sleepwell/ci-failure-log.txt`
(cap 100KB) is appended to the next iteration's prompt under section:

```
## CI failure log (injected by sleepwell-ci-monitor)
<log content>
```

This lets the next iteration reason about the error and try to fix it.
The loop clears this file after a PASS iteration.

## 7. UI in /sleepwell:sleepwell-status

When `state.ci_green == true`, `/sleepwell:sleepwell-status` shows a check next to the
branch. When the latest verdict was `failure` or `fix`, shows an X with a
link to the run.

### 7.1 External failure detection

Regex over `.sleepwell/ci-failure-log.txt`:

```
secret (expired|invalid|missing)|EAI_AGAIN|ENETUNREACH|getaddrinfo|registry.*\b50[023]\b|runner (offline|unavailable)|GitHub Actions (outage|degraded)
```

Match → **external** failure: the problem is NOT in the code under test.
Does not increment `ci_attempts.count`, logs to notes, next iter waits 600s
(long backoff) instead of fixing.

### 7.2 Actions cost

Use `sleepwell-helper` if available (future `actions-cost` subcommand);
heuristic fallback:

```
duration_min = (run.updatedAt - run.createdAt) / 60
state.ci_attempts[branch].actions_minutes_spent += duration_min
```

Estimated USD cost = `Σ minutes * $0.008` (public Linux GitHub-hosted
runner price, Apr 2026).

## 8. Abort gates

The skill RETURNS the verdict, but `sleepwell-loop` is what aborts. See
`lib/ritual.md §8.1` (CI cost guardrails).

| Return                      | Loop action                                  |
|-----------------------------|----------------------------------------------|
| `no_ci`                     | proceed normally (no PR/push yet)            |
| `green`                     | continue, set state.ci_green = true          |
| `pending`                   | skip iter, increment ci_waiting_iters        |
| `wait_long`                 | longer sleep on ScheduleWakeup (≥600s)       |
| `external_failure`          | wait 600s, re-poll (without incrementing)    |
| `fix`                       | inject log and invoke fix-CI routine         |
| `ci_attempts_exceeded`      | finalize("ci_attempts_exceeded")             |
| `actions_minutes_exceeded`  | finalize("actions_minutes_exceeded")         |
| `actions_cost_exceeded`     | finalize("actions_cost_exceeded")            |

## 9. State updates

Always via tmpfile + rename (see `lib/ritual.md §7.2`). Initialize
`state.ci_attempts[branch]` on the 1st failure:

```json
{
  "count": 1,
  "first_attempt_at": "<ISO>",
  "last_run_id": 123456,
  "actions_minutes_spent": 2.4
}
```

## 10. Edge cases

- **`gh` missing:** skill logs warning in `notes.md`
  ("ci-monitor: gh CLI not found, skipping") and returns `no_ci`. Loop
  proceeds normally.
- **Branch with no runs:** `gh run list` returns `[]` → status
  `pending`, sentinel records `run_id: null`.
- **`gh` not authenticated:** same response as `gh` missing — warning + `no_ci`.
- **Divergent `headSha`:** new push happened but Actions hasn't fired
  yet — status `pending` until the run appears. Don't confuse with an
  old-version failure.
- **Same `databaseId` across `pending` invocations:** only increment
  `ci_waiting_iters` when `status == "in_progress"` AND `headSha` matches.
