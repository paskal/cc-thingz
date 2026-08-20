---
worth: yes
where: .github/workflows/ci.yml
added: 2026-08-19
---
# nothing verifies that a ${CLAUDE_PLUGIN_ROOT} path in plugin markdown actually exists

`ebd1cfb` moved `plugins/release-tools/skills/{release => new}/scripts/*.sh` while touching `SKILL.md` by
one insertion and one deletion, leaving all three helper invocations pointing at `skills/release/`. That
directory has not existed since 2026-02-17, so every helper step of the release skill failed at runtime for
six months, for anyone who installed release-tools from the marketplace. No CI step could notice: the lint
job runs frontmatter YAML validation, shellcheck, an hg-grep, the shell tests and the python self-tests, and
none of them resolves a path.

`grep -rn 'CLAUDE_PLUGIN_ROOT.*\.sh' plugins --include=*.md` returns 20+ references across planning,
brainstorm and release-tools. A check that resolves each `${CLAUDE_PLUGIN_ROOT}/<path>` occurrence in
`plugins/<name>/**.md` against `plugins/<name>/<path>` and fails on a miss pins all of them. Verified
against the current tree: every reference resolves, so it goes green immediately.

Related and separate: the three release-tools helpers have no test at all. `tests/` holds only
`test-brainstorm-resolve-rules.sh`, `test-exec-vcs-detect.sh`, `test-exec-vcs-dispatch.sh`,
`test-planning-disable-review.sh` and `test-planning-resolve-rules.sh`, so CI's
`for t in tests/test-*.sh` has nothing to run for this plugin. `tests/test-exec-vcs-detect.sh:155-162` is
the direct precedent — it covers `detect-vcs.sh` end to end including its non-VCS failure path. A
`tests/test-release-tools-helpers.sh` in that shape would also pin the error paths PR #44 made reachable
(no origin, non-repo, missing/invalid argument → exit 1, non-empty stderr, empty stdout), which currently
depend on a bare `|| true` at `detect-platform.sh:13` that reads as redundant next to the `2>/dev/null`
beside it and would silently restore the original bug if tidied away.

The CI path check is the higher-value half: a few generic lines, covering every plugin, pinning a break
that actually shipped.

Surfaced reviewing PR #44, which fixed the stale paths but added no test.
