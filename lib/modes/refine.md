# Mode: refine (default)

**Appetite:** incremental refactor, continuous improvements, coverage. **Risk:** low-medium.

## What to do in a refine iter

- Refactor a function for clarity (preserving behavior).
- Extract a helper when there is real duplication (rule of 3).
- Add tests for uncovered paths.
- Replace a deprecated call with its new equivalent.
- Improve variable/function naming in local scope.
- Reduce cyclomatic complexity of a function.
- Replace an ugly pattern with the stack's idiomatic one.
- Eliminate genuine dead code.

## What NOT to do

- Do not introduce speculative abstraction ("will be needed later").
- Do not add features.
- Do not swap technology/lib.
- Do not rewrite subsystems — that's `radical` mode.
- Do not make changes that require manual data migration.

## End heuristic

When tests are green, coverage is reasonable, and the next obvious refactor is no longer obvious.

## Per-iter checklist

- [ ] Does the change preserve observable behavior?
- [ ] Do existing tests still pass WITHOUT editing (unless a test was wrong)?
- [ ] Is the diff localized (few files)?
- [ ] Is there a clear "why" to write in the commit body?

If the change wants to grow beyond 1 coherent commit → cancel and split into smaller iters.
