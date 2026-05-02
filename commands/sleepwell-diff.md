---
description: Mostra o diff acumulado da branch sleepwell em relação à base (main por default).
argument-hint: [--base <branch>] [--stat]
---

# /sleepwell-diff

Mostra o que o loop sleepwell produziu até agora.

## Comportamento

1. Lê `.sleepwell/state.json` para descobrir `branch`. Se ausente → erro: "nenhum loop sleepwell aqui".
2. Determina base:
   - `--base <branch>` se passado.
   - Senão usa o helper `sleepwell_base_branch` (detecta `main` / `master` / `develop` na ordem; ver `lib/ritual.md §7.1`).
3. Roda:
   ```bash
   # contagem de commits
   git log --oneline <base>..<state.branch>

   # diff completo OU apenas stat
   git diff <base>...<state.branch>           # default
   git diff --stat <base>...<state.branch>    # se --stat
   ```
4. Mostra:
   - Lista de commits da branch (com `[sleepwell-iter:N]`).
   - Stat resumido sempre (arquivos alterados / +N -M).
   - Diff completo se não foi pedido `--stat`.

## Sem efeitos colaterais

Read-only. Não modifica nada. Pode rodar enquanto loop está ativo (não interfere no `ScheduleWakeup`).
