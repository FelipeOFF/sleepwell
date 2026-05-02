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

## 6. Compatibilidade com skills externas

Dentro de uma iteração, a skill `sleepwell-loop` pode invocar:

- `superpowers:test-driven-development` — modo `build`.
- `superpowers:systematic-debugging` — em iters de fix.
- `superpowers:verification-before-completion` — gating de PASS.
- `gsd-execute-phase` — quando intent é "executar fase X do plano GSD".
- `gitnexus-impact-analysis` — antes de modo `radical`.

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

## 8. State schema v2 — migration

O `state-schema.json` foi bumpado para `version: 2`. Os campos novos são todos opcionais — runs antigas (`version: 1`) seguem compatíveis e podem ser retomadas sem alteração. Campos novos persistidos do CLI:

- `worktree_enabled` (boolean, default true) — espelha `--no-worktree`.
- `no_voice` / `no_meta` (boolean, default false) — flags do CLI persistidas.
- `intent_file` (string|null) — alternativa a intent inline.
- `tokens_used` `{input, output, cache_read, cache_creation}` — telemetria.
- `cost_so_far_usd` (number, default 0) — custo acumulado.
- `cost_budget_usd` (number|null) — orçamento via `--max-cost <USD>`.

O `verify_cmds.{lint,typecheck,test}` agora aceita explicitamente o sentinel literal `"auto"` (oneOf string|"auto"), além de comando shell.

`additionalProperties` na raiz é `true` (sub-objetos críticos como `verify_cmds` mantêm `false`) — permite evolução do schema sem quebrar parsing.

### 8.1 Abort gate de custo

Adicione ao §3 abort checks:

```
if state.cost_budget_usd != null and
   state.cost_so_far_usd  >= state.cost_budget_usd
   → finalize("cost", abort_reason="cost budget reached")
```

## 9. Recuperação de falhas catastróficas

Se o processo CC for derrubado no meio de uma iter:
- `state.json` está parcialmente atualizado (o último write é atômico via tmpfile + rename).
- Próxima invocação manual de `/sleepwell` (sem args) detecta `status == "running"` e retoma.
- Working tree pode estar sujo se a falha foi após edit mas antes de commit/reset → loop detecta diff vs HEAD na 1ª checagem da retomada e oferece: "rollback ou recuperar?".
