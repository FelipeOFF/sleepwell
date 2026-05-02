---
name: sleepwell-profile
description: Use para extrair ou atualizar o voice profile estruturado do usuário a partir dos transcripts JSONL do runtime ativo (claude/codex/gemini). Persiste JSON em .sleepwell/voice-profile.json. Cache 7 dias. Sem dependências externas — só bash + jq.
---

# sleepwell-profile (estruturado)

Extrai um **voice profile estruturado** do usuário lendo os transcripts JSONL
do runtime ativo (Claude Code, Codex CLI ou Gemini CLI). O profile é injetado
nas iterações do `sleepwell-loop` para que as mudanças soem como o próprio
usuário escreveria.

A skill é **standalone**: usa apenas `bash` + `jq`, sem chamar outras skills
nem APIs externas.

## Quando ativar

- Bootstrap do `sleepwell-loop` (1ª iter), se `--no-voice` não for passado.
- Cache `.sleepwell/voice-profile.json` ausente OU mais antigo que 7 dias.
- Pedido explícito: "atualiza o voice profile do sleepwell".

## Schema do profile (`.sleepwell/voice-profile.json`)

```json
{
  "tone": "direct|warm|terse|verbose|mixed",
  "message_length": "short|medium|long",
  "linguistic_patterns": [
    "uses 'pls' regularly",
    "PT-BR misturado com termos técnicos em inglês",
    "cita arquivo:linha estilo grep"
  ],
  "values_and_priorities": [
    "pragmatismo",
    "type-safety",
    "testes verdes antes de merge"
  ],
  "vocabulary_examples": [
    "worktree",
    "commit atômico",
    "verde",
    "rebase limpo"
  ],
  "extracted_at": "2026-05-02T15:42:00-03:00",
  "source_runtime": "claude|codex|gemini",
  "n_messages_analyzed": 47
}
```

## Detecção de runtime

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

## Extração de mensagens — bash + jq

Diretórios por runtime:

| runtime | path                                        |
|---------|---------------------------------------------|
| claude  | `~/.claude/projects/<slug>/*.jsonl`         |
| codex   | `~/.codex/sessions/*.jsonl`                 |
| gemini  | `~/.gemini/sessions/*.jsonl` (se existir)   |

`<slug>` para claude = `pwd | sed 's@/@-@g'`.

Pipeline tolerante (suporta content como string OU array de blocks):

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

## Agregação heurística

Sobre `MSGS`, infira:

- **`tone`**: presença de "pls/por favor", emojis, verbosidade média.
  - <80 chars/msg → `terse`; 80–250 → `direct`; >250 → `verbose`.
  - Predominância de imperativos ("faça", "corrige") → `direct`.
- **`message_length`**: média de palavras por msg → `short` (<25), `medium`
  (25–80), `long` (>80).
- **`linguistic_patterns`**: tokens recorrentes (top-N por contagem,
  dedupe) — gírias, marcadores de identidade, code-switching PT-BR/EN.
- **`values_and_priorities`**: extraia frases-marca (ex.: "verde",
  "type-safety", "atômico"). Manual heuristic; até 5 itens.
- **`vocabulary_examples`**: até 6 termos técnicos recorrentes.

## Persistência atômica

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

## Cache (7 dias)

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

## Injeção no prompt (loop)

A cada iter, o `sleepwell-loop` adiciona ao prompt seções nominais lidas do
JSON:

```markdown
## Voice profile
- Tone: <tone>
- Message length: <message_length>
- Patterns: <linguistic_patterns | join(", ")>
- Values: <values_and_priorities | join(", ")>
- Vocab: <vocabulary_examples | join(", ")>
```

## Fallback — 0 mensagens encontradas

Se `N == 0` (sem JSONLs, runtime desconhecido, ou pasta vazia), persistir um
profile **neutro** default em vez de pular:

```json
{
  "tone": "direct",
  "message_length": "medium",
  "linguistic_patterns": [],
  "values_and_priorities": ["pragmatismo"],
  "vocabulary_examples": [],
  "extracted_at": "<ISO>",
  "source_runtime": "unknown",
  "n_messages_analyzed": 0
}
```

Loga: `voice profile: 0 mensagens, usando perfil neutro`.

## Privacidade

- 100% local. Nada sai do disco.
- Não inclua segredos ou paths privados em `linguistic_patterns` ou
  `vocabulary_examples`.

## Quando NÃO extrair

- Flag `--no-voice` no `/sleepwell:sleepwell` → pula completamente.
- Cache válido (<7 dias) e arquivo bem-formado → reusa.
