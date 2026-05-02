# Modo: tidy

**Apetite:** limpeza, organização, deps. **Risco:** baixíssimo.

## O que fazer numa iter tidy

- Remover imports não usados.
- Aplicar formatador (prettier, black, gofmt, rustfmt).
- Renomear identificadores claramente errados (typo, inconsistência).
- Reorganizar ordem de funções/imports por convenção.
- Atualizar deps minor/patch.
- Adicionar JSDoc/docstrings que estavam faltando em APIs públicas.
- Mover arquivo pra pasta correta (sem mudar conteúdo).
- Quebrar arquivo gigante em arquivos menores (sem mudar comportamento).

## O que NÃO fazer

- **Nunca** mudar comportamento. Se um teste passa antes, passa depois.
- Não introduzir abstrações novas.
- Não refatorar lógica.
- Não adicionar features.
- Não fazer dep bumps major.

## Heurística de fim

Quando o repo "se sente arrumado": linter limpo, sem warnings óbvios, naming consistente, deps em dia.

## Checklist por iter

- [ ] Mudança é puramente sintática/organizacional?
- [ ] Lint melhorou ou continuou ok?
- [ ] Testes continuam passando sem edição?
- [ ] Diff é pequeno e mecânico?

Se algum desses falha → cancela a iter, vai pro modo `refine`.
