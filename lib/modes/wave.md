# Modo: wave (experimental)

**Apetite:** explorar mudanças significativas com auto-crítica embutida.
**Risco:** médio-alto — escopo de cada wave é maior que `refine`, menor que `radical`.

> **Status:** experimental. Ative com `--mode wave` no `/sleepwell`. Espere
> custo por iter ~3x maior (3 sub-agents em sequência). Feedback bem-vindo.

## Conceito

Cada **wave** = 1 iteração do loop, mas internamente roda **3 sub-agents em
sequência**, cada um com role distinta:

1. **Propor radical** (`role: proposer`) — gera uma mudança ambiciosa.
2. **Criticar** (`role: critic`) — adversarial review da proposta.
3. **Consolidar + commit** (`role: consolidator`) — aplica versão final
   ajustada pelo critic e commita.

Só o terceiro sub-agent escreve no working tree e commita. Os dois primeiros
produzem artefatos textuais (proposta + crítica) anexados ao `notes.md`.

## Quando usar

- Você quer a coragem do `radical` mas sem comprar o risco de não-revisão.
- A mudança tem múltiplas formas válidas e vale considerar trade-offs.
- O custo extra por iter é aceitável (orçamento via `--max-cost`).

## Quando NÃO usar

- Tarefas mecânicas (use `tidy`).
- Refactor pequeno bem definido (use `refine`).
- TDD cadenciado (use `build`).
- Reescrita estrutural óbvia já planejada (use `radical` direto).

## Roles e prompts

### Sub-agent 1 — Proposer

> Você é o **proposer** de uma wave do sleepwell. Sua tarefa é propor a
> mudança mais audaciosa que ainda seja defensável para a intent atual.
>
> Inputs: `state.intent`, `state.mode = wave`, últimas 30 linhas de
> `notes.md`, `git log <branch>` recente, `git diff --stat <base>..HEAD`.
>
> Output: uma proposta em Markdown com seções:
> - **Mudança proposta** (1 parágrafo claro).
> - **Por que radical** (o que essa abordagem ousa que uma refine não ousaria).
> - **Trade-offs conhecidos** (≥2).
> - **Plano de aplicação** (lista de passos concretos).
>
> NÃO escreva código no working tree. NÃO commite. Apenas devolva o markdown.

### Sub-agent 2 — Critic

> Você é o **critic** desta wave. Recebeu a proposta do proposer. Sua tarefa
> é abater a proposta com rigor — busque furos, riscos ocultos, soluções
> mais simples que entreguem 80% do valor.
>
> Output em Markdown:
> - **Furos** (lista numerada, cada item com 1-3 linhas).
> - **Riscos ocultos** (efeitos colaterais não-óbvios).
> - **Alternativa simpler** (proposta mais conservadora que entrega valor
>   parecido — pode ser "manter como está").
> - **Veredicto:** `aprovar`, `aprovar-com-ajustes`, ou `descartar`.
>
> Se `aprovar-com-ajustes`, liste os ajustes obrigatórios para o consolidator.
> NÃO escreva código. NÃO commite.

### Sub-agent 3 — Consolidator

> Você é o **consolidator**. Recebeu a proposta + a crítica.
>
> Regras:
> - Veredicto `aprovar` → aplica a proposta original.
> - Veredicto `aprovar-com-ajustes` → aplica a proposta integrando os
>   ajustes obrigatórios do critic.
> - Veredicto `descartar` → não toca em código; commita apenas anotação em
>   `notes.md` registrando a wave como aprendizado e marca a iter como
>   `pass` lógico (não fail — descartar é decisão válida).
>
> Tarefa final: aplicar mudanças no working tree, rodar `verify_cmds`
> (lint/typecheck/test), e fazer **um commit atômico** seguindo a
> convenção do repo. Anexa proposta + crítica + decisão final no
> `notes.md` da iter.

## Integração com `sleepwell-loop`

Quando `state.mode == "wave"`:

1. A skill `sleepwell-loop` detecta o modo no início da iter.
2. Em vez de executar o passo de "edição+verify+commit" diretamente,
   dispatcha 3 sub-agents em sequência (Task tool ou skill equivalente),
   passando o estado e os artefatos de cada etapa adiante.
3. O resultado da wave (pass/fail) é determinado pelo terceiro sub-agent,
   exatamente como em qualquer outro modo (lint+typecheck+test).
4. `consecutive_failures`, `total_passes`, `total_fails` continuam
   funcionando igual.
5. `cost_so_far_usd` acumula tokens dos 3 sub-agents — daí o custo ~3x.

## Notes.md por wave

Cada wave produz 3 blocos no `notes.md`:

```
### iter <N> — wave (proposer)
<conteúdo proposta>

### iter <N> — wave (critic)
<conteúdo crítica + veredicto>

### iter <N> — wave (consolidator)
<decisão final + commit hash + verify result>
```

## Permissões

Iguais a `refine` para o consolidator (não pode quebrar API pública sem
plano). Proposer pode sugerir radical, mas o consolidator é quem decide
aplicar — e respeita as restrições do modo.

## Heurística de fim

Igual aos outros modos: `stop_when` cumprido OU `max_iter` OU
`consecutive_failures >= 3` OU `cost_budget_usd` excedido.

## Checklist por wave

- [ ] Proposer entregou markdown estruturado, sem tocar working tree?
- [ ] Critic emitiu veredicto explícito (`aprovar`/`aprovar-com-ajustes`/`descartar`)?
- [ ] Consolidator respeitou o veredicto?
- [ ] Notes.md contém os 3 blocos da wave?
- [ ] Custo da iter foi anotado e somado em `cost_so_far_usd`?
