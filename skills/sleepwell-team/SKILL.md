---
name: sleepwell-team
description: Orchestrates multi-agent PR workflow — implement → PR → review → fix → CI → merge → optional post-merge. Use when you want a coordinated team-of-agents to ship a change end-to-end.
---

# sleepwell-team

Coordinates a multi-agent workflow on top of the existing sleepwell primitives.
Activated by `/sleepwell:sleepwell-team-fix "<intent>" [opts]`.

> **Authoritative flow:** `lib/team-workflow.md`. This skill **implements** the
> ritual described there — when in doubt, the lib file wins.

## Architecture

Four coordinated agents, plus an optional fifth:

| Agent | Role | Tooling |
|---|---|---|
| Implementer | Drives `sleepwell-loop` until status `done` (or aborted). | `sleepwell-loop` skill |
| Reviewer | Inspects PR diff and posts line-level review comments. | `gh api` (REST reviews endpoint) |
| Fixer | Reads review comments, applies changes, replies in-thread. | Edit/Write + `gh api` replies |
| CI-Watcher | Polls PR checks until green or timeout. | `gh pr checks --watch` |
| Post-Merge (optional) | Runs configured action after merge succeeds. | Workflow dispatch / shell / sleepwell command |

## Activation

- User invokes `/sleepwell:sleepwell-team-fix`.
- Or another skill explicitly delegates orchestration here.

## Inputs

Forwarded from the command:

```
<intent>                  required
--mode <m>                forwarded to sleepwell-loop
--max-iter <N>            forwarded to sleepwell-loop
--no-review               skip review phase
--no-fix                  skip fixer (review-only)
--max-review-rounds <N>   default 2
--ci-timeout <minutes>    default 30
--no-merge                stop after CI green
--post-merge <action>     overrides config
--config <path>           alternative team.config.yaml
```

Plus `.sleepwell/team.config.yaml` (or `--config`). See
`.sleepwell/team.config.example.yaml`.

## Persisted state — `.sleepwell/team-state.json`

```json
{
  "run_id": "team-2026-05-03-abcd",
  "intent": "implement OAuth2 with PKCE",
  "mode": "build",
  "branch": "sleepwell/oauth2-pkce",
  "pr_number": 142,
  "pr_url": "https://github.com/owner/repo/pull/142",
  "phase": "review|fix|ci|merge|post_merge|done|aborted",
  "current_round": 1,
  "max_review_rounds": 2,
  "ci_timeout_minutes": 30,
  "post_merge_action": "none",
  "review_comments_seen": [123, 124, 125],
  "ci_status": "pending|success|failure",
  "merged_sha": null,
  "started_at": "2026-05-03T22:00:00Z",
  "updated_at": "2026-05-03T22:14:00Z"
}
```

The file lives next to `state.json` — both can coexist (the loop's state is
referenced by the team state via `branch`).

## Pseudocode (high level)

```
parse_args()
config = load_config(args.config or ".sleepwell/team.config.yaml")
state  = init_team_state(args, config)

# 1. Implement
invoke_skill("sleepwell-loop", intent=state.intent, mode=state.mode,
             max_iter=state.max_iter)
wait_until(loop_status in {"done", "aborted"})
if loop_status != "done": finalize("aborted_implement"); return

# 2. PR
run_command("/sleepwell:sleepwell-pr")
state.pr_number = extract_pr_number_from(loop_state.pr_url)
persist(state)

# 3. Review/Fix rounds
if config.review.enabled and not args.no_review:
  for round in 1..config.review.max_rounds:
    state.phase = "review"; state.current_round = round; persist(state)
    review_comments = run_reviewer(state.pr_number, config.review)
    if not review_comments: break  # reviewer approved
    if not config.fix.enabled or args.no_fix: break
    state.phase = "fix"; persist(state)
    run_fixer(state.pr_number, review_comments, config.fix)

# 4. CI gate
if not args.no_merge:
  state.phase = "ci"; persist(state)
  ci_ok = poll_ci(state.pr_number, config.ci, args.ci_timeout)
  if not ci_ok: finalize("ci_failed"); return

  # 5. Merge
  state.phase = "merge"; persist(state)
  merge_pr(state.pr_number, config.merge)

  # 6. Post-merge
  state.phase = "post_merge"; persist(state)
  for action in resolve_post_merge(config, args):
    dispatch_post_merge(action)

finalize("done")
```

## Reviewer protocol

The Reviewer is dispatched as a subagent (`config.review.agent`,
`general-purpose` by default). It is given:

- The PR number and base/head SHAs.
- The diff (`gh pr diff $PR`) limited by `config.review.scope`.
- A review rubric (severity levels: `low`, `medium`, `high`).

It must output a JSON array of comments and submit them as a single review
via:

```bash
gh api \
  -X POST \
  -H "Accept: application/vnd.github+json" \
  "repos/$OWNER/$REPO/pulls/$PR/reviews" \
  -f event="REQUEST_CHANGES" \
  -f body="Automated review (round $ROUND)" \
  --input - <<'JSON'
{
  "comments": [
    { "path": "src/auth/oauth.ts", "line": 42, "side": "RIGHT",
      "body": "**[high]** Missing PKCE verifier validation before token exchange." },
    { "path": "src/auth/oauth.ts", "line": 88, "side": "RIGHT",
      "body": "**[medium]** Consider extracting redirect URL builder for testability." }
  ]
}
JSON
```

If `block_on_severity` is `none` or no comments meet the threshold, the
Reviewer submits `event=APPROVE` and the loop exits the round.

## Fixer protocol

The Fixer receives the list of unresolved review comments (`gh api
repos/$OWNER/$REPO/pulls/$PR/comments`) and:

1. Applies edits to the worktree.
2. Commits as `fix(review): address round N comments` (one commit per round).
3. Pushes to the PR branch.
4. For each addressed comment, posts a reply on the same thread:

```bash
gh api \
  -X POST \
  -H "Accept: application/vnd.github+json" \
  "repos/$OWNER/$REPO/pulls/$PR/comments/$COMMENT_ID/replies" \
  -f body="Addressed in $(git rev-parse --short HEAD)."
```

When `config.fix.reply_to_threads = false`, the Fixer pushes the commit but
does not reply (the next reviewer round will re-evaluate).

## CI-Watcher protocol

```bash
gh pr checks "$PR" --watch --interval "$POLL" --required \
  || ci_failed=1
```

Falls back to a manual loop when `--watch` is unavailable:

```bash
end=$(( $(date +%s) + 60 * MAX_WAIT ))
while [ "$(date +%s)" -lt "$end" ]; do
  status=$(gh pr view "$PR" --json statusCheckRollup -q \
    '[.statusCheckRollup[].conclusion] | unique | join(",")')
  case "$status" in
    *FAILURE*|*CANCELLED*|*TIMED_OUT*) ci_failed=1; break ;;
    *SUCCESS*) [[ "$status" != *PENDING* ]] && break ;;
  esac
  sleep "$POLL"
done
```

`required_checks` from config can pin specific check names; otherwise the
detected branch protection rules are used.

## Merge protocol

```bash
case "$config.merge.strategy" in
  squash)  flag="--squash" ;;
  rebase)  flag="--rebase" ;;
  merge)   flag="--merge"  ;;
esac
delete_flag=""
[ "$config.merge.delete_branch" = "true" ] && delete_flag="--delete-branch"
gh pr merge "$PR" $flag $delete_flag
```

When `config.merge.auto_merge` is true the skill instead enables GitHub
auto-merge (`gh pr merge --auto $flag`) and exits without polling locally.

## Post-merge dispatch

Each action in `config.post_merge` (or `--post-merge` override) runs in
order. Built-in types:

- `dispatch_workflow` → `gh workflow run <workflow> -f key=value …`
- `run_command` → invoke `/sleepwell:<command>` with provided args
- `shell` → run a shell command (must match `post_merge.allowed_shell`)
- `none` → no-op

A failure in post-merge does **not** roll back the merge; the skill
records it under `state.post_merge_errors[]` and finalizes with
`status = "merged_with_post_merge_errors"`.

## Round termination

A round ends when either:

- Reviewer submits `APPROVE` (no comments at/above `block_on_severity`), or
- `current_round == max_review_rounds`.

If the cap is hit while comments remain, the skill finalizes
`status = "review_unresolved"` and leaves the PR unmerged (unless
`--no-merge` was already implied).

## Failure handling

- Implementer aborts → no PR created; team-state finalized as `aborted_implement`.
- Review API errors → retry with exponential backoff (3 attempts) before
  marking the round as `review_error` and stopping.
- CI timeout → `ci_failed`; PR left open with explanatory comment.
- Merge conflict during merge → finalize `merge_conflict`; user resolves
  manually.

## Composition

This skill does not re-implement the loop, the PR creation or the verify
ritual. It composes the existing sleepwell skills and `gh` CLI calls. New
behavior should land in `lib/team-workflow.md` first, then be referenced
from here.
