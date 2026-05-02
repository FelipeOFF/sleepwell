---
description: Diagnostica o ambiente do sleepwell, verifica binário sleepwell-helper e (re)instala se necessário.
argument-hint: "[--reinstall] [--version <tag>] [--dest <dir>]"
---

# /sleepwell:sleepwell-doctor

Verifica o ambiente local e garante que o binário `sleepwell-helper` está
instalado para a plataforma atual.

## Etapas

1. **Detecta plataforma** (OS + arch).
2. **Verifica `sleepwell-helper`** em ordem:
   - `$XDG_DATA_HOME/sleepwell/bin/sleepwell-helper` (Linux/macOS)
   - `~/.local/share/sleepwell/bin/sleepwell-helper`
   - `$LOCALAPPDATA/sleepwell/bin/sleepwell-helper.exe` (Windows)
   - `$PATH`
3. **Se ausente ou flag `--reinstall`**, executa `scripts/install-helper.sh`
   (Linux/macOS) ou `scripts/install-helper.ps1` (Windows) baixando o
   binário do GitHub Releases (`FelipeOFF/sleepwell`).
4. **Smoke test**: roda `sleepwell-helper --version` e `sleepwell-helper --help`.
5. **Verifica deps externas**: `git`, `gh` (opcional), `jq` (opcional para
   fallback bash).
6. **Reporta tabela** com cada verificação e remediation hint.

## Args

- `--reinstall` — força redownload mesmo que binário esteja presente.
- `--version <tag>` — instala uma versão específica (ex: `bin-v0.5.0`).
- `--dest <dir>` — diretório alternativo de instalação.

## Saída

```
Platform:           darwin / aarch64
sleepwell-helper:   ✓ installed (v0.5.0) at ~/.local/share/sleepwell/bin/sleepwell-helper
git:                ✓ 2.45.1
gh:                 ✓ 2.45.0 (authenticated as user@example.com)
jq:                 ✓ 1.7
verify_cmds:        ⚠ partial — typecheck=auto, test=npm test, lint=missing
hooks:              ✓ block-push.sh, scope-guard.sh, ensure-helper.sh executable
state schema:       ✓ v3
```

## Comportamento por OS

- **macOS / Linux**: invoca `bash scripts/install-helper.sh --skip-if-present`.
- **Windows**: invoca `powershell -ExecutionPolicy Bypass -File scripts/install-helper.ps1 -SkipIfPresent`.

## Quando usar

- Primeira vez instalando o plugin.
- Após upgrade do plugin (verificar se há novo binário).
- Antes de runs longos (overnight) para garantir o ambiente.
- Quando alguma skill reportar `sleepwell-helper not found`.

## Notas

- O hook `SessionStart` (`hooks/ensure-helper.sh`) já tenta instalar
  automaticamente em background quando uma sessão Claude Code abre. Este
  comando é o caminho explícito quando você quer feedback imediato ou
  forçar reinstalação.
- O download usa GitHub Releases públicos — não requer autenticação.
- Se nenhum binário pré-compilado existir para sua plataforma, o doctor
  sugere `cargo install --path bin/sleepwell-helper`.
