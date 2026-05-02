# Mapa de dependências de skills

O sleepwell foi desenhado para **funcionar standalone** — o fluxo core
(bootstrap, iteração, verify, commit, rollback, ScheduleWakeup) não exige
nenhuma skill externa. Skills opcionais melhoram a experiência mas não
bloqueiam o loop.

## Política minimalista de bundling

Vendoramos **apenas** o estritamente necessário pro fluxo core. Tudo o que é
"nice to have" fica como recomendação opcional — o usuário instala se quiser.

| Skill referenciada                         | Tipo      | Política                          | Vendor path                                |
|--------------------------------------------|-----------|-----------------------------------|--------------------------------------------|
| `superpowers:test-driven-development`      | dev       | opcional (recomenda)              | —                                          |
| `obsidian-markdown`                        | recap     | opcional                          | —                                          |
| `superpowers:using-git-worktrees`          | bootstrap | required → vendor                 | `skills/vendor/git-worktrees/SKILL.md`     |
| `everything-claude-code:gateguard`         | hooks     | substituído pelos hooks locais    | `hooks/block-push.sh`, `hooks/scope-guard.sh` |

### Detalhes por linha

**`superpowers:test-driven-development`** — usada no modo `build` quando o loop
opta por TDD-first. Sem ela, o loop ainda funciona; cai no fluxo verify
padrão. Recomendado para usuários que rodam `--mode build`.

**`obsidian-markdown`** — usada apenas no recap final/diário. Sem ela, recap
gera markdown plain. Não bloqueia.

**`superpowers:using-git-worktrees`** — referenciada no bootstrap quando
`worktree_enabled=true` (default). Como worktree é o caminho default e
seguro, vendoramos um stub mínimo (`skills/vendor/git-worktrees/SKILL.md`)
para garantir que o fluxo funcione sem instalar superpowers.

**`everything-claude-code:gateguard`** — guardas de escrita/push. **Não
vendoramos** porque temos hooks próprios (`hooks/block-push.sh`,
`hooks/scope-guard.sh`) registrados em `.claude-plugin/plugin.json` que
cobrem o caso de uso.

## Verificação

Rode `scripts/check-skill-deps.sh` para listar referências a skills externas
no plugin e checar quais não estão vendoradas. Saída útil em CI / pre-release.
