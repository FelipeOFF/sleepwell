---
description: TUI live com status do loop sleepwell em curso.
argument-hint: "[--interval 3] [--tail 15]"
---

# /sleepwell:sleepwell-watch

Mostra um dashboard TUI live com o estado do loop sleepwell. Bloqueia o
terminal até `Ctrl+C`. Read-only — não muda `state.json` nem dispara skill.

## Argumentos

```
--interval <segundos>   intervalo entre refreshs (default: 3)
--tail <N>              linhas finais de notes.md a mostrar (default: 15)
```

## O que mostra

A cada refresh:

- linha resumo: `iter X/Y  pass=P fail=F  status=<S>  cost=$<USD>`
- separador
- últimas N linhas de `.sleepwell/notes.md`
- separador
- últimos 5 commits da branch (`git log --oneline <branch>`)

## Implementação

Dispara um Bash blocante. Usa `watch(1)` se disponível; senão fallback `while
true`. Trata state ausente sem crashar.

```bash
INTERVAL=${1:-3}
TAIL=${2:-15}

if command -v watch >/dev/null; then
  watch -n "$INTERVAL" -c bash -c '
    [ -f .sleepwell/state.json ] || { echo "sem loop ativo"; exit 0; }
    jq -r "\"iter \(.iteration)/\(.max_iter)  pass=\(.total_passes) fail=\(.total_fails)  status=\(.status)  cost=\$\(.cost_so_far_usd // 0)\"" .sleepwell/state.json
    echo "---"
    tail -n '"$TAIL"' .sleepwell/notes.md 2>/dev/null
    echo "---"
    B=$(jq -r .branch .sleepwell/state.json)
    git log --oneline "$B" 2>/dev/null | head -5
  '
else
  while true; do
    clear
    if [ ! -f .sleepwell/state.json ]; then
      echo "sem loop ativo"
    else
      jq -r '"iter \(.iteration)/\(.max_iter)  pass=\(.total_passes) fail=\(.total_fails)  status=\(.status)  cost=$\(.cost_so_far_usd // 0)"' .sleepwell/state.json
      echo "---"
      tail -n "$TAIL" .sleepwell/notes.md 2>/dev/null
      echo "---"
      B=$(jq -r .branch .sleepwell/state.json)
      git log --oneline "$B" 2>/dev/null | head -5
    fi
    sleep "$INTERVAL"
  done
fi
```

## Saída

`Ctrl+C` encerra. Como o comando é read-only, encerrar a qualquer momento é
seguro — não deixa o loop em estado inconsistente.

## Edge cases

- `.sleepwell/state.json` ausente → mostra "sem loop ativo" (não falha).
- `notes.md` ausente → tail silencioso (sem stderr).
- `jq` não instalado → recomende instalar; `watch` usa `jq` para formatar.
- Branch sleepwell removida (após merge) → `git log` retorna vazio, não
  quebra o refresh.

## Quando usar

- Acompanhar loop overnight em outro terminal/aba.
- Confirmar progresso sem rodar `/sleepwell:sleepwell-status` repetidamente.
- Detectar travamentos: se `iter` não muda em vários refreshs e `status =
  running`, considere `/sleepwell:sleepwell-resume`.
