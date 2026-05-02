---
description: Inicia (ou retoma) o loop autônomo sleepwell. Combina disciplina gnhf (branch isolada, commit atômico, rollback em fail) com adaptação overnight (voice matching, modos, meta-learning). Roda dentro da sessão CC com cache quente entre iterações.
argument-hint: "<intent>" [--mode tidy|refine|build|radical] [--max-iter N] [--stop-when "<condição>"] [--dry-run] [--no-worktree] [--no-voice] [--no-meta]
---

# /sleepwell

Inicia ou retoma o loop autônomo. Use a skill `sleepwell-loop` como entrypoint — ela vai bootstrapar o estado, criar a branch isolada, extrair voice profile, ler calibration, e rodar a 1ª iteração.

## Argumentos parseados

```
<intent>                        primeira string entre aspas — obrigatório no bootstrap
--mode tidy|refine|build|radical    default: refine
--max-iter <N>                       default: 20
--stop-when "<condição NL>"          opcional
--dry-run                            opcional (não commita)
--no-worktree                        opcional (default: usa worktree)
--no-voice                           opcional
--no-meta                            opcional
```

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
