#!/bin/bash
# validate Codex marketplace structure and Codex-specific override resolution

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
MARKETPLACE="$REPO_ROOT/.agents/plugins/marketplace.json"
CODEX_ROOT="$REPO_ROOT/plugins/codex"

TMP_ROOT="$(mktemp -d)"
case "$TMP_ROOT" in
    /tmp/*|/private/tmp/*|/private/var/*|/var/folders/*) ;;
    *) echo "FATAL: unsafe temp path: $TMP_ROOT" >&2; exit 1 ;;
esac
cleanup() { rm -rf "$TMP_ROOT"; }
trap cleanup EXIT

python3 - "$REPO_ROOT" "$MARKETPLACE" <<'PY'
import json
import os
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
marketplace = json.loads(pathlib.Path(sys.argv[2]).read_text())
entries = marketplace["plugins"]
expected = {
    "brainstorm",
    "planning",
    "release-tools",
    "review",
    "skill-eval",
    "thinking-tools",
    "workflow",
}
expected_skills = {
    "brainstorm": {"brainstorm"},
    "planning": {"exec", "make", "plan-review"},
    "release-tools": {"last-tag", "new"},
    "review": {"git-review", "pr", "writing-style"},
    "skill-eval": {"skill-eval"},
    "thinking-tools": {"ask-codex", "dialectic", "root-cause-investigator"},
    "workflow": {"backlog", "clarify", "learn", "md-copy", "txt-copy", "wrong"},
}
names = {entry["name"] for entry in entries}
assert names == expected, f"marketplace names differ: {sorted(names)}"

for entry in entries:
    name = entry["name"]
    plugin_root = root / entry["source"]["path"]
    manifest = json.loads((plugin_root / ".codex-plugin/plugin.json").read_text())
    claude = json.loads((root / "plugins" / name / ".claude-plugin/plugin.json").read_text())
    assert manifest["name"] == name
    assert manifest["version"] == claude["version"], name
    assert manifest["skills"] == "./skills/"
    skills = {path.parent.name for path in (plugin_root / "skills").glob("*/SKILL.md")}
    assert skills == expected_skills[name], f"{name}: {sorted(skills)}"
    assert entry["source"]["source"] == "local"
    assert entry["policy"]["installation"] == "AVAILABLE"
    assert entry["policy"]["authentication"] == "ON_INSTALL"

planning_files = {
    "skills/exec/references/prompts/codex-review.md",
    "skills/exec/references/prompts/finalizer.md",
    "skills/exec/references/prompts/fixer.md",
    "skills/exec/references/prompts/progress-file.md",
    "skills/exec/references/prompts/review.md",
    "skills/exec/references/prompts/stats.md",
    "skills/exec/references/prompts/task.md",
}
planning_root = root / "plugins/codex/planning"
missing = sorted(path for path in planning_files if not (planning_root / path).is_file())
assert not missing, f"planning package is missing: {missing}"

hook_root = root / "plugins/codex/skill-eval/hooks"
hook = json.loads((hook_root / "hooks.json").read_text())
command = hook["hooks"]["UserPromptSubmit"][0]["hooks"][0]["command"]
assert command == "sh ${PLUGIN_ROOT}/hooks/skill-forced-eval-hook.sh"
hook_script = hook_root / "skill-forced-eval-hook.sh"
assert hook_script.is_file()
assert os.stat(hook_script).st_mode & 0o111, "skill-eval hook is not executable"
PY

if grep -RInE \
    'CLAUDE_PLUGIN|\$\{PLUGIN_ROOT\}|AskUserQuestion|EnterPlanMode|EnterWorktree|TodoWrite|Bash tool|subagent_type|\$\{user_config|allowed-tools:' \
    "$CODEX_ROOT" --exclude-dir='hooks' --include='*.md' --include='*.txt' --include='*.sh' --include='*.py'; then
    echo "Codex package contains a Claude-only runtime instruction" >&2
    exit 1
fi

WORK_DIR="$TMP_ROOT/work"
CODEX_HOME="$TMP_ROOT/codex-home"
mkdir -p "$WORK_DIR/.codex" "$CODEX_HOME/cc-thingz/brainstorm" "$CODEX_HOME/cc-thingz/planning/exec-plan/prompts"

printf 'user brainstorm\n' >"$CODEX_HOME/cc-thingz/brainstorm/test-rules.md"
actual="$(cd "$WORK_DIR" && CODEX_HOME="$CODEX_HOME" bash "$CODEX_ROOT/brainstorm/scripts/resolve-rules.sh" test-rules.md)"
test "$actual" = "user brainstorm"

printf 'project brainstorm\n' >"$WORK_DIR/.codex/test-rules.md"
actual="$(cd "$WORK_DIR" && CODEX_HOME="$CODEX_HOME" bash "$CODEX_ROOT/brainstorm/scripts/resolve-rules.sh" test-rules.md)"
test "$actual" = "project brainstorm"

printf 'user task prompt\n' >"$CODEX_HOME/cc-thingz/planning/exec-plan/prompts/task.md"
actual="$(cd "$WORK_DIR" && CODEX_HOME="$CODEX_HOME" bash "$CODEX_ROOT/planning/skills/exec/scripts/resolve-file.sh" prompts/task.md)"
test "$actual" = "user task prompt"

mkdir -p "$WORK_DIR/.codex/exec-plan/prompts"
printf 'project task prompt\n' >"$WORK_DIR/.codex/exec-plan/prompts/task.md"
actual="$(cd "$WORK_DIR" && CODEX_HOME="$CODEX_HOME" bash "$CODEX_ROOT/planning/skills/exec/scripts/resolve-file.sh" prompts/task.md)"
test "$actual" = "project task prompt"

echo "Codex package tests passed"
