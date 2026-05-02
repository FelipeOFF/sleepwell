---
description: Gera narrativa "minha noite" pós-run em vault Obsidian.
argument-hint: "[--vault PATH] [--no-write]"
---

# /sleepwell-recap

Gera uma nota de diário em primeira pessoa (PT-BR) sobre a noite que o agente
trabalhou. Lê todo o material da run e escreve em vault Obsidian no formato
canônico de dev journal.

## Argumentos

```
--vault <PATH>        diretório raiz do vault Obsidian (override)
--no-write            apenas mostra a nota gerada, não cria arquivo
```

## Resolução do vault

Ordem de precedência:

1. `--vault <path>` (se passado)
2. `$OBSIDIAN_VAULT` (env)
3. `~/obsidian-vault` (default)

Se o diretório não existir → cria com `mkdir -p`.

## Inputs lidos

- `.sleepwell/state.json` — intent, mode, branch, iters, passes, fails,
  cost_so_far_usd, started_at, last_iter_at.
- `.sleepwell/notes.md` — log cronológico do loop.
- `.sleepwell/calibration.md` (se existir) — tom/estilo do usuário.
- `git log <branch>` — commits da run.
- `git diff --stat <base>..HEAD` — onde `<base>` é `main`/`master`/`develop`
  (detecta via `lib/ritual.md §7.1`). Se nenhum existir, usa `HEAD~N`.

## Path da nota

```
<vault>/SleepWell/<YYYY-MM-DD>-<slug>.md
```

`<slug>` vem de `state.slug`. Se a nota já existir, sufixa: `-2`, `-3`, ...

## Frontmatter

```yaml
---
date: <YYYY-MM-DD>
type: sleepwell-recap
intent: "<state.intent>"
mode: <state.mode>
branch: <state.branch>
iters: <state.iteration>
passes: <state.total_passes>
fails: <state.total_fails>
cost_usd: <state.cost_so_far_usd>
tags: [sleepwell, dev-journal]
---
```

## Corpo (geração)

Use a skill `obsidian-markdown` se disponível, passando este prompt:

> Você é o usuário escrevendo no diário sobre a noite que o agente trabalhou.
> Tom em PT-BR, primeira pessoa, contemplativo mas honesto. Inclua:
> - o que foi tentado (intent + mode);
> - o que deu certo e o que falhou (sem maquiar);
> - 1 insight da noite;
> - 1 dúvida que ficou em aberto.
>
> ~400 palavras. Sem listas longas — prosa de diário.
>
> Material:
> - intent: <state.intent>
> - mode: <state.mode>
> - iters/passes/fails: <X/P/F>
> - cost: $<USD>
> - calibration (tom): <conteúdo de calibration.md, se existir>
> - notes.md (resumo): <últimas 50 linhas>
> - commits: <git log oneline>
> - diff stat: <diff --stat>

Se a skill `obsidian-markdown` não estiver disponível, gere a nota
diretamente com o mesmo prompt.

## `--no-write`

Apenas imprime no terminal o frontmatter + corpo gerados. Não toca o vault.
Útil para revisar antes de persistir.

## Edge cases

- `state.json` ausente → erro: "nenhum loop sleepwell encontrado neste repo."
- `notes.md` ausente → segue com aviso (provavelmente run muito curta).
- vault inexistente → cria diretório (`<vault>` e `<vault>/SleepWell`).
- nota já existe → sufixa `-2`, `-3`... antes de escrever.
- `git diff --stat` vazio → menciona no corpo que a noite foi de exploração
  sem mudança consolidada.

## Pós-execução

Mostra o path final da nota e sugere:
```
nota gerada: <vault>/SleepWell/<YYYY-MM-DD>-<slug>.md
abra no Obsidian ou rode `obsidian-cli open` se configurado.
```
