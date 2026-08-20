---
worth: later
where: plugins/planning/scripts/launch-plan-review.sh:193
added: 2026-08-20
---
# orca is the one overlay backend this copy has and revdiff's canonical launcher does not

`launch-plan-review.sh` is a port of `umputun/revdiff`'s
`.claude-plugin/skills/revdiff/scripts/launch-revdiff.sh`, and PR #18 says so outright: "the sibling
`revdiff/plugins/revdiff-planning` plugin already ships a launcher that handles all of these. This PR
ports that launcher back into `planning` so the two stay in sync."

PR #47 added an `orca` branch here (`:193`). Upstream has no `orca` string anywhere in its launcher and no
issue asking for one, so this is the first backend that exists downstream and not up. Every other backend
in this file exists in both.

Not a reason the PR should not have merged - the contributor never raised it, nothing in this repo tells
him to, and his branch already satisfies each of the five alignment items asked for on PR #12. It is sync
work, and it belongs to whoever owns both repos.

Note the two files already diverge the other way: upstream carries an `agent-deck` branch
(`launch-revdiff.sh:224`) that this copy lacks, and upstream is ahead on exit-code propagation
(`write_rc_cmd` / `print_output_and_exit`). So the invariant worth protecting is "the copy mirrors the
canonical", not strict equality, and a re-sync in either direction has to preserve the other's extras by
hand.

Surfaced reviewing PR #47.
