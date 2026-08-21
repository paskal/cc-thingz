---
worth: later
where: plugins/release-tools/skills/new/scripts/get-notes.sh:200
added: 2026-08-21
---
# gitea release notes list no pull requests at all

The gitea arm at `get-notes.sh:200-208` collects nothing. It warns on stderr and falls through to
commit-derived notes, so a gitea release still ships, but it has never carried a single PR entry.

`tea pr list` cannot implement the contract the other two arms do. Its `--state` accepts only
`all`, `open` or `closed`, so the `--state merged` the script used until v2.0.6 was rejected outright.
And `tea --output json` serializes the printable table rather than the API structs: keys are field names
and every value is a flat string. The default set is `index,title,state,author,milestone,updated,labels`,
and widening it with `--fields` does not help — the full available list (`index`, `state`, `author`,
`author-id`, `url`, `title`, `body`, `mergeable`, `base`, `base-commit`, `head`, `diff`, `patch`,
`created`, `updated`, `deadline`, `assignees`, `milestone`, `labels`, `comments`, `ci`) has no merged
flag and no merge timestamp. `mergeable` is a different thing, and `state` reads `closed` for merged and
closed-unmerged alike, so no combination separates the two or filters against the tag date.

The replacement is `tea api '/repos/{owner}/{repo}/pulls?state=closed'`, which keeps tea's login and
repository-context resolution but returns the raw REST payload. That payload does carry `merged`,
`merged_at`, `number` and `user.login` — the four fields the arm needs. Verified against a public
Gitea endpoint; `tea api` and the `{owner}`/`{repo}` placeholders exist in tea 0.15.1.

Two properties the rebuilt arm has to satisfy:

- **Pagination completeness.** It must retrieve every relevant closed PR or fail explicitly. No default
  first page, no fixed silent ceiling — that is the same defect the v2.0.7 GitHub and GitLab pagination
  work closed. Needs a fixture spanning more than one page and a mutation check proving the assertion
  fails when paging is removed. Page size, loop shape, and whether to read response headers are open.
- **Live verification before the fallback is replaced.** Run against an authenticated real Gitea
  repository and prove repository and login resolution, one merged PR included, one closed-unmerged PR
  excluded, the merge-time cutoff on both sides of the tag, and the number/title/author mapping.
  Pagination can stay synthetic; creating 101 live PRs adds no confidence.

Failure semantics once a supported `tea api` path is chosen: authentication, API, malformed JSON, and
mid-pagination failures all abort with a diagnostic. They must not silently fall back to commit-only
notes, which is the exit-0 hole v2.0.5 and v2.0.6 exist to close.

Do not pin a numeric tea version floor yet. Local tea 0.15.1 proves `tea api` works here, not when it
appeared or what version consumers actually run. Establish the earliest usable version first, then pick
a policy: document and enforce a minimum, or keep the current warning-plus-commit-notes fallback for
installs where `tea api` is unavailable. A floor is one option, not a settled requirement.

The v2.0.6 warning fallback stays until a replacement passes the two properties above.

Surfaced reviewing PR #50. The invalid `tea pr list` call and the wrong field names predate it; that PR
made the failure fatal, and v2.0.6 turned it back into a warning.
