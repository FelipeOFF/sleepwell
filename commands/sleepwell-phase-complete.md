---
description: Fecha a fase ativa do run, gera VERIFICATION.md e arquiva.
argument-hint: "[--abandon]"
---

# /sleepwell-phase-complete

Encerra a fase com `status == "active"`. Gera `VERIFICATION.md` checando
critérios do `PLAN.md` contra o estado real (commits da fase, testes,
diff acumulado), atualiza `state.json` e libera o slot para a próxima
fase.

Ver `lib/ritual.md §9`.

## Argumentos

```
--abandon       marca a fase como abandoned em vez de completed.
                Use quando os critérios não foram cumpridos e você
                explicitamente decide encerrar sem verificação.
```

## Pré-requisitos

- `.sleepwell/state.json` existe.
- Existe exatamente uma fase com `status == "active"`.

## Comportamento (modo padrão — completed)

1. Lê fase ativa de `state.phases` (item com `status="active"`).
2. Lê `PLAN.md` da fase para extrair critérios de aceite (lista
   `- [ ] <texto>`).
3. Coleta evidência:
   - commits da fase: `git log <started_at>..HEAD` filtrado pela branch
     do run;
   - resumo de `EXECUTION.md` (passes/fails);
   - diff acumulado: `git diff $(merge-base base started_at)..HEAD`.
4. Avalia cada critério (raciocínio curto na sessão):
   - marca `[x]` quando há evidência clara;
   - mantém `[ ]` quando incompleto/ambíguo, com nota.
5. Gera `VERIFICATION.md`:
   ```markdown
   # Verificação — fase <NN>-<slug>

   ## Critérios
   - [x] <critério 1> — <evidência: sha curto, arquivo, ou frase>
   - [ ] <critério 2> — <por que ainda não>

   ## Resumo
   <2-3 frases>

   ## Commits
   - <sha> <título>
   - ...

   ## Decisão
   completed | partially-completed
   ```
6. Atualiza atomically `state.json`:
   - `status: "completed"`
   - `completed_at: "<ISO>"`
   - `verification_path: ".sleepwell/phases/<NN>-<slug>/VERIFICATION.md"`

## Comportamento — `--abandon`

- Cria `VERIFICATION.md` minimalista marcando "fase abandonada,
  critérios não verificados".
- `state.phases[i].status = "abandoned"`, `completed_at` setado.

## Output

```
fase <NN>-<slug> fechada (completed | abandoned)
verification: .sleepwell/phases/<NN>-<slug>/VERIFICATION.md
critérios:    <X>/<Y> verificados

próximos passos:
  /sleepwell-phase-start "<próxima>"   # iniciar nova fase
  /sleepwell-recap                      # encerrar run
```

## Edge cases

- Nenhuma fase ativa → "nenhuma fase ativa para fechar."
- Mais de uma fase active (corrupção) → erro pedindo correção manual
  do `state.json`.
- Sem critérios marcáveis em `PLAN.md` → gera VERIFICATION.md com
  "nenhum critério explícito; status = completed por decisão manual".
