# Mode: build

**Appetite:** build a new end-to-end feature. **Risk:** medium.

## Strategy

TDD-first. Each iter advances ONE stage of the funnel:

1. **Red:** write a test that fails for the right reason.
2. **Green:** implement the minimum to pass.
3. **Refactor:** clean up without changing behavior.

Each of these phases is a commit/iter. Do not skip a step.

## Typical iter sequence

| Iter | Focus |
|---|---|
| 1 | Define minimal interface (signature, types, contract). Failing stub. |
| 2 | Happy path test — fails. |
| 3 | Minimal implementation → green. |
| 4 | Refactor the implementation. |
| 5 | Edge case test — fails. |
| 6 | Implementation covering the edge case → green. |
| 7+ | Repeat 5-6 until covered. |
| N | Integration with the real caller. |
| N+1 | Documentation / comment if WHY is non-obvious. |

<!-- Inspiration (not required at runtime): superpowers:test-driven-development. The TDD flow above is already embedded. -->


## What NOT to do

- Do not write implementation before the failing test.
- Do not skip refactor because "it's fast".
- Do not add scope beyond the intent — note it and move on.
- Do not silence tests to pass (`@pytest.skip`, `it.skip`).

## End heuristic

Feature working end-to-end with:
- Coverage of happy path + known edge cases.
- Integrated with the real caller (not just isolated in tests).
- No critical TODOs in the diff.

## Per-iter checklist

- [ ] Does this iter advance ONE TDD phase (red OR green OR refactor)?
- [ ] Is the new test specific and failing for the right reason?
- [ ] Does the implementation not go beyond what this phase needs?
- [ ] No hidden side-effects outside the iter scope?
