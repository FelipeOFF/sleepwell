---
description: Retoma um loop sleepwell pausado/abortado/crashed.
argument-hint: "[--force] [--from-iter N]"
---

# /sleepwell:sleepwell-resume

Retoma um loop existente em qualquer estado terminal (`stopped`, `aborted`,
`running` órfão após crash) sem reiniciar do zero. Reusa a skill
`sleepwell-loop` — não cria fluxo paralelo.

> Ver `lib/ritual.md` §2 (bootstrap) e §3 (iteração). Esta entrada apenas
> normaliza o `state.json` e chama a skill no ponto certo.

## Argumentos

```
--force                  pula AskUserQuestion em casos ambíguos (assume default seguro)
--from-iter <N>          força reentrada na iteração N (raro; padrão é manter state.iteration)
```

## Pré-condições

1. `.sleepwell/state.json` deve existir. Se não existir → erro:
   "nenhum loop sleepwell encontrado aqui. Use `/sleepwell:sleepwell \"<intent>\"`."
2. Cria lock `.sleepwell/resume.lock` com `{ "ts": "<ISO>", "pid": <pid> }`
   antes de relançar a skill. Se o lock já existir e for recente (<5min),
   aborta com aviso ("possível wakeup órfão; remova o lock manualmente se
   souber que não há outro loop ativo"). O lock é removido pelo
   `sleepwell-loop` ao iniciar a próxima iteração de fato.

## Comportamento por `state.status`

### `running` (crash mid-iter)
1. Assume crash entre `started_at` da iter e o commit final.
2. Roda `git status -s` no worktree (ou repo raiz se `worktree_enabled=false`).
3. Se sujo → `AskUserQuestion`:
   - **rollback** → `git checkout -- .` + `git clean -fd`, decrementa nada (a iter
     ainda não tinha incrementado), e dispara skill na iter atual.
   - **preservar WIP** → faz `git stash push -m "sleepwell-resume-wip <ISO>"`,
     anota o stash em `notes.md`, e dispara skill.
   - **abortar** → seta `status: aborted`, `abort_reason: "crash mid-iter, usuário abortou"`.
4. Se `--force`, escolhe **rollback** silenciosamente.
5. Reusa `sleepwell-loop` na **iter atual sem incrementar** (`iteration` fica
   como está; a skill detecta retomada via lock + status).

### `stopped`
1. Reverte `status` para `running`, limpa `stopped_at`.
2. Append em `notes.md`:
   ```
   ## resume manual — <ISO>
   - state revertido de "stopped" para "running"
   - próximo wakeup em 60s
   ```
3. Dispara `ScheduleWakeup(60s)` reusando `sleepwell-loop`.
4. Termina (a próxima iter roda no wakeup).

### `aborted`
1. Provável `consecutive_failures >= 3`. AskUserQuestion:
   - **zerar contador e retomar** → `consecutive_failures = 0`, `status = running`,
     anota em `notes.md`, dispara `ScheduleWakeup(60s)`.
   - **inspecionar antes** → não muda nada, sugere `/sleepwell:sleepwell-status` e `/sleepwell:sleepwell-diff`.
2. Se `--force`, escolhe **zerar e retomar**.
3. Se `abort_reason` indica `cost_budget_usd` excedido → recusa zerar contador
   e instrui o usuário a relançar com `--max-cost` maior via novo `/sleepwell:sleepwell`.

### `done`
Erro: "loop já concluído. Para começar outro intent, use
`/sleepwell:sleepwell \"<novo intent>\"` (state antigo será arquivado)."

## `--from-iter N`
Override avançado. Seta `state.iteration = N-1` antes de relançar a skill (a
skill incrementa para N na próxima iter). Útil para repetir uma iter que
passou mas sentiu errado. Anota override em `notes.md`.

## Lock anti-órfão

Antes de qualquer `ScheduleWakeup` ou invocação direta da skill:

```
.sleepwell/resume.lock = { "ts": "<ISO>", "pid": <process-pid-aprox> }
```

A skill `sleepwell-loop` deve ler esse lock no boot, comparar com o próprio
contexto, e remover ao começar a iter. Wakeups disparados antes do `/resume`
veem `status != running` e abortam sem trabalho.

## Exemplos

```
/sleepwell:sleepwell-resume                    # caso comum: detecta state e age
/sleepwell:sleepwell-resume --force            # sem perguntar, escolhe defaults seguros
/sleepwell:sleepwell-resume --from-iter 5      # reentra na iter 5
```
