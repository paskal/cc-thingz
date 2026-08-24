---
worth: yes
where: tests/test-planning-external-review.sh
added: 2026-08-24
---
# nothing pins customize-file.sh refusing a symlinked `.claude`

`customize-file.sh:86` sets `stop="."` on the project-level branch, so the ancestor walk covers `.claude`
itself, while the user-level branch stops at the data dir and exempts it. The script's own comment calls
that asymmetry deliberate: `.claude` comes from the checked-out repository, so a repo shipping it as a
symlink could otherwise redirect the copy anywhere.

The suite covers two symlink cases, both below the override root, so they would still pass if `stop` were
changed to `.claude/exec-plan` for symmetry with the user-level branch. The one component the guard exists
for is the one nothing pins.

Behavior is correct today, confirmed by hand in a scratch tree: a repo whose `.claude` is a symlink gets
`refusing to write through a symlinked directory component: .claude` and nothing is written. Three lines to
pin it, beside the existing pair.
