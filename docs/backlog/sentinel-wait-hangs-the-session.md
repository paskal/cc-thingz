---
worth: yes
where: plugins/planning/scripts/launch-plan-review.sh:118
added: 2026-08-20
---
# an overlay that dies without touching the sentinel hangs the session forever

Every sentinel-based backend in `launch-plan-review.sh` blocks on `while [ ! -f "$SENTINEL" ]; do sleep
0.3; done` with no bound and no liveness check on the terminal it created. If the overlay dies before
revdiff reaches `touch "$SENTINEL"`, the loop never exits. Eight blocks share it: zellij `:118`, herdr
`:184`, orca `:233`, kitty `:256`, wezterm `:281`, cmux `:314`, ghostty `:358`, iTerm2 `:421`.

The caller has no escape either. `plan-review-hook.py:78` and `:132` run the launcher with
`timeout=345600` - four days - so the Claude Code session sits with no output until someone kills it.

Reachable by closing the overlay tab or window instead of quitting revdiff with `q`, quitting the terminal
app, killing revdiff, or the launch script failing to start at all (a remote-runtime terminal cannot see
the local `$TMPDIR` path the sentinel lives at). That closing a tab kills the child shell before the
`; touch` runs is inference, not tested - but the other three paths do not depend on it.

Two shapes of fix, and the cheap one is not in this file:

- cap `timeout=345600` in `plan-review-hook.py` to something a real review cannot exceed. One edit,
  covers all eight backends, and the hook already degrades to the plain ExitPlanMode dialog on failure.
- bound each loop on terminal liveness, polling whether the overlay still exists. Per-backend machinery,
  and each terminal exposes a different way to ask.

A plain time bound inside the loop is wrong by construction: a plan review legitimately takes an hour,
which is why these loops are unbounded in the first place. Whatever the fix, it must still
`cat "$OUTPUT_FILE"` on the give-up path so a partially written review is not thrown away.

Related to [overlay-failure-reads-as-empty-review.md](overlay-failure-reads-as-empty-review.md), which
owns the other half of the same contract - how a failed overlay reports to the caller. These want doing
together: both rewrite what the launcher signals on a path where the user wrote nothing.

Surfaced reviewing PR #47 (orca backend), which reproduces the established shape rather than introducing
it. Four independent review sources flagged it.
