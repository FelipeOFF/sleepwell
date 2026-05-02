---
description: Para o loop sleepwell. Marca state como "stopped" para que próximas wakeups abortem na primeira checagem.
---

# /sleepwell:sleepwell-stop

Para o loop. Não destrói nada — apenas seta o flag de parada.

## Comportamento

1. Lê `.sleepwell/state.json`. Se ausente → erro: "nenhum loop ativo".
2. Se `status != "running"` → mostra "loop já está em status <X>, nada a fazer".
3. Atualiza `.sleepwell/state.json`:
   ```json
   {
     ...
     "status": "stopped",
     "stopped_at": "<ISO now>"
   }
   ```
4. Append em `notes.md`:
   ```
   ## stop manual — <ISO>
   - usuário invocou /sleepwell:sleepwell-stop
   - próxima wakeup vai abortar na 1ª checagem
   ```
5. (Opcional) tenta cancelar wakeups agendados — não há API direta de cancel, mas o `sleepwell-loop` no próximo wake checa `status == "stopped"` e finaliza.
6. Mostra:
   ```
   sleepwell parado.
   próxima ação automática: nenhuma.
   para retomar: /sleepwell:sleepwell (sem args, vai detectar state e perguntar)
   para finalizar e mergear: /sleepwell:sleepwell-diff && git checkout main && git merge --squash <branch>
   ```

## Sem efeitos destrutivos

`sleepwell-stop` não toca em commits, não muda branch. Apenas marca o state. É reversível: `/sleepwell:sleepwell` (sem args) pode retomar.
