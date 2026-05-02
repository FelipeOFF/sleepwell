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

> **Fluxo canônico:** `lib/ritual.md` §1–§9 documenta princípios, bootstrap, iteração, finalize, helpers e migration. Esta SKILL implementa aquele fluxo — abaixo apenas o que é específico de runtime/execução. Mudanças de comportamento começam no `ritual.md`.

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

1. Parse args do `/sleepwell`: intent (ou `--intent-file <path>`), mode (default `refine`), max-iter (default 20), `--max-cost <USD>` (opcional), stop-when, dry-run, worktree (default true), no-voice, no-meta, `--no-pr` (default false: cria PR no finalize), `--draft-pr` (cria PR como draft). Todas as flags são **gravadas no `state.json`** (campos `worktree_enabled`, `no_voice`, `no_meta`, `intent_file`, `cost_budget_usd`, `pr_mode` ∈ {`auto`,`none`,`draft`}) para que retomadas via `ScheduleWakeup` preservem o setup.
2. Slug do intent → kebab-case curto, ex: `refactor-auth-middleware`. Persistido em `state.slug` (campo separado).
3. **Run-id:** gere identificador único `<unix-epoch>-<rand4hex>` (ex: `1714678920-a3f2`). Usado para nomear a branch, evitando colisão com slugs duplicados e garantindo PR-friendly naming.
4. **Worktree:**
   - Branch sempre nomeada `sleepwell/auto/<run-id>` (não mais `sleepwell/<slug>`).
   - Se `worktree=true`: cria `git worktree add ../<repo>-wt/sleepwell-auto-<run-id> -b sleepwell/auto/<run-id>` (vendored stub em `skills/vendor/git-worktrees`).
   - Senão: `git checkout -b sleepwell/auto/<run-id>` (abortar se branch existe — improvável dado o rand).
5. **Voice profile** (se `no-voice=false`):
   - Invoque skill `sleepwell-profile`.
   - Resultado em `.sleepwell/voice-profile.md`.
6. **Meta-calibration** (se `no-meta=false`):
   - Invoque skill `sleepwell-meta`.
   - Resultado em `.sleepwell/calibration.md`.
7. Cria `.sleepwell/state.json` (schema em `lib/state-schema.json`, version `3`):
   ```json
   {
     "version": 3,
     "intent": "<frase do user>",
     "intent_file": null,
     "slug": "<kebab-case>",
     "run_id": "<unix-epoch>-<rand4hex>",
     "mode": "refine",
     "branch": "sleepwell/auto/<run-id>",
     "pr_url": null,
     "pr_mode": "auto",
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
8. Cria `.sleepwell/notes.md` com header.
9. Adiciona `.sleepwell/` ao `.gitignore` se ainda não estiver.
10. **Lockfile de concorrência (`.sleepwell/ci-lock`):** ver `lib/ritual.md §10`.
    Antes de criar, checa se o arquivo existe:
    - Se existe: lê pid; em unix `kill -0 $pid 2>/dev/null` (em windows
      `tasklist /FI "PID eq $pid"`). Se vivo → recusa com mensagem
      `sleepwell-loop: lock owned by pid <X> @ <hostname> (started_at <ISO>)`.
      Se pid morto → considera lock stale, sobrescreve.
    - Se ausente: cria.
    Conteúdo: `{ "pid": <int>, "started_at": "<ISO>", "hostname": "<host>" }`
    via tmpfile + rename. Lock removido no finalize (success ou abort).

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

### 3.5 Gate de fase ativa

Antes de executar (passo 4), checa `state.phases`:

- Se há item com `status == "active"`:
  - Lê `<plan_path>` e adiciona ao prompt seção `## Fase em curso`.
  - Lê últimas 30 linhas de `<execution_path>` e adiciona seção
    `## Execução da fase (recente)`.
  - Mantém o prompt da iteração focado nos critérios da fase.
- Sem fase ativa: comportamento original (sem injeção extra).

Após PASS (passo 6, decisão), além de append em `notes.md`, espelha a
mesma linha em `<execution_path>` para que a fase tenha seu próprio log.

Após cada iter (PASS ou FAIL), avalia se os critérios da fase ativa
estão cumpridos (raciocínio curto sobre `PLAN.md` + diff acumulado da
fase). Se sim:

- Modo interativo: pergunta ao usuário "fase completa — abrir nova?".
- Modo autônomo: executa `/sleepwell-phase-complete` automaticamente e
  oferece próximas via `/sleepwell-suggest`.

Ver `lib/ritual.md §9`.

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

### 6.5 Poda automática de contexto

Após telemetry (passo 7 abaixo), avalie pressão de contexto da iteração
recém-concluída. Threshold default: `80%` do `model_context_window`.
Configurável via `state.context_threshold_pct` (campo opcional v3).

**Tabela de janelas de contexto (inline):**

| Modelo            | Window (input tokens) |
|-------------------|----------------------:|
| Claude Sonnet     | 200000                |
| Claude Opus       | 200000                |
| Claude Haiku      | 200000                |
| Sonnet 1M (beta)  | 1000000               |
| Opus 1M (beta)    | 1000000               |
| Codex / GPT-5     | 200000                |

Se desconhecido, fallback `200000`.

**Disparo:**

```
threshold_pct = state.context_threshold_pct ?? 80
window        = lookup(model_id) || 200000
limit         = window * threshold_pct / 100

if iter.tokens_used.input > limit:
  # 1. Truncar notes.md para últimas 20 entries (preservar header).
  header  = primeiras linhas até a primeira "## Iter " (exclusive)
  entries = blocos "## Iter ..." — pega os últimos 20
  rewrite notes.md = header + "\n\n" + last20

  # 2. Cache de last_diff > 5MB → remover.
  if exists(.sleepwell/last_diff) and size > 5MB:
    rm .sleepwell/last_diff

  # 3. Log do evento no notes.md.
  append:
    "## Poda — <ISO ts>: contexto reduzido (input=<N> > limit=<L>)"
```

A poda é registrada como entry própria em `notes.md` (linha
`## Poda — <ts>`) para auditoria — futuras inspeções (recap, suggest)
sabem que o histórico foi truncado.

Idempotente: se o limite continuar excedido em iters seguintes, cada
poda re-trunca para últimas 20 — sem efeito perverso.

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
2.5. Remove `.sleepwell/ci-lock` (apenas se o pid no lock é o pid atual).
2.7. **Gate ci-mirror (paridade local/CI):** se `sleepwell-helper` está
    disponível, antes do push/PR roda
    `sleepwell-helper ci-mirror | bash` (cwd = worktree). Se exit `!= 0`,
    o push e a criação do PR são **bloqueados**: status muda para
    `aborted`, `abort_reason="ci_mirror_failed"`, log no notes com a
    saída do bash. Se o helper não está no PATH, o gate é pulado com
    warning em notes (degradação grácil). Ver issue #37.
3. **PR-only flow:** se `state.pr_mode != "none"` E `state.status == "done"` E há ≥1 commit na branch → invoque `/sleepwell-pr` para criar PR. Persiste URL em `state.pr_url`. Em modo `"draft"`, cria com `--draft`. Auto-merge desabilitado por default; aplicar label `sleepwell-auto-merge` manualmente liga merge condicional via Action server-side (referência apenas — não implementado neste plugin).
4. Mostra ao usuário:
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

## Skills compostas (opcional, fonte de inspiração)

O loop core é **standalone** — não depende destas skills externas. Se
estiverem instaladas no ambiente, podem ser invocadas dentro de uma
iteração; senão, o comportamento equivalente já está embutido aqui.

<!--
Inspirações (não chamadas em runtime se ausentes):
- superpowers:test-driven-development — espelha o modo `build`.
- superpowers:systematic-debugging — espelha o handling de iters de fix.
- superpowers:verification-before-completion — espelhada pelo passo §5 verify.
- gsd-execute-phase — agora substituído pelas sub-fases internas (§9).
- gitnexus-impact-analysis — heurística usada em `refine`/`radical`.
-->


## Não faça

- Não rode em `main`/`master`/`develop`.
- Não `--no-verify`, não `--force-push`.
- Não amend de commits anteriores do loop (cada iter = commit novo).
- Não delete `.sleepwell/` no meio do loop.
- Não escreva em arquivos fora do repo de trabalho.
