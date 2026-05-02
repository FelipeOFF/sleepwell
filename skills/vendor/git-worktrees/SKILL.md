---
name: git-worktrees
description: Stub mínimo para uso de git worktree no bootstrap do sleepwell. Cria/remove worktrees em ../<repo>-wt/<name> com branch isolada.
---

<!--
Licença: Apache-2.0
Origem inspirada em superpowers:using-git-worktrees (apenas conceitos
gerais de uso de git worktree do próprio Git). Esta versão é uma
reescrita simplificada e original em PT-BR, voltada ao fluxo do
sleepwell. Nenhum conteúdo proprietário foi copiado.
-->

# git-worktrees (vendor stub)

Stub minimalista para o fluxo core do sleepwell rodar **sem depender** da
skill externa `superpowers:using-git-worktrees`. Cobre só o que o bootstrap
precisa.

## Quando usar

Quando o bootstrap do sleepwell roda com `worktree_enabled=true` (default) e
precisa criar uma árvore de trabalho isolada para a branch `sleepwell/<slug>`.

## Padrão de path

```
../<repo>-wt/<name>
```

Onde `<repo>` é o basename do diretório atual e `<name>` é normalmente
`sleepwell-<slug>`.

## Comandos

### Criar worktree com branch nova

```bash
git worktree add ../<repo>-wt/<name> -b <branch>
```

Exemplo (sleepwell):

```bash
git worktree add ../sleepwell-wt/sleepwell-refactor-auth \
  -b sleepwell/refactor-auth
```

### Listar worktrees existentes

```bash
git worktree list
```

### Remover worktree

```bash
git worktree remove ../<repo>-wt/<name>
```

Se ficou órfão (diretório deletado manualmente):

```bash
git worktree prune
```

## Pré-requisitos

- Git ≥ 2.5 (suporte a `worktree`).
- Working tree do repo principal limpo (ou estado já tratado por stash).
- Branch alvo não existe ainda (ou `git worktree add` falha; sleepwell
  detecta e ajusta o slug).

## Erros comuns

- `fatal: '<branch>' is already checked out at '<path>'` → worktree existente
  para a mesma branch. Use `git worktree list` e remova o antigo se órfão.
- `fatal: invalid reference: <branch>` → flag `-b` ausente quando a branch
  não existe.

## Referência

- `git help worktree` (manpage oficial).
- `lib/ritual.md §2` — uso do worktree no bootstrap.
- `commands/wt.md` (se presente no perfil global do usuário).
