# sleepwell

Loop autônomo nativo do Claude Code. Junta o melhor do **gnhf** (disciplina: branch isolada, commit atômico por iteração, rollback automático em falha) com o melhor do **overnight** (adaptação ao usuário: voice matching, 4 modos de operação, meta-learning entre runs).

Diferente do gnhf/overnight que rodam fora via `claude -p`, o sleepwell vive **dentro** da sessão Claude Code:

- **Cache de prompt quente** entre iterações (TTL 5min) — sem cold start a cada loop.
- **MCPs continuam vivos** durante o loop (gitnexus, GSD, context7, memory).
- **Skills compõem** — pode invocar `superpowers:tdd`, `gsd-execute-phase`, etc.
- **Memory persistente** (`MEMORY.md`, feedbacks salvos) disponível dentro da iteração.

## Instalação

Como o repo já está em `~/Projects/my-claude-code-skills`, você pode:

**Opção A — symlink global:**
```bash
ln -s ~/Projects/my-claude-code-skills/sleepwell ~/.claude/plugins/sleepwell
```

**Opção B — copiar:**
```bash
cp -r ~/Projects/my-claude-code-skills/sleepwell ~/.claude/plugins/
```

**Opção C — usar via marketplace** (se publicar):
```bash
/plugin install sleepwell@FelipeOFF/sleepwell
```

Reinicie o Claude Code (`/restart`). Os comandos `/sleepwell*` aparecem.

## Uso rápido

```
/sleepwell "refatora o módulo de auth pra usar o novo middleware" --mode refine --max-iter 15
```

Outros comandos:

| Comando | O que faz |
|---|---|
| `/sleepwell "<intent>" [opts]` | Inicia o loop |
| `/sleepwell-status` | Estado atual (iteração, branch, modo, últimos commits) |
| `/sleepwell-diff` | Diff acumulado da branch sleepwell vs base |
| `/sleepwell-undo` | Reverte a última iteração com sucesso (`git reset --hard HEAD~1`) |
| `/sleepwell-stop` | Para o loop (cancela próximos `ScheduleWakeup`) |

## Modos

| Modo | Quando usar | Comportamento |
|---|---|---|
| `tidy` | Limpeza, organização, deps | Mudanças mecânicas, sem alterar comportamento |
| `refine` (default) | Melhorias contínuas, refactor incremental | Refatora preservando testes verdes |
| `build` | Construir feature nova end-to-end | TDD-first, rampa até feature completa |
| `radical` | Reescrever subsistemas | Permite quebrar e reconstruir, mais arriscado |

## Opções

```
/sleepwell "<intent>"
  --mode tidy|refine|build|radical    (default: refine)
  --max-iter <N>                       (default: 20)
  --stop-when "<condição NL>"          (avalia ao fim de cada iter)
  --no-worktree                        (default: usa worktree)
  --dry-run                            (não commita; mostra diff)
  --no-voice                           (pula voice profile)
  --no-meta                            (pula meta-learning)
```

## Anatomia de uma iteração

1. **Carrega state** — `.sleepwell/state.json` (counter, branch, modo, intent, profile, calibration).
2. **Checa abort** — max-iter, max-cost, stop-when, falhas consecutivas ≥3.
3. **Bootstrap** (só na 1ª iter):
   - Cria branch `sleepwell/<slug>` (com worktree se ativado).
   - Extrai voice profile dos JSONLs do projeto se cache >7 dias.
   - Lê meta-calibration do run anterior (`git log` da última branch sleepwell).
4. **Monta prompt da iteração** — intent + modo + voice + notes.md + last_diff + calibration.
5. **Executa** — Claude raciocina e edita arquivos.
6. **Verifica** — lint + type-check + testes (configuráveis no `.sleepwell/config.json` se existir).
7. **Branch de decisão**:
   - **Pass:** `git add -A && git commit` com mensagem conventional, `notes.md` recebe summary.
   - **Fail:** `git reset --hard HEAD`, incrementa contador de falhas, backoff exponencial.
8. **Atualiza state**.
9. **Decide próxima iter:**
   - Done (stop-when OK ou max-iter): finaliza, mostra resumo.
   - Continue: `ScheduleWakeup(delay=60-270s)` mantém cache quente; relança a si mesmo.

## Voice matching

Lê `~/.claude/projects/<proj>/*.jsonl`, extrai mensagens recentes do role `user`, sumariza em ~500 tokens (tom, vocabulário, idioma, padrões de pedido). Cacheia em `.sleepwell/voice-profile.md`. Re-extrai se >7 dias.

## Meta-learning

Antes da próxima run, compara:
- `git log --oneline` da branch sleepwell anterior
- `git log main --since=<run anterior>`

Mede quais commits foram cherry-picked/merged vs descartados. Persiste em `.sleepwell/calibration.md` insights tipo: *"usuário mantém refactors de naming, descarta abstrações novas"*. Injeta no prompt da próxima iter.

## Segurança

- **Nunca** roda em `main`/`master`/`develop` — sempre cria branch isolada.
- **Nunca** `--no-verify`, **nunca** `--force-push`.
- Falhas consecutivas ≥3 → abort automático.
- Worktree default isola mudanças do working tree principal.
- `--dry-run` permite avaliar antes de commitar.

## Estado

Toda a máquina de estado vive em `.sleepwell/` na raiz do repo onde rodou:

```
.sleepwell/
├── state.json          # counter, branch, mode, intent, status
├── notes.md            # log appendável de cada iteração
├── voice-profile.md    # cache do voice matching
└── calibration.md      # insights do meta-learning
```

`.sleepwell/` deve ir no `.gitignore` do projeto-cliente (não do plugin).

## Roadmap

Itens em progresso ou planejados:

- **`--max-cost <USD>`** (em progresso) — abort gate por orçamento; campos `cost_so_far_usd` / `cost_budget_usd` já no schema v2.
- **Telemetria de tokens** — `tokens_used.{input,output,cache_read,cache_creation}` acumulados por iter (já no schema v2; coleta a fazer).
- **`/sleepwell-resume`** — retomar explicitamente um loop pausado/abortado a partir do último state válido.
- **`/sleepwell-watch`** — modo TUI/dashboard para acompanhar iterações em tempo real.
- **`/sleepwell-recap`** — gera resumo final do run (commits, padrões, custo, tokens) em formato legível.
- **Modo `review-only`** — itera apenas com sugestões/diffs propostos, sem aplicar (útil pra revisão pré-merge).
- **Hook `PreToolUse` de escopo** — bloqueia edição fora do worktree/branch durante o loop, reforçando isolamento.

## Inspirações

- [yail259/overnight](https://github.com/yail259/overnight) — 4 modos (tidy/refine/build/radical), voice matching, meta-learning.
- [thebasedcapital/nightcrawler](https://github.com/thebasedcapital/nightcrawler) — loop autônomo overnight com TUI.
- [kunchenguid/gnhf](https://github.com/kunchenguid/gnhf) — disciplina de loop: branch isolada, commit atômico por iter, rollback em fail, caps de iteração/tokens.
- GSD (`get-shit-done`) — discuss + plan + execute + ship + verify como pipeline.
- `everything-claude-code:autonomous-agent-harness` — uso nativo de `ScheduleWakeup`/`Cron` e MCPs vivos durante o loop.

## Licença

MIT
