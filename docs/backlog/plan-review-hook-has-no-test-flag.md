---
worth: later
where: plugins/planning/scripts/plan-review-hook.py
added: 2026-08-20
---
# plan-review-hook.py carries no embedded tests, unlike every other python script here

CLAUDE.md's Testing section states "Python scripts include embedded tests run via `--test` flag".
`plan-annotate.py --test` runs 22 of them; `check-frontmatter.py --test` has its own.
`plan-review-hook.py` has no `--test` flag at all - grep finds no occurrence - and no suite in `tests/`
exercises it. CI runs every `tests/test-*.sh` plus the `--test` suites, so nothing checks this file
beyond whether it parses.

It is not a passive file. It decides the `permissionDecision` returned to `ExitPlanMode`, shells out to
the launcher with a four-day timeout, and reads annotations back from its stdout - the three things that
determine whether a plan review happens at all or degrades to the plain confirmation dialog.

The cases worth pinning are the ones with a branch behind them: `PLANNING_DISABLE_REVDIFF` set, revdiff
absent so the `$EDITOR` fallback runs, launcher exits non-zero, launcher returns empty stdout, launcher
returns annotation text. `tests/test-planning-disable-review.sh` already covers the first from the
launcher side and shows the stubbing pattern.

Surfaced running the checks over PR #47, which touched this file's docstring only.
