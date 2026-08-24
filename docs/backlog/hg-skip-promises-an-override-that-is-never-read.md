---
worth: yes
where: plugins/planning/skills/exec/SKILL.md:216
added: 2026-08-24
---
# the hg skip message points at an override step 9 never reads

Step 9's hg branch tells the user "Override `prompts/codex-review.md` via `.claude/exec-plan/` to enable
hg-native review", and `README.md:253` repeats the promise. The skip happens before the loop that resolves
that file, so an hg user who writes `.claude/exec-plan/prompts/codex-review.md` and reruns exec gets the
same skip and the same message.

Surfaced reviewing PR #43, which made the wording more firmly wrong: `SKILL.md:222` now tells the
orchestrator to ignore launcher and availability instructions in a `codex-review.md` override, and says
step 9 alone controls invocation.

Two ways out and they are not equivalent, which is why this was not fixed inline. Either the message stops
promising a route that does not exist, or step 9's hg branch resolves the prompt before deciding to skip.
The second only makes sense if hg external review is wanted at all. The wording fix alone is one sentence
in two files and no behavior change.
