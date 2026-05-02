# Mode: radical

**Appetite:** rewrite subsystems. **Risk:** high.

## When to use

- Refactor is no longer viable: the structure must die.
- Targeted lib/stack swap (e.g. in-memory cache → Redis).
- Reorganize module architecture (e.g. extract domain into a separate package).
- Replace implementation with a significantly different equivalent.

## Strategy

Strangler-fig friendly. Each iter advances ONE step:

1. Build the new implementation in parallel (without killing the old).
2. Add a feature flag / code fork to choose between old and new.
3. Point one or a few call-sites to the new one.
4. Run tests — if it breaks, rollback.
5. Migrate more call-sites, iter by iter.
6. Once all are migrated, remove the old.

## Extra permissions (vs. refine)

- May introduce a new abstraction IF it replaces an equivalent existing one.
- May break an internal API IF it updates all callers in the same iter (atomic commit).
- May invalidate data in a local environment IF state.dry_run=true or with an explicit warning in notes.

## Retained restrictions

- **Never** break the public API without clearly documented migrations.
- **Never** remove the old implementation before the NEW one is 100% in place.
- **Never** operate on production / shared state without explicit confirmation.

## End heuristic

- Old subsystem removed.
- New subsystem covering all call-sites.
- Tests green, including regression for cases that motivated the rewrite.

## Per-iter checklist

- [ ] Does this iter create a strangler slice or migrate a group of callers?
- [ ] Is there an obvious rollback if it breaks (feature flag, separate branch)?
- [ ] Am I keeping public-API compat until the end?
- [ ] Did I document migration state in notes.md (% migrated)?

## Recommendation

Before starting `radical`, build the plan in a sub-phase
(`/sleepwell-phase-start "plan-radical"`) and fill in acceptance criteria
in `PLAN.md`. `radical` without a plan tends to become churn.

<!--
Inspirations (not required at runtime):
- gitnexus-impact-analysis — understand the change blast radius.
- superpowers:writing-plans — discipline of upfront planning.
The internal sub-phase (lib/ritual.md §9) plays the same role without external dependencies.
-->

