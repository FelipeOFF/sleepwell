---
name: sleepwell-evaluator
description: Avalia heuristicamente cada iteração via sleepwell-helper evaluate; persiste rating/observation/course_correct em state.last_eval e injeta no prompt seguinte.
---

# sleepwell-evaluator

Avaliação heurística leve por iteração. Roda **após o verify e antes/junto da telemetria** (ver `lib/ritual.md §3`). Produz um rating curto (1–5), uma observação textual e um booleano `course_correct` indicando se a próxima iter deve ajustar o curso.

A skill **coleta** sinais. A decisão de escalar (trocar de modo, abortar) fica no `sleepwell-loop` baseada no que está persistido em `state.last_eval`.

## Quando ativar

- Toda iteração do `sleepwell-loop`, depois do verify (PASS ou FAIL).
- Pedido explícito: "avalia última iter".

## Pipeline preferencial — `sleepwell-helper evaluate`

```bash
DIFFSTAT=$(git diff --stat "$(sleepwell_base_branch)"..HEAD)
sleepwell-helper evaluate \
  --state .sleepwell/state.json \
  --diff-stat <(printf '%s\n' "$DIFFSTAT") \
  --last-notes .sleepwell/notes.md
```

Saída esperada (JSON em stdout):

```json
{
  "rating": 4,
  "observation": "iter focada, 1 arquivo, testes verdes",
  "course_correct": false,
  "evaluated_at": "2026-05-02T15:42:00-03:00"
}
```

## Fallback — heurística bash mínima

Quando o binário `sleepwell-helper` não está disponível (`command -v sleepwell-helper` falha), produz um JSON equivalente via heurística:

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
  observation="heurística fallback (helper ausente)"

  case "$LAST_STATUS" in
    *PASS*)
      files=$(printf '%s\n' "$STAT" | tail -1 | grep -oE '[0-9]+ files?' | awk '{print $1}')
      if [ -n "$files" ] && [ "$files" -le 3 ]; then
        rating=5
        observation="PASS limpo, ${files} arquivo(s) tocados"
      else
        rating=4
        observation="PASS, diff amplo"
      fi
      ;;
    *FAIL*)
      rating=2
      course_correct=true
      observation="FAIL — sugerir ajuste de curso"
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

## Persistência atômica

Escrever `state.last_eval` via tmpfile + rename (ver `lib/ritual.md §7.2`):

```bash
tmp=$(mktemp .sleepwell/state.json.XXXXXX)
jq --argjson e "$eval_json" '.last_eval = $e' .sleepwell/state.json > "$tmp"
mv "$tmp" .sleepwell/state.json
```

`state.last_eval` segue o schema definido em `lib/state-schema.json` (v3, opcional):

```json
{
  "rating": 1..5,
  "observation": "string curta",
  "course_correct": false,
  "evaluated_at": "RFC3339"
}
```

## Injeção no prompt da próxima iter

O `sleepwell-loop` (ver `lib/ritual.md §3` etapa `[prompt]`) deve adicionar, quando `state.last_eval` estiver presente:

```markdown
## Avaliação anterior
- Rating: <X>/5
- Observação: <observation>
- Curso de correção sugerido: <true|false>
```

Isso entra **antes** do `git diff --stat`, depois de voice profile/calibration.

## Escalonamento por curso de correção persistente

Se `course_correct == true` em **2 iters consecutivas**, o loop deve escalar:

1. Se `state.mode == "refine"` → trocar para `tidy` (modo mais conservador) e avisar no notes.md: `mode escalation: refine → tidy (2× course_correct)`.
2. Se já estiver em `tidy` ou outro modo conservador → solicitar abort com `abort_reason="evaluator: course_correct sustained"`.

A detecção é feita lendo o `state.last_eval.course_correct` atual e comparando com a marca da iter anterior (que pode ser persistida em `state.last_eval_prev` se necessário, ou inferida do tail de `notes.md` onde a skill registra cada avaliação).

## Privacidade

- Avaliação roda 100% local. Nada sai do disco.
- Não inclua paths sensíveis na observation.

## Quando NÃO avaliar

- `state.dry_run == true` → ainda avalia (informativo), mas o loop pode ignorar `course_correct` para decisões.
- Iter 0 (bootstrap) → não há o que avaliar; pula.
