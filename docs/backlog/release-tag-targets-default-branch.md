---
worth: yes
where: plugins/release-tools/skills/new/SKILL.md:191
added: 2026-08-19
---
# the release skill publishes a tag at the remote default branch, not the commit it just built

`grep -rn 'push\|--target\|--ref\|git tag' plugins/release-tools/skills/new/` returns nothing. The
workflow never pushes and never creates a local tag — Step 5 computes a version *string*, and the tag
comes into existence only when Step 9 calls the forge.

- `SKILL.md:133-134` — Step 7 does `git add "$changelog"` / `git commit` **locally**, and nothing after it
  pushes.
- `SKILL.md:191` `gh release create "$new_version" --title … --notes …` sends no `target_commitish`, whose
  documented default is the repository's default branch. `glab release create` without `--ref` (`:198`)
  and `tea release create` without `--target` (`:205`) behave the same.
- `SKILL.md:146-165` — Step 8's preview shows the version and "CHANGELOG: … will be updated" but never a
  target SHA, so the human gate does not catch it.

So the normal path publishes a tag that omits the changelog commit Step 7 just made, and running the skill
from a non-default branch can publish the wrong branch entirely.

Fix: after confirmation, commit the changelog, push it, create and push the tag at that exact SHA, and make
each release command reference the existing tag — or pass the pushed SHA via `gh --target` / `glab --ref` /
`tea --target`. Confined to Steps 7-9 of one markdown file.

[Unverified] The default-target behavior rests on the documented GitHub API and CLI defaults; the verifier
did not execute `gh`/`glab`/`tea` to observe it, since those commands publish.

Surfaced reviewing PR #44 (an adversarial pass over the whole workflow, not the diff). `git blame` puts
every line above at `a59bb1f5`, so it predates that PR entirely.
