# Changelog

All notable changes to **sleepwell** (the Claude Code plugin) are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/) and
[Conventional Commits](https://www.conventionalcommits.org/).

Each section is generated automatically by `scripts/generate-changelog.sh` during
the `Bump version & release` workflow. The `bin-v*` (helper binary) tags are
tracked separately on the GitHub Releases page.

## v0.7.2 — 2026-05-04

_Compare: [`bin-v0.7.1…v0.7.2`](https://github.com/FelipeOFF/sleepwell/compare/bin-v0.7.1...v0.7.2)_

### Bug fixes

- Corrige plugin_latest unknown e hooks com path relativo (05778fb)


## v0.7.1 — 2026-05-04

_Compare: [`bin-v0.7.0…v0.7.1`](https://github.com/FelipeOFF/sleepwell/compare/bin-v0.7.0...v0.7.1)_

### Features

- lib/team-workflow.md + config example YAML (21e5fcc)
- skill sleepwell-team + command sleepwell-team-fix (637220b)
- --restore-cache flag e cache integrity check (d73bded)
- scripts/restore-plugin-cache.sh standalone (b6c0feb)

### Bug fixes

- shellcheck SC2034+SC2155 em restore-plugin-cache.sh (2376d41)
- alinhar block_on_severity + interação restore-cache×reinstall (b71dde7)
- gh api/checks corrigidos + edge case no-checks (a6d0ce5)
- atomic write + parametrizar repo + cleanup de backups (3c34842)
- bump-version precisa de actions:write para gh workflow run (4f55fa0)

### Documentation

- README + integração com /sleepwell:sleepwell --with-team (93b4099)
- README Recovery section EN+PT-BR (c9a704b)


## v0.7.0 — 2026-05-04

_Compare: [`bin-v0.6.0…v0.7.0`](https://github.com/FelipeOFF/sleepwell/compare/bin-v0.6.0...v0.7.0)_

### Features

- registra check-update no plugin.json e plugando ensure-helper (7903e7a)
- hooks/check-update.sh + commands/sleepwell-update.md (e0834b2)

### Bug fixes

- Aplica gaps do review do update check (16d3187)
- bump-version dispara release.yml apos criar a tag (735d808)

### Documentation

- Clarifica fluxo do /sleepwell-update e documenta opt-out (6912439)

### Other

- docs+sec: README updates section + Tab tip + auditoria eval/read (c8851bf)

