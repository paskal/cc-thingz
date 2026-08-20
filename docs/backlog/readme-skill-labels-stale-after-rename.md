---
worth: yes
where: README.md:304
added: 2026-08-19
---
# four README skill labels still carry the pre-rename names

`ebd1cfb` ("refactor: rename skills to eliminate stutter in plugin:skill invocations") rewrote the trigger
tables but not the prose around them, so a component label names a skill that no longer exists while the
correct trigger sits two lines above it.

- `README.md:304` — `**release**`, but the directory is `plugins/release-tools/skills/new/` and the table
  at `:301` gives `/release-tools:new`.
- `README.md:173` — `**review-pr**`, but the directory is `plugins/review/skills/pr/` and the table gives
  `/review:pr`.
- `README.md:165` — the same stale name in prose ("review-pr uses writing-style for drafting comments").
- `README.md:39` — the manual-install heading says `review-pr` while the `cp` command below it already says
  `skills/pr`.

Every other bold component label matches its skill directory (`**last-tag**`, `**git-review**`,
`**writing-style**`, `**ask-codex**`, `**dialectic**`, `**learn**`, `**clarify**`, `**wrong**`,
`**md-copy**`, `**txt-copy**`), so this is drift, not a convention.

Fix: rename the four labels. One pass closes the whole `ebd1cfb` prose sweep.

Surfaced reviewing PR #44, which fixed the *runnable* half of the same rename (the `chmod` path in the
manual-install block) but left the descriptive prose.
