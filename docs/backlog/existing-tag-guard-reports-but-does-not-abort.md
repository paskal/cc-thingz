---
worth: yes
where: plugins/release-tools/skills/new/SKILL.md:77
added: 2026-08-19
---
# the existing-tag guard prints an error and lets the workflow continue

`SKILL.md:77-79` is `if git rev-parse "$new_version" &>/dev/null; then echo "error: …"; fi` — no `exit`, no
instruction to stop. The block's exit status is 0, so the numbered workflow proceeds to Step 6 and on to
publication. That contradicts the Edge Cases table in the same file at `:225`: `| Tag already exists | Error
and abort |`.

The collision is producible, not hypothetical: `calc-version.sh:20` uses `git describe --tags --abbrev=0`,
which only considers tags reachable from HEAD, while `calc-version.sh:17` has just run
`git fetch origin --tags` and pulled in refs from other history lines. So a calculated version can already
exist on another branch, and release creation then targets that existing tag rather than the intended
commit.

Fix: check `refs/tags/<version>` locally and remotely, print to stderr, `exit 1`, and state that the
workflow must stop. Adding `exit 1` plus one sentence makes the block match the table it already
contradicts.

Partly mitigated today: Step 8 puts the version in front of the user before anything is published, and the
agent does see the echoed error and can read the abort row in the same file — which is why this is minor
rather than major.

Not worth including in the fix: the adjacent "empty version slips the guard" case (`git rev-parse ""` fails,
so the `if` is false). It buys nothing — an empty version means `calc-version.sh` already exited 1 with
visible stderr, Step 8 renders a blank version to the user, and `gh release create ""` cannot create a
release.

Surfaced reviewing PR #44. `git blame` puts `:77-79` and `:225` at `a59bb1f5`; the PR touches neither.
