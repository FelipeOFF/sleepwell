---
description: Mostra o estado atual do loop sleepwell — iteração, modo, branch, commits, falhas, próximo wakeup agendado.
---

# /sleepwell:sleepwell-status

Inspeciona `.sleepwell/state.json` (se existir) e apresenta um snapshot legível do loop.

## Comportamento

1. Procura `.sleepwell/state.json` no cwd.
   - Não encontrou → mostra "nenhum loop sleepwell ativo aqui. Use `/sleepwell:sleepwell \"<intent>\"` para iniciar."
2. Lê o JSON e formata:

```
sleepwell — status
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
intent:   <state.intent>
modo:     <state.mode>
branch:   <state.branch>  (worktree: <path or "—">)
status:   <running|done|aborted|stopped>
iter:     <state.iteration> / <state.max_iter>
passes:   <state.total_passes>
fails:    <state.total_fails> (consecutivas: <state.consecutive_failures>)
iniciado: <state.started_at>
última:   <state.last_iter_at>
stop-when: <state.stop_when or "—">

# Telemetria (se presentes em state.json — ver skill sleepwell-telemetry).
custo:    <state.cost_so_far_usd> USD (budget: <state.cost_budget_usd or "—">)
tokens:   in=<state.tokens_used.input> out=<state.tokens_used.output>
          cache_read=<state.tokens_used.cache_read>
          cache_creation=<state.tokens_used.cache_creation>

# Calibração (se presente — ver skill sleepwell-meta v2).
overall:    <state.prediction_profile.overall * 100>% (n=<state.prediction_profile.n_runs>)
trusted:    <state.prediction_profile.trusted | join(", ") or "—">
distrusted: <state.prediction_profile.distrusted | join(", ") or "—">

últimos commits da branch:
$(BASE=$(sleepwell_base_branch); git log --oneline -5 <state.branch> ^"$BASE" 2>/dev/null)
# `sleepwell_base_branch` detecta main/master/develop — ver lib/ritual.md §7.1.

últimas linhas do notes.md:
$(tail -n 20 .sleepwell/notes.md 2>/dev/null)
```

3. Se `status == "running"`, sugere:
   - `/sleepwell:sleepwell-stop` para parar.
   - `/sleepwell:sleepwell-diff` para ver diff.
   - `/sleepwell:sleepwell-undo` para reverter última iter.

4. Se `status != "running"`, mostra resumo final + comandos pra mergear/descartar.

## Sem efeitos colaterais

`/sleepwell:sleepwell-status` é **read-only**. Não modifica state.json, não cria commits, não dispara loop.
