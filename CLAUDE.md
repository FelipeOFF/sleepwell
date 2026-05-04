# CLAUDE.md — sleepwell

Project-specific instructions for Claude Code agents working inside this repo.

## Asking the user questions

**Always use the `AskUserQuestion` tool when you need a decision, clarification,
or preference from the user.** Never ask via plain text in the chat when the
question expects a discrete answer.

This applies to:

- Disambiguating intent (e.g. "did you mean A or B?")
- Choosing between implementation strategies
- Confirming destructive or hard-to-reverse actions
- Selecting target scope (which repo, which branch, which env)

Why: structured questions with explicit options are auditable, parseable by
downstream skills (`sleepwell-team`, `sleepwell-meta`), and avoid ambiguous
free-text replies that derail multi-agent runs.

Plain text questions are only acceptable when:

- The answer is genuinely free-form prose (e.g. "describe the bug").
- You are inside a sub-agent that does not have `AskUserQuestion` available —
  in that case, return control to the orchestrator and let it ask.

This rule is also reflected in `lib/team-workflow.md` §11 and the
`sleepwell-team` SKILL.md.

## Other repo conventions

- Conventional Commits + Jira format from the user's global rules
- Branches: `<type>/<slug_snake_case>` (no Jira card for this repo's internal work)
- Plugin hook paths must use `${CLAUDE_PLUGIN_ROOT}/...`, never relative
- Cross-platform helper binary lives in `bin/sleepwell-helper/` (Rust)
- Release process: `bump-version.yml` → tag `vX.Y.Z` (plugin) + `bin-vX.Y.Z` (helper)
