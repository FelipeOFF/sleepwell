---
name: sleepwell-meta
description: Use no bootstrap do sleepwell-loop para gerar uma calibração baseada nos runs anteriores. Versão v2 consome `sleepwell-helper calibrate` e persiste prediction_profile em state.json; fallback grácil mantém calibration.md textual antigo.
---

# sleepwell-meta (v2)

Meta-learning leve do sleepwell. No bootstrap (e por pedido explícito), lê o
histórico de runs sleepwell anteriores e produz **dois artefatos**:

1. **`state.prediction_profile`** (estruturado, v3) — consumido pelo
   `sleepwell-loop` para influenciar o prompt das iters.
2. **`.sleepwell/calibration.md`** (textual, legado) — mantido como fallback
   humano-legível quando o helper Rust não está disponível.

## Quando ativar

- Bootstrap do `sleepwell-loop` (1ª iter), se `--no-meta` não for passado.
- Pedido explícito do usuário: "atualiza calibration".

## Pipeline preferencial — `sleepwell-helper calibrate`

```bash
if command -v sleepwell-helper >/dev/null 2>&1; then
  profile_json=$(sleepwell-helper calibrate \
    --archive .sleepwell/archive/ \
    --repo .)
fi
```

Saída esperada (JSON em stdout, salvo em `state.prediction_profile`):

```json
{
  "overall": 0.72,
  "by_category": {
    "feat":    0.81,
    "fix":     0.65,
    "refactor":0.50,
    "tidy":    0.90,
    "refine":  0.74,
    "build":   0.60
  },
  "trusted":   ["tidy", "feat"],
  "distrusted":["radical", "refactor"],
  "n_runs": 12,
  "calibrated_at": "2026-05-02T15:42:00-03:00"
}
```

`overall` = % de commits aprovados pelo usuário (mantidos na base, não
descartados). `by_category` quebra por mode e/ou conventional type.
`trusted`/`distrusted` saem do top/bottom de `by_category` (threshold default
≥0.75 trusted, ≤0.55 distrusted).

## Persistência atômica

```bash
tmp=$(mktemp .sleepwell/state.json.XXXXXX)
jq --argjson p "$profile_json" '.prediction_profile = $p' \
   .sleepwell/state.json > "$tmp"
mv "$tmp" .sleepwell/state.json
```

Ver `lib/ritual.md §7.2`.

## Injeção no prompt do loop

A cada iter, o `sleepwell-loop` consulta `state.prediction_profile` e injeta
no prompt:

- Se `state.mode in trusted` → adiciona linha:
  `## Calibração\n- Mode "<mode>" tem histórico positivo (acurácia <X>%, n=<N>).
  Encoraja-se profundidade.`
- Se `state.mode in distrusted` → adiciona linha:
  `## Calibração\n- Mode "<mode>" tem histórico negativo (acurácia <X>%, n=<N>).
  Cautela: prefira diff pequeno e reversível.`
- Se `state.mode` não está em nenhum → omite seção (sinal insuficiente).

## Fallback grácil — sem helper

Quando `command -v sleepwell-helper` falha:

1. **NÃO** tenta replicar parsing de git log em bash (a versão v1 fazia isso
   via grep — removida nesta v2 por ser frágil e duplicar lógica do helper).
2. Mantém o comportamento textual legado em `.sleepwell/calibration.md`:
   - Se já existir `.sleepwell/calibration.md` (de run anterior), só lê e
     repassa para o caller.
   - Se ausente, cria uma versão mínima:
     ```markdown
     # Calibration — extraída em <ISO>
     _sleepwell-helper indisponível; calibration estruturada pulada._

     Sem sinais por categoria. Loop opera sem ajuste de profile.
     ```
3. **NÃO** escreve `state.prediction_profile` quando em fallback (deixa o campo
   ausente — o loop trata ausência como neutro).

Logue `meta: helper ausente, prediction_profile pulado` no notes.md.

## Limites e edge cases

- Sem `.sleepwell/archive/` ou repo recém-iniciado: helper retorna
  `n_runs: 0`; persiste o profile mesmo assim, e o loop trata `n_runs < 3`
  como "sem sinal" (não injeta).
- Runs muito antigas (>60 dias): o helper já pondera com peso menor; a skill
  apenas confia no output.
- Privacidade: tudo local. Nada sai do disco.

## Output curto pro caller

Após persistir, retorne uma string de 1 linha:
`"meta: prediction_profile atualizado (overall=X%, n=N, trusted=[...], distrusted=[...])"`.

Em fallback: `"meta: helper ausente, calibration textual mantida"`.

## Quando NÃO calibrar

- Flag `--no-meta` no `/sleepwell` → pula completamente.
- `state.prediction_profile.calibrated_at` < 24h → reusa o existente.
