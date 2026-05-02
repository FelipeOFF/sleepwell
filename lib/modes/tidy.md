# Mode: tidy

**Appetite:** cleanup, organization, deps. **Risk:** very low.

## What to do in a tidy iter

- Remove unused imports.
- Apply a formatter (prettier, black, gofmt, rustfmt).
- Rename clearly wrong identifiers (typo, inconsistency).
- Reorder functions/imports per convention.
- Update minor/patch deps.
- Add missing JSDoc/docstrings on public APIs.
- Move a file to the correct folder (without changing content).
- Split a giant file into smaller ones (without changing behavior).

## What NOT to do

- **Never** change behavior. If a test passes before, it passes after.
- Do not introduce new abstractions.
- Do not refactor logic.
- Do not add features.
- Do not do major dep bumps.

## End heuristic

When the repo "feels tidy": clean linter, no obvious warnings, consistent naming, deps up to date.

## Per-iter checklist

- [ ] Is the change purely syntactic/organizational?
- [ ] Did lint improve or stay ok?
- [ ] Do tests still pass without editing?
- [ ] Is the diff small and mechanical?

If any of these fails → cancel the iter, switch to `refine`.
