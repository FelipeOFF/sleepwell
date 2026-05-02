---
name: sleepwell-evaluator
description: Heuristically evaluates each iteration via sleepwell-helper evaluate; persists rating/observation/course_correct in state.last_eval and injects into the next prompt.
---

# sleepwell-evaluator

> **Lockfile guard.** Before operating, check `.sleepwell/ci-lock`: if it
> exists and contains a live pid DIFFERENT from the current pid, refuse
> (`sleepwell-evaluator: lock owned by pid <X>`). If absent or pid is dead,
> ok. See `lib/ritual.md §10`.

Lightweight heuristic evaluation per iteration. Runs **after verify and before/alongside telemetry** (see `lib/ritual.md §3`). Produces a short rating (1–5), a textual observation and a `course_correct` boolean indicating whether the next iter should adjust course.

The skill **collects** signals. The decision to escalate (switch mode, abort) lives in `sleepwell-loop` based on what is persisted in `state.last_eval`.

## When to activate

- Every `sleepwell-loop` iteration, after verify (PASS or FAIL).
- Explicit request: "evaluate the last iter".

## Preferred pipeline — `sleepwell-helper evaluate`

```bash
DIFFSTAT=$(git diff --stat "$(sleepwell_base_branch)"..HEAD)
sleepwell-helper evaluate \
  --state .sleepwell/state.json \
  --diff-stat <(printf '%s\n' "$DIFFSTAT") \
  --last-notes .sleepwell/notes.md
```

Expected output (JSON on stdout):

```json
{
  "rating": 4,
  "observation": "focused iter, 1 file, green tests",
  "course_correct": false,
  "evaluated_at": "2026-05-02T15:42:00-03:00"
}
```

## Fallback — minimal bash heuristic

When `sleepwell-helper` is not available (`command -v sleepwell-helper` fails), produce an equivalent JSON via heuristic:

```bash
if command -v sleepwell-helper >/dev/null 2>&1; then
  eval_json=$(sleepwell-helper evaluate \
    --state .sleepwell/state.json \
    --diff-stat <(git diff --stat "$(sleepwell_base_branch)"..HEAD) \
    --last-notes .sleepwell/notes.md)
else
  BASE=$(sleepwell_base_branch)
  STAT=$(git diff --stat "$BASE"..HEAD 2>/dev/null || echo "")
  LAST_STATUS=$(tail -n 30 .sleepwell/notes.md | grep -E '^\- (PASS|FAIL)' | tail -1)

  rating=3
  course_correct=false
  observation="fallback heuristic (helper missing)"

  case "$LAST_STATUS" in
    *PASS*)
      files=$(printf '%s\n' "$STAT" | tail -1 | grep -oE '[0-9]+ files?' | awk '{print $1}')
      if [ -n "$files" ] && [ "$files" -le 3 ]; then
        rating=5
        observation="clean PASS, ${files} file(s) touched"
      else
        rating=4
        observation="PASS, wide diff"
      fi
      ;;
    *FAIL*)
      rating=2
      course_correct=true
      observation="FAIL — suggest course correction"
      ;;
  esac

  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  eval_json=$(jq -n \
    --argjson r "$rating" \
    --arg o "$observation" \
    --argjson c "$course_correct" \
    --arg t "$ts" \
    '{rating:$r, observation:$o, course_correct:$c, evaluated_at:$t}')
fi
```

## Atomic persistence

Write `state.last_eval` via tmpfile + rename (see `lib/ritual.md §7.2`):

```bash
tmp=$(mktemp .sleepwell/state.json.XXXXXX)
jq --argjson e "$eval_json" '.last_eval = $e' .sleepwell/state.json > "$tmp"
mv "$tmp" .sleepwell/state.json
```

`state.last_eval` follows the schema defined in `lib/state-schema.json` (v3, optional):

```json
{
  "rating": 1..5,
  "observation": "short string",
  "course_correct": false,
  "evaluated_at": "RFC3339"
}
```

## Injection into the next iteration prompt

`sleepwell-loop` (see `lib/ritual.md §3` step `[prompt]`) must add, when `state.last_eval` is present:

```markdown
## Previous evaluation
- Rating: <X>/5
- Observation: <observation>
- Suggested course correction: <true|false>
```

This goes **before** `git diff --stat`, after voice profile/calibration.

## Escalation on persistent course correction

If `course_correct == true` for **2 consecutive iters**, the loop must escalate:

1. If `state.mode == "refine"` → switch to `tidy` (more conservative mode) and warn in notes.md: `mode escalation: refine → tidy (2× course_correct)`.
2. If already in `tidy` or another conservative mode → request abort with `abort_reason="evaluator: course_correct sustained"`.

Detection works by reading the current `state.last_eval.course_correct` and comparing with the previous iter's mark (which can be persisted in `state.last_eval_prev` if needed, or inferred from the tail of `notes.md` where the skill records each evaluation).

## Privacy

- Evaluation runs 100% local. Nothing leaves the disk.
- Do not include sensitive paths in the observation.

## When NOT to evaluate

- `state.dry_run == true` → still evaluate (informative), but the loop may ignore `course_correct` for decisions.
- Iter 0 (bootstrap) → nothing to evaluate; skip.
