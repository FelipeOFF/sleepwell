# Troubleshooting — sleepwell

Playbook for common issues when running the loop. Each scenario follows the
**Symptoms / Diagnosis / Remediation** format.

---

## 1. Corrupted state (`.sleepwell/state.json` invalid)

**Symptoms**

- `/sleepwell:sleepwell-status` fails with a JSON parse error.
- Next loop resume crashes immediately.
- `cat .sleepwell/state.json` shows truncated JSON or garbage characters.

**Diagnosis**

```bash
jq . .sleepwell/state.json
```

If `jq` complains about parsing, the file is corrupted. Common causes:
CC process killed between `mktemp` and `mv` (rare — write is atomic), disk
full, or bad manual edit.

**Remediation**

1. Find the latest valid archive:
   ```bash
   ls -lt .sleepwell/archive/
   ```
2. Restore:
   ```bash
   cp .sleepwell/archive/<timestamp>/state.json .sleepwell/state.json
   ```
3. If no usable archive, fresh bootstrap:
   ```bash
   mv .sleepwell/state.json .sleepwell/state.json.broken
   /sleepwell:sleepwell "<original intent>" [--mode ...] [--max-iter ...]
   ```

---

## 2. Orphaned worktree

**Symptoms**

- `git worktree add` fails with `<branch> is already checked out at <path>`.
- The directory `../<repo>-wt/sleepwell:sleepwell-<slug>` was removed manually, but
  Git still records the worktree.

**Diagnosis**

```bash
git worktree list
```

Worktrees marked as `prunable` or pointing to a non-existent path are
orphans.

**Remediation**

```bash
git worktree prune          # cleans up records without on-disk dirs
git worktree remove <path>  # explicitly removes a worktree
```

Confirm with `git worktree list`. Then resume the loop normally.

---

## 3. Duplicated ScheduleWakeup

**Symptoms**

- Multiple iterations firing "at the same time".
- `notes.md` shows two iters with very close timestamps.
- Claude Code logs with two consecutive resumes.

**Diagnosis**

```bash
ls -la .sleepwell/resume.lock 2>/dev/null
cat .sleepwell/resume.lock 2>/dev/null
```

If `.sleepwell/resume.lock` exists and is old (dead PID, or old date),
a previous wakeup hung without releasing the lock — and a second schedule was
created.

**Remediation**

1. Check whether the PID listed in the lock is still alive (`ps -p <pid>`).
2. If dead, remove the lock manually:
   ```bash
   rm .sleepwell/resume.lock
   ```
3. If alive and duplicated, stop the loop with `/sleepwell:sleepwell-stop` and restart.

---

## 4. Stale voice cache

**Symptoms**

- Loop produces commits with a tone very different from the user's usual.
- `voice-profile.md` is dated many days ago.
- The user changed request style recently and the loop continues with old
  voice.

**Diagnosis**

```bash
stat -f '%Sm' .sleepwell/voice-profile.md   # macOS
stat -c '%y' .sleepwell/voice-profile.md    # linux
```

If the file is more than 7 days old, it should have been re-extracted
automatically. If not, force it.

**Remediation**

```bash
rm .sleepwell/voice-profile.md
```

Next iter triggers fresh extraction via `sleepwell-profile`.

---

## 5. Lint not detected

**Symptoms**

- `verify_cmds.lint` is empty in `state.json`.
- Iters commit code without checking lint.
- `auto` detection found nothing (project without `eslint`/`ruff`/etc).

**Diagnosis**

```bash
jq '.verify_cmds' .sleepwell/state.json
```

**Remediation**

Set manually via atomic edit:

```bash
tmp=$(mktemp .sleepwell/state.json.XXXXXX)
jq '.verify_cmds.lint = "npm run lint"' .sleepwell/state.json > "$tmp"
mv "$tmp" .sleepwell/state.json
```

Replace `npm run lint` with the project's actual command. Apply the same pattern
for `typecheck` and `test`.

---

## 6. Cost growing without limit

**Symptoms**

- `/sleepwell:sleepwell-status` shows `cost_so_far_usd` rising fast.
- Without `cost_budget_usd` configured, the loop can consume budget
  indefinitely.

**Diagnosis**

```bash
jq '{cost_so_far_usd, cost_budget_usd, max_cost_per_iter_usd}' \
  .sleepwell/state.json
```

**Remediation**

1. **Enable `--max-cost`** on the next bootstrap:
   ```
   /sleepwell:sleepwell "<intent>" --max-cost 5
   ```
2. **Enable `--max-cost-per-iter`** for per-iter guardrail:
   ```
   /sleepwell:sleepwell "<intent>" --max-cost 5 --max-cost-per-iter 0.50
   ```
3. In an active loop, update the budget directly in state:
   ```bash
   tmp=$(mktemp .sleepwell/state.json.XXXXXX)
   jq '.cost_budget_usd = 5' .sleepwell/state.json > "$tmp"
   mv "$tmp" .sleepwell/state.json
   ```

Next iter will check the gate (see `lib/ritual.md §8.1`).

---

## 7. Push blocked by the hook

**Symptoms**

- `git push` fails with a message from the `block-push.sh` hook.
- Message mentions "active sleepwell loop".

**Diagnosis**

This behavior is **expected**. During an active loop, `hooks/block-push.sh`
prevents push to avoid publishing work that has not been validated yet.

**Remediation**

1. Stop the loop before pushing:
   ```
   /sleepwell:sleepwell-stop
   ```
2. Confirm `status == "stopped"` in `/sleepwell:sleepwell-status`.
3. Push normally.

If you need to push with the loop still active (e.g., parallel hotfix on another
branch), use a separate worktree outside the scope of `scope-guard.sh`.
