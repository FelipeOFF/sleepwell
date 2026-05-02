# sleepwell-helper

Binário Rust auxiliar do plugin **Sleepwell** para Claude Code. Distribuído como
artefato pré-compilado por release (multi-target) e usado pelos hooks/skills do
plugin.

## Build

```bash
cd bin/sleepwell-helper
cargo build --release
```

> Primeiro build precisa de internet para baixar dependências do registry.
> Builds posteriores são offline.

## Subcomandos

| Comando        | Status      | Descrição                                                                 |
|----------------|-------------|---------------------------------------------------------------------------|
| `parse-jsonl`  | stub (#17)  | Parser tolerante de JSONL para Claude / Codex / Gemini / Generic.         |
| `cost`         | stub (#18)  | Calcula custo USD a partir de usage + tabela `prices.toml` embutida.      |
| `hash`         | implementado| Hash blake3 de conteúdo (cache).                                          |
| `watch`        | implementado| Observa diretório com debounce e emite eventos JSONL.                     |
| `evaluate`     | stub        | Avalia outputs contra expectativas.                                       |
| `calibrate`    | stub        | Calibra parâmetros a partir de histórico.                                 |

### `parse-jsonl`

```bash
sleepwell-helper parse-jsonl <file> [--format auto|claude|codex|gemini|generic]
```

Auto-detect via path (`~/.claude/projects/`, `~/.codex/sessions/`, `~/.gemini/`).
Linhas com JSON inválido são puladas. Saída em stdout:

```json
{"format":"claude","turns":3,"totals":{"input":12,"output":34,"cache_read":0,"cache_creation":0}}
```

### `cost`

```bash
sleepwell-helper parse-jsonl session.jsonl | sleepwell-helper cost --format claude --model sonnet-4-5
```

Lê o JSON do `parse-jsonl` por stdin (ou `--input <file>`). Modelos
desconhecidos retornam `{"cost_usd": null, "error": "unknown model"}` com
warning em stderr.

## CI

`.github/workflows/release.yml` builda 5 alvos a cada tag `bin-v*` e publica os
artefatos no GitHub Release correspondente:

- `x86_64-apple-darwin`
- `aarch64-apple-darwin`
- `x86_64-unknown-linux-gnu`
- `aarch64-unknown-linux-gnu` (via `cross`)
- `x86_64-pc-windows-msvc`

Cache via `Swatinem/rust-cache@v2`; upload via
`softprops/action-gh-release@v2`.

## Tracking

- skeleton + CI multi-target — issue **#16**
- `parse-jsonl` multi-LLM — issue **#17**
- `cost` com `prices.toml` — issue **#18**
