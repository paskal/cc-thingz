---
worth: later
where: README.md:270
added: 2026-08-24
---
# the seeded-override upgrade note gives no way to tell an edited copy from a pristine one

The removed `SessionStart` hook seeded 7 prompts and 6 agent files into `$CLAUDE_PLUGIN_DATA`
copy-if-absent, so every install before planning 3.10.0 still carries a full shadow layer that outranks
bundled defaults. `README.md:270` and `usage.md:67` tell those users to "delete anything you did not
deliberately edit", with no discriminator. Someone opening the directory sees 13 files with no provenance,
so his real options are keep everything and stay pinned, or delete everything and lose his edits.

The obvious recipe does not work: `diff -rq` against the bundled tree also reports every pristine copy
seeded from an older bundled version as differing, and per the changelog's own "twelve later fixes never
reached anyone seeded before them", that is the normal state of a stale install.

The only actionable form is one clause naming the dominant case, something like "if you never deliberately
customized anything, delete both directories". Deliberately kept minimal on PR #43 ("no migration and no
nag"), so this records the residue rather than reopening it.
