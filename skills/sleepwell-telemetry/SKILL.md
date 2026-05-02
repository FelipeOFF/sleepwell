---
name: sleepwell-telemetry
description: Coleta tokens/custo do runtime ativo (Claude Code ou Codex CLI) e atualiza .sleepwell/state.json.
---

# sleepwell-telemetry

Coleta telemetria de uso (tokens consumidos, custo derivado em USD) do runtime
ativo onde o loop sleepwell está rodando. Atualiza `.sleepwell/state.json` ao
final de cada iteração — antes do abort gate de custo (`§8.1` em
`lib/ritual.md`).

Saída persistida no state:

- `state.tokens_used.{input, output, cache_read, cache_creation}` (acumulado)
- `state.cost_so_far_usd` (acumulado, calculado a partir dos tokens)

## Detecção de runtime

```
if [ -n "$CLAUDE_CODE_VERSION" ] || [ -d "$HOME/.claude/projects" ]; then
  runtime=claude
elif command -v codex >/dev/null 2>&1; then
  runtime=codex
else
  runtime=unknown
fi
```

Em ambiente híbrido (ex.: CC instalado mas executando dentro do Codex CLI),
prefere Claude se a env var `CLAUDE_CODE_VERSION` estiver presente.

## Parsing — Claude Code

Claude Code persiste turns em
`~/.claude/projects/<slug>/<sessionId>.jsonl`, onde:

- `slug` = `pwd` com `/` → `-` (ex.: `/Users/foo/proj` → `-Users-foo-proj`).
- `sessionId` = arquivo `.jsonl` mais recente dentro do diretório do slug.

Cada linha é um JSON com (entre outros campos) `usage`:

```json
{ "usage": {
    "input_tokens": 1234,
    "output_tokens": 567,
    "cache_read_input_tokens": 2000,
    "cache_creation_input_tokens": 0
  }
}
```

Soma todas as ocorrências do `.jsonl` ativo da sessão atual.

## Parsing — Codex CLI

Codex grava sessões em `~/.codex/sessions/*.jsonl` em formato análogo. Quando
disponível, prefira `codex usage --json` (mais confiável, evita parsear formato
interno):

```bash
if codex usage --json >/dev/null 2>&1; then
  codex usage --json
else
  cat ~/.codex/sessions/*.jsonl
fi
```

Soma `tokens` (ou `usage.{input,output}`) por turn.

## Tabela de preços (USD por 1M tokens)

> **ATUALIZAR PERIODICAMENTE.** Preços públicos da Anthropic / OpenAI mudam.
> Última revisão: 2025-Q4. Use `unknown=true` quando o modelo não estiver
> mapeado para evitar custo silenciosamente errado.

| Modelo                     | input | output | cache_read | cache_creation |
|----------------------------|-------|--------|------------|----------------|
| Claude Sonnet 4.5          | 3.00  | 15.00  | 0.30       | 3.75           |
| Claude Haiku 4.5           | 1.00  | 5.00   | 0.10       | 1.25           |
| GPT-5 / Codex (placeholder)| 0     | 0      | 0          | 0              |

GPT-5/Codex: preencher quando confirmado; até lá, marcar `unknown=true` no
state extra para o usuário saber que o custo do run Codex não está somado.

## Cálculo

```
cost = (input * P_in + output * P_out + cache_read * P_cr + cache_creation * P_cc) / 1e6
```

Acumula com o valor já presente em `state.cost_so_far_usd` (incremental por
iter; não recalcula tudo do zero — desempate a favor de evitar overflow caso
o JSONL seja truncado).

## Escrita atômica

Sempre tmpfile+rename (ver `lib/ritual.md §7.2`):

```bash
tmp=$(mktemp .sleepwell/state.json.XXXXXX)
jq --argjson tu "$tokens_json" --argjson cost "$cost" \
   '.tokens_used = $tu | .cost_so_far_usd = $cost' \
   .sleepwell/state.json > "$tmp"
mv "$tmp" .sleepwell/state.json
```

## Snippet bash de exemplo

```bash
#!/usr/bin/env bash
set -euo pipefail

STATE=.sleepwell/state.json
[ -f "$STATE" ] || { echo "no sleepwell state"; exit 0; }

# Detect runtime
if [ -n "${CLAUDE_CODE_VERSION:-}" ] || [ -d "$HOME/.claude/projects" ]; then
  runtime=claude
elif command -v codex >/dev/null 2>&1; then
  runtime=codex
else
  runtime=unknown
fi

# Locate session file
sum_tokens() {
  jq -s '
    map(.usage // {})
    | reduce .[] as $u (
        {input:0,output:0,cache_read:0,cache_creation:0};
        .input          += ($u.input_tokens // 0)          |
        .output         += ($u.output_tokens // 0)         |
        .cache_read     += ($u.cache_read_input_tokens // 0) |
        .cache_creation += ($u.cache_creation_input_tokens // 0)
      )
  '
}

if [ "$runtime" = "claude" ]; then
  slug=$(pwd | sed 's@/@-@g')
  dir="$HOME/.claude/projects/$slug"
  [ -d "$dir" ] || { echo "no claude session for $slug"; exit 0; }
  jsonl=$(ls -t "$dir"/*.jsonl 2>/dev/null | head -1)
  tokens=$(jq -c '.message // .' "$jsonl" 2>/dev/null | sum_tokens)
elif [ "$runtime" = "codex" ]; then
  if codex usage --json >/dev/null 2>&1; then
    tokens=$(codex usage --json | sum_tokens)
  else
    tokens=$(cat "$HOME"/.codex/sessions/*.jsonl 2>/dev/null | sum_tokens)
  fi
else
  echo "unknown runtime; skipping telemetry"; exit 0
fi

# Pricing — Sonnet 4.5 default. Atualizar tabela periodicamente.
P_IN=3 P_OUT=15 P_CR=0.30 P_CC=3.75
cost=$(jq -n \
  --argjson t "$tokens" \
  --argjson pin "$P_IN" --argjson pout "$P_OUT" \
  --argjson pcr "$P_CR" --argjson pcc "$P_CC" \
  '($t.input*$pin + $t.output*$pout + $t.cache_read*$pcr + $t.cache_creation*$pcc)/1e6')

tmp=$(mktemp "$(dirname "$STATE")/state.json.XXXXXX")
jq --argjson tu "$tokens" --argjson cost "$cost" \
   '.tokens_used = $tu | .cost_so_far_usd = $cost' \
   "$STATE" > "$tmp"
mv "$tmp" "$STATE"

echo "telemetry: tokens=$(echo "$tokens" | jq -c .) cost_usd=$cost"
```

## Abort gate de custo

Após atualizar o state, o loop deve avaliar (ver `lib/ritual.md §8.1`):

```
if state.cost_budget_usd != null and
   state.cost_so_far_usd  >= state.cost_budget_usd
   → finalize("cost", abort_reason="cost budget reached")
```

A skill apenas **coleta**. A decisão de abortar fica no `sleepwell-loop`.
