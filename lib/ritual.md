# sleepwell — ritual completo

> **Fonte autoritativa.** Este documento é a referência canônica do fluxo sleepwell. Skills (`sleepwell-loop`, `sleepwell-meta`) e comandos (`/sleepwell*`) devem **referenciar** este arquivo (`Ver lib/ritual.md §<seção>`) em vez de duplicar a lógica. Mudanças no fluxo começam aqui.

Documentação canônica do ritual de iteração. A skill `sleepwell-loop` implementa este fluxo. Esta página existe para humanos lerem.

## 1. Princípios

1. **Uma iteração = uma unidade lógica = um commit.** Não empilha, não amend.
2. **Verde antes de pass.** Lint + types + tests devem passar pra commitar.
3. **Falhou? Reset.** `git reset --hard HEAD && git clean -fd` descarta tentativa (incluindo arquivos não-rastreados criados na iter falha). Próxima iter recomeça do zero da iter anterior bem-sucedida.
4. **Branch isolada sempre.** Nunca toca main/master/develop.
5. **Notes append-only.** O `notes.md` é o "diário de bordo" do loop — só cresce.
6. **State é fonte da verdade.** `state.json` é o que o loop consulta entre wakeups.

## 2. Bootstrap (iter 0)

```
[parse args]
  /sleepwell "<intent>" --mode refine --max-iter 20

[validations]
  ✓ git repo
  ✗ branch é main → continua (vai criar branch nova)
  ✓ working tree limpo (ou stash automático com confirmação)

[branch]
  slug = kebab(intent)
  worktree path = ../<repo>-wt/sleepwell-<slug>
  git worktree add <path> -b sleepwell/<slug>

[adaptation]
  voice_profile = sleepwell-profile()  # se !no-voice
  calibration   = sleepwell-meta()     # se !no-meta

[state]
  write .sleepwell/state.json
  write .sleepwell/notes.md (header)
  add .sleepwell/ to .gitignore
```

## 3. Iteração N

```
[load]
  state = read .sleepwell/state.json

[abort?]
  if state.status == "stopped" → finalize("stopped")
  if state.iteration >= state.max_iter → finalize("max_iter")
  if state.consecutive_failures >= 3 → finalize("3 fails seguidas")
  if state.stop_when and evaluate(state.stop_when, notes, last_diff) → finalize("stop-when met")

[prompt]
  intent + voice_profile + calibration + mode_template + tail(notes) + git diff --stat

[execute]
  Claude reasons + edits files

[verify]
  run state.verify_cmds.lint
  run state.verify_cmds.typecheck
  run state.verify_cmds.test
  → pass | fail

[decide]
  if pass:
    if !state.dry_run:
      git add -A
      git commit -m "<conventional msg> [sleepwell-iter:N]"
    append notes.md (PASS, sha, summary)
    state.consecutive_failures = 0
    state.total_passes++
    delay = 60s
  else:
    git reset --hard HEAD
    git clean -fd                     # remove arquivos não-rastreados criados na iter
    append notes.md (FAIL, error)
    state.consecutive_failures++
    state.total_fails++
    delay = min(270, 60 * 2^failures)

[evaluate]
  invoke skill `sleepwell-evaluator`
  → atualiza state.last_eval = {rating, observation, course_correct, evaluated_at}
  → próxima iter injeta `## Avaliação anterior` no prompt
  → 2× course_correct consecutivos: escala mode (refine→tidy) ou pede abort

[telemetry]
  invoke skill `sleepwell-telemetry`
  → atualiza state.tokens_used e state.cost_so_far_usd

[abort por custo?]
  if state.cost_budget_usd != null and
     state.cost_so_far_usd  >= state.cost_budget_usd
     → finalize("cost", abort_reason="cost budget reached")

[update]
  state.iteration++
  state.last_iter_at = now
  write state.json

[continue?]
  if next iter would abort → finalize now
  else → ScheduleWakeup(delay, prompt="continuar loop sleepwell")
```

## 4. Finalize

```
state.status = "done"|"aborted"|"stopped"
state.abort_reason = "<reason>"
write notes.md final summary
write state.json

display:
  intent / mode / branch / iter / passes/fails / commits

suggest next steps:
  /sleepwell-diff
  git checkout main && git merge --squash <branch>
  git branch -D <branch>
```

## 5. Cache de prompt

`ScheduleWakeup` com `delaySeconds` entre 60-270s mantém o cache de prompt da Anthropic quente (TTL 5min). Isso significa que cada wakeup re-entra no contexto SEM cache miss caro.

- 60s = next iter pronta rápido (default).
- 270s = próximo do TTL, mas ainda dentro da janela.
- 300s+ = paga cache miss → evite a menos que esperando algo externo.

Em backoff de fail, o delay pode ultrapassar 270s; aceitamos o cache miss em troca de espaçamento.

## 6. Compatibilidade com skills externas (opcional)

O loop core é **standalone** — comportamentos equivalentes estão
embutidos no fluxo. Se as skills abaixo estiverem instaladas no
ambiente, podem ser invocadas para reforço; senão, o loop opera sem
elas.

<!--
Inspirações (não obrigatórias):
- superpowers:test-driven-development — espelhada pelo modo `build`.
- superpowers:systematic-debugging — espelhada pelo handling de FAIL.
- superpowers:verification-before-completion — espelhada pelo §3 verify.
- gsd-execute-phase — substituída pelas sub-fases internas (§9).
- gitnexus-impact-analysis — heurística usada antes de `radical`.
-->

Contexto mantido entre invocações via cache de prompt.

## 7. Helpers

### 7.1 Detector de base branch

Nunca hardcode `main`. Use o helper abaixo para detectar a base correta (`main`, `master`, `develop`) — todos os comandos e skills devem referenciar esta lógica:

```bash
# Detecta a base branch do repositório.
# Ordem: HEAD do remote origin → main local → master local → develop.
sleepwell_base_branch() {
  local base
  base=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
          | sed 's@^refs/remotes/origin/@@')
  if [ -z "$base" ]; then
    if   git rev-parse --verify --quiet main    >/dev/null; then base=main
    elif git rev-parse --verify --quiet master  >/dev/null; then base=master
    elif git rev-parse --verify --quiet develop >/dev/null; then base=develop
    fi
  fi
  echo "$base"
}
```

Usar em qualquer lugar que precise de `merge-base`, range `..`, exclusão `^<base>`. Lugares já adaptados: `skills/sleepwell-loop` (diff acumulado), `commands/sleepwell-status`, `commands/sleepwell-diff`, `skills/sleepwell-meta`.

### 7.2 Escrita atômica de state

`state.json` é fonte da verdade — corrupção quebra retomadas. Sempre escreva via tmpfile + rename (atômico no mesmo filesystem):

```bash
tmp=$(mktemp .sleepwell/state.json.XXXXXX)
echo "$payload" > "$tmp"
mv "$tmp" .sleepwell/state.json
```

Mesmo padrão para `notes.md` em reescritas (apend simples pode usar `>>`).

### 7.3 Guard de upstream em undo

Antes de checar `git log @{u}..` (detectar commits já pushados), verifique se há upstream configurado. Sem o guard, branches locais sem tracking remoto fazem o `git log @{u}..` falhar e bloqueiam o undo erroneamente.

```bash
if git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
  # tem upstream — checa @{u}..
  pushed=$(git log @{u}..)
fi
# sem upstream → pular o check; undo é seguro.
```

Branches sleepwell são locais por default, então normalmente o guard pula o check.

## 8. State schema v3 — migration

O `state-schema.json` foi bumpado para `version: 3`. Os campos novos (v3) são
todos opcionais — runs antigas (`version: 1` ou `version: 2`) seguem
compatíveis e podem ser retomadas sem alteração.

### v2 (já existentes)

- `worktree_enabled` (boolean, default true) — espelha `--no-worktree`.
- `no_voice` / `no_meta` (boolean, default false) — flags do CLI persistidas.
- `intent_file` (string|null) — alternativa a intent inline.
- `tokens_used` `{input, output, cache_read, cache_creation}` — telemetria.
- `cost_so_far_usd` (number, default 0) — custo acumulado.
- `cost_budget_usd` (number|null) — orçamento via `--max-cost <USD>`.

### v3 (novos)

- `last_eval` `{rating, observation, course_correct, evaluated_at}` — saída
  da skill `sleepwell-evaluator`. Opcional; ausente em runs v1/v2.
- `prediction_profile` `{overall, by_category, trusted, distrusted, n_runs,
  calibrated_at}` — saída de `sleepwell-helper calibrate`, consumido pela
  skill `sleepwell-meta`. Opcional.
- `context_threshold_pct` (integer, default 80) — pressão de contexto para
  poda automática.
- `phases` (array) — sub-fases internas do run.

Migration v2 → v3: nada a fazer. Runs antigas continuam abrindo; o loop
adiciona os novos campos quando as skills correspondentes rodam pela primeira
vez na run retomada.

O `verify_cmds.{lint,typecheck,test}` agora aceita explicitamente o sentinel literal `"auto"` (oneOf string|"auto"), além de comando shell.

`additionalProperties` na raiz é `true` (sub-objetos críticos como `verify_cmds` mantêm `false`) — permite evolução do schema sem quebrar parsing.

### 8.1 Abort gate de custo

Adicione ao §3 abort checks:

```
if state.cost_budget_usd != null and
   state.cost_so_far_usd  >= state.cost_budget_usd
   → finalize("cost", abort_reason="cost budget reached")
```

#### Cost guardrail per-iter

Quando `state.max_cost_per_iter_usd` está setado (via `--max-cost-per-iter
<USD>`), medimos o **delta de custo da iter atual** (diferença entre
`cost_so_far_usd` antes e depois da telemetria). Se o delta excede o limite:

```
delta = cost_so_far_usd_after - cost_so_far_usd_before
if state.max_cost_per_iter_usd != null and
   delta > state.max_cost_per_iter_usd
   → mark iter as FAIL
   → git reset --hard HEAD && git clean -fd
   → state.consecutive_failures++
   → state.total_fails++
   → backoff exponencial (mesma fórmula do FAIL normal: min(270, 60*2^failures))
   → NÃO incrementa abort_total; o loop continua até consecutive_failures >= 3
     ou até qualquer outro abort gate (max_iter, cost_budget_usd, stop_when).
```

Racional: per-iter é um **guardrail**, não um corte. Uma iter cara não deve
matar o loop inteiro — pode ser uma iter outlier. Mas falhas seguidas (3
caras em sequência) caem no abort de `consecutive_failures >= 3` e cortam
naturalmente.

## 9. Sub-fases internas (`.sleepwell/phases/`)

Um run sleepwell pode ser decomposto em **sub-fases** — blocos lógicos de
trabalho com plano, execução e verificação próprios. É um conceito
**interno** ao plugin (não depende de skills externas como GSD): cada fase
vive em `.sleepwell/phases/<NN>-<slug>/`.

### Layout

```
.sleepwell/phases/
├── 01-bootstrap/
│   ├── PLAN.md          # gerado no início da fase (escopo, critérios)
│   ├── EXECUTION.md     # log de iterações da fase (append-only)
│   └── VERIFICATION.md  # critérios de aceite verificados ao fim
├── 02-iteration-set-A/
│   └── ...
└── ...
```

Numeração `NN` é sequencial (zero-pad, 2 dígitos). `slug` é kebab-case.

### Modelo no state.json

Campo `phases: array` (v3, opcional) com itens:

```json
{
  "id": 1,
  "slug": "bootstrap",
  "status": "active|completed|abandoned",
  "started_at": "<ISO>",
  "completed_at": "<ISO|null>",
  "plan_path":         ".sleepwell/phases/01-bootstrap/PLAN.md",
  "execution_path":    ".sleepwell/phases/01-bootstrap/EXECUTION.md",
  "verification_path": ".sleepwell/phases/01-bootstrap/VERIFICATION.md"
}
```

A fase com `status == "active"` é a **fase em curso**. Apenas uma por vez.

### Comandos

- `/sleepwell-phase-start "<slug>" [--plan <path>]` — abre nova fase.
  Cria diretório, gera `PLAN.md` (template inline), `EXECUTION.md` vazio,
  acrescenta entrada em `state.phases` com `status="active"`.
- `/sleepwell-phase-complete [--abandon]` — fecha a fase ativa.
  Gera/preenche `VERIFICATION.md`, marca `completed_at`, status →
  `completed` (ou `abandoned` se `--abandon`).

### Integração com a skill `sleepwell-loop`

No passo 3 (construir prompt), se há fase ativa (status=`active`), a skill:

- Anexa o conteúdo de `<plan_path>` ao prompt (seção `## Fase em curso`).
- Anexa as últimas 30 linhas de `<execution_path>`.
- Após cada PASS, append em `<execution_path>` a mesma linha que vai em
  `notes.md` (espelho local da fase).

Ao fim de cada iter, a skill avalia (via raciocínio curto sobre os
critérios em `PLAN.md` + diff acumulado da fase) se os critérios da fase
estão atendidos. Se sim:

- Apresenta ao usuário: "fase `<slug>` completa — abrir nova fase ou
  finalizar run?".
- Em modo autônomo (sem usuário ativo), executa
  `/sleepwell-phase-complete` automaticamente e propõe próxima fase via
  `/sleepwell-suggest`.

### Compatibilidade

- Runs sem `phases` (legados v1/v2 ou v3 sem usar fases) seguem
  funcionando exatamente como antes.
- Comandos de status/recap/diff existentes não precisam mudar; apenas
  ganham informação extra quando `state.phases` existe.

## 10. Recuperação de falhas catastróficas

Se o processo CC for derrubado no meio de uma iter:
- `state.json` está parcialmente atualizado (o último write é atômico via tmpfile + rename).
- Próxima invocação manual de `/sleepwell` (sem args) detecta `status == "running"` e retoma.
- Working tree pode estar sujo se a falha foi após edit mas antes de commit/reset → loop detecta diff vs HEAD na 1ª checagem da retomada e oferece: "rollback ou recuperar?".
