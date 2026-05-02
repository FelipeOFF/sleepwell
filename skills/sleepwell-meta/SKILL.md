---
name: sleepwell-meta
description: Use no bootstrap do sleepwell-loop para gerar uma calibração baseada nos runs anteriores — quais commits foram mantidos vs descartados, e quais padrões o usuário endossou. Persiste em .sleepwell/calibration.md.
---

# sleepwell-meta

Meta-learning leve do sleepwell. Antes de uma nova run, lê o histórico das runs anteriores (branches `sleepwell/*` + main desde a última run) e infere insights sobre o que o usuário tende a manter.

## Quando ativar

- Bootstrap do `sleepwell-loop` (1ª iter), se `--no-meta` não for passado.
- Pedido explícito do usuário: "atualiza calibration".

## Algoritmo

1. **Localizar branches sleepwell anteriores:**
   ```bash
   git for-each-ref --format='%(refname:short) %(committerdate:iso)' refs/heads/sleepwell/* | sort -k2 -r | head -5
   ```
   Pega as 5 últimas branches sleepwell (ou todas se <5).

2. **Para cada branch sleepwell anterior:**
   - Lista commits da branch que NÃO estão em main:
     ```bash
     git log --oneline <branch>..main → o que foi pra main
     git log --oneline main..<branch>  → o que ficou só na branch
     ```
   - Classifica:
     - **Cherry-picked/merged em main** → usuário aprovou.
     - **Ficou na branch** → não foi aprovado (descartado, abandonado, ou pendente).
     - **Squash merge:** detecta via mensagem `[sleepwell-iter:N]` no log do main.

3. **Categoriza commits** pelo tipo (do `<type>` do conventional commit) e pelo conteúdo:
   - feat / refactor / fix / chore / test / docs.
   - Padrões textuais no diff: renames, novas abstrações, deletes, cobertura de testes, etc.

4. **Sumariza padrões** em `.sleepwell/calibration.md`:

```markdown
# Calibration — extraída em <ISO>
_Baseada em <N> runs sleepwell anteriores._

## Sinal positivo (mantenha fazendo)
- <pattern> — <evidência: "branch X iter 3 foi merged"> — confiança <high|med|low>
- ...

## Sinal negativo (evite)
- <pattern> — <evidência: "branch Y iter 5 ficou na branch e foi descartada">
- ...

## Volatilidade
- <quanto o usuário muda de ideia entre runs>
- <iterações típicas até convergir>

## Recomendações para próxima run
- <ação concreta>
```

5. **Limites:**
   - Se <2 runs anteriores: gera calibration mínima ("histórico insuficiente, sem ajustes").
   - Se runs muito antigas (>60 dias): pondera com peso menor.
   - Não invente padrões sem evidência.

## Output curto pro caller

Retorne uma string de 1-2 linhas: `"calibration: N runs prévias, X padrões positivos, Y negativos"` para o `sleepwell-loop` mostrar no boot.

## Privacidade

- Calibration é derivada SOMENTE do git log local. Não envia nada externo.
- Não inclua nomes de arquivos sensíveis (segredos, credenciais).

## Quando NÃO criar calibration

- Repo recém-iniciado, sem branches sleepwell anteriores → escreve calibration vazia com header.
- Flag `--no-meta` no `/sleepwell` → pula completamente.
