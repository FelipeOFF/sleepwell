# Modo: build

**Apetite:** construir feature nova end-to-end. **Risco:** médio.

## Estratégia

TDD-first. Cada iter avança UMA fatia do funil:

1. **Red:** escreve teste que falha pela razão certa.
2. **Green:** implementa o mínimo pra passar.
3. **Refactor:** limpa sem mudar comportamento.

Cada uma dessas fases é um commit/iter. Não pula etapa.

## Sequência típica de iters

| Iter | Foco |
|---|---|
| 1 | Definir interface mínima (assinatura, tipos, contrato). Stub que falha. |
| 2 | Teste do happy path — falha. |
| 3 | Implementação mínima → green. |
| 4 | Refactor da implementação. |
| 5 | Teste de edge case — falha. |
| 6 | Implementação cobrindo edge case → green. |
| 7+ | Repete 5-6 até cobrir. |
| N | Integração com chamador real. |
| N+1 | Documentação / comentário se WHY não-óbvio. |

Use a skill `superpowers:test-driven-development` quando aplicável.

## O que NÃO fazer

- Não escreve implementação antes do teste vermelho.
- Não pula refactor por achar que "tá rápido".
- Não adiciona escopo além da intent — anota e segue.
- Não silencia testes pra passar (`@pytest.skip`, `it.skip`).

## Heurística de fim

Feature funcionando end-to-end com:
- Cobertura de happy path + edge cases conhecidos.
- Integrada ao chamador real (não só vive isolada nos testes).
- Sem TODOs críticos no diff.

## Checklist por iter

- [ ] Esta iter avança UMA fase TDD (red OU green OU refactor)?
- [ ] O teste novo é específico e falha pela razão certa?
- [ ] A implementação não vai além do necessário pra essa fase?
- [ ] Não há side-effect oculto fora do escopo da iter?
