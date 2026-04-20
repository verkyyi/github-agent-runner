#!/usr/bin/env bash
# Tier-2 invariant checks. Fast, runner-free, deterministic.
#
# Each assertion is tied to a specific past bug so we detect regressions
# without paying for a tier-3 dogfood run. Add new invariants only when
# caught-in-review (not preemptively) — the cost is maintenance drag.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

fails=0
pass() { echo "  [PASS] $1"; }
fail() { echo "  [FAIL] $1"; fails=$((fails+1)); }

# Scope of user-facing text we check:
USER_FACING=(
  "$REPO_ROOT/README.md"
  "$REPO_ROOT/CONTRIBUTING.md"
  "$REPO_ROOT/skills/"
  "$REPO_ROOT/catalog/"
)

check_forbidden() {
  local phrase="$1" reason="$2"
  if grep -rqF -- "$phrase" "${USER_FACING[@]}" 2>/dev/null; then
    fail "Forbidden: \"$phrase\" — $reason"
    grep -rnF -- "$phrase" "${USER_FACING[@]}" 2>/dev/null | sed 's/^/    /' | head -3
  else
    pass "Absent: \"$phrase\""
  fi
}

check_required() {
  local file="$1" phrase="$2" reason="$3"
  if grep -qF -- "$phrase" "$REPO_ROOT/$file" 2>/dev/null; then
    pass "$file contains: \"$phrase\""
  else
    fail "$file missing: \"$phrase\" — $reason"
  fi
}

check_exists() {
  local path="$1"
  [ -e "$REPO_ROOT/$path" ] && pass "Exists: $path" || fail "Missing: $path"
}

check_absent() {
  local path="$1" reason="$2"
  if [ -e "$REPO_ROOT/$path" ]; then
    fail "Re-introduced: $path — $reason"
  else
    pass "Stays absent: $path"
  fi
}

echo "=== Tier-2 invariant checks ==="

echo ""
echo "-- Forbidden stale phrases (past migrations) --"
# d4295cf: update-docs switched push→schedule
check_forbidden "every push to \`main\`" "update-docs now runs schedule: daily"
# dispatch-workflow migration dropped state:spec-needed as a control label
check_forbidden "state:spec-needed" "removed during dispatch-workflow migration"
# b3f6341: the Publishing TODO is gone (replaced by Releases section)
check_forbidden "Once v0.1 is scope-locked" "Publishing section replaced by Releases in v0.2"
# v0.2.0 shipped; status line updated
check_forbidden "pre-scope-lock" "v0.2.0 shipped"

echo ""
echo "-- Required phrases (past fixes, c99b00f) --"
check_required "skills/install-workflow/SKILL.md" "gh auth refresh -s workflow" "workflow-scope preflight remediation"
check_required "skills/install-agent-team/SKILL.md" "gh auth refresh -s workflow" "workflow-scope preflight remediation"
check_required "skills/install-workflow/auth.md" "silently hang" "claude setup-token TTY warning"
check_required "skills/install-workflow/auth.md" "headless containers" "specific failure envs named"
check_required "catalog/agent-team/reviewer-agent.md" "--workflow=\"Spec Agent\"" "reviewer run-lookup uses display name, not .yml"

echo ""
echo "-- Core files exist --"
check_exists "LICENSE"
check_exists ".claude-plugin/plugin.json"
check_exists "catalog/agent-team/spec-agent.md"
check_exists "catalog/agent-team/planner-agent.md"
check_exists "catalog/agent-team/implementer-agent.md"
check_exists "catalog/agent-team/reviewer-agent.md"

echo ""
echo "-- Dropped workflows stay dropped --"
# b3f6341: trimmed the dogfood set. Re-introducing the source files would
# mean a workflow is live again and may contradict the README.
check_absent ".github/workflows/pr-nitpick-reviewer.md" "dropped in b3f6341"
check_absent ".github/workflows/repo-assist.md" "dropped in b3f6341"
check_absent ".github/workflows/q.md" "dropped in b3f6341"
check_absent ".github/workflows/daily-plan.md" "dropped in b3f6341"
check_absent ".github/workflows/markdown-linter.md" "dropped in b3f6341"

echo ""
echo "-- README ↔ filesystem consistency --"
# Every workflow path mentioned in the README dogfood table must exist.
while IFS= read -r wf; do
  check_exists "$wf"
done < <(grep -oE "\.github/workflows/[a-z][a-z0-9-]*\.md" "$REPO_ROOT/README.md" | sort -u)

echo ""
echo "-- Plugin manifest version matches README claim --"
manifest_version=$(grep -oE '"version": *"[^"]+"' "$REPO_ROOT/.claude-plugin/plugin.json" | grep -oE '"[^"]+"$' | tr -d '"')
if grep -qF "v${manifest_version}" "$REPO_ROOT/README.md"; then
  pass "README mentions v${manifest_version} from plugin.json"
else
  fail "plugin.json says v${manifest_version} but README doesn't mention it — bump one or the other"
fi

echo ""
if [ "$fails" -gt 0 ]; then
  echo "=== FAILED ($fails assertion(s)) ==="
  exit 1
else
  echo "=== All invariants PASSED ==="
fi
