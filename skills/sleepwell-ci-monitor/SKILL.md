---
name: sleepwell-ci-monitor
description: Verifica status do CI no início de cada wake e persiste sentinela em .sleepwell/ci-status.json. Classifica falhas (próprias vs. externas), atua como circuit breaker para a feedback loop de fix-CI e enforça guardrails (max_ci_attempts_per_branch, max_actions_minutes_per_run, max_actions_cost_usd).
---

# sleepwell-ci-monitor

Skill invocada **logo após o bootstrap e antes de compose-prompt** em cada
iteração do `sleepwell-loop` (ver `lib/ritual.md §3`). Verifica o status do
CI da branch atual, classifica falhas, persiste sentinela e decide se o
loop deve invocar fix-CI, esperar ou abortar.

## 1. Trigger

- Invocada por `sleepwell-loop` no início de cada wake, após bootstrap e
  antes da composição do prompt.
- Também pode ser invocada manualmente via `/sleepwell:sleepwell-ci-status`.

## 2. Pré-condição

Existe `state.pr_url` OU a branch sleepwell foi pushada (registrado em
`state.last_push_sha`). Se nenhum dos dois, a skill não tem nada para
monitorar e retorna `no_ci`.

## 3. Lockfile

Antes de operar, esta skill **respeita** o lockfile `.sleepwell/ci-lock`
criado pelo `sleepwell-loop`. Se o lock existe e contém um pid vivo
DIFERENTE do pid atual → recusa rodar (mensagem: "ci-monitor: lock owned
by pid <X>, abortando"). Se ausente ou pid morto → ok. Ver
`lib/ritual.md §10`.

## 4. Coleta

```bash
gh run list --branch "$BRANCH" --limit 5 --json \
  status,conclusion,headSha,databaseId,createdAt,workflowName \
  --jq '.[0]' > .sleepwell/ci-run-latest.json
```

Pega o run mais recente. Se nenhum run existe ainda → status `pending`
(branch foi pushada mas o workflow ainda não disparou).

### 4.1 Validação de SHA

```
latest = read .sleepwell/ci-run-latest.json
if latest.headSha != state.last_push_sha:
  status = "pending"   # push registrado mas run ainda não iniciou
                       # OU run aponta para commit anterior
```

Apenas runs cujo `headSha == state.last_push_sha` contam para a decisão.

### 4.2 Sentinela atômica

Persiste em `.sleepwell/ci-status.json` via tmpfile + rename:

```json
{
  "branch": "sleepwell/auto/<run-id>",
  "head_sha": "<sha>",
  "run_id": <databaseId>,
  "status": "in_progress|completed|pending",
  "conclusion": "success|failure|cancelled|null",
  "workflow": "<name>",
  "checked_at": "<ISO>",
  "verdict": "green|pending|fix|external_failure|ci_attempts_exceeded|no_ci"
}
```

```bash
tmp=$(mktemp .sleepwell/ci-status.json.XXXXXX)
echo "$payload" > "$tmp"
mv "$tmp" .sleepwell/ci-status.json
```

## 5. Decisão

```
if no_ci (sem PR e sem last_push_sha):
  return "no_ci"

if status == "in_progress" or pending:
  state.ci_waiting_iters++
  if state.ci_waiting_iters > 5:
    return "wait_long"   # backoff passivo, sleep maior no ScheduleWakeup
  return "pending"

if conclusion == "success":
  state.ci_green = true
  state.ci_waiting_iters = 0
  reset state.ci_attempts[branch].count = 0
  return "green"

if conclusion == "failure":
  # Captura log do job que falhou.
  gh run view "$RUN_ID" --log-failed > .sleepwell/ci-failure-log.txt
  # Cap em 100KB (truncate head se necessário).
  truncate --size=100K .sleepwell/ci-failure-log.txt 2>/dev/null \
    || head -c 102400 .sleepwell/ci-failure-log.txt > .sleepwell/ci-failure-log.txt.tmp \
    && mv .sleepwell/ci-failure-log.txt.tmp .sleepwell/ci-failure-log.txt

  ext = match_external_failure(.sleepwell/ci-failure-log.txt)
  if ext:
    log notes.md ("external_failure: <signal>")
    return "external_failure"   # NÃO incrementa count, backoff 600s
  else:
    state.ci_attempts[branch].count++
    state.ci_attempts[branch].last_run_id = RUN_ID
    state.ci_attempts[branch].actions_minutes_spent += <duração>
    # Injeta o log na próxima iter (ver §6).
    if state.ci_attempts[branch].count >= state.max_ci_attempts_per_branch:
      return "ci_attempts_exceeded"
    return "fix"
```

## 6. Injeção de log no próximo prompt

Quando a skill retorna `fix`, o conteúdo de `.sleepwell/ci-failure-log.txt`
(cap 100KB) é anexado ao prompt da próxima iteração na seção:

```
## CI failure log (injected by sleepwell-ci-monitor)
<log content>
```

Isso permite que a iteração seguinte raciocine sobre o erro e tente
corrigir. O loop limpa esse arquivo após uma iteração PASS.

## 7. UI no /sleepwell:sleepwell-status

Quando `state.ci_green == true`, `/sleepwell:sleepwell-status` mostra ✅ ao lado da
branch. Quando o último verdict foi `failure` ou `fix`, mostra ❌ com
link para o run.

### 7.1 Detecção de falha externa

Regex sobre `.sleepwell/ci-failure-log.txt`:

```
secret (expired|invalid|missing)|EAI_AGAIN|ENETUNREACH|getaddrinfo|registry.*\b50[023]\b|runner (offline|unavailable)|GitHub Actions (outage|degraded)
```

Match → falha **externa**: o problema NÃO é do código sob teste. Não
incrementa `ci_attempts.count`, log no notes, próxima iter espera 600s
(backoff longo) em vez de fixar.

### 7.2 Cost de Actions

Usa `sleepwell-helper` se disponível (subcomando futuro
`actions-cost`); fallback heurístico:

```
duration_min = (run.updatedAt - run.createdAt) / 60
state.ci_attempts[branch].actions_minutes_spent += duration_min
```

Cost USD estimado = `Σ minutes * $0.008` (preço Linux runner público
GitHub-hosted, abr 2026).

## 8. Abort gates

A skill RETORNA o veredicto, mas o `sleepwell-loop` é quem aborta. Ver
`lib/ritual.md §8.1` (cost guardrails de CI).

| Retorno                     | Ação do loop                                |
|-----------------------------|---------------------------------------------|
| `no_ci`                     | segue normalmente (sem PR/push ainda)       |
| `green`                     | continua, marca state.ci_green = true       |
| `pending`                   | skip iter, incrementa ci_waiting_iters      |
| `wait_long`                 | sleep maior no ScheduleWakeup (≥600s)       |
| `external_failure`          | wait 600s, re-poll (sem incrementar count)  |
| `fix`                       | injeta log e invoca rotina de fix-CI        |
| `ci_attempts_exceeded`      | finalize("ci_attempts_exceeded")            |
| `actions_minutes_exceeded`  | finalize("actions_minutes_exceeded")        |
| `actions_cost_exceeded`     | finalize("actions_cost_exceeded")           |

## 9. State updates

Sempre via tmpfile + rename (ver `lib/ritual.md §7.2`). Inicializa
`state.ci_attempts[branch]` na 1ª falha:

```json
{
  "count": 1,
  "first_attempt_at": "<ISO>",
  "last_run_id": 123456,
  "actions_minutes_spent": 2.4
}
```

## 10. Edge cases

- **`gh` ausente:** skill loga warning em `notes.md`
  ("ci-monitor: gh CLI not found, skipping") e retorna `no_ci`. O loop
  segue normalmente.
- **Branch sem nenhum run:** `gh run list` retorna `[]` → status
  `pending`, sentinela registra `run_id: null`.
- **`gh` sem auth:** mesma resposta de `gh` ausente — warning + `no_ci`.
- **`headSha` divergente:** novo push aconteceu mas Actions ainda não
  disparou — status `pending` até o run aparecer. Não confundir com
  failure de versão antiga.
- **`databaseId` mesmo entre invocações com `pending`:** só incrementa
  `ci_waiting_iters` quando `status == "in_progress"` E `headSha` bate.
