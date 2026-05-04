# sleepwell-team — multi-agent workflow

> **Authoritative source.** Canonical reference for the team workflow.
> The `sleepwell-team` skill and `/sleepwell:sleepwell-team-fix` command
> reference this document instead of duplicating logic. Behavior changes
> begin here.

## §1. Philosophy

The standard sleepwell loop excels at **driving an isolated branch to a
green commit**. Shipping that change still requires a series of human
ceremonies: opening the PR, reading the diff, asking for fixes, watching
CI, merging, optionally cutting a release. The team workflow encodes
those ceremonies as a deterministic chain of agents, so a single intent
can flow from idea to merged commit without the operator manually
context-switching between roles.

Three properties guide the design:

1. **Composition over reimplementation.** Each phase delegates to an
   existing primitive (`sleepwell-loop`, `/sleepwell:sleepwell-pr`,
   `gh`). The team skill is a coordinator, not a new engine.
2. **Configurable, not opinionated.** Defaults ship in
   `team.config.example.yaml`, but every step is opt-out. Teams
   without a release flow simply leave `post_merge: [{type: none}]`.
3. **Auditable.** State is persisted in `.sleepwell/team-state.json`
   between phases, every reviewer/fixer interaction lives on the PR as
   a real comment thread, and CI gating uses GitHub's required checks
   API — there is no parallel ledger to reconcile.

## §2. Personas

### Implementer

Runs `sleepwell-loop` with the user-provided intent, mode and
`max_iter`. Operates exactly as the standalone loop: isolated branch,
atomic commit per iter, rollback on failure. Hands control back when
the loop's status becomes `done` (or aborts upstream).

### Reviewer

A subagent dispatched after the PR exists. Receives the full PR diff
(scoped per `review.scope`) and a severity rubric, and emits a single
GitHub review per round. Does **not** modify code. Outputs:

- `APPROVE` when no comments at/above `review.block_on_severity`.
- `REQUEST_CHANGES` with line-level comments otherwise.

### Fixer

A subagent activated only when there are unresolved review comments
and `fix.enabled = true`. Reads the comment list, applies code edits
to the PR branch, creates one commit per round
(`fix(review): address round N comments`), pushes, and optionally
replies on each thread with the resolving SHA.

### CI-Watcher

A non-LLM agent: it polls `gh pr checks` (or watches branch protection
required checks) until success, failure, or timeout. Fail-fast aborts
on first required-check failure when `ci.fail_fast = true`.

### Post-Merge (optional)

Runs configured actions in order after merge succeeds. Built-in action
types: `dispatch_workflow`, `run_command`, `shell`, `none`. Errors are
recorded but do not roll back the merge.

## §3. Macro flow

```
                    ┌──────────────┐
                    │  Implementer │ (sleepwell-loop)
                    └──────┬───────┘
                           │ status=done
                           ▼
                    ┌──────────────┐
                    │   PR creator │ (/sleepwell:sleepwell-pr)
                    └──────┬───────┘
                           ▼
       ┌───────────────────────────────────────┐
       │     Reviewer ──comments──► Fixer      │ rounds 1..N
       │       ▲                       │       │
       │       └──── re-review ◄───────┘       │
       └───────────────────────────────────────┘
                           │ approved or rounds-exhausted
                           ▼
                    ┌──────────────┐
                    │  CI-Watcher  │ (gh pr checks --watch)
                    └──────┬───────┘
                           │ green
                           ▼
                    ┌──────────────┐
                    │     Merge    │ (gh pr merge)
                    └──────┬───────┘
                           ▼
                    ┌──────────────┐
                    │  Post-Merge  │ (workflow / command / shell / none)
                    └──────────────┘
```

## §4. Reviewer protocol

### Severity rubric

| Severity | Examples |
|---|---|
| `high` | correctness, security, data loss, missing tests for new behavior |
| `medium` | maintainability, performance regressions, unclear naming |
| `low` | style nits, redundant comments, minor doc gaps |

`review.block_on_severity` selects the threshold that triggers
`REQUEST_CHANGES`. Comments below the threshold are still posted but do
not block.

### REST payload

A single POST per round at `repos/$OWNER/$REPO/pulls/$PR/reviews`:

```json
{
  "event": "REQUEST_CHANGES",
  "body": "Automated review (round 1)",
  "comments": [
    {
      "path": "src/auth/oauth.ts",
      "line": 42,
      "side": "RIGHT",
      "body": "**[high]** Missing PKCE verifier validation before token exchange."
    },
    {
      "path": "src/auth/oauth.ts",
      "start_line": 70,
      "start_side": "RIGHT",
      "line": 88,
      "side": "RIGHT",
      "body": "**[medium]** Extract redirect URL builder for testability."
    }
  ]
}
```

`start_line` is used for multi-line comments; `position` is avoided in
favor of `line` because it is stable across diff updates.

### Scope

| `scope` value | Behavior |
|---|---|
| `changed-files` (default) | Only the files in the PR diff |
| `full-pr` | All commits in the PR, including unmodified context for surrounding files |
| `branch-vs-base` | `git diff $base...$head` independent of GitHub's diff view |

## §5. Fixer protocol

1. Fetch unresolved comments:
   ```bash
   gh api "repos/$OWNER/$REPO/pulls/$PR/comments" \
     --jq '.[] | select(.in_reply_to_id == null)'
   ```
2. For each comment, decide an action: `apply`, `defer-with-reply`,
   or `reject-with-reply`. Only `high`-severity comments are eligible
   for `defer`/`reject` when `block_on_severity = high`.
3. Group `apply` actions, edit the worktree, run local verify
   (lint + types + tests). If verify fails, drop changes and reply
   `defer-with-reply: verify failed locally`.
4. Commit:
   ```
   fix(review): address round N comments
   ```
5. Push to PR branch.
6. Reply on each thread (when `reply_to_threads = true`):
   ```bash
   gh api -X POST \
     "repos/$OWNER/$REPO/pulls/$PR/comments/$COMMENT_ID/replies" \
     -f body="Addressed in $(git rev-parse --short HEAD)."
   ```

A round is considered **answered** when every blocking comment has
either an `apply` commit or an explicit reply. Threads can also be
resolved via the GraphQL `resolveReviewThread` mutation when the
GitHub repo enforces resolution gating.

## §6. CI gate

### Polling

Default — `gh pr checks $PR --watch --required --interval $poll`.
Manual fallback (when `--watch` unsupported):

```bash
end=$(( $(date +%s) + 60 * MAX_WAIT ))
while [ "$(date +%s)" -lt "$end" ]; do
  rollup=$(gh pr view "$PR" --json statusCheckRollup \
    -q '[.statusCheckRollup[] | {name, conclusion, status}]')
  # … evaluate …
  sleep "$poll_interval_secs"
done
```

### Required checks

When `required_checks` is empty, the workflow consults branch
protection (`gh api repos/$OWNER/$REPO/branches/$BASE/protection`) and
requires the same set. Setting `required_checks` explicitly overrides
that — useful when working against a base branch without protection.

### Retry policy

There is no automatic retry of CI runs from the team workflow. If a
required check fails, the run finalizes `ci_failed` and leaves the PR
open with a comment explaining the failure. The user (or another
sleepwell run) decides whether to push a fix.

## §7. Merge protocol

| `merge.strategy` | `gh pr merge` flag |
|---|---|
| `squash` (default) | `--squash` |
| `merge` | `--merge` |
| `rebase` | `--rebase` |

`merge.delete_branch = true` adds `--delete-branch`. When
`merge.auto_merge = true`, the skill calls `gh pr merge --auto $flag`
instead of waiting locally — it relinquishes control to GitHub once
the PR satisfies branch protection. In that case the team-state
phase moves to `awaiting_auto_merge` and the run completes without
post-merge hooks (because the merge happens server-side, possibly
much later).

Conflicts during merge raise `merge_conflict`. The skill never resolves
conflicts unattended.

## §8. Post-merge hooks

Configured as an ordered list under `post_merge:`. Each entry is an
object with at least `type`. Built-in types:

- **`dispatch_workflow`** — `gh workflow run <workflow> -f k=v …`.
  Useful for triggering bump/release pipelines after merge.
- **`run_command`** — invokes a sleepwell command in the same session
  (`/sleepwell:sleepwell-recap`, `/sleepwell:sleepwell-suggest`, etc.).
- **`shell`** — runs a literal shell command. Must match the
  allowlist in `post_merge.allowed_shell` (regex). Disabled by default.
- **`none`** — explicit no-op (recommended default for teams without
  release automation).

Errors are accumulated into `team-state.post_merge_errors[]` and the
final status becomes `merged_with_post_merge_errors` instead of
`done` — but the merge itself is **not** rolled back.

## §9. State persistence

`.sleepwell/team-state.json` is the single source of truth between
phases:

```json
{
  "run_id": "team-2026-05-03-abcd",
  "intent": "implement OAuth2 with PKCE",
  "mode": "build",
  "branch": "sleepwell/oauth2-pkce",
  "pr_number": 142,
  "pr_url": "https://github.com/owner/repo/pull/142",
  "phase": "review",
  "current_round": 1,
  "max_review_rounds": 2,
  "ci_timeout_minutes": 30,
  "post_merge_action": "none",
  "review_comments_seen": [123, 124, 125],
  "ci_status": "pending",
  "merged_sha": null,
  "post_merge_errors": [],
  "started_at": "2026-05-03T22:00:00Z",
  "updated_at": "2026-05-03T22:14:00Z"
}
```

Writes are atomic (`mktemp` + `mv`). The file is added to
`.gitignore` along with the rest of `.sleepwell/`.

The team-state references the loop's `state.json` via `branch`. The two
files coexist: the loop owns iteration data; the team owns the
post-loop pipeline.

## §10. Configuration via YAML

Defaults ship in `.sleepwell/team.config.example.yaml` (copy into
`.sleepwell/team.config.yaml` and edit). Resolution order:

1. CLI flags on `/sleepwell:sleepwell-team-fix`.
2. `--config <path>` if provided.
3. `.sleepwell/team.config.yaml` in the repo.
4. Defaults from `team.config.example.yaml`.

YAML values can be partially overridden — missing keys fall back to
the next layer. Validation:

- `review.max_rounds` must be `>= 1`.
- `ci.max_wait_minutes` must be `>= 1`.
- `merge.strategy` must be one of `squash | merge | rebase`.
- `post_merge[].type` must be one of the documented types.

The team skill validates the merged config at startup and aborts with
a descriptive error before any agent is dispatched.
