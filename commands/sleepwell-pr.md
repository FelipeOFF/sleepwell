---
description: Creates a PR from the active sleepwell branch with a structured body.
---

# /sleepwell:sleepwell-pr

Creates a pull request from the current sleepwell branch against the detected
base branch (`sleepwell_base_branch` — see `lib/ritual.md §7.1`). The body includes
a structured summary: intent, mode, iters, passes/fails, USD cost, last evaluator
rating, and list of commits.

## Preconditions

- `.sleepwell/state.json` exists and has `branch` set.
- Branch was pushed to remote (otherwise, runs `git push -u origin <branch>` first).
- `gh` CLI authenticated.

## Behavior

```bash
state=".sleepwell/state.json"
branch=$(jq -r '.branch' "$state")
intent=$(jq -r '.intent' "$state")
mode=$(jq -r '.mode' "$state")
iter=$(jq -r '.iteration' "$state")
passes=$(jq -r '.total_passes' "$state")
fails=$(jq -r '.total_fails' "$state")
cost=$(jq -r '.cost_so_far_usd // 0' "$state")
rating=$(jq -r '.last_eval.rating // "n/a"' "$state")
pr_mode=$(jq -r '.pr_mode // "auto"' "$state")
base=$(sleepwell_base_branch)

# title derived from intent (truncated ~70 chars).
title="sleepwell: ${intent:0:60}"

# body
commits=$(git log --oneline "$base..$branch")
body=$(cat <<EOF
## Sleepwell run

- **Intent:** $intent
- **Mode:** $mode
- **Iterations:** $iter ($passes pass / $fails fail)
- **Cost USD:** $cost
- **Last rating (evaluator):** $rating

## Commits

\`\`\`
$commits
\`\`\`

---

> Auto-merge disabled by default. To enable conditional server-side
> merge, manually apply the \`sleepwell-auto-merge\` label —
> an external GitHub Action (not included in this plugin) should consume
> the label and merge when CI passes.
EOF
)

# push + create
git push -u origin "$branch" 2>/dev/null || true

draft_flag=""
[ "$pr_mode" = "draft" ] && draft_flag="--draft"

pr_url=$(gh pr create \
  --base "$base" \
  --head "$branch" \
  --title "$title" \
  --body "$body" \
  $draft_flag)

# persist in state.json (atomic)
tmp=$(mktemp .sleepwell/state.json.XXXXXX)
jq --arg url "$pr_url" '.pr_url = $url' "$state" > "$tmp"
mv "$tmp" "$state"

echo "PR created: $pr_url"
```

## Auto-merge (reference, not implemented)

The `sleepwell-auto-merge` label, when manually applied to the created PR,
serves as a signal to an external GitHub Action configured in the repo
(server-side). The Action observes the `labeled` event and, if CI is
green, runs `gh pr merge --auto`. This logic lives **outside** the
sleepwell plugin — the plugin only documents the convention.

## Common errors

- `gh` not authenticated → clear failure: ask for `gh auth login`.
- Branch with no new commits vs base → aborts with warning.
- PR already exists for the branch → shows existing URL, updates `state.pr_url`.
