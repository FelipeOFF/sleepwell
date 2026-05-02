# Mode: wave (experimental)

**Appetite:** explore significant changes with built-in self-criticism.
**Risk:** medium-high — each wave's scope is larger than `refine`, smaller than `radical`.

> **Status:** experimental. Activate with `--mode wave` on `/sleepwell:sleepwell`. Expect
> per-iter cost ~3x higher (3 sub-agents in sequence). Feedback welcome.

## Concept

Each **wave** = 1 loop iteration, but internally runs **3 sub-agents in
sequence**, each with a distinct role:

1. **Propose radical** (`role: proposer`) — generate an ambitious change.
2. **Criticize** (`role: critic`) — adversarial review of the proposal.
3. **Consolidate + commit** (`role: consolidator`) — apply the final version
   adjusted by the critic and commit.

Only the third sub-agent writes to the working tree and commits. The first two
produce textual artifacts (proposal + critique) appended to `notes.md`.

## When to use

- You want the courage of `radical` without the risk of skipping review.
- The change has multiple valid forms and trade-offs are worth weighing.
- Extra cost per iter is acceptable (budget via `--max-cost`).

## When NOT to use

- Mechanical tasks (use `tidy`).
- Small well-defined refactor (use `refine`).
- Cadenced TDD (use `build`).
- Obvious structural rewrite already planned (use `radical` directly).

## Roles and prompts

### Sub-agent 1 — Proposer

> You are the **proposer** of a sleepwell wave. Your task is to propose the
> most audacious change that is still defensible for the current intent.
>
> Inputs: `state.intent`, `state.mode = wave`, last 30 lines of
> `notes.md`, recent `git log <branch>`, `git diff --stat <base>..HEAD`.
>
> Output: a Markdown proposal with sections:
> - **Proposed change** (1 clear paragraph).
> - **Why radical** (what this approach dares that a refine would not).
> - **Known trade-offs** (≥2).
> - **Application plan** (list of concrete steps).
>
> Do NOT write code in the working tree. Do NOT commit. Just return the markdown.

### Sub-agent 2 — Critic

> You are the **critic** of this wave. You received the proposer's proposal.
> Your task is to take it down rigorously — find holes, hidden risks,
> simpler solutions that deliver 80% of the value.
>
> Output in Markdown:
> - **Holes** (numbered list, each item 1-3 lines).
> - **Hidden risks** (non-obvious side effects).
> - **Simpler alternative** (more conservative proposal delivering similar
>   value — may be "leave as-is").
> - **Verdict:** `approve`, `approve-with-changes`, or `discard`.
>
> If `approve-with-changes`, list mandatory adjustments for the consolidator.
> Do NOT write code. Do NOT commit.

### Sub-agent 3 — Consolidator

> You are the **consolidator**. You received the proposal + the critique.
>
> Rules:
> - Verdict `approve` → apply the original proposal.
> - Verdict `approve-with-changes` → apply the proposal integrating the
>   mandatory adjustments from the critic.
> - Verdict `discard` → do not touch code; commit only an annotation in
>   `notes.md` recording the wave as a learning and mark the iter as
>   logical `pass` (not fail — discarding is a valid decision).
>
> Final task: apply changes to the working tree, run `verify_cmds`
> (lint/typecheck/test), and make **one atomic commit** following the
> repo convention. Append proposal + critique + final decision to the
> iter's `notes.md`.

## Integration with `sleepwell-loop`

When `state.mode == "wave"`:

1. The `sleepwell-loop` skill detects the mode at the start of the iter.
2. Instead of running "edit+verify+commit" directly, it dispatches 3
   sub-agents in sequence (Task tool or equivalent skill), passing state
   and the artifacts of each step forward.
3. The wave result (pass/fail) is determined by the third sub-agent,
   exactly like any other mode (lint+typecheck+test).
4. `consecutive_failures`, `total_passes`, `total_fails` keep working
   the same.
5. `cost_so_far_usd` accumulates tokens from the 3 sub-agents — hence the ~3x cost.

## notes.md per wave

Each wave produces 3 blocks in `notes.md`:

```
### iter <N> — wave (proposer)
<proposal content>

### iter <N> — wave (critic)
<critique content + verdict>

### iter <N> — wave (consolidator)
<final decision + commit hash + verify result>
```

## Permissions

Same as `refine` for the consolidator (cannot break public API without a
plan). The proposer may suggest radical, but the consolidator decides
whether to apply — respecting the mode's restrictions.

## End heuristic

Same as other modes: `stop_when` met OR `max_iter` OR
`consecutive_failures >= 3` OR `cost_budget_usd` exceeded.

## Per-wave checklist

- [ ] Did the proposer return structured markdown without touching the working tree?
- [ ] Did the critic emit an explicit verdict (`approve`/`approve-with-changes`/`discard`)?
- [ ] Did the consolidator respect the verdict?
- [ ] Does notes.md contain the 3 wave blocks?
- [ ] Was the iter cost recorded and added to `cost_so_far_usd`?
