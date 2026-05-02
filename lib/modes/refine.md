# Modo: refine (default)

**Apetite:** refactor incremental, melhorias contínuas, cobertura. **Risco:** baixo-médio.

## O que fazer numa iter refine

- Refatorar uma função para clareza (preservando comportamento).
- Extrair helper quando há duplicação real (regra do 3).
- Adicionar testes pra caminhos não cobertos.
- Substituir chamada deprecated por equivalente novo.
- Melhorar naming de variável/função em escopo local.
- Reduzir complexidade ciclomática de uma função.
- Trocar pattern feio por idiomático da stack.
- Eliminar dead code real.

## O que NÃO fazer

- Não introduzir abstração especulativa ("vai precisar futuramente").
- Não adicionar features.
- Não trocar tecnologia/lib.
- Não reescrever subsistemas — isso é modo `radical`.
- Não fazer mudança que requer migration manual de dados.

## Heurística de fim

Quando os testes estão verdes, cobertura tá razoável, e a próxima refatoração óbvia não é mais óbvia.

## Checklist por iter

- [ ] A mudança preserva comportamento observável?
- [ ] Testes existentes ainda passam SEM edição (a não ser que o teste estava errado)?
- [ ] Diff é localizado (poucos arquivos)?
- [ ] Há um "porquê" claro pra escrever no commit body?

Se a mudança quer crescer pra além de 1 commit coerente → cancela e quebra em iters menores.
