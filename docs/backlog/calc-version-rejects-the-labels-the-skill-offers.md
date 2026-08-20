---
worth: yes
where: plugins/release-tools/skills/new/scripts/calc-version.sh:24
added: 2026-08-19
---
# the release skill offers capitalized release types that calc-version.sh rejects

`SKILL.md:36-38` defines the AskUserQuestion options as `Hotfix` / `Minor` / `Major`, and Step 5 at `:72`
says only to pass `<release_type>` — nothing instructs the agent to lowercase the selected label. Both
`case` statements in `calc-version.sh` (`:24-29` for the no-tags path, `:45-49` for the normal path) accept
lowercase `major|minor|hotfix` only.

Verified: `bash calc-version.sh Hotfix` prints `error: invalid type: Hotfix` and exits 1, so the release
aborts at Step 5 whenever the agent passes the label verbatim.

Fix, one line either side: state the mapping in Step 5 (pass the selected label lowercased), or make the
script accept either case via `${release_type,,}`. The SKILL.md edit is the safer of the two — it leaves the
script's contract alone.

PR #44 strictly improved the failure mode here: before it, `error: invalid type: Hotfix` went to stdout and
landed in `$new_version`, from where it could reach `gh release create` as a tag name. It now goes to stderr
and leaves the variable empty.

Surfaced reviewing PR #44. Both the capitalized labels and the lowercase-only `case` predate it; its only
edits to those lines are the `>&2` redirections.
