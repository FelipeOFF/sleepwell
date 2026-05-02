# Skill dependency map

sleepwell was designed to **work standalone** — the core flow
(bootstrap, iteration, verify, commit, rollback, ScheduleWakeup) does not require
any external skill. Optional skills enhance the experience but do not
block the loop.

## Minimalist bundling policy

We vendor **only** what is strictly necessary for the core flow. Anything that is
"nice to have" stays as an optional recommendation — the user installs it if desired.

| Referenced skill                           | Type      | Policy                            | Vendor path                                |
|--------------------------------------------|-----------|-----------------------------------|--------------------------------------------|
| `superpowers:test-driven-development`      | dev       | optional (recommended)            | —                                          |
| `obsidian-markdown`                        | recap     | optional                          | —                                          |
| `superpowers:using-git-worktrees`          | bootstrap | required → vendor                 | `skills/vendor/git-worktrees/SKILL.md`     |
| `everything-claude-code:gateguard`         | hooks     | replaced by local hooks           | `hooks/block-push.sh`, `hooks/scope-guard.sh` |

### Per-line details

**`superpowers:test-driven-development`** — used in `build` mode when the loop
opts for TDD-first. Without it, the loop still works; falls back to the standard
verify flow. Recommended for users running `--mode build`.

**`obsidian-markdown`** — used only in the final/diary recap. Without it, recap
generates plain markdown. Does not block.

**`superpowers:using-git-worktrees`** — referenced at bootstrap when
`worktree_enabled=true` (default). Since worktree is the default and
safe path, we vendor a minimal stub (`skills/vendor/git-worktrees/SKILL.md`)
to ensure the flow works without installing superpowers.

**`everything-claude-code:gateguard`** — write/push guards. **We do not
vendor** because we have our own hooks (`hooks/block-push.sh`,
`hooks/scope-guard.sh`) registered in `.claude-plugin/plugin.json` that
cover the use case.

## Verification

Run `scripts/check-skill-deps.sh` to list references to external skills
in the plugin and check which are not vendored. Useful output for CI / pre-release.
