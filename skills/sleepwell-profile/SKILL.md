---
name: sleepwell-profile
description: Use to extract or update the structured user voice profile from the JSONL transcripts of the active runtime (claude/codex/gemini). Persists JSON in .sleepwell/voice-profile.json. 7-day cache. No external dependencies — just bash + jq.
---

# sleepwell-profile (structured)

Extracts a **structured voice profile** of the user by reading the JSONL transcripts
of the active runtime (Claude Code, Codex CLI or Gemini CLI). The profile is injected
into `sleepwell-loop` iterations so that changes sound like the user would
write them.

The skill is **standalone**: uses only `bash` + `jq`, without calling other skills
or external APIs.

## When to activate

- `sleepwell-loop` bootstrap (1st iter), if `--no-voice` is not passed.
- `.sleepwell/voice-profile.json` cache absent OR older than 7 days.
- Explicit request: "update the sleepwell voice profile".

## Profile schema (`.sleepwell/voice-profile.json`)

```json
{
  "tone": "direct|warm|terse|verbose|mixed",
  "message_length": "short|medium|long",
  "linguistic_patterns": [
    "uses 'pls' regularly",
    "mixes PT-BR with English technical terms",
    "cites file:line grep-style"
  ],
  "values_and_priorities": [
    "pragmatism",
    "type-safety",
    "green tests before merge"
  ],
  "vocabulary_examples": [
    "worktree",
    "atomic commit",
    "green",
    "clean rebase"
  ],
  "extracted_at": "2026-05-02T15:42:00-03:00",
  "source_runtime": "claude|codex|gemini",
  "n_messages_analyzed": 47
}
```

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

## Message extraction — bash + jq

Directories per runtime:

| runtime | path                                        |
|---------|---------------------------------------------|
| claude  | `~/.claude/projects/<slug>/*.jsonl`         |
| codex   | `~/.codex/sessions/*.jsonl`                 |
| gemini  | `~/.gemini/sessions/*.jsonl` (if it exists) |

`<slug>` for claude = `pwd | sed 's@/@-@g'`.

Tolerant pipeline (supports content as string OR array of blocks):

```bash
RUNTIME=$(detect_runtime)
case "$RUNTIME" in
  claude) DIR="$HOME/.claude/projects/$(pwd | sed 's@/@-@g')" ;;
  codex)  DIR="$HOME/.codex/sessions" ;;
  gemini) DIR="$HOME/.gemini/sessions" ;;
  *)      DIR="" ;;
esac

extract_user_msgs() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  ls -t "$dir"/*.jsonl 2>/dev/null | head -10 | while IFS= read -r f; do
    [ -f "$f" ] || continue
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      printf '%s\n' "$line" | jq -r '
        try (
          select(.type=="user" or .role=="user")
          | (.message.content // .content // .message // empty)
          | if   type == "string" then .
            elif type == "array"  then
              (map(select(.type=="text") | .text) | join(" "))
            else empty end
        ) catch empty
      ' 2>/dev/null
    done < "$f"
  done | grep -v '^/' | grep -v '^<system-reminder>' | awk 'length > 20' | head -50
}

MSGS=$(extract_user_msgs "$DIR")
N=$(printf '%s\n' "$MSGS" | grep -c .)
```

## Heuristic aggregation

On `MSGS`, infer:

- **`tone`**: presence of "pls/please", emojis, average verbosity.
  - <80 chars/msg → `terse`; 80–250 → `direct`; >250 → `verbose`.
  - Predominance of imperatives ("do", "fix") → `direct`.
- **`message_length`**: average words per msg → `short` (<25), `medium`
  (25–80), `long` (>80).
- **`linguistic_patterns`**: recurring tokens (top-N by count,
  deduped) — slang, identity markers, PT-BR/EN code-switching.
- **`values_and_priorities`**: extract signature phrases (e.g. "green",
  "type-safety", "atomic"). Manual heuristic; up to 5 items.
- **`vocabulary_examples`**: up to 6 recurring technical terms.

## Atomic persistence

```bash
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
profile=$(jq -n \
  --arg tone "$tone" \
  --arg ml "$message_length" \
  --argjson lp "$linguistic_patterns_json" \
  --argjson vp "$values_json" \
  --argjson ve "$vocab_json" \
  --arg ts "$ts" \
  --arg rt "$RUNTIME" \
  --argjson n "$N" \
  '{tone:$tone, message_length:$ml, linguistic_patterns:$lp,
    values_and_priorities:$vp, vocabulary_examples:$ve,
    extracted_at:$ts, source_runtime:$rt, n_messages_analyzed:$n}')

mkdir -p .sleepwell
tmp=$(mktemp .sleepwell/voice-profile.json.XXXXXX)
printf '%s\n' "$profile" > "$tmp"
mv "$tmp" .sleepwell/voice-profile.json
```

## Cache (7 days)

```bash
CACHE=.sleepwell/voice-profile.json
if [ -f "$CACHE" ]; then
  age=$(( $(date +%s) - $(stat -f %m "$CACHE" 2>/dev/null || stat -c %Y "$CACHE") ))
  if [ "$age" -lt 604800 ]; then
    echo "voice profile cache hit ($(($age/86400))d)"
    exit 0
  fi
fi
# Re-extrai…
```

## Prompt injection (loop)

On each iter, `sleepwell-loop` adds to the prompt nominal sections read from
the JSON:

```markdown
## Voice profile
- Tone: <tone>
- Message length: <message_length>
- Patterns: <linguistic_patterns | join(", ")>
- Values: <values_and_priorities | join(", ")>
- Vocab: <vocabulary_examples | join(", ")>
```

## Fallback — 0 messages found

If `N == 0` (no JSONLs, unknown runtime, or empty folder), persist a
default **neutral** profile instead of skipping:

```json
{
  "tone": "direct",
  "message_length": "medium",
  "linguistic_patterns": [],
  "values_and_priorities": ["pragmatism"],
  "vocabulary_examples": [],
  "extracted_at": "<ISO>",
  "source_runtime": "unknown",
  "n_messages_analyzed": 0
}
```

Logs: `voice profile: 0 messages, using neutral profile`.

## Privacy

- 100% local. Nothing leaves the disk.
- Do not include secrets or private paths in `linguistic_patterns` or
  `vocabulary_examples`.

## When NOT to extract

- `--no-voice` flag on `/sleepwell:sleepwell` → skip entirely.
- Valid cache (<7 days) and well-formed file → reuse.
