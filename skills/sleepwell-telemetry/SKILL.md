---
name: sleepwell-telemetry
description: v2 — collects tokens/cost via sleepwell-helper (Rust) with multi-LLM detection (claude/codex/gemini); bash+jq fallback when the helper is unavailable. Updates state.tokens_used, state.cost_so_far_usd and triggers the cost abort gate.
---

# sleepwell-telemetry (v2)

> **Lockfile guard.** Before operating, check `.sleepwell/ci-lock`: if it
> exists and contains a live pid DIFFERENT from the current pid, refuse
> (`sleepwell-telemetry: lock owned by pid <X>`). If absent or pid is dead,
> ok. See `lib/ritual.md §10`.

Collects usage telemetry (tokens consumed, cost derived in USD) from the
active runtime where the sleepwell loop is running. Updates
`.sleepwell/state.json` at the end of each iteration — before the cost
abort gate (`§8.1` in `lib/ritual.md`).

State output:

- `state.tokens_used.{input, output, cache_read, cache_creation}` (cumulative)
- `state.cost_so_far_usd` (cumulative, computed from tokens)

## Runtime detection

```bash
detect_runtime() {
  if [ -n "${CLAUDE_CODE_VERSION:-}" ] || [ -d "$HOME/.claude/projects" ]; then
    echo claude
  elif command -v codex >/dev/null 2>&1 && [ -d "$HOME/.codex/sessions" ]; then
    echo codex
  elif command -v gemini >/dev/null 2>&1 && [ -d "$HOME/.gemini" ]; then
    echo gemini
  else
    echo unknown
  fi
}
```

In a hybrid environment, prefers Claude when `CLAUDE_CODE_VERSION` is present.

## Locating the active JSONL (most recent by mtime)

```bash
case "$RUNTIME" in
  claude)
    slug=$(pwd | sed 's@/@-@g')
    DIR="$HOME/.claude/projects/$slug"
    ;;
  codex)  DIR="$HOME/.codex/sessions"  ;;
  gemini) DIR="$HOME/.gemini/sessions" ;;
  *)      DIR=""                        ;;
esac
JSONL=$(ls -t "$DIR"/*.jsonl 2>/dev/null | head -1)
```

## Preferred pipeline — `sleepwell-helper`

When the Rust binary is available, delegate parsing and computation:

```bash
MODEL=$(jq -r '.model // "claude-sonnet-4-5"' .sleepwell/state.json)

if command -v sleepwell-helper >/dev/null 2>&1 && [ -n "$JSONL" ]; then
  result=$(sleepwell-helper parse-jsonl "$JSONL" --format "$RUNTIME" \
           | sleepwell-helper cost --model "$MODEL")
  # result: {"tokens_used":{...}, "cost_usd": <float>}
fi
```

`parse-jsonl` extracts `usage` per turn in the detected format; `cost` applies
the helper's pricing table (kept in `bin/sleepwell-helper/prices.toml`).

## Fallback — bash + jq

When `command -v sleepwell-helper` fails, emit a visible warning and use
inline parsing (legacy v1):

```bash
if ! command -v sleepwell-helper >/dev/null 2>&1; then
  echo "warning: sleepwell-helper unavailable — using legacy bash parser" >&2

  sum_tokens() {
    jq -s '
      map(.usage // {})
      | reduce .[] as $u (
          {input:0,output:0,cache_read:0,cache_creation:0};
          .input          += ($u.input_tokens // 0)              |
          .output         += ($u.output_tokens // 0)             |
          .cache_read     += ($u.cache_read_input_tokens // 0)   |
          .cache_creation += ($u.cache_creation_input_tokens // 0)
        )
    '
  }

  if [ "$RUNTIME" = "claude" ] && [ -n "$JSONL" ]; then
    tokens=$(jq -c '.message // .' "$JSONL" 2>/dev/null | sum_tokens)
  elif [ "$RUNTIME" = "codex" ]; then
    if codex usage --json >/dev/null 2>&1; then
      tokens=$(codex usage --json | sum_tokens)
    else
      tokens=$(cat "$HOME"/.codex/sessions/*.jsonl 2>/dev/null | sum_tokens)
    fi
  elif [ "$RUNTIME" = "gemini" ] && [ -n "$JSONL" ]; then
    tokens=$(jq -c '.message // .' "$JSONL" 2>/dev/null | sum_tokens)
  else
    echo "telemetry: unknown runtime, skipping" >&2
    exit 0
  fi

  # Default pricing (Sonnet 4.5). See bin/sleepwell-helper/prices.toml.
  P_IN=3 P_OUT=15 P_CR=0.30 P_CC=3.75
  cost=$(jq -n \
    --argjson t "$tokens" \
    --argjson pin "$P_IN" --argjson pout "$P_OUT" \
    --argjson pcr "$P_CR" --argjson pcc "$P_CC" \
    '($t.input*$pin + $t.output*$pout + $t.cache_read*$pcr + $t.cache_creation*$pcc)/1e6')

  result=$(jq -n --argjson t "$tokens" --argjson c "$cost" \
    '{tokens_used:$t, cost_usd:$c}')
fi
```

## Atomic state write

```bash
tokens=$(printf '%s\n' "$result" | jq '.tokens_used')
cost=$(printf '%s\n' "$result"  | jq '.cost_usd')

tmp=$(mktemp .sleepwell/state.json.XXXXXX)
jq --argjson tu "$tokens" --argjson cost "$cost" \
   '.tokens_used = $tu | .cost_so_far_usd = $cost' \
   .sleepwell/state.json > "$tmp"
mv "$tmp" .sleepwell/state.json
```

See `lib/ritual.md §7.2`.

## Cost abort gate

After updating the state, the loop evaluates (see `lib/ritual.md §8.1`):

```
if state.cost_budget_usd != null and
   state.cost_so_far_usd  >= state.cost_budget_usd
   → finalize("cost", abort_reason="cost budget reached")
```

The skill **collects**. The decision to abort lives in `sleepwell-loop`. When the
skill detects `cost_so_far_usd >= cost_budget_usd`, it **must** signal via
non-zero exit code + stderr message, so the loop handles the abort gate
unambiguously.

## Pricing table

For the preferred pipeline, the table lives in
`bin/sleepwell-helper/prices.toml` (update there when prices change). The
fallback uses inline defaults for Sonnet 4.5; review quarterly.

| Model                       | input | output | cache_read | cache_creation |
|-----------------------------|-------|--------|------------|----------------|
| Claude Sonnet 4.5           | 3.00  | 15.00  | 0.30       | 3.75           |
| Claude Haiku 4.5            | 1.00  | 5.00   | 0.10       | 1.25           |
| GPT-5 / Codex (placeholder) | 0     | 0      | 0          | 0              |
| Gemini 2.5 Pro (placeholder)| 0     | 0      | 0          | 0              |

Unmapped models → cost 0 + warning `unknown=true`.
