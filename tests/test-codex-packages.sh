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
import ast
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

copy_pairs = {
    "plugins/planning/skills/exec/scripts/append-progress.sh": "plugins/codex/planning/skills/exec/scripts/append-progress.sh",
    "plugins/planning/skills/exec/scripts/create-branch.sh": "plugins/codex/planning/skills/exec/scripts/create-branch.sh",
    "plugins/planning/skills/exec/scripts/detect-branch.sh": "plugins/codex/planning/skills/exec/scripts/detect-branch.sh",
    "plugins/planning/skills/exec/scripts/detect-vcs.sh": "plugins/codex/planning/skills/exec/scripts/detect-vcs.sh",
    "plugins/planning/skills/exec/scripts/init-progress.sh": "plugins/codex/planning/skills/exec/scripts/init-progress.sh",
    "plugins/planning/skills/exec/scripts/move-plan.sh": "plugins/codex/planning/skills/exec/scripts/move-plan.sh",
    "plugins/planning/skills/exec/scripts/stage-and-commit.sh": "plugins/codex/planning/skills/exec/scripts/stage-and-commit.sh",
    "plugins/release-tools/skills/new/scripts/calc-version.sh": "plugins/codex/release-tools/skills/new/scripts/calc-version.sh",
    "plugins/release-tools/skills/new/scripts/detect-platform.sh": "plugins/codex/release-tools/skills/new/scripts/detect-platform.sh",
    "plugins/release-tools/skills/new/scripts/get-notes.sh": "plugins/codex/release-tools/skills/new/scripts/get-notes.sh",
}

code_equivalent_pairs = {
    "plugins/planning/scripts/launch-plan-review.sh": "plugins/codex/planning/scripts/launch-plan-review.sh",
    "plugins/planning/scripts/plan-annotate.py": "plugins/codex/planning/scripts/plan-annotate.py",
    "plugins/review/skills/git-review/scripts/git-review.py": "plugins/codex/review/skills/git-review/scripts/git-review.py",
}

adapted_pairs = {
    "plugins/brainstorm/scripts/resolve-rules.sh": "plugins/codex/brainstorm/scripts/resolve-rules.sh",
    "plugins/planning/scripts/resolve-rules.sh": "plugins/codex/planning/scripts/resolve-rules.sh",
    "plugins/planning/skills/exec/scripts/customize-file.sh": "plugins/codex/planning/skills/exec/scripts/customize-file.sh",
    "plugins/planning/skills/exec/scripts/resolve-file.sh": "plugins/codex/planning/skills/exec/scripts/resolve-file.sh",
    "plugins/planning/skills/exec/scripts/run-codex.sh": "plugins/codex/planning/skills/exec/scripts/run-codex.sh",
    "plugins/planning/skills/exec/scripts/run-external-review.sh": "plugins/codex/planning/skills/exec/scripts/run-external-review.sh",
    "plugins/skill-eval/hooks/skill-forced-eval-hook.sh": "plugins/codex/skill-eval/hooks/skill-forced-eval-hook.sh",
}

classified = set(copy_pairs.values()) | set(code_equivalent_pairs.values()) | set(adapted_pairs.values())
claude_script_names = {
    path.name
    for path in (root / "plugins").rglob("*")
    if path.suffix in {".py", ".sh"} and "plugins/codex/" not in path.as_posix()
}
same_named_codex_scripts = {
    path.relative_to(root).as_posix()
    for path in (root / "plugins/codex").rglob("*")
    if path.suffix in {".py", ".sh"} and path.name in claude_script_names
}
unclassified = same_named_codex_scripts - classified
stale = classified - same_named_codex_scripts
assert not unclassified and not stale, (
    f"Codex script parity classification differs: unclassified={sorted(unclassified)}, "
    f"stale={sorted(stale)}"
)

for source_path, codex_path in {**copy_pairs, **code_equivalent_pairs, **adapted_pairs}.items():
    assert (root / source_path).is_file(), f"classified Claude script is missing: {source_path}"
    assert (root / codex_path).is_file(), f"classified Codex script is missing: {codex_path}"

for source_path, copy_path in copy_pairs.items():
    source = (root / source_path).read_bytes()
    copy = (root / copy_path).read_bytes()
    assert copy == source, f"Codex copy drifted from {source_path}: {copy_path}"

def python_code(path):
    source = path.read_text()
    first_line = source.splitlines()[0]
    tree = ast.parse(source, filename=str(path))
    for node in ast.walk(tree):
        body = getattr(node, "body", None)
        if (
            isinstance(body, list)
            and body
            and isinstance(body[0], ast.Expr)
            and isinstance(body[0].value, ast.Constant)
            and isinstance(body[0].value.value, str)
        ):
            del body[0]
    return first_line, ast.dump(tree, include_attributes=False)


for source_path, codex_path in code_equivalent_pairs.items():
    source = root / source_path
    codex = root / codex_path
    if source.suffix == ".py":
        equal = python_code(source) == python_code(codex)
    else:
        source_text = source.read_text()
        old = '# empty stdout signals "no annotations", so the hook and /planning:make loop proceed.'
        new = '# empty stdout signals "no annotations", so the hook and planning:make loop proceed.'
        assert source_text.count(old) == 1, f"expected launch comment changed in {source_path}"
        equal = source_text.replace(old, new) == codex.read_text()
    assert equal, f"Codex script code drifted from {source_path}: {codex_path}"

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
    'CLAUDE_PLUGIN|AskUserQuestion|EnterPlanMode|EnterWorktree|TodoWrite|Bash tool|subagent_type|\$\{user_config|allowed-tools:' \
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
