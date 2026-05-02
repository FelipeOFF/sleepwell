---
name: sleepwell-modes
description: Index dos 4 modos de operação do sleepwell (tidy, refine, build, radical). Use para escolher o modo certo dada a intent ou para carregar o template do modo durante uma iteração.
---

# sleepwell-modes

O sleepwell opera em 4 modos. Cada modo molda o "ritmo" e o "apetite por risco" das iterações.

| Modo | Apetite | Risco | Output típico |
|---|---|---|---|
| `tidy` | Limpeza, organização, deps | Baixíssimo | Renames, reorganização, dep bumps, lint fixes |
| `refine` (default) | Refactor incremental, melhorias | Baixo-médio | Pequenos refactors, cobertura de testes, naming |
| `build` | Construir feature nova | Médio | TDD-first feature, novos endpoints/componentes |
| `radical` | Reescrever subsistemas | Alto | Substitui módulos, troca de stack pontual |

## Como escolher

- "Limpa imports desnecessários e rode prettier" → **tidy**.
- "Refatora o auth pra usar o novo middleware sem mudar a API" → **refine**.
- "Implementa o endpoint /reports/csv com testes" → **build**.
- "Reescreve o cache em cima de Redis em vez de in-memory" → **radical**.

Default seguro: **refine** quando a intent não é clara.

## Templates

Cada modo tem um template que é injetado no prompt da iteração. Os arquivos vivem em:

- `lib/modes/tidy.md`
- `lib/modes/refine.md`
- `lib/modes/build.md`
- `lib/modes/radical.md`

Carregue via `Read` no momento de montar o prompt da iteração (ver `sleepwell-loop`).

## Princípios comuns aos 4 modos

- **Uma iteração = uma unidade lógica = um commit.** Não empilhar.
- **Verde antes de pass:** lint + types + tests devem passar.
- **Rollback agressivo:** falhou? `git reset --hard HEAD`. Não tente "consertar de novo na mesma iter".
- **Conventional commits.** `<type>(sleepwell): <título PT-BR>` com corpo explicando o porquê.
- **Notes append-only.** Cada iter adiciona ao `notes.md`, nunca reescreve.

## Quando trocar de modo no meio do loop

Permitido, mas raro. Atualize `state.json` `mode` e o ritual continua. Casos:

- Modo `build` virou `tidy` porque a feature ficou pronta antes do max-iter (sobra: limpeza).
- Modo `refine` virou `radical` porque viu que o subsistema não dá pra refatorar — precisa reescrever.

Se trocar, registre em `notes.md` o motivo.
