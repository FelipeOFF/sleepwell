# ADR-001: PR-only flow and CI awareness in SleepWell

- **Date:** 2026-05-02
- **Status:** Accepted

## Context

The SleepWell autonomous loop runs overnight, with no human operator at the
console, and produces successive commits on an isolated branch. For the cycle
to provide real value (not just "run until tired"), it must **react to CI**: if
an Actions run fails, the next iter should try to fix it; if a sequence
of fixes does not converge, the loop must stop before burning runner
hours. At the same time, **direct push to `main` is
unacceptable** — it breaks history, ignores human review, and exposes
production to the output of an unsupervised agent.

The design question was: how does the loop react to CI without human interference
and without compromising repository hygiene?

## Decision

1. **PR-only flow.** Every run creates branch
   `sleepwell/auto/<run-id>` and, on finalize, opens a Pull Request via
   `/sleepwell:sleepwell-pr`. There is never a direct push to `main`.
2. **CI awareness via wake-time polling.** At the start of each iteration
   (after bootstrap, before composing the prompt), the
   `sleepwell-ci-monitor` skill calls `gh run list` for the active branch and
   classifies the latest run as `green | pending | fix |
   external_failure`. The verdict feeds the prompt for the next iter
   (injects `.sleepwell/ci-failure-log.txt` when it is `fix`).
3. **Circuit breaker.** Schema v3.1 introduces
   `state.ci_attempts[<branch>]` with a counter, `last_run_id`, and
   `actions_minutes_spent`. Configurable limits:
   `max_ci_attempts_per_branch` (default 3),
   `max_actions_minutes_per_run` (default 60),
   `max_actions_cost_usd` (default 5.0). Overflow → finalize with
   `abort_reason ∈ {ci_attempts_exceeded,
   actions_minutes_exceeded, actions_cost_exceeded}`.
4. **External failure detection.** Regex over the log captures signals of
   issues the loop cannot resolve (expired secret, DNS,
   registry 5xx, runner offline, GitHub outage). Match → long
   600s backoff, without incrementing `ci_attempts.count`.

## Alternatives Considered

- **Webhook push-based.** A server would receive GitHub events and
  wake up the loop. **Rejected:** requires infra (always-on server,
  tunnel, authentication), incompatible with plug-and-play installation
  of the local plugin.
- **`workflow_run` commit-back.** Server-side Action would commit back
  to the branch when CI is green. **Rejected:** high latency (workflow
  must finish before re-triggering), pollutes git history with
  synthetic commits, and introduces coupling between the loop and
  the repo's Actions configuration.
- **Synchronous polling inside the iter.** Loop would be blocked on
  `gh run watch` waiting for completion. **Rejected:** breaks the
  `ScheduleWakeup` wake-up model (each iter should be short), blocks
  the execution slot for minutes without progress, and wastes token
  caches.

## Consequences

- **Added complexity.** Branch named by `run-id`, command
  `/sleepwell:sleepwell-pr`, schema v3.1, `sleepwell-ci-monitor` skill,
  sentinel at `.sleepwell/ci-status.json`.
- **Auto-merge is server-side and optional.** The loop only adds the
  `sleepwell-auto-merge` label when configured; an external Action
  (reference only, not included) decides conditional merge after green
  CI + approved reviews. Default: PR awaits human merge.
- **CI awareness is best-effort, not SLA.** Network flake from `gh`,
  missing auth, or degraded Actions cause `no_ci`/`pending` without
  aborting the loop. False negatives are acceptable: the local
  gate (lint/type/test in each iter's verify) is the first line; CI is
  redundancy.
- **Explicit local/CI parity.** `sleepwell-helper ci-mirror` lets you
  run an approximation of the workflows locally before pushing,
  reducing the surprise window.

## Council Validation

On **2026-05-02** four voices were convened (Architect, Skeptic,
Pragmatist, Critic) to validate the decision.

- **Architect:** PR-only is the only arrangement that keeps the loop
  decoupled from infra and auditable post-hoc — approved.
- **Pragmatist:** the loop must deliver value even without CI; the local
  gate (`verify` in each iter) is already strong — approved.
- **Critic:** the `sleepwell/auto/<run-id>` notation is readable and PR-friendly
  — approved.
- **Skeptic (dissent):** "depending on external polling is fragile; what if
  GitHub is unstable all night?" — incorporated: the local
  gate + `ci-mirror` reduce online-CI dependency; external failure
  classified and handled with long backoff instead of fixing; circuit
  breaker ensures exit in any pathological scenario.

Consensus: **PR-only with best-effort CI awareness**.
