---
description: Cria PR a partir da branch sleepwell ativa com body estruturado.
---

# /sleepwell-pr

Cria pull request da branch sleepwell atual contra a base branch detectada
(`sleepwell_base_branch` — ver `lib/ritual.md §7.1`). Body inclui resumo
estruturado: intent, modo, iters, passes/fails, custo USD, último rating do
evaluator e lista de commits.

## Pré-condições

- `.sleepwell/state.json` existe e tem `branch` setada.
- Branch foi pushada ao remote (se não, faz `git push -u origin <branch>` antes).
- `gh` CLI autenticado.

## Comportamento

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

# título derivado do intent (truncado ~70 chars).
title="sleepwell: ${intent:0:60}"

# corpo
commits=$(git log --oneline "$base..$branch")
body=$(cat <<EOF
## Sleepwell run

- **Intent:** $intent
- **Modo:** $mode
- **Iterações:** $iter ($passes pass / $fails fail)
- **Custo USD:** $cost
- **Último rating (evaluator):** $rating

## Commits

\`\`\`
$commits
\`\`\`

---

> Auto-merge desabilitado por default. Para ligar merge condicional
> server-side, aplique manualmente o label \`sleepwell-auto-merge\` —
> uma GitHub Action externa (não incluída neste plugin) deve consumir
> o label e mergear quando o CI passar.
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

# persiste em state.json (atomic)
tmp=$(mktemp .sleepwell/state.json.XXXXXX)
jq --arg url "$pr_url" '.pr_url = $url' "$state" > "$tmp"
mv "$tmp" "$state"

echo "PR criado: $pr_url"
```

## Auto-merge (referência, não implementado)

O label `sleepwell-auto-merge`, quando aplicado manualmente ao PR criado,
serve como sinal para uma GitHub Action externa configurada no repo
(server-side). A Action observa o evento `labeled` e, se o CI estiver
verde, executa `gh pr merge --auto`. Esta lógica vive **fora** do
plugin sleepwell — o plugin apenas documenta a convenção.

## Erros comuns

- `gh` não autenticado → falha clara: peça `gh auth login`.
- Branch sem commits novos vs base → aborta com aviso.
- PR já existe para a branch → mostra URL existente, atualiza `state.pr_url`.
