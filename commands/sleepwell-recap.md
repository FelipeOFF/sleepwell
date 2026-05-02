---
description: Generates a "my night" post-run narrative in an Obsidian vault.
argument-hint: "[--vault PATH] [--no-write]"
---

# /sleepwell-recap

Generates a first-person diary note (PT-BR) about the night the agent
worked. Reads all material from the run and writes it to an Obsidian vault in the
canonical dev-journal format.

## Arguments

```
--vault <PATH>        Obsidian vault root directory (override)
--no-write            only shows the generated note, does not create file
```

## Vault resolution

Order of precedence:

1. `--vault <path>` (if passed)
2. `$OBSIDIAN_VAULT` (env)
3. `~/obsidian-vault` (default)

If the directory does not exist → creates it with `mkdir -p`.

## Inputs read

- `.sleepwell/state.json` — intent, mode, branch, iters, passes, fails,
  cost_so_far_usd, started_at, last_iter_at.
- `.sleepwell/notes.md` — chronological loop log.
- `.sleepwell/calibration.md` (if present) — user tone/style.
- `git log <branch>` — commits of the run.
- `git diff --stat <base>..HEAD` — where `<base>` is `main`/`master`/`develop`
  (detected via `lib/ritual.md §7.1`). If none exist, uses `HEAD~N`.

## Note path

```
<vault>/SleepWell/<YYYY-MM-DD>-<slug>.md
```

`<slug>` comes from `state.slug`. If the note already exists, suffix with: `-2`, `-3`, ...

## Frontmatter

```yaml
---
date: <YYYY-MM-DD>
type: sleepwell-recap
intent: "<state.intent>"
mode: <state.mode>
branch: <state.branch>
iters: <state.iteration>
passes: <state.total_passes>
fails: <state.total_fails>
cost_usd: <state.cost_so_far_usd>
tags: [sleepwell, dev-journal]
---
```

## Body (generation)

Use the `obsidian-markdown` skill if available, passing this prompt:

> You are the user writing in a diary about the night the agent worked.
> Tone in PT-BR, first person, contemplative but honest. Include:
> - what was attempted (intent + mode);
> - what worked and what failed (no sugarcoating);
> - 1 insight from the night;
> - 1 open question.
>
> ~400 words. No long lists — diary prose.
>
> Material:
> - intent: <state.intent>
> - mode: <state.mode>
> - iters/passes/fails: <X/P/F>
> - cost: $<USD>
> - calibration (tone): <contents of calibration.md, if present>
> - notes.md (summary): <last 50 lines>
> - commits: <git log oneline>
> - diff stat: <diff --stat>

If the `obsidian-markdown` skill is unavailable, generate the note
directly with the same prompt.

## `--no-write`

Only prints the generated frontmatter + body to the terminal. Does not touch the vault.
Useful for reviewing before persisting.

## Edge cases

- `state.json` missing → error: "no sleepwell loop found in this repo."
- `notes.md` missing → proceed with warning (likely a very short run).
- vault non-existent → creates directory (`<vault>` and `<vault>/SleepWell`).
- note already exists → suffix `-2`, `-3`... before writing.
- empty `git diff --stat` → mentions in the body that the night was exploratory
  with no consolidated change.

## Post-execution

Shows the final note path and suggests:
```
note generated: <vault>/SleepWell/<YYYY-MM-DD>-<slug>.md
open it in Obsidian or run `obsidian-cli open` if configured.
```
