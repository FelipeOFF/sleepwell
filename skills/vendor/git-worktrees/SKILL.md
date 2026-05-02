---
name: git-worktrees
description: Minimal stub for using git worktree during sleepwell bootstrap. Creates/removes worktrees in ../<repo>-wt/<name> with an isolated branch.
---

<!--
License: Apache-2.0
Inspired by superpowers:using-git-worktrees (only general concepts of
using git worktree from Git itself). This version is a simplified,
original rewrite tailored to the sleepwell flow. No proprietary content
was copied.
-->

# git-worktrees (vendor stub)

Minimal stub so the sleepwell core flow can run **without depending on** the
external `superpowers:using-git-worktrees` skill. Covers only what the
bootstrap needs.

## When to use

When the sleepwell bootstrap runs with `worktree_enabled=true` (default) and
needs to create an isolated working tree for the `sleepwell/<slug>` branch.

## Path pattern

```
../<repo>-wt/<name>
```

Where `<repo>` is the basename of the current directory and `<name>` is
typically `sleepwell-<slug>`.

## Commands

### Create worktree with new branch

```bash
git worktree add ../<repo>-wt/<name> -b <branch>
```

Example (sleepwell):

```bash
git worktree add ../sleepwell-wt/sleepwell-refactor-auth \
  -b sleepwell/refactor-auth
```

### List existing worktrees

```bash
git worktree list
```

### Remove worktree

```bash
git worktree remove ../<repo>-wt/<name>
```

If orphaned (directory deleted manually):

```bash
git worktree prune
```

## Prerequisites

- Git ≥ 2.5 (`worktree` support).
- Main repo working tree clean (or state already handled via stash).
- Target branch does not exist yet (or `git worktree add` fails; sleepwell
  detects and adjusts the slug).

## Common errors

- `fatal: '<branch>' is already checked out at '<path>'` → existing worktree
  for the same branch. Use `git worktree list` and remove the old one if orphaned.
- `fatal: invalid reference: <branch>` → `-b` flag missing when the branch
  does not exist.

## Reference

- `git help worktree` (official manpage).
- `lib/ritual.md §2` — worktree usage in bootstrap.
- `commands/wt.md` (if present in the user's global profile).
