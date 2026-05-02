---
description: Inicia (ou retoma) o loop autônomo sleepwell. Combina disciplina gnhf (branch isolada, commit atômico, rollback em fail) com adaptação overnight (voice matching, modos, meta-learning). Roda dentro da sessão CC com cache quente entre iterações.
argument-hint: "<intent>" [--mode tidy|refine|build|radical] [--max-iter N] [--max-cost USD] [--max-cost-per-iter USD] [--stop-when "<condição>"] [--dry-run] [--no-worktree] [--no-voice] [--no-meta] [--intent-file <path>] [--no-pr] [--draft-pr]
---

# /sleepwell

Inicia ou retoma o loop autônomo. Use a skill `sleepwell-loop` como entrypoint — ela vai bootstrapar o estado, criar a branch isolada, extrair voice profile, ler calibration, e rodar a 1ª iteração.

> **Fluxo canônico:** ver `lib/ritual.md` §2 (bootstrap) e §3 (iteração). Aqui ficam apenas args do CLI e dispatching pra skill — sem duplicar passos.

## Argumentos parseados

```
<intent>                        primeira string entre aspas — obrigatório no bootstrap
--intent-file <path>                  opcional, alternativa para intent longo (lê arquivo)
--mode tidy|refine|build|radical      default: refine
--max-iter <N>                        default: 20
--max-cost <USD>                      opcional, orçamento máximo total em USD (abort gate)
--max-cost-per-iter <USD>             opcional, guardrail per-iter (iter que excede aborta como FAIL e entra em backoff; não conta como abort total — ver lib/ritual.md §8.1)
--stop-when "<condição NL>"           opcional
--dry-run                             opcional (não commita)
--no-worktree                         opcional (default: usa worktree)
--no-voice                            opcional
--no-meta                             opcional
--no-pr                               opcional (default: cria PR ao final do run)
--draft-pr                            opcional (cria PR como draft)
```

> **PR-only flow:** ao final de um run com `status == done`, o loop invoca
> `/sleepwell-pr` automaticamente (a menos que `--no-pr` tenha sido passado).
> Auto-merge fica desabilitado por padrão. Veja `commands/sleepwell-pr.md`.

Todas as flags são **persistidas no `state.json`** no bootstrap (`worktree_enabled`,
`no_voice`, `no_meta`, `intent_file`, `cost_budget_usd`,
`max_cost_per_iter_usd`) — assim retomadas via
`ScheduleWakeup` preservam o setup escolhido. Ver `lib/state-schema.json` (v2)
e `lib/ritual.md §8`.

## Comportamento

1. Se `.sleepwell/state.json` **não existe** e há `<intent>` → bootstrap completo.
2. Se `.sleepwell/state.json` **existe** e `status == "running"` → retoma do ponto que parou (relança skill `sleepwell-loop`).
3. Se `.sleepwell/state.json` **existe** e `status == "done"|"aborted"|"stopped"`:
   - Se `<intent>` foi passado → bootstrap novo (move state antigo para `.sleepwell/archive/<timestamp>/`).
   - Senão → mostra status final e sugere `/sleepwell-status`/`/sleepwell-diff`.

## Validações antes de bootstrapar

- Repo é git? Se não → erro: "sleepwell precisa de git. Rode `git init`."
- Branch atual é `main`/`master`/`develop`? OK — vamos criar branch nova.
- Working tree limpo? Se não → AskUserQuestion: stash automático? abortar?

## Invocação

Invoque agora a skill `sleepwell-loop` com o input `${ARGUMENTS}`.

A skill cuida de:
- Parse de args
- Bootstrap (se for o caso)
- Execução da iteração
- ScheduleWakeup pra próxima

Não execute trabalho fora dela — só dispatching aqui.
