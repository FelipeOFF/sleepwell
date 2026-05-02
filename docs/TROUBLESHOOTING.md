# Troubleshooting — sleepwell

Playbook PT-BR para problemas comuns ao rodar o loop. Cada cenário segue o
formato **Sintomas / Diagnóstico / Remediação**.

---

## 1. State corrompido (`.sleepwell/state.json` inválido)

**Sintomas**

- `/sleepwell:sleepwell-status` falha com erro de parse JSON.
- Próxima retomada do loop crasha imediatamente.
- `cat .sleepwell/state.json` mostra JSON truncado ou caractere lixo.

**Diagnóstico**

```bash
jq . .sleepwell/state.json
```

Se `jq` reclama de parse, o arquivo está corrompido. Causas usuais:
processo CC derrubado entre `mktemp` e `mv` (raro — escrita é atômica), disk
full, ou edição manual mal feita.

**Remediação**

1. Procurar o último archive válido:
   ```bash
   ls -lt .sleepwell/archive/
   ```
2. Restaurar:
   ```bash
   cp .sleepwell/archive/<timestamp>/state.json .sleepwell/state.json
   ```
3. Se não houver archive utilizável, bootstrap fresh:
   ```bash
   mv .sleepwell/state.json .sleepwell/state.json.broken
   /sleepwell:sleepwell "<intent original>" [--mode ...] [--max-iter ...]
   ```

---

## 2. Worktree órfão

**Sintomas**

- `git worktree add` falha com `<branch> is already checked out at <path>`.
- Diretório `../<repo>-wt/sleepwell:sleepwell-<slug>` foi removido manualmente, mas o
  Git ainda registra o worktree.

**Diagnóstico**

```bash
git worktree list
```

Worktrees marcados como `prunable` ou apontando para path inexistente são
órfãos.

**Remediação**

```bash
git worktree prune          # limpa registros sem diretório no disco
git worktree remove <path>  # remove explicitamente um worktree
```

Confirme com `git worktree list`. Depois retome o loop normalmente.

---

## 3. ScheduleWakeup duplicado

**Sintomas**

- Múltiplas iterações disparando "ao mesmo tempo".
- `notes.md` mostra duas iters com timestamp muito próximo.
- Logs do Claude Code com dois resumes consecutivos.

**Diagnóstico**

```bash
ls -la .sleepwell/resume.lock 2>/dev/null
cat .sleepwell/resume.lock 2>/dev/null
```

Se o `.sleepwell/resume.lock` existe e está velho (PID morto, ou data antiga),
um wakeup anterior travou sem soltar a trava — e um segundo schedule foi
criado.

**Remediação**

1. Verificar se o PID listado no lock ainda está vivo (`ps -p <pid>`).
2. Se morto, remover o lock manualmente:
   ```bash
   rm .sleepwell/resume.lock
   ```
3. Se vivo e duplicado, parar o loop com `/sleepwell:sleepwell-stop` e reiniciar.

---

## 4. Voice cache stale

**Sintomas**

- Loop produz commits com tom muito diferente do habitual do usuário.
- `voice-profile.md` está datado de muitos dias atrás.
- O usuário mudou o estilo de pedido recentemente e o loop continua com voice
  antigo.

**Diagnóstico**

```bash
stat -f '%Sm' .sleepwell/voice-profile.md   # macOS
stat -c '%y' .sleepwell/voice-profile.md    # linux
```

Se o arquivo tem mais de 7 dias, deveria ter sido re-extraído
automaticamente. Se não foi, force.

**Remediação**

```bash
rm .sleepwell/voice-profile.md
```

Próxima iter dispara nova extração via `sleepwell-profile`.

---

## 5. Lint não detectado

**Sintomas**

- `verify_cmds.lint` está vazio em `state.json`.
- Iters comitam código sem checar lint.
- `auto` detection não encontrou nada (projeto sem `eslint`/`ruff`/etc).

**Diagnóstico**

```bash
jq '.verify_cmds' .sleepwell/state.json
```

**Remediação**

Setar manualmente via edição atômica:

```bash
tmp=$(mktemp .sleepwell/state.json.XXXXXX)
jq '.verify_cmds.lint = "npm run lint"' .sleepwell/state.json > "$tmp"
mv "$tmp" .sleepwell/state.json
```

Substitua `npm run lint` pelo comando real do projeto. Aplica o mesmo padrão
para `typecheck` e `test`.

---

## 6. Custo crescendo sem limite

**Sintomas**

- `/sleepwell:sleepwell-status` mostra `cost_so_far_usd` subindo rápido.
- Sem `cost_budget_usd` configurado, o loop pode consumir orçamento
  indefinidamente.

**Diagnóstico**

```bash
jq '{cost_so_far_usd, cost_budget_usd, max_cost_per_iter_usd}' \
  .sleepwell/state.json
```

**Remediação**

1. **Habilitar `--max-cost`** no próximo bootstrap:
   ```
   /sleepwell:sleepwell "<intent>" --max-cost 5
   ```
2. **Habilitar `--max-cost-per-iter`** para guardrail por iter:
   ```
   /sleepwell:sleepwell "<intent>" --max-cost 5 --max-cost-per-iter 0.50
   ```
3. Em loop ativo, atualizar o budget direto no state:
   ```bash
   tmp=$(mktemp .sleepwell/state.json.XXXXXX)
   jq '.cost_budget_usd = 5' .sleepwell/state.json > "$tmp"
   mv "$tmp" .sleepwell/state.json
   ```

Próxima iter vai checar o gate (ver `lib/ritual.md §8.1`).

---

## 7. Push bloqueado pelo hook

**Sintomas**

- `git push` falha com mensagem do hook `block-push.sh`.
- Mensagem cita "loop sleepwell ativo".

**Diagnóstico**

Esse comportamento é **esperado**. Durante um loop ativo, `hooks/block-push.sh`
impede push para evitar publicar trabalho ainda não validado.

**Remediação**

1. Pare o loop antes de pushar:
   ```
   /sleepwell:sleepwell-stop
   ```
2. Confirme `status == "stopped"` em `/sleepwell:sleepwell-status`.
3. Faça o push normalmente.

Se você precisa pushar com o loop ainda ativo (ex.: hotfix paralelo em outra
branch), use um worktree separado fora do escopo do `scope-guard.sh`.
