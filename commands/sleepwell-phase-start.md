---
description: Inicia nova sub-fase do run sleepwell em .sleepwell/phases/<NN>-<slug>/.
argument-hint: "<slug> [--plan <path>]"
---

# /sleepwell-phase-start

Abre uma nova sub-fase dentro do run corrente. Cada fase tem `PLAN.md`,
`EXECUTION.md` e `VERIFICATION.md` próprios, e é referenciada pelo
`state.phases` em `state.json`.

Ver `lib/ritual.md §9`.

## Argumentos

```
<slug>          slug kebab-case da fase (obrigatório). Ex: bootstrap, refactor-auth.
--plan <path>   caminho para um PLAN.md já preparado; se ausente, gera template.
```

## Pré-requisitos

- `.sleepwell/state.json` existe (há run em curso).
- Não há fase com `status == "active"` (apenas uma fase ativa por vez).
  Se houver, instrua o usuário a `/sleepwell-phase-complete` antes.

## Comportamento

1. Lê `state.json`. Calcula próximo `id`:
   - `id = max(state.phases[].id) + 1`, ou `1` se array vazio/ausente.
2. Diretório: `.sleepwell/phases/<NN>-<slug>/` (NN zero-pad 2 dígitos).
3. Cria estrutura:
   - `PLAN.md` — copiado de `--plan <path>` se passado, senão gera
     template:
     ```markdown
     # Fase <NN> — <slug>

     ## Objetivo
     <1-2 frases. O que esta fase entrega.>

     ## Critérios de aceite
     - [ ] <critério mensurável 1>
     - [ ] <critério mensurável 2>

     ## Escopo (in)
     - <item>

     ## Fora de escopo
     - <item>

     ## Riscos / dependências
     - <item>
     ```
   - `EXECUTION.md` — header simples:
     ```markdown
     # Execução — fase <NN> <slug>

     <log append-only por iteração da skill sleepwell-loop>
     ```
   - `VERIFICATION.md` — não é criado agora; gerado por
     `/sleepwell-phase-complete`.
4. Atualiza atomically (`tmpfile + mv`) `state.json`:
   - Adiciona em `state.phases`:
     ```json
     {
       "id": <NN>,
       "slug": "<slug>",
       "status": "active",
       "started_at": "<ISO>",
       "completed_at": null,
       "plan_path":      ".sleepwell/phases/<NN>-<slug>/PLAN.md",
       "execution_path": ".sleepwell/phases/<NN>-<slug>/EXECUTION.md",
       "verification_path": null
     }
     ```

## Output

```
fase <NN>-<slug> iniciada
plan:      .sleepwell/phases/<NN>-<slug>/PLAN.md
execution: .sleepwell/phases/<NN>-<slug>/EXECUTION.md

próximos passos:
  edite o PLAN.md preenchendo critérios de aceite
  retome o loop com /sleepwell-resume
```

## Edge cases

- `state.json` ausente → "nenhum run sleepwell aqui — inicie com /sleepwell."
- Slug inválido (não kebab-case) → erro com sugestão de correção.
- Diretório já existe (colisão) → sufixa `-2`, `-3`, ... no slug.
- `--plan <path>` aponta para arquivo inexistente → erro, não cria fase.
