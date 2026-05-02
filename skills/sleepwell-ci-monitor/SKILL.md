---
name: sleepwell-ci-monitor
description: Monitora runs de GitHub Actions disparadas pelo loop sleepwell. Detecta sucesso/falha do último push da branch, classifica falhas (próprias vs. externas) e atua como circuit breaker para a feedback loop de fix-CI. Atualiza state.ci_attempts e enforce os guardrails de v3.1 (max_ci_attempts_per_branch, max_actions_minutes_per_run, max_actions_cost_usd).
---

# sleepwell-ci-monitor

Skill invocada após cada push para uma branch `sleepwell/auto/*`. Decide
se o loop deve invocar a rotina de fix-CI, esperar (backoff longo) ou
abortar.

## 1. Trigger

Invocada por `sleepwell-loop` após cada push, antes da próxima iteração.
Também pode ser invocada manualmente via `/sleepwell-ci-status`.

## 2. Lockfile

Antes de operar, esta skill **respeita** o lockfile `.sleepwell/ci-lock`
criado pelo `sleepwell-loop`. Se o lock existe e contém um pid vivo
DIFERENTE do pid atual → recusa rodar (mensagem: "ci-monitor: lock owned
by pid <X>, abortando"). Se ausente ou pid morto → ok. Ver
`lib/ritual.md §10`.

## 3. Coleta

```bash
gh run list --branch "$BRANCH" --limit 5 --json \
  databaseId,status,conclusion,createdAt,updatedAt,name,event \
  > .sleepwell/ci-runs.json
```

Pega o último run cujo `event ∈ {push, pull_request}`. Salva o log do
job que falhou (se houver) em `.sleepwell/ci-failure-log.txt`:

```bash
gh run view "$RUN_ID" --log-failed > .sleepwell/ci-failure-log.txt 2>&1
```

## 4. Decisão

```
if conclusion == "success":
  reset state.ci_attempts[branch].count = 0
  return "green"

if conclusion == "failure":
  ext = match_external_failure(.sleepwell/ci-failure-log.txt)
  if ext:
    log notes.md ("external_failure: <signal>")
    return "external_failure"  # NÃO incrementa count, backoff 600s
  else:
    state.ci_attempts[branch].count++
    state.ci_attempts[branch].last_run_id = RUN_ID
    state.ci_attempts[branch].actions_minutes_spent += <duração estimada>
    if state.ci_attempts[branch].count >= state.max_ci_attempts_per_branch:
      return "ci_attempts_exceeded"     # abort no loop
    return "fix"  # invoca rotina de fix-CI

if conclusion == null and status == "in_progress":
  return "pending"  # backoff curto (60–120s)
```

### 4.1 Detecção de falha externa

Regex sobre `.sleepwell/ci-failure-log.txt`:

```
secret (expired|invalid|missing)|EAI_AGAIN|ENETUNREACH|getaddrinfo|registry.*\b50[023]\b|runner (offline|unavailable)|GitHub Actions (outage|degraded)
```

Match → falha **externa**: o problema NÃO é do código sob teste. Não
incrementa `ci_attempts.count`, log no notes, próxima iter espera 600s
(backoff longo) em vez de fixar.

### 4.2 Cost de Actions

Usa `sleepwell-helper` se disponível (subcomando futuro
`actions-cost`); fallback heurístico:

```
duration_min = (run.updatedAt - run.createdAt) / 60
state.ci_attempts[branch].actions_minutes_spent += duration_min
```

Cost USD estimado = `Σ minutes * $0.008` (preço Linux runner público
GitHub-hosted, abr 2026).

## 5. Abort gates

A skill RETORNA o veredicto, mas o `sleepwell-loop` é quem aborta. Ver
`lib/ritual.md §8.1` (cost guardrails de CI).

| Retorno                     | Ação do loop                                |
|-----------------------------|---------------------------------------------|
| `green`                     | continua                                    |
| `pending`                   | wait 60–120s, re-poll                       |
| `external_failure`          | wait 600s, re-poll (sem incrementar count)  |
| `fix`                       | invoca rotina de fix-CI                     |
| `ci_attempts_exceeded`      | finalize("ci_attempts_exceeded")            |
| `actions_minutes_exceeded`  | finalize("actions_minutes_exceeded")        |
| `actions_cost_exceeded`     | finalize("actions_cost_exceeded")           |

## 6. State updates

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
