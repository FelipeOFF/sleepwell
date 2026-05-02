---
name: sleepwell-profile
description: Use para extrair ou atualizar o voice profile do usuário a partir dos transcripts JSONL do Claude Code. Produz um sumário curto (~500 tokens) sobre tom, vocabulário, idioma e padrões de pedido, cacheado em .sleepwell/voice-profile.md. Re-extrai se cache >7 dias.
---

# sleepwell-profile

Extrai um **voice profile** do usuário lendo os transcripts JSONL do Claude Code do projeto atual. O profile é injetado nas iterações do `sleepwell-loop` para que as mudanças soem como o próprio usuário escreveria — não como output genérico de assistente.

## Quando ativar

- Bootstrap do `sleepwell-loop` (1ª iter), se `--no-voice` não for passado.
- Cache `.sleepwell/voice-profile.md` ausente OU mais antigo que 7 dias (mtime).
- Usuário pediu explicitamente: "atualiza o voice profile do sleepwell".

## Algoritmo

1. **Localizar transcripts:**
   - Path padrão: `~/.claude/projects/<project-slug>/*.jsonl`.
   - `<project-slug>` = transformação do absolute path do repo: barras viram hífens, sem leading slash.
     - Ex: `/Users/felipeoliveira/Projects/my-claude-code-skills` → `-Users-felipeoliveira-Projects-my-claude-code-skills`.
   - Comando: `ls -t ~/.claude/projects/<slug>/*.jsonl 2>/dev/null | head -10` (10 sessões mais recentes).

2. **Extrair mensagens do user:**
   - Cada linha JSONL é um evento. Filtre `type == "user_message"` ou similar.
   - Extraia campo `content`/`text` da mensagem do role `user`.
   - **Ignore** mensagens curtas (<20 chars) ou que sejam apenas comandos (`/foo`, `git ...`).
   - Limite total: 50 mensagens mais recentes não-triviais (truque: leia até atingir 50 ou esgotar arquivos).

3. **Filtrar para sinal:**
   - Remova system reminders, hooks, tool results, `<system-reminder>` blocks.
   - Mantenha o que o usuário REALMENTE escreveu.

4. **Sumarizar em ~500 tokens** com seções fixas:

```markdown
# Voice Profile — <usuário, se identificável>
_Extraído em <ISO date> de <N> mensagens recentes._

## Idioma
<idioma dominante, mistura de idiomas, code-switching>

## Tom
<formal/informal, direto/explicativo, técnico/conversacional>

## Vocabulário recorrente
<termos técnicos preferidos, jargões, marcas de identidade>

## Padrões de pedido
<como abre tarefas: "faça X", "to pensando em X", "explica Y", etc>
<como dá feedback: corrige direto / explica antes / questiona>

## Anti-padrões (o que NÃO fazer)
<inferir do que ele corrige: emojis, redundância, etc>

## Exemplos curtos
- "<frase real ou parafraseada>"
- "<outra>"
- "<outra>"
```

5. **Persistir** em `<repo-do-cliente>/.sleepwell/voice-profile.md`.

6. **Retornar** um resumo de 1 linha pra quem invocou: `"voice profile extraído de N msgs, idioma X, tom Y"`.

## Fallback

- Sem JSONLs / projeto não encontrado: retorne profile genérico:
  ```markdown
  # Voice Profile — fallback
  Sem histórico disponível. Use defaults: PT-BR, tom direto, sem emojis,
  termos técnicos em inglês, identificadores em inglês.
  ```
- Pasta `~/.claude/projects/` não existe: mesmo fallback.

## Privacidade

- **Não** inclua segredos, paths privados, ou conteúdo sensível no profile.
- **Não** envie o profile para fora do disco local.
- O profile cacheado deve ser legível por humano e revisável.

## Implementação prática

Comando shell sugerido (Bash) para coletar mensagens:

```bash
PROJ_SLUG=$(pwd | sed 's|/|-|g')
JSONL_DIR=~/.claude/projects/${PROJ_SLUG}

ls -t "${JSONL_DIR}"/*.jsonl 2>/dev/null | head -10 | \
  xargs cat 2>/dev/null | \
  jq -r 'select(.type=="user" or .role=="user") | .content // .message // empty' 2>/dev/null | \
  grep -v '^/' | \
  grep -v '^<system-reminder>' | \
  awk 'length > 20' | \
  head -50
```

Depois sumarize com seu próprio raciocínio (não chame outro modelo).

## Quando re-extrair

- Cache `.sleepwell/voice-profile.md` mtime >7 dias.
- Usuário rodou `/sleepwell` em projeto novo (slug diferente).
- Usuário pediu explicitamente.
- Bootstrap detecta voice profile vazio ou malformado.
