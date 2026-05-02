---
name: sleepwell-telemetry
description: v2 — coleta tokens/custo via sleepwell-helper (Rust) com detecção multi-LLM (claude/codex/gemini); fallback bash+jq quando o helper não está disponível. Atualiza state.tokens_used, state.cost_so_far_usd e dispara abort gate de custo.
---

# sleepwell-telemetry (v2)

Coleta telemetria de uso (tokens consumidos, custo derivado em USD) do
runtime ativo onde o loop sleepwell está rodando. Atualiza
`.sleepwell/state.json` ao final de cada iteração — antes do abort gate de
custo (`§8.1` em `lib/ritual.md`).

Saída persistida no state:

- `state.tokens_used.{input, output, cache_read, cache_creation}` (acumulado)
- `state.cost_so_far_usd` (acumulado, calculado a partir dos tokens)

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

Em ambiente híbrido, prefere Claude se `CLAUDE_CODE_VERSION` estiver presente.

## Localização do JSONL ativo (mais recente em mtime)

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

## Pipeline preferencial — `sleepwell-helper`

Quando o binário Rust está disponível, delega o parsing e cálculo:

```bash
MODEL=$(jq -r '.model // "claude-sonnet-4-5"' .sleepwell/state.json)

if command -v sleepwell-helper >/dev/null 2>&1 && [ -n "$JSONL" ]; then
  result=$(sleepwell-helper parse-jsonl "$JSONL" --format "$RUNTIME" \
           | sleepwell-helper cost --model "$MODEL")
  # result: {"tokens_used":{...}, "cost_usd": <float>}
fi
```

`parse-jsonl` extrai `usage` por turn no formato detectado; `cost` aplica a
tabela de preços do helper (mantida em `bin/sleepwell-helper/prices.toml`).

## Fallback — bash + jq

Quando `command -v sleepwell-helper` falha, emite warning visível e usa o
parsing inline (o legado v1):

```bash
if ! command -v sleepwell-helper >/dev/null 2>&1; then
  echo "warning: sleepwell-helper indisponível — usando parser bash legado" >&2

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
    echo "telemetry: runtime desconhecido, pulando" >&2
    exit 0
  fi

  # Pricing default (Sonnet 4.5). Ver bin/sleepwell-helper/prices.toml.
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

## Escrita atômica do state

```bash
tokens=$(printf '%s\n' "$result" | jq '.tokens_used')
cost=$(printf '%s\n' "$result"  | jq '.cost_usd')

tmp=$(mktemp .sleepwell/state.json.XXXXXX)
jq --argjson tu "$tokens" --argjson cost "$cost" \
   '.tokens_used = $tu | .cost_so_far_usd = $cost' \
   .sleepwell/state.json > "$tmp"
mv "$tmp" .sleepwell/state.json
```

Ver `lib/ritual.md §7.2`.

## Abort gate de custo

Após atualizar o state, o loop avalia (ver `lib/ritual.md §8.1`):

```
if state.cost_budget_usd != null and
   state.cost_so_far_usd  >= state.cost_budget_usd
   → finalize("cost", abort_reason="cost budget reached")
```

A skill **coleta**. A decisão de abortar fica no `sleepwell-loop`. Quando a
skill detecta `cost_so_far_usd >= cost_budget_usd`, **deve** sinalizar via
exit code != 0 + mensagem stderr, para que o loop trate o abort gate sem
ambiguidade.

## Tabela de preços

Para o pipeline preferencial, a tabela vive em
`bin/sleepwell-helper/prices.toml` (atualizar lá quando preços mudarem). O
fallback usa defaults inline para Sonnet 4.5; revisar trimestralmente.

| Modelo                     | input | output | cache_read | cache_creation |
|----------------------------|-------|--------|------------|----------------|
| Claude Sonnet 4.5          | 3.00  | 15.00  | 0.30       | 3.75           |
| Claude Haiku 4.5           | 1.00  | 5.00   | 0.10       | 1.25           |
| GPT-5 / Codex (placeholder)| 0     | 0      | 0          | 0              |
| Gemini 2.5 Pro (placeholder)| 0    | 0      | 0          | 0              |

Modelos não mapeados → custo 0 + warning `unknown=true`.
