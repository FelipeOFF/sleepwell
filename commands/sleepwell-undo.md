---
description: Reverte a última iteração com sucesso do loop sleepwell (git reset --hard HEAD~1 na branch sleepwell).
argument-hint: [--n N] [--keep-changes]
---

# /sleepwell-undo

Reverte a última iteração com sucesso da branch sleepwell.

## Argumentos

- `--n N` — reverte as últimas N iterações (default: 1).
- `--keep-changes` — usa `git reset --soft` (mantém as mudanças staged) em vez de `--hard`.

## Comportamento

1. Lê `.sleepwell/state.json`. Se ausente → erro.
2. Confirma com o usuário via AskUserQuestion (mostrando os commits que vai descartar):
   ```
   Vou reverter os últimos N commits da branch <state.branch>:
   - <sha> <msg>
   - <sha> <msg>

   ⚠️  Isso é destrutivo (--hard). Continuar?
   [confirmar / cancelar]
   ```
3. Se confirmado:
   - Verifica que branch atual é `state.branch`. Se não → checkout pra ela primeiro.
   - `git reset --hard HEAD~N` (ou `--soft` com `--keep-changes`).
   - Decrementa `state.iteration` e `state.total_passes` em `.sleepwell/state.json`.
   - Append em `notes.md`:
     ```
     ## undo manual — <ISO>
     - revertidos N commits via /sleepwell-undo
     - novo HEAD: <sha>
     ```
4. Mostra estado pós-undo (chama lógica de `/sleepwell-status` no fim).

## Salvaguardas

- **Nunca** roda em main/master/develop — aborta com erro.
- **Nunca** descarta commits que já foram pushados (verifica via `git log @{u}..` se há tracking remoto).
- Se loop está em `status == "running"`, sugere também `/sleepwell-stop` antes do undo (pra não conflitar com próximo wakeup).
