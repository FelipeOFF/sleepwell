---
description: Sugere 3 planos overnight ranqueados a partir do workspace, TODOs, status e calibração.
---

# /sleepwell-suggest

Inspeciona o workspace atual e propõe **3 planos overnight** ordenados por
confiança, derivada da calibração estatística de runs anteriores.

## Inputs lidos

1. **Workspace dirty:** `git status -s` — arquivos modificados/staged
   sugerem trabalho em curso passível de "polish/refine".
2. **TODOs/FIXMEs:** `grep -rE "TODO|FIXME" --include="*.{md,ts,tsx,js,jsx,py,rs,go,rb,java,cs}"`
   limitado às primeiras 50 ocorrências (head -n 50).
3. **State atual** (se houver): `.sleepwell/state.json` — intent corrente,
   modo, status. Evita sugerir o que já está rodando.
4. **Calibração:** `.sleepwell/calibration.md` (output da skill
   `sleepwell-meta`) e, se existir, o campo `prediction_profile` no
   `state.json` (ou `.sleepwell/prediction_profile.json`) com forma:
   ```json
   {
     "by_category": {
       "tidy":    { "merge_rate": 0.85, "avg_cost_usd": 0.30, "avg_iters": 6 },
       "refine":  { "merge_rate": 0.70, "avg_cost_usd": 0.90, "avg_iters": 12 },
       "build":   { "merge_rate": 0.55, "avg_cost_usd": 1.80, "avg_iters": 18 },
       "radical": { "merge_rate": 0.30, "avg_cost_usd": 2.50, "avg_iters": 20 }
     }
   }
   ```
   - `Confidence` (0-100) = `merge_rate * 100`. Se `prediction_profile`
     ausente, fallback heurístico: tidy=80, refine=65, build=50,
     radical=35, wave=40.

## Fluxo

1. Coleta os inputs acima na sessão atual (sem chamada externa).
2. **Compõe prompt para o próprio Claude** (mesma sessão) com:
   - lista de TODOs/FIXMEs (com path:linha);
   - resumo de `git status -s`;
   - intent/mode da run em curso (se houver);
   - tabela `by_category` da calibração.
3. Pede ao Claude que ranqueie 3 planos diversos, cada um com:
   - **Intent** (frase imperativa curta, PT-BR);
   - **Mode** (tidy/refine/build/radical/wave);
   - **Max-iter** sugerido (alinhado com `avg_iters` da categoria);
   - **Expected cost** (alinhado com `avg_cost_usd`);
   - **Confidence** (de `prediction_profile.by_category[mode].merge_rate`,
     ou fallback heurístico se ausente);
   - **Justificativa** — 1 frase explicando por que esse plano agora.
4. Ordena por `Confidence` desc.

## Output

Tabela markdown:

```
| # | Intent                                | Mode    | Max-iter | Expected cost | Confidence |
|---|---------------------------------------|---------|----------|---------------|------------|
| 1 | Limpar deps não usadas e formatar     | tidy    | 6        | ~$0.30        | 85%        |
| 2 | Extrair middleware de auth            | refine  | 12       | ~$0.90        | 70%        |
| 3 | Adicionar endpoint /metrics com tests | build   | 18       | ~$1.80        | 55%        |
```

Abaixo da tabela, para cada linha, 1 frase de justificativa:

```
1. tidy — Limpar deps não usadas e formatar
   Há 14 TODOs em arquivos JS e working tree limpo: noite ideal para
   higienização mecânica de baixo risco.

2. refine — Extrair middleware de auth
   `src/auth/*` aparece em 8 commits recentes; refine tem alta merge_rate
   histórica (70%) nesta categoria.

3. build — Adicionar endpoint /metrics com tests
   TODO claro em `server/routes.ts:42`; modo build com TDD encaixa.
```

## Edge cases

- Sem TODOs e working tree limpo → sugere planos baseados em
  calibração genérica (refactor de hot-spots de `git log --stat`).
- Sem calibração → fallback heurístico em Confidence; nota no rodapé:
  "Confidence baseada em heurística (sem prediction_profile)."
- Run ativa em curso → não sugere o mesmo intent; pode sugerir
  tidy/refine paralelo em outra branch.
- `prediction_profile` malformado → ignora, usa fallback.

## Sem efeitos colaterais

`/sleepwell-suggest` é **read-only**. Não cria branch, não escreve em
`.sleepwell/`, não dispara loop. Apenas imprime a tabela.

## Pós-execução

```
para iniciar plano #1:
  /sleepwell "<intent>" --mode <mode> --max-iter <N>
```
