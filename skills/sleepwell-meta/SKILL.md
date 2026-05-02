---
name: sleepwell-meta
description: Use during sleepwell-loop bootstrap to generate a calibration based on previous runs. v2 consumes `sleepwell-helper calibrate` and persists prediction_profile in state.json; graceful fallback keeps the legacy textual calibration.md.
---

# sleepwell-meta (v2)

> **Lockfile guard.** Before operating, check `.sleepwell/ci-lock`: if it
> exists and contains a live pid DIFFERENT from the current pid, refuse
> (`sleepwell-meta: lock owned by pid <X>`). If absent or pid is dead,
> ok. See `lib/ritual.md §10`.

Lightweight meta-learning for sleepwell. On bootstrap (and on explicit request), reads the
history of previous sleepwell runs and produces **two artifacts**:

1. **`state.prediction_profile`** (structured, v3) — consumed by
   `sleepwell-loop` to influence the iteration prompts.
2. **`.sleepwell/calibration.md`** (textual, legacy) — kept as a
   human-readable fallback when the Rust helper is unavailable.

## When to activate

- `sleepwell-loop` bootstrap (1st iter), if `--no-meta` is not passed.
- Explicit user request: "update calibration".

## Preferred pipeline — `sleepwell-helper calibrate`

```bash
if command -v sleepwell-helper >/dev/null 2>&1; then
  profile_json=$(sleepwell-helper calibrate \
    --archive .sleepwell/archive/ \
    --repo .)
fi
```

Expected output (JSON on stdout, saved into `state.prediction_profile`):

```json
{
  "overall": 0.72,
  "by_category": {
    "feat":    0.81,
    "fix":     0.65,
    "refactor":0.50,
    "tidy":    0.90,
    "refine":  0.74,
    "build":   0.60
  },
  "trusted":   ["tidy", "feat"],
  "distrusted":["radical", "refactor"],
  "n_runs": 12,
  "calibrated_at": "2026-05-02T15:42:00-03:00"
}
```

`overall` = % of commits approved by the user (kept on base, not
discarded). `by_category` breaks down by mode and/or conventional type.
`trusted`/`distrusted` come from the top/bottom of `by_category` (default thresholds
≥0.75 trusted, ≤0.55 distrusted).

## Atomic persistence

```bash
tmp=$(mktemp .sleepwell/state.json.XXXXXX)
jq --argjson p "$profile_json" '.prediction_profile = $p' \
   .sleepwell/state.json > "$tmp"
mv "$tmp" .sleepwell/state.json
```

See `lib/ritual.md §7.2`.

## Loop prompt injection

On each iter, `sleepwell-loop` queries `state.prediction_profile` and injects
into the prompt:

- If `state.mode in trusted` → add line:
  `## Calibration\n- Mode "<mode>" has positive history (accuracy <X>%, n=<N>).
  Depth is encouraged.`
- If `state.mode in distrusted` → add line:
  `## Calibration\n- Mode "<mode>" has negative history (accuracy <X>%, n=<N>).
  Caution: prefer small, reversible diffs.`
- If `state.mode` is in neither → omit section (insufficient signal).

## Graceful fallback — no helper

When `command -v sleepwell-helper` fails:

1. Do **NOT** try to replicate git log parsing in bash (the v1 version did this
   via grep — removed in v2 because it was fragile and duplicated helper logic).
2. Keep the legacy textual behavior in `.sleepwell/calibration.md`:
   - If `.sleepwell/calibration.md` already exists (from a previous run), just read it
     and pass it through to the caller.
   - If absent, create a minimal version:
     ```markdown
     # Calibration — extracted on <ISO>
     _sleepwell-helper unavailable; structured calibration skipped._

     No per-category signals. Loop runs without profile adjustment.
     ```
3. Do **NOT** write `state.prediction_profile` in fallback (leave the field
   absent — the loop treats absence as neutral).

Log `meta: helper missing, prediction_profile skipped` in notes.md.

## Limits and edge cases

- No `.sleepwell/archive/` or freshly-initialized repo: helper returns
  `n_runs: 0`; persist the profile anyway, and the loop treats `n_runs < 3`
  as "no signal" (does not inject).
- Very old runs (>60 days): the helper already weights them lower; the skill
  just trusts the output.
- Privacy: all local. Nothing leaves the disk.

## Short output for the caller

After persisting, return a 1-line string:
`"meta: prediction_profile updated (overall=X%, n=N, trusted=[...], distrusted=[...])"`.

In fallback: `"meta: helper missing, textual calibration retained"`.

## When NOT to calibrate

- `--no-meta` flag on `/sleepwell:sleepwell` → skip entirely.
- `state.prediction_profile.calibrated_at` < 24h → reuse existing.
