---
worth: later
where: plugins/planning/skills/exec/references/prompts/stats.md:27
added: 2026-08-24
---
# stats groups fixers by exact description, but only phase 3 prescribes one

`stats.md:27-31` groups subagents by matching exact `description` strings: "Fixer for phase 1", "Fixer
phase 1 findings", "Fixer - smells", "Fixer - external review". Step 9 at `SKILL.md:242` is the only fixer
spawn that prescribes its string. The phase-1, phase-2 and phase-4 spawns at `:190`, `:210` and step 10 say
only to resolve `prompts/fixer.md` and launch it, so the orchestrator picks the wording.

A fixer whose description comes out differently matches no group, and its tokens and duration drop out of
the stats report entirely. That is the same defect PR #43 fixed for phase 3 by adding the prescription
there.

Three one-clause edits, in steps this change did not touch. The only symptom is a missing row in the stats
summary, which is why it is `later` rather than `yes`.
