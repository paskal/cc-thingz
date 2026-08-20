---
worth: no
where: plugins/planning/scripts/launch-plan-review.sh
added: 2026-08-20
---
# no test covers any of the twelve overlay backends

`launch-plan-review.sh` dispatches across twelve terminals and not one branch is exercised.
`tests/test-planning-disable-review.sh` is the only test touching the file, and it asserts the
`PLANNING_DISABLE_REVDIFF` early-exit at `:17`, which returns before any backend is reached. CI runs
shellcheck over the script, which proves syntax and nothing about behavior.

Filed as `no` deliberately, so it stops being rediscovered on every backend PR. Writing the first backend
test would either leave one branch covered against eleven bare ones, or commission eleven more, and each
needs a different stub CLI. Precedent agrees: commits `990008b` (herdr + agterm) and `817b558` (zellij,
kaku, cmux, ghostty, iTerm2, emacs vterm) added six and two backends respectively with no test, and PR #47
followed them.

A harness is mechanically available if this ever changes: `tests/test-release-tools.sh:154` and
`tests/test-exec-vcs-dispatch.sh:528` already stub CLIs with `PATH="$STUB_DIR:$PATH"`, and a stub terminal
CLI plus a stub `revdiff` would cover handle parsing, the create-failure exit, and the close call.

Revisit when the launcher's failure contract is reworked - see
[sentinel-wait-hangs-the-session.md](sentinel-wait-hangs-the-session.md) and
[overlay-failure-reads-as-empty-review.md](overlay-failure-reads-as-empty-review.md). Changing what all
eight sentinel loops do is the point where a harness pays for itself; adding one now is not.
