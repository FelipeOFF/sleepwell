# sleepwell

> **Idiomas:** [English](README.md) · [Português (Brasil)](README.pt-BR.md)

Loop autônomo overnight para o Claude Code. Iteração disciplinada (branch isolada, commit atômico por iteração, rollback automático em caso de falha) combinada com comportamento adaptativo (4 modos de operação, voice matching opcional, meta-aprendizado entre runs).

Diferente de wrappers externos do tipo `claude -p`, o sleepwell roda **dentro** de uma sessão ativa do Claude Code — mantendo o prompt cache quente, os MCP servers vivos e as skills compostas entre iterações.

Agnóstico de linguagem e stack: funciona com qualquer projeto onde lint, type-check e testes possam ser invocados pelo shell. Os comandos de verificação são auto-detectados (Node, Python, Go, Rust, Ruby, .NET, Java, etc.) ou definidos explicitamente.

## Destaques

- **Prompt cache quente** entre iterações (TTL de 5 min) — sem cold start a cada loop.
- **MCP servers vivos** persistem entre iterações.
- **Componível** com qualquer skill ou plugin do Claude Code que você tenha instalado.
- **Standalone por design** — o ritual core funciona sem skills externas. Veja [`docs/SKILLS.md`](docs/SKILLS.md).
- **Segurança em primeiro lugar** — branch isolada, sem `--no-verify`, sem force-push, hook de scope-guard bloqueia edits fora do worktree, hook de push-guard bloqueia `git push` acidental enquanto um loop está rodando.

## Instalação

Dentro do Claude Code, registre o repo como marketplace e instale:

```
/plugin marketplace add FelipeOFF/sleepwell
/plugin install sleepwell@sleepwell
```

Ou clone e crie um symlink no seu diretório de plugins do Claude Code:

```bash
git clone https://github.com/FelipeOFF/sleepwell.git
ln -s "$(pwd)/sleepwell" ~/.claude/plugins/sleepwell
```

Reinicie o Claude Code. Os comandos `/sleepwell:*` aparecem.

> **Nota sobre namespacing.** O Claude Code coloca todo comando de plugin
> sob um namespace com o nome do plugin. Então o comando de início é
> `/sleepwell:sleepwell`, o de status é `/sleepwell:sleepwell-status`, etc.
> O `/sleepwell` puro (sem dois-pontos) vai retornar *Unknown command*.
> Use sempre a forma com namespace.

### Helper binary (auto-install)

O plugin usa um pequeno helper em Rust (`sleepwell-helper`) para parsing
rápido de JSONL, cálculo de custo multi-LLM, hashing, file watching e
calibração. Na primeira sessão, um hook `SessionStart`
(`hooks/ensure-helper.sh`) baixa o binário pré-compilado certo para a sua
plataforma a partir do GitHub Releases e instala em
`~/.local/share/sleepwell/bin/` (ou `%LOCALAPPDATA%\sleepwell\bin\` no
Windows). Binários já instalados são preservados; re-runs são no-op.

Controle manual:

```
/sleepwell:sleepwell-doctor                       # diagnose env + install if missing
/sleepwell:sleepwell-doctor --reinstall           # force redownload latest
/sleepwell:sleepwell-doctor --version bin-v0.5.0  # pin a specific version
```

Targets pré-compilados suportados:

| OS | Arch | Target |
|---|---|---|
| macOS | aarch64 (Apple Silicon) | `aarch64-apple-darwin` |
| Linux | x86_64 | `x86_64-unknown-linux-gnu` |
| Linux | aarch64 | `aarch64-unknown-linux-gnu` |
| Windows | x86_64 | `x86_64-pc-windows-msvc` |

Se sua plataforma não for coberta, faça o build localmente:

```bash
cargo install --path bin/sleepwell-helper
```

O helper é **opcional** — toda skill tem fallback em `bash`/`jq`. A
ausência dele só reduz precisão (telemetria de custo, calibração), não
quebra o loop.

### Atualizações

O plugin verifica novas releases do SleepWell e do binário helper uma
vez por sessão (em background, com throttling de 24h). Atualizações
disponíveis aparecem via `/sleepwell:sleepwell-update`.

```
/sleepwell:sleepwell-update              # ver o que está disponível
/sleepwell:sleepwell-update --apply      # baixa update do helper
/sleepwell:sleepwell-update --helper-only
/sleepwell:sleepwell-update --plugin-only
```

Desative o check em background com `SLEEPWELL_SKIP_UPDATE_CHECK=1`.
Ajuste o TTL com `SLEEPWELL_UPDATE_TTL=<segundos>` (padrão 86400).
Sobrescreva o repo com `SLEEPWELL_UPDATE_REPO=<owner>/<name>`.

Para suprimir notificações sobre o binário helper opcional (caso
você nunca queira tê-lo instalado), crie um arquivo sentinela:

```bash
mkdir -p ~/.config/sleepwell && touch ~/.config/sleepwell/no-helper
```

#### Smoke test manual

Para validar o check de update ponta-a-ponta:

```bash
rm -f ~/.cache/sleepwell/update.json
bash hooks/check-update.sh
sleep 3
cat ~/.cache/sleepwell/update.json
```

Deve gerar um JSON válido com `plugin_installed`, `plugin_latest`,
`helper_installed`, `helper_latest` e flags `*_update_available`.

### Recovery

Se os comandos `/sleepwell:*` sumirem do Claude Code (tipicamente após
um update do CC ou ferramenta de terceiros que mexe em
`~/.claude/plugins/`), o diretório de cache pode ter sido removido
enquanto `installed_plugins.json` ainda o referencia. Recupere com:

```bash
# A partir de qualquer terminal (não requer o sleepwell carregado):
bash <(curl -fsSL https://raw.githubusercontent.com/FelipeOFF/sleepwell/main/scripts/restore-plugin-cache.sh)

# Ou de dentro do Claude Code (se o doctor ainda funcionar):
/sleepwell:sleepwell-doctor --restore-cache
```

Depois de restaurar, rode `/reload-plugins` no Claude Code.

> **Dica:** digite `/sl` e pressione `Tab` no Claude Code para
> autocompletar os comandos longos namespaced.

## Início rápido

```
/sleepwell:sleepwell "extract auth middleware into its own module" --mode refine --max-iter 15
```

| Comando | Função |
|---|---|
| `/sleepwell:sleepwell "<intent>" [opts]` | Inicia o loop |
| `/sleepwell:sleepwell-status` | Iteração atual, branch, modo, commits recentes, custo |
| `/sleepwell:sleepwell-diff` | Diff acumulado contra a branch base |
| `/sleepwell:sleepwell-resume` | Retoma um loop pausado, parado ou crashado |
| `/sleepwell:sleepwell-watch` | TUI live do progresso do loop |
| `/sleepwell:sleepwell-recap` | Narrativa pós-run |
| `/sleepwell:sleepwell-undo` | Reverte a última iteração bem-sucedida |
| `/sleepwell:sleepwell-stop` | Cancela wakeups pendentes |

## Modos

| Modo | Quando usar | Comportamento |
|---|---|---|
| `tidy` | Cleanup, dependências, formatação | Mudanças mecânicas, sem mudança de comportamento |
| `refine` (default) | Melhoria incremental, refactor | Refatora mantendo testes verdes |
| `build` | Nova feature end-to-end | Tests-first, ramp até feature funcionando |
| `radical` | Reescritas de subsistema | Permite quebrar e reconstruir; risco maior |
| `wave` | Colaboração multi-agent (experimental) | Propõe → critica → consolida por iteração |

## Opções

```
/sleepwell:sleepwell "<intent>"
  --mode tidy|refine|build|radical|wave   (default: refine)
  --max-iter <N>                          (default: 20)
  --max-cost <USD>                        (abort when total cost exceeds budget)
  --max-cost-per-iter <USD>               (per-iteration cap)
  --stop-when "<NL condition>"            (evaluated after each iter)
  --intent-file <path>                    (long intent from file)
  --no-worktree                           (default: uses git worktree)
  --dry-run                               (no commits; show diff)
  --no-voice                              (skip voice profile extraction)
  --no-meta                               (skip meta-learning calibration)
```

## Anatomia de uma iteração

1. **Carrega o estado** de `.sleepwell/state.json`.
2. **Checks de abort** — max-iter, max-cost, stop-when, ≥3 falhas consecutivas.
3. **Bootstrap** (apenas na primeira iteração) — cria branch `sleepwell/<slug>`, worktree opcional, voice profile, calibração prévia.
4. **Compõe o prompt** — intent + modo + voice + notas recentes + último diff + calibração.
5. **Executa** — Claude raciocina e edita arquivos.
6. **Verifica** — lint + type-check + testes (auto-detectados ou definidos em `verify_cmds`).
7. **Decisão** — Pass: commit atômico + log. Fail: `git reset --hard HEAD && git clean -fd`, incrementa contador de falhas, exponential backoff.
8. **Telemetria** — acumula uso de tokens e custo.
9. **Agenda a próxima** — `ScheduleWakeup(60-270s)` mantém o cache quente e relança o loop.

## Estado

```
.sleepwell/
├── state.json          # iteration, branch, mode, status, cost, tokens
├── notes.md            # appended log per iteration
├── voice-profile.md    # cached voice matching summary
├── calibration.md      # cross-run meta-learning insights
└── archive/            # previous runs
```

Adicione `.sleepwell/` ao `.gitignore` do seu projeto.

## Comandos de verificação

Defina por projeto (em `state.json` ou via flags). Cada um aceita um comando de shell ou o literal `"auto"`:

```json
{
  "verify_cmds": {
    "lint": "auto",
    "typecheck": "auto",
    "test": "npm test"
  }
}
```

`auto` detecta toolchains comuns: `eslint`, `ruff`, `golangci-lint`, `cargo clippy`, `rubocop`, `dotnet format`, etc.

## Telemetria de custo

Detecta o runtime ativo (Claude Code ou Codex CLI), faz parse do JSONL da sessão, acumula tokens `input/output/cache_read/cache_creation` por iteração, deriva o custo em USD a partir de uma price table e aplica o budget definido em `--max-cost`. Veja [`skills/sleepwell-telemetry/SKILL.md`](skills/sleepwell-telemetry/SKILL.md).

## Segurança

- Nunca roda em `main`/`master`/`develop` — sempre isola em uma branch `sleepwell/<slug>`.
- Nunca usa `--no-verify` ou `--force-push`.
- ≥3 falhas consecutivas → abort automático.
- Hooks `PreToolUse` bloqueiam `git push` e edits fora do worktree durante um loop ativo.
- `--dry-run` faz preview sem commitar.

## Solução de problemas

Cenários comuns (estado corrompido, worktree órfão, custo descontrolado, voice cache obsoleto, push bloqueado) estão documentados em [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) com **Sintomas / Diagnóstico / Remediação**.

## Fases (internas)

Um run pode ser quebrado em **sub-fases internas** que vivem em
`.sleepwell/phases/<NN>-<slug>/`. Cada fase tem seu próprio `PLAN.md`,
`EXECUTION.md` e `VERIFICATION.md`. Rastreadas via `state.phases` no
`state.json`. Fases são opcionais — runs sem fases funcionam exatamente
como antes.

```
/sleepwell:sleepwell-phase-start "<slug>"          # opens a new phase (only one active at a time)
/sleepwell:sleepwell-phase-complete [--abandon]    # closes the active phase, generating VERIFICATION.md
```

Quando uma fase está ativa, o loop injeta o `PLAN.md` dela e o
`EXECUTION.md` recente em cada prompt de iteração e avalia critérios de
aceitação após cada iter. Veja [`lib/ritual.md` §9](lib/ritual.md).

## Fluxo PR-only

Runs do sleepwell sempre rodam numa branch descartável chamada
`sleepwell/auto/<run-id>` (onde `run-id = <unix-epoch>-<rand4hex>`). O
slug human-readable derivado da intent é preservado separadamente em
`state.slug`. Isso garante unicidade da branch entre runs paralelos e
mantém o namespace de branches limpo.

Quando um run termina (`status == done`), o loop invoca
`/sleepwell:sleepwell-pr` automaticamente e persiste a URL do PR resultante em
`state.pr_url`. O body do PR inclui intent, modo, contagem de iterações,
custo em USD, rating mais recente do evaluator e a lista de commits.

```bash
/sleepwell:sleepwell "<intent>"             # default: cria PR ao final
/sleepwell:sleepwell "<intent>" --no-pr     # roda mas não cria PR
/sleepwell:sleepwell "<intent>" --draft-pr  # cria PR como draft
```

Auto-merge fica **desabilitado por default**. Para habilitar auto-merge
condicional, aplique manualmente a label `sleepwell-auto-merge` no PR —
espera-se que uma GitHub Action server-side (não distribuída com este
plugin) consuma a label e rode `gh pr merge --auto` quando o CI passar.
O plugin apenas documenta a convenção.

## Compatibilidade

- Claude Code (target principal).
- Codex CLI (suporte de telemetria; execução do loop pode exigir adapter — veja roadmap).
- Qualquer linguagem com test runner via CLI.

## Projetos relacionados

- [anthropics/claude-code](https://github.com/anthropics/claude-code) — CLI oficial do Claude Code.
- Marketplaces de skills e plugin registries do Claude Code — sleepwell compõe com qualquer skill bem-formada ou MCP server que você instale.

Inspirado por trabalho prévio da comunidade em overnight-agents: loops com branch isolada e commits atômicos, prompting baseado em modos, e adaptação por voice/meta.

## Architecture Decisions

Veja [`docs/adr/`](docs/adr/) para os architecture decision records (ADRs).
Comece por [ADR-001: PR-only flow e CI awareness](docs/adr/001-pr-only-ci-awareness.md).

## Contribuindo

Issues e pull requests são bem-vindos. O loop, schema e ritual estão documentados em [`lib/ritual.md`](lib/ritual.md) (a fonte autoritativa). Rode `scripts/check-skill-deps.sh` para auditar referências a skills externas antes de abrir um PR.

## Créditos — veja [NOTICE.md](NOTICE.md) e [CREDITS.md](CREDITS.md).

## Licença

MIT
