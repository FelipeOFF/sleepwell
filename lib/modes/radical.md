# Modo: radical

**Apetite:** reescrever subsistemas. **Risco:** alto.

## Quando usar

- Refactor não é mais viável: a estrutura precisa morrer.
- Trocar lib/stack pontual (ex: in-memory cache → Redis).
- Reorganizar arquitetura de módulo (ex: extrair domínio para pacote separado).
- Substituir implementação por uma equivalente significativamente diferente.

## Estratégia

Strangler-fig friendly. Cada iter avança UM degrau:

1. Cria nova implementação em paralelo (sem matar a antiga).
2. Adiciona feature flag / fork de código pra escolher entre antiga e nova.
3. Aponta um ou poucos call-sites pra nova.
4. Roda testes — se quebra, rollback.
5. Migra mais call-sites, iter por iter.
6. Quando todos migraram, remove a antiga.

## Permissões extras (vs. refine)

- Pode introduzir abstração nova SE substitui uma existente equivalente.
- Pode quebrar uma API interna SE atualiza todos os callers na mesma iter (commit atômico).
- Pode invalidar dados em ambiente local SE state.dry_run=true ou se aviso explícito em notes.

## Restrições mantidas

- **Nunca** quebra a API pública sem ter migrações claras documentadas.
- **Nunca** remove a antiga implementação antes que NEW esteja 100% no lugar.
- **Nunca** opera em produção / shared state sem confirmação explícita.

## Heurística de fim

- Subsistema antigo removido.
- Subsistema novo cobrindo todos os call-sites.
- Testes verdes, incluindo regression para casos que motivaram a reescrita.

## Checklist por iter

- [ ] Esta iter cria uma fatia do strangler ou migra um grupo de callers?
- [ ] Há rollback óbvio se quebrar (feature flag, branch separada)?
- [ ] Estou mantendo compat de API pública até o final?
- [ ] Documentei em notes.md o estado da migração (% migrado)?

## Recomendação

Antes de iniciar `radical`, monte o plano em uma sub-fase
(`/sleepwell-phase-start "plan-radical"`) e preencha critérios de aceite
em `PLAN.md`. `radical` sem plano costuma virar churn.

<!--
Inspirações (não obrigatórias em runtime):
- gitnexus-impact-analysis — entender raio da mudança.
- superpowers:writing-plans — disciplina de planejamento prévio.
A sub-fase interna (lib/ritual.md §9) cumpre o mesmo papel sem dependência externa.
-->

