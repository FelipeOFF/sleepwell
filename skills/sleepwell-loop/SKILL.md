---
name: sleepwell-loop
description: Use ao iniciar ou continuar o loop autônomo sleepwell. Implementa o ritual gnhf-style (branch isolada, commit atômico, rollback em falha) com ganchos para voice matching e meta-learning. Executa uma iteração por invocação e usa ScheduleWakeup para se relançar até concluir.
---

# sleepwell-loop

Skill central do plugin `sleepwell`. Executa **uma iteração** do loop autônomo a cada invocação e decide se continua (via `ScheduleWakeup`) ou para.

## Quando ativar

- Quando o usuário invoca `/sleepwell "<intent>" [opts]` (1ª iteração — bootstrap).
- Quando um `ScheduleWakeup` agendado refire este skill (iter seguinte).
- Quando outro skill/agent solicitar continuação explícita do loop.

**Não ativar** se:
- Usuário invocou `/sleepwell-status`, `/sleepwell-diff`, `/sleepwell-stop`, `/sleepwell-undo` (esses têm seus próprios fluxos).
- Não existe `.sleepwell/state.json` E não há intent fornecido (sem âncora — abort).

## Pré-requisitos

- Repo é git (`git rev-parse --is-inside-work-tree`).
- Working tree limpo OU usuário aceitou stash automático (perguntar via AskUserQuestion na 1ª iter).
- Branch atual ≠ main/master/develop (se for, criar branch sleepwell antes de tocar em qualquer arquivo).

## Anatomia de uma iteração

```
┌────────────────────────────────────────┐
│  load state.json                        │
│  if missing: bootstrap                  │
└─────────────┬──────────────────────────┘
              ▼
┌────────────────────────────────────────┐
│  abort checks                           │
│  - iter >= max-iter        → finalize   │
│  - failures >= 3           → abort      │
│  - stop-when met           → finalize   │
│  - sleepwell-stop sentinel → abort      │
└─────────────┬──────────────────────────┘
              ▼
┌────────────────────────────────────────┐
│  build iteration prompt                 │
│  intent + mode template + voice +       │
│  notes.md tail + last_diff + calib.     │
└─────────────┬──────────────────────────┘
              ▼
┌────────────────────────────────────────┐
│  EXECUTE — Claude edits files          │
└─────────────┬──────────────────────────┘
              ▼
┌────────────────────────────────────────┐
│  verify: lint + types + tests          │
└─────────────┬──────────────────────────┘
              ▼
        ┌─────┴─────┐
        ▼           ▼
     PASS         FAIL
       │           │
       ▼           ▼
  commit+notes  reset+clean -fd
  reset fail    failures++
  counter       backoff exp
       │           │
       └─────┬─────┘
             ▼
┌────────────────────────────────────────┐
│  update state.json                      │
└─────────────┬──────────────────────────┘
              ▼
        ┌─────┴─────┐
       done?        no
        │            │
       finalize     ScheduleWakeup
                    delay 60-270s
                    prompt: continuar
```

## Algoritmo detalhado

### 0. Bootstrap (apenas iter 0)

Detecte: `.sleepwell/state.json` não existe E há `--intent "<text>"` no input.

1. Parse args do `/sleepwell`: intent (ou `--intent-file <path>`), mode (default `refine`), max-iter (default 20), `--max-cost <USD>` (opcional), stop-when, dry-run, worktree (default true), no-voice, no-meta. Todas as flags são **gravadas no `state.json`** (campos `worktree_enabled`, `no_voice`, `no_meta`, `intent_file`, `cost_budget_usd`) para que retomadas via `ScheduleWakeup` preservem o setup.
2. Slug do intent → kebab-case curto, ex: `refactor-auth-middleware`.
3. **Worktree:**
   - Se `worktree=true`: usa skill `superpowers:using-git-worktrees` ou cria `git worktree add ../<repo>-wt/sleepwell-<slug> -b sleepwell/<slug>`.
   - Senão: `git checkout -b sleepwell/<slug>` (abortar se branch existe).
4. **Voice profile** (se `no-voice=false`):
   - Invoque skill `sleepwell-profile`.
   - Resultado em `.sleepwell/voice-profile.md`.
5. **Meta-calibration** (se `no-meta=false`):
   - Invoque skill `sleepwell-meta`.
   - Resultado em `.sleepwell/calibration.md`.
6. Cria `.sleepwell/state.json` (schema em `lib/state-schema.json`, version `2`):
   ```json
   {
     "version": 2,
     "intent": "<frase do user>",
     "intent_file": null,
     "slug": "<kebab-case>",
     "mode": "refine",
     "branch": "sleepwell/<slug>",
     "worktree_enabled": true,
     "worktree_path": "<abs path ou null>",
     "iteration": 0,
     "max_iter": 20,
     "stop_when": null,
     "dry_run": false,
     "no_voice": false,
     "no_meta": false,
     "consecutive_failures": 0,
     "total_passes": 0,
     "total_fails": 0,
     "started_at": "<ISO>",
     "last_iter_at": null,
     "status": "running",
     "verify_cmds": {
       "lint": "auto",
       "typecheck": "auto",
       "test": "auto"
     },
     "tokens_used": {
       "input": 0, "output": 0,
       "cache_read": 0, "cache_creation": 0
     },
     "cost_so_far_usd": 0,
     "cost_budget_usd": null
   }
   ```
   - `verify_cmds.lint = "auto"` → detecta no momento (npm/pnpm/bun script `lint`, `ruff`, `eslint`, `golangci-lint`, etc).
   - `cost_budget_usd` (de `--max-cost <USD>`) gera abort gate (ver `lib/ritual.md §8.1`).
7. Cria `.sleepwell/notes.md` com header.
8. Adiciona `.sleepwell/` ao `.gitignore` se ainda não estiver.

Pula direto para passo 2 (sem checar abort).

### 1. Load state

Lê `.sleepwell/state.json`. Se ausente e sem intent → erro: peça `/sleepwell "<intent>"` antes.

### 2. Abort checks

- `state.status == "stopped"` → finalize silencioso.
- `state.iteration >= state.max_iter` → finalize "max iter atingida".
- `state.consecutive_failures >= 3` → finalize "3 falhas seguidas".
- `state.stop_when != null`:
  - Avalie: leia `notes.md` + último diff + condição NL. Decida (curto raciocínio) se atingida. Se sim → finalize "stop-when met".
- `state.cost_budget_usd != null && state.cost_so_far_usd >= state.cost_budget_usd` → finalize "cost budget reached" (ver `lib/ritual.md §8.1`).

Em finalize: escrever resumo em notes.md, atualizar `state.status = "done"|"aborted"`, mostrar para o usuário status final + comando para revisar diff.

### 3. Construir prompt da iteração

Componha (concatene):

```
# Iteração ${iter+1}/${max_iter} — modo: ${mode}

## Intent original
${intent}

## Voice profile (estilo do usuário)
${cat .sleepwell/voice-profile.md, se existir}

## Calibration do run anterior
${cat .sleepwell/calibration.md, se existir}

## Modo: ${mode}
${cat sleepwell/lib/modes/${mode}.md}

## Notas das últimas iterações
${tail -n 80 .sleepwell/notes.md}

## Diff acumulado da branch
${BASE=$(sleepwell_base_branch); git diff --stat $(git merge-base HEAD "$BASE")..HEAD}
# `sleepwell_base_branch` detecta main/master/develop — ver lib/ritual.md §7.1.

## Próxima ação
Pense numa ÚNICA mudança coerente que avance a intent. Implemente-a agora.
Mantenha escopo cirúrgico — uma iteração = uma unidade lógica = um commit.
```

### 4. Execute

Faça o trabalho real. Use Edit/Write/Bash conforme necessário. **Mantenha o foco**: uma unidade lógica.

### 5. Verify

Detecte stack uma vez (cacheie em state.verify_cmds):
- **Node/TS:** `package.json` → `npm run lint` (se existir), `npm run typecheck`/`tsc --noEmit`, `npm test`.
- **Python:** `pyproject.toml`/`requirements.txt` → `ruff check`, `mypy` (se config), `pytest`.
- **Go:** `go.mod` → `go vet`, `go build`, `go test ./...`.
- **Rust:** `Cargo.toml` → `cargo clippy`, `cargo check`, `cargo test`.
- **Sem stack detectada:** pula verify, marca em notes.md.

Tempo limite por comando: 5min. Se travar, considera fail.

### 6. Decisão

**Se PASS:**
1. Se `dry_run=true`: pula commit, escreve notes.md "[dry-run] mudanças não comitadas".
2. Senão:
   - `git add -A`
   - Commit com mensagem conventional derivada do diff:
     ```
     <type>(sleepwell): <ação curta da iter>

     Iter ${iter+1}/${max_iter} — modo ${mode}.
     ${1-2 linhas do que mudou e porquê}

     [sleepwell-iter:${iter+1}]
     ```
3. Append em `notes.md`:
   ```
   ## Iter ${iter+1} — PASS — ${ISO}
   - <resumo 1-2 linhas>
   - commit: <sha>
   ```
4. `state.consecutive_failures = 0`, `state.total_passes++`.

**Se FAIL:**
1. `git reset --hard HEAD && git clean -fd` (descarta mudanças desta iter, incluindo arquivos não-rastreados criados — ver `lib/ritual.md §1`).
2. Append em `notes.md`:
   ```
   ## Iter ${iter+1} — FAIL — ${ISO}
   - falha em: <lint|types|tests>
   - resumo do erro: <100 chars>
   - rollback aplicado
   ```
3. `state.consecutive_failures++`, `state.total_fails++`.
4. Backoff: próximo wakeup com `delay = min(270, 60 * 2^failures)`.

### 7. Update state

Escreva state.json novo (incluindo `last_iter_at`, `iteration++`). Atualize também os campos de telemetria v2: incremente `tokens_used.{input,output,cache_read,cache_creation}` e recalcule `cost_so_far_usd` a partir do consumo da iteração. Nunca mexa nas flags persistidas (`worktree_enabled`, `no_voice`, `no_meta`, `intent_file`, `cost_budget_usd`) — elas são imutáveis após o bootstrap.

Use escrita atômica (tmpfile + rename) para evitar corromper o state em caso de crash.

### 8. Continuar ou parar

- Se algum abort check da próxima iter já vai disparar (ex: iter+1 ≥ max), finalize agora.
- Senão: `ScheduleWakeup`:
  - `delaySeconds`: 60 (default), 270 se acabou de fazer mudança grande, ou backoff se fail.
  - `prompt`: `"continuar loop sleepwell — invoque a skill sleepwell-loop"`.
  - `reason`: `"sleepwell iter ${iter+1} → ${iter+2}, status ${PASS|FAIL}"`.

## Finalize

Quando aborta ou conclui:

1. Atualiza `state.status` para `"done"|"aborted"|"stopped"`.
2. Escreve resumo final em `notes.md`.
3. Mostra ao usuário:
   ```
   sleepwell finalizado
   ━━━━━━━━━━━━━━━━━━━━
   intent: <intent>
   modo:   <mode>
   branch: sleepwell/<slug>
   iters:  ${total_passes} pass / ${total_fails} fail
   commits: ${git log sleepwell/<slug> ^$(sleepwell_base_branch) --oneline | wc -l}
   custo:  $${cost_so_far_usd} USD${cost_budget_usd:+ / $cost_budget_usd USD orçados}
   tokens: ${tokens_used.input} in / ${tokens_used.output} out (cache: ${tokens_used.cache_read} read, ${tokens_used.cache_creation} write)

   próximos passos:
   - revisar:  /sleepwell-diff
   - mergear:  git checkout main && git merge --squash sleepwell/<slug>
   - descartar: git branch -D sleepwell/<slug>
   ```

## Tratamento de erros

- **Working tree sujo na 1ª iter:** AskUserQuestion → "stash automático? abortar?"
- **Branch sleepwell/<slug> já existe:** sufixo `-2`, `-3`, ...
- **Worktree falha (espaço, etc):** cai pra modo sem worktree, avisa user em notes.md.
- **Verify cmd não encontrado:** marca em notes.md, considera "skip" não fail.
- **Ctrl+C/sleepwell-stop:** o slash `/sleepwell-stop` seta `state.status = "stopped"` — abort check pega na próxima iter.

## Skills compostas

Sinta-se livre para invocar dentro de uma iteração:

- `superpowers:test-driven-development` — modo `build`.
- `superpowers:systematic-debugging` — quando uma iter falha por bug não-trivial.
- `superpowers:verification-before-completion` — antes de considerar PASS.
- `gsd-execute-phase` — se a intent envolve plano GSD existente.
- `gitnexus-impact-analysis` — para entender raio de mudança no modo `refine`/`radical`.

## Não faça

- Não rode em `main`/`master`/`develop`.
- Não `--no-verify`, não `--force-push`.
- Não amend de commits anteriores do loop (cada iter = commit novo).
- Não delete `.sleepwell/` no meio do loop.
- Não escreva em arquivos fora do repo de trabalho.
