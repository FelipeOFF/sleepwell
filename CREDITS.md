# Credits

This file documents what sleepwell took as inspiration from each MIT-licensed
upstream and what was independently re-implemented in this codebase. No
upstream code was vendored verbatim — every concept below was rewritten in
the sleepwell idiom (PT-BR comments, ritual-driven structure, schema v3
state).

---

## yail259/overnight

License: MIT.
Repo: https://github.com/yail259/overnight

### What we drew on

- **Voice profile extraction** — the idea of summarizing a user's recent
  authored text (commits, PRs, notes) into a compact "tone" descriptor that
  later prompts can adopt.
- **Self-evaluation tool** — periodic, structured judgment of an
  iteration's quality (rating + observation + course-correct flag) instead
  of relying solely on tests.
- **Statistical calibration via merge-rate** — using the historical
  fraction of branches actually merged as a confidence signal for ranking
  future runs.

### What sleepwell re-implemented

- `skills/sleepwell-profile/` (voice profile, PT-BR, JSONL-tolerant parser).
- `skills/sleepwell-evaluator/` (rating 1-5 + course-correct boolean).
- `state.last_eval` and `state.prediction_profile` schema fields (v3).
- `/sleepwell-suggest` ranks plans by `merge_rate` from
  `prediction_profile.by_category[mode]`.

No code or prose was copied — only the abstract patterns above.

---

## kunchenguid/gnhf

License: MIT.
Repo: https://github.com/kunchenguid/gnhf

### What we drew on

- **Disciplined loop pattern**:
  - One iteration = one logical unit = one commit.
  - Lint + types + tests must be green before commit.
  - On fail: `git reset --hard HEAD && git clean -fd`, increment failure
    counter, abort after 3 consecutive failures.
  - Isolated `<name>/<slug>` branch per run; never touches main.

### What sleepwell re-implemented

- `lib/ritual.md` §1-§4 codifies these principles.
- `skills/sleepwell-loop/SKILL.md` implements the iteration anatomy
  (load → abort checks → prompt → execute → verify → decide → state →
  schedule).
- Exponential backoff on FAIL, atomic state.json writes, base-branch
  detector helper.

The loop runs **inside** an active Claude Code session (keeping the
prompt cache warm) rather than as an external `claude -p` wrapper —
that part is original to sleepwell.

---

## thebasedcapital/nightcrawler

License: MIT.
Repo: https://github.com/thebasedcapital/nightcrawler

### What we drew on

- **Overnight TUI loop** — the user-facing affordance of watching an
  unattended loop progress over many iterations through a live terminal
  UI.

### What sleepwell re-implemented

- `commands/sleepwell-watch.md` — live status TUI built on top of
  `state.json` and `notes.md`, no external dependency.
- `commands/sleepwell-status.md` — read-only snapshot for quick checks.
- `commands/sleepwell-recap.md` — post-run narrative summary in PT-BR
  written to an Obsidian vault.

---

## License notes

sleepwell itself is MIT. Each upstream above is also MIT, which is
compatible with re-implementation under attribution. If any upstream
maintainer objects to the framing here, please open an issue on
[FelipeOFF/sleepwell](https://github.com/FelipeOFF/sleepwell) and we
will adjust the attribution promptly.
