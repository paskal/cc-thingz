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
import re
import sys
from urllib.parse import urlparse

import yaml

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

semver = re.compile(
    r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)"
    r"(?:-(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*)(?:\."
    r"(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*))*)?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$"
)
plugin_fields = {
    "id", "name", "version", "description", "skills", "apps", "mcpServers",
    "interface", "author", "homepage", "repository", "license", "keywords",
}
interface_fields = {
    "displayName", "shortDescription", "longDescription", "developerName", "category",
    "capabilities", "websiteURL", "privacyPolicyURL", "termsOfServiceURL", "brandColor",
    "composerIcon", "logo", "logoDark", "screenshots", "defaultPrompt", "default_prompt",
}
skill_fields = {"name", "description", "license", "allowed-tools", "metadata"}


def nonempty(value):
    return isinstance(value, str) and bool(value.strip())


def https_url(value):
    parsed = urlparse(value) if isinstance(value, str) else None
    return parsed is not None and parsed.scheme == "https" and bool(parsed.netloc)


def contains_todo(value):
    if isinstance(value, str):
        return "[TODO:" in value
    if isinstance(value, list):
        return any(contains_todo(item) for item in value)
    if isinstance(value, dict):
        return any(contains_todo(item) for item in value.values())
    return False


def contract_path(value, expected):
    if not isinstance(value, str):
        return False
    path = pathlib.PurePosixPath(value.replace("\\", "/"))
    return not path.is_absolute() and path.as_posix().rstrip("/") == expected


def load_companion(plugin_root, filename):
    path = plugin_root / filename
    assert path.is_file(), f"missing companion manifest: {path}"
    value = json.loads(path.read_text())
    assert isinstance(value, dict), f"companion manifest is not an object: {path}"
    return value


def validate_assets(plugin_root, interface):
    paths = [interface[field] for field in ("composerIcon", "logo", "logoDark") if field in interface]
    screenshots = interface.get("screenshots", [])
    assert isinstance(screenshots, list), "interface.screenshots must be a list"
    paths.extend(screenshots)
    for value in paths:
        assert nonempty(value), f"invalid asset path: {value!r}"
        candidate = pathlib.PurePosixPath(value.replace("\\", "/"))
        assert not candidate.is_absolute() and not any(part in {"", ".", ".."} for part in candidate.parts), value
        resolved = (plugin_root / candidate.as_posix()).resolve()
        assert resolved.is_relative_to(plugin_root.resolve()) and resolved.is_file(), value


def validate_skill(skill_path):
    content = skill_path.read_text()
    match = re.match(r"^---\n(.*?)\n---(?:\n|$)", content, re.DOTALL)
    assert match, f"invalid skill frontmatter delimiters: {skill_path}"
    frontmatter = yaml.safe_load(match.group(1))
    assert isinstance(frontmatter, dict), f"skill frontmatter is not an object: {skill_path}"
    unknown = set(frontmatter) - skill_fields
    assert not unknown, f"unsupported skill frontmatter in {skill_path}: {sorted(unknown)}"
    name = frontmatter.get("name")
    description = frontmatter.get("description")
    assert nonempty(name), f"skill name is missing: {skill_path}"
    assert re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", name), f"invalid skill name: {name}"
    assert len(name) <= 64, f"skill name is too long: {name}"
    assert name == skill_path.parent.name, f"skill directory and name differ: {skill_path}"
    assert nonempty(description), f"skill description is missing: {skill_path}"
    assert len(description.strip()) <= 1024, f"skill description is too long: {skill_path}"
    assert "<" not in description and ">" not in description, f"skill description has angle brackets: {skill_path}"
    assert not description.startswith("[TODO:"), f"skill description has a TODO: {skill_path}"


names = {entry["name"] for entry in entries}
assert names == expected, f"marketplace names differ: {sorted(names)}"
assert set(marketplace) == {"name", "interface", "plugins"}
assert nonempty(marketplace["name"])
assert set(marketplace["interface"]) == {"displayName"}
assert nonempty(marketplace["interface"]["displayName"])

for entry in entries:
    name = entry["name"]
    assert set(entry) == {"name", "source", "policy", "category"}, f"{name}: invalid marketplace entry"
    assert set(entry["source"]) == {"source", "path"}, f"{name}: invalid marketplace source"
    assert set(entry["policy"]) <= {"installation", "authentication", "products"}, name
    assert nonempty(entry["category"]), f"{name}: marketplace category is missing"
    plugin_root = root / entry["source"]["path"]
    manifest = json.loads((plugin_root / ".codex-plugin/plugin.json").read_text())
    claude = json.loads((root / "plugins" / name / ".claude-plugin/plugin.json").read_text())
    assert not contains_todo(manifest), f"{name}: manifest contains a TODO placeholder"
    assert not set(manifest) - plugin_fields, f"{name}: unsupported manifest fields"
    if "id" in manifest:
        assert nonempty(manifest["id"]), f"{name}: id is empty"
    assert manifest["name"] == name
    assert re.fullmatch(r"[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*", name), name
    assert semver.fullmatch(manifest["version"]), f"{name}: version is not strict semver"
    assert manifest["version"] == claude["version"], name
    assert nonempty(manifest.get("description")), f"{name}: description is missing"
    author = manifest.get("author")
    assert isinstance(author, dict) and not set(author) - {"name", "email", "url"}, f"{name}: invalid author"
    assert nonempty(author.get("name")), f"{name}: author name is missing"
    if "email" in author:
        assert nonempty(author["email"]), f"{name}: author email is empty"
    if "url" in author:
        assert https_url(author["url"]), f"{name}: author URL is invalid"
    assert all(nonempty(manifest.get(field)) for field in ("homepage", "repository", "license")), name
    assert https_url(manifest["homepage"]) and https_url(manifest["repository"]), name
    assert isinstance(manifest.get("keywords"), list) and all(nonempty(item) for item in manifest["keywords"]), name
    assert manifest["skills"] == "./skills/"
    if "apps" in manifest:
        assert contract_path(manifest["apps"], ".app.json"), f"{name}: invalid apps path"
        app_manifest = load_companion(plugin_root, ".app.json")
        assert set(app_manifest) == {"apps"} and isinstance(app_manifest["apps"], dict), name
        for app_name, app in app_manifest["apps"].items():
            assert nonempty(app_name) and isinstance(app, dict), f"{name}: invalid app entry"
            assert not set(app) - {"id", "category"} and nonempty(app.get("id")), app_name
            assert "category" not in app or nonempty(app["category"]), app_name
    if "mcpServers" in manifest:
        servers = manifest["mcpServers"]
        if isinstance(servers, str):
            assert contract_path(servers, ".mcp.json"), f"{name}: invalid MCP path"
            mcp_manifest = load_companion(plugin_root, ".mcp.json")
            assert set(mcp_manifest) == {"mcpServers"}, name
            servers = mcp_manifest["mcpServers"]
        assert isinstance(servers, dict), f"{name}: MCP servers must be an object"
        assert all(nonempty(server_name) and isinstance(server, dict) for server_name, server in servers.items()), name
    interface = manifest.get("interface")
    assert isinstance(interface, dict) and not set(interface) - interface_fields, f"{name}: invalid interface"
    for field in ("displayName", "shortDescription", "longDescription", "developerName", "category"):
        assert nonempty(interface.get(field)), f"{name}: interface.{field} is missing"
    assert isinstance(interface.get("capabilities"), list), f"{name}: capabilities must be a list"
    assert all(nonempty(item) for item in interface["capabilities"]), f"{name}: invalid capability"
    prompts = interface.get("defaultPrompt", interface.get("default_prompt"))
    assert isinstance(prompts, list) and 1 <= len(prompts) <= 3, f"{name}: invalid default prompts"
    assert all(nonempty(item) and len(item) <= 128 for item in prompts), f"{name}: invalid default prompt"
    for field in ("websiteURL", "privacyPolicyURL", "termsOfServiceURL"):
        if field in interface:
            assert https_url(interface[field]), f"{name}: interface.{field} is invalid"
    if "brandColor" in interface:
        assert isinstance(interface["brandColor"], str) and re.fullmatch(r"#[0-9A-Fa-f]{6}", interface["brandColor"]), name
    validate_assets(plugin_root, interface)
    skills = {path.parent.name for path in (plugin_root / "skills").glob("*/SKILL.md")}
    assert skills == expected_skills[name], f"{name}: {sorted(skills)}"
    for skill in sorted((plugin_root / "skills").glob("*/SKILL.md")):
        validate_skill(skill)
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

claude_only_scripts = {
    "plugins/planning/scripts/plan-review-hook.py",
}
behaviour_checked_adaptations = {
    "plugins/codex/brainstorm/scripts/resolve-rules.sh",
    "plugins/codex/planning/scripts/resolve-rules.sh",
    "plugins/codex/planning/skills/exec/scripts/customize-file.sh",
    "plugins/codex/planning/skills/exec/scripts/resolve-file.sh",
    "plugins/codex/planning/skills/exec/scripts/run-codex.sh",
    "plugins/codex/planning/skills/exec/scripts/run-external-review.sh",
    "plugins/codex/skill-eval/hooks/skill-forced-eval-hook.sh",
}
classified_sources = set(copy_pairs) | set(code_equivalent_pairs) | set(adapted_pairs)
classified_codex = set(copy_pairs.values()) | set(code_equivalent_pairs.values()) | set(adapted_pairs.values())
claude_scripts = {
    path.relative_to(root).as_posix()
    for path in (root / "plugins").rglob("*")
    if path.suffix in {".py", ".sh"} and "plugins/codex/" not in path.as_posix()
}
codex_scripts = {
    path.relative_to(root).as_posix()
    for path in (root / "plugins/codex").rglob("*")
    if path.suffix in {".py", ".sh"}
}
assert claude_scripts == classified_sources | claude_only_scripts, (
    f"Claude script parity classification differs: unclassified={sorted(claude_scripts - classified_sources - claude_only_scripts)}, "
    f"stale={sorted((classified_sources | claude_only_scripts) - claude_scripts)}"
)
assert codex_scripts == classified_codex, (
    f"Codex script parity classification differs: unclassified={sorted(codex_scripts - classified_codex)}, "
    f"stale={sorted(classified_codex - codex_scripts)}"
)
assert behaviour_checked_adaptations == set(adapted_pairs.values())

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

mkdir -p "$CODEX_HOME/cc-thingz/planning"
printf 'user planning\n' >"$CODEX_HOME/cc-thingz/planning/planning-rules.md"
actual="$(cd "$WORK_DIR" && CODEX_HOME="$CODEX_HOME" bash "$CODEX_ROOT/planning/scripts/resolve-rules.sh" planning-rules.md)"
test "$actual" = "user planning"

printf 'project planning\n' >"$WORK_DIR/.codex/planning-rules.md"
actual="$(cd "$WORK_DIR" && CODEX_HOME="$CODEX_HOME" bash "$CODEX_ROOT/planning/scripts/resolve-rules.sh" planning-rules.md)"
test "$actual" = "project planning"

printf 'user task prompt\n' >"$CODEX_HOME/cc-thingz/planning/exec-plan/prompts/task.md"
actual="$(cd "$WORK_DIR" && CODEX_HOME="$CODEX_HOME" bash "$CODEX_ROOT/planning/skills/exec/scripts/resolve-file.sh" prompts/task.md)"
test "$actual" = "user task prompt"

mkdir -p "$WORK_DIR/.codex/exec-plan/prompts"
printf 'project task prompt\n' >"$WORK_DIR/.codex/exec-plan/prompts/task.md"
actual="$(cd "$WORK_DIR" && CODEX_HOME="$CODEX_HOME" bash "$CODEX_ROOT/planning/skills/exec/scripts/resolve-file.sh" prompts/task.md)"
test "$actual" = "project task prompt"

CUSTOM_WORK="$TMP_ROOT/custom-work"
mkdir -p "$CUSTOM_WORK"
actual="$(cd "$CUSTOM_WORK" && CODEX_HOME="$CODEX_HOME" bash "$CODEX_ROOT/planning/skills/exec/scripts/customize-file.sh" prompts/review.md)"
test "$actual" = ".codex/exec-plan/prompts/review.md"
cmp "$CUSTOM_WORK/$actual" "$CODEX_ROOT/planning/skills/exec/references/prompts/review.md"

actual="$(cd "$CUSTOM_WORK" && CODEX_HOME="$CODEX_HOME" bash "$CODEX_ROOT/planning/skills/exec/scripts/customize-file.sh" agents/quality.txt --user)"
test "$actual" = "$CODEX_HOME/cc-thingz/planning/exec-plan/agents/quality.txt"
cmp "$actual" "$CODEX_ROOT/planning/skills/exec/references/agents/quality.txt"

FAKE_BIN="$TMP_ROOT/fake-bin"
CAPTURE="$TMP_ROOT/args"
mkdir -p "$FAKE_BIN"
cat >"$FAKE_BIN/codex" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >"$CAPTURE"
EOF
chmod +x "$FAKE_BIN/codex"

CAPTURE="$CAPTURE" PATH="$FAKE_BIN:$PATH" CODEX_MODEL="review-model" \
    bash "$CODEX_ROOT/planning/skills/exec/scripts/run-codex.sh" "review prompt"
cat >"$TMP_ROOT/expected-args" <<'EOF'
exec
--sandbox
read-only
-c
model_reasoning_effort=xhigh
-c
stream_idle_timeout_ms=3600000
-c
model=review-model
review prompt
EOF
cmp "$CAPTURE" "$TMP_ROOT/expected-args"

CAPTURE="$CAPTURE" PATH="$FAKE_BIN:$PATH" CODEX_NO_OVERRIDES=1 \
    bash "$CODEX_ROOT/planning/skills/exec/scripts/run-codex.sh" "proxy prompt"
cat >"$TMP_ROOT/expected-args" <<'EOF'
exec
--sandbox
read-only
proxy prompt
EOF
cmp "$CAPTURE" "$TMP_ROOT/expected-args"

cat >"$FAKE_BIN/reviewer" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >"$CAPTURE"
EOF
chmod +x "$FAKE_BIN/reviewer"
CAPTURE="$CAPTURE" PATH="$FAKE_BIN:$PATH" \
    bash "$CODEX_ROOT/planning/skills/exec/scripts/run-external-review.sh" "reviewer --strict" "external prompt"
printf '%s\n' '--strict' 'external prompt' >"$TMP_ROOT/expected-args"
cmp "$CAPTURE" "$TMP_ROOT/expected-args"

hook_output="$(sh "$CODEX_ROOT/skill-eval/hooks/skill-forced-eval-hook.sh")"
case "$hook_output" in
    *"MANDATORY SKILL EVALUATION"*"Read each selected SKILL.md completely"*) ;;
    *) echo "Codex skill-eval hook output is incomplete" >&2; exit 1 ;;
esac
case "$hook_output" in
    *Claude*|*'Skill('*) echo "Codex skill-eval hook contains Claude-only instructions" >&2; exit 1 ;;
esac

echo "Codex package tests passed"
