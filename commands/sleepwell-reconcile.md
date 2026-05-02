---
description: Reconcilia outcomes de runs anteriores (merged/partial/discarded) via git branch --merged.
---

# /sleepwell-reconcile

Marca, retroativamente, o **outcome** de cada run sleepwell já arquivada,
inspecionando se a branch `sleepwell/<slug>` foi de fato integrada à base.

Idempotente: pode ser rodado quantas vezes necessário; sobrescreve apenas o
campo `outcome` no `state.json` arquivado.

## Outcomes

- **merged** — todos os commits da branch aparecem na base (totalmente
  integrada). Detectado via `git branch --merged $(sleepwell_base_branch)`.
- **partial** — pelo menos um commit foi cherry-picked (mas a branch como um
  todo não está merged). Detectado via `git cherry <base> <branch>`: linhas
  começando com `+` indicam commits NÃO presentes na base; linhas com `-`
  indicam commits presentes (cherry-picked). `partial` quando há ao menos um
  `-` mas nem todos.
- **discarded** — nenhum commit absorvido (todos `+` em `git cherry`, e
  branch não está em `--merged`).

## Comportamento

1. Detecta a base via helper de `lib/ritual.md §7.1` (`sleepwell_base_branch`).
2. Lista candidatos:
   - branches locais que casam com `sleepwell/*` (`git branch --list 'sleepwell/*'`);
   - subdiretórios de `.sleepwell/archive/<run-id>/` que contenham `state.json`.
3. Para cada run arquivada:
   - Lê `.sleepwell/archive/<run-id>/state.json` (campo `branch`, `mode`,
     `iteration`, `cost_so_far_usd`).
   - Se a branch não existe mais localmente:
     - Sem refs → `outcome = "discarded"` (não há como inferir cherry-pick).
   - Se a branch existe:
     - `git branch --merged "$BASE" | grep -qx "  $branch"` → `merged`.
     - Senão, `git cherry "$BASE" "$branch"`:
       - todas as linhas começam com `+` → `discarded`;
       - mistura de `+` e `-` → `partial`;
       - todas com `-` mas branch não está em `--merged` (raro) → `partial`.
4. Atualiza atomically (`tmpfile + mv`) o `state.json` arquivado adicionando:
   ```json
   {
     "outcome": "merged|partial|discarded",
     "outcome_reconciled_at": "<ISO>"
   }
   ```
5. Imprime tabela markdown:

```
| Branch                       | Categoria | Outcome   | Iters | Cost     |
|------------------------------|-----------|-----------|-------|----------|
| sleepwell/extract-auth       | refine    | merged    | 12    | $0.84    |
| sleepwell/rewrite-pipeline   | radical   | partial   | 18    | $2.10    |
| sleepwell/cleanup-deps       | tidy      | discarded | 4     | $0.12    |
```

`Categoria` = `state.mode`. `Cost` = `state.cost_so_far_usd` formatado em
USD (2 casas).

## Idempotência

- Roda apenas leitura sobre git (sem modificações de branch).
- O único side-effect é reescrever o campo `outcome` em arquivos JSON de
  arquivo (`.sleepwell/archive/<run-id>/state.json`). Sobrescrever com o
  mesmo valor é no-op semântico.
- Pode ser invocado N vezes; cada chamada recalcula com base no estado
  atual do git.

## Edge cases

- `.sleepwell/archive/` ausente → mensagem: "nenhuma run arquivada para
  reconciliar."
- `state.json` arquivado corrompido → pula com aviso, segue.
- Base branch não detectável (repo sem main/master/develop) → erro
  explicativo, abort.
- Run cuja branch foi deletada **e** rebase/squash sumiu com os SHAs
  originais → `discarded` (sem âncora para inferir cherry-pick).

## Sem efeitos colaterais destrutivos

Nunca deleta branch, nunca dá `git gc`, nunca move arquivo. Apenas
**lê git** e **escreve campo `outcome`** no JSON arquivado.

## Pós-execução

Sugere:
```
para auditar runs descartadas:
  ls .sleepwell/archive/

para limpar branches já merged:
  git branch --merged $(sleepwell_base_branch) | grep '^  sleepwell/' | xargs -r git branch -d
```
