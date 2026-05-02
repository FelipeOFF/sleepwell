# ADR-001: PR-only flow e CI awareness no SleepWell

- **Date:** 2026-05-02
- **Status:** Accepted

## Context

O loop autônomo do SleepWell roda overnight, sem operador humano no
console, e produz commits sucessivos em uma branch isolada. Para o ciclo
ter valor real (não só "rodar até cansar"), precisa **reagir ao CI**: se
um run de Actions falha, a próxima iter deveria tentar fixar; se uma
sequência de fixes não converge, o loop precisa parar antes de queimar
horas de runner. Ao mesmo tempo, **push direto em `main` é
inaceitável** — quebra o histórico, ignora review humano e expõe
produção ao output de um agente sem supervisão.

A pergunta de design foi: como o loop reage a CI sem interferência humana
e sem comprometer a higiene do repositório?

## Decision

1. **PR-only flow.** Toda run cria branch
   `sleepwell/auto/<run-id>` e, no finalize, abre um Pull Request via
   `/sleepwell:sleepwell-pr`. Nunca há push direto em `main`.
2. **CI awareness via polling no wake.** No início de cada iteração
   (após bootstrap, antes de compor o prompt), a skill
   `sleepwell-ci-monitor` chama `gh run list` para a branch ativa e
   classifica o último run como `green | pending | fix |
   external_failure`. O verdict alimenta o prompt da iter seguinte
   (injeta `.sleepwell/ci-failure-log.txt` quando é `fix`).
3. **Circuit breaker.** Schema v3.1 introduz
   `state.ci_attempts[<branch>]` com contador, `last_run_id` e
   `actions_minutes_spent`. Limites configuráveis:
   `max_ci_attempts_per_branch` (default 3),
   `max_actions_minutes_per_run` (default 60),
   `max_actions_cost_usd` (default 5.0). Estouro → finalize com
   `abort_reason ∈ {ci_attempts_exceeded,
   actions_minutes_exceeded, actions_cost_exceeded}`.
4. **Detecção de falha externa.** Regex sobre o log captura sinais de
   problemas que o loop não pode resolver (secret expirado, DNS,
   registry 5xx, runner offline, outage do GitHub). Match → backoff
   longo de 600s, sem incrementar `ci_attempts.count`.

## Alternatives Considered

- **Webhook push-based.** Servidor receberia eventos do GitHub e
  acordaria o loop. **Rejeitado:** requer infra (servidor sempre
  ligado, túnel, autenticação), incompatível com instalação plug-and-play
  do plugin local.
- **`workflow_run` commit-back.** Action server-side commitaria de volta
  na branch quando CI verde. **Rejeitado:** latência alta (workflow
  precisa terminar antes de re-disparar), polui o git history com
  commits sintéticos, e introduz acoplamento entre o loop e
  configuração de Actions do repo.
- **Polling síncrono dentro da iter.** Loop ficaria bloqueado em
  `gh run watch` aguardando conclusão. **Rejeitado:** quebra o modelo
  de wake-up do `ScheduleWakeup` (cada iter deveria ser curta), bloqueia
  o slot de execução por minutos sem progresso, e desperdiça tokens
  caches.

## Consequences

- **Complexidade adicionada.** Branch nomeada por `run-id`, comando
  `/sleepwell:sleepwell-pr`, schema v3.1, skill `sleepwell-ci-monitor`,
  sentinela em `.sleepwell/ci-status.json`.
- **Auto-merge é server-side e opcional.** O loop apenas adiciona o
  label `sleepwell-auto-merge` quando configurado; um Action externo
  (referência apenas, não incluso) decide o merge condicional após CI
  verde + reviews aprovados. Default: PR aguarda merge humano.
- **CI awareness é best-effort, não SLA.** Network flake do `gh`,
  ausência de auth, ou Actions degradados causam `no_ci`/`pending` sem
  abortar o loop. Falsos negativos são aceitáveis: o gate local
  (lint/type/test no verify de cada iter) é a primeira linha; CI é
  redundância.
- **Paridade local/CI explícita.** `sleepwell-helper ci-mirror` permite
  rodar uma aproximação dos workflows localmente antes do push,
  reduzindo a janela de surpresa.

## Council Validation

Em **2026-05-02** quatro vozes foram convocadas (Architect, Skeptic,
Pragmatist, Critic) para validar a decisão.

- **Architect:** PR-only é o único arranjo que mantém o loop
  desacoplado da infra e auditável a posteriori — aprovado.
- **Pragmatist:** o loop precisa entregar valor mesmo sem CI; o gate
  local (`verify` em cada iter) já é forte — aprovado.
- **Critic:** notação `sleepwell/auto/<run-id>` é legível e PR-friendly
  — aprovado.
- **Skeptic (dissent):** "depender de polling externo é frágil; e se o
  GitHub estiver instável a noite inteira?" — incorporado: o gate
  local + `ci-mirror` reduzem dependência de CI online; falha externa
  classificada e tratada com backoff longo em vez de fixar; circuit
  breaker garante saída em qualquer cenário patológico.

Consensus: **PR-only com CI awareness best-effort**.
