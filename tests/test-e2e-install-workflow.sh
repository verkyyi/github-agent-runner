#!/usr/bin/env bash
# Tier-3 (skill E2E): exercise /install-workflow on a fresh throwaway repo.
#
# Single-workflow install is the plugin's core path — everything else builds
# on it. This test verifies: given a clean repo and a workflow name, does
# invoking install-workflow produce the expected end-state (fetched .md,
# compiled .lock.yml with OAuth tweak, engine: claude applied if upstream
# omitted it, `source:` frontmatter pointing at agentics)?
#
# Uses `daily-repo-status` as the test target since it's the README-advertised
# starter and exercises the important Step-5 path (upstream omits engine:,
# skill must detect and fix it, then recompile, then apply the tweak).
#
# Usage:
#   ./tests/test-e2e-install-workflow.sh                  # fresh run, cleanup on exit
#   ./tests/test-e2e-install-workflow.sh --keep           # leave repo around
#   ./tests/test-e2e-install-workflow.sh --workflow NAME  # install a different workflow
#
# Cost: ~2-4 min wall-clock, creates 1 private repo per run (deleted on
# success unless --keep).
#
# Prereqs same as test-e2e-install-agent-team.sh: gh CLI with admin scope,
# AWS CLI, /claude/oauth-token SSM parameter.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

OWNER="${OWNER:-verkyyi}"
REPO_NAME=""
WORKFLOW="${WORKFLOW:-daily-repo-status}"
KEEP=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --keep)        KEEP=true; shift ;;
    --repo)        REPO_NAME="$2"; shift 2 ;;
    --workflow)    WORKFLOW="$2"; shift 2 ;;
    --help|-h)     sed -n '1,27p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

[ -z "$REPO_NAME" ] && REPO_NAME="install-workflow-e2e-$(date -u +%Y%m%d%H%M%S)"
FULL="$OWNER/$REPO_NAME"
WORKDIR="$(mktemp -d -t iw-e2e-XXXXXX)"
trap '[ "$KEEP" = true ] || rm -rf "$WORKDIR"' EXIT

command -v gh >/dev/null || { echo "gh CLI required"; exit 1; }
command -v aws >/dev/null || { echo "aws CLI required"; exit 1; }
command -v claude >/dev/null || { echo "claude CLI required"; exit 1; }

# Preflight: required gh scopes. `repo` for create, `delete_repo` for teardown.
check_gh_scope() {
    local scope="$1"
    gh auth status 2>&1 | grep -q "'$scope'" \
        || { echo "Missing gh scope: $scope"; echo "  Fix: gh auth refresh -h github.com -s $scope"; exit 1; }
}
check_gh_scope repo
[ "$KEEP" = true ] || check_gh_scope delete_repo

# Cleanup with two guards to prevent accidental deletion of real repos:
#  1. Name must match the timestamped e2e-throwaway pattern.
#  2. Repo must be less than 2 hours old.
# Script-driven only — the AI agent invoked via claude -p does not run this.
E2E_REPO_PATTERN='install-workflow-e2e-[0-9]{14}$'
cleanup_repo() {
    local repo="$1"
    local short="${repo##*/}"
    if ! [[ "$short" =~ $E2E_REPO_PATTERN ]]; then
        echo "  REFUSING to delete $repo — name does not match e2e-throwaway pattern ($E2E_REPO_PATTERN)"
        return 1
    fi
    local created_at
    created_at=$(gh api "/repos/$repo" --jq '.created_at' 2>/dev/null) || { echo "  Repo $repo not found"; return 1; }
    local age=$(( $(date -u +%s) - $(date -u -d "$created_at" +%s) ))
    if [ "$age" -gt 7200 ]; then
        echo "  REFUSING to delete $repo — age ${age}s exceeds 2-hour threshold (created $created_at)"
        return 1
    fi
    if ! gh repo delete "$repo" --yes 2>&1; then
        echo "  FAILED to delete $repo — check delete_repo scope"
        return 1
    fi
    echo "  Deleted $repo (age ${age}s)"
}

fails=0
pass() { echo "  [PASS] $1"; }
fail() { echo "  [FAIL] $1"; fails=$((fails+1)); }

echo "=== Tier-3 skill E2E: /install-workflow $WORKFLOW on $FULL ==="

# 1. Provision
echo ""
echo "-- Provisioning fresh repo --"
gh repo create "$FULL" --private --description "Throwaway E2E test repo for /install-workflow" >/dev/null
git clone "https://github.com/$FULL.git" "$WORKDIR/repo" --quiet
(
  cd "$WORKDIR/repo"
  echo "# install-workflow-e2e-test" > README.md
  echo "Throwaway repo — exercises \`/install-workflow $WORKFLOW\`. Deleted on success." >> README.md
  git add -A && git -c user.name="e2e" -c user.email="e2e@local" commit -m "seed" --quiet
  git push origin main --quiet
)
echo "  Provisioned $FULL"

# 2. Pre-seed secret (auth flow not under test — see skills/install-workflow/auth.md)
echo ""
echo "-- Pre-seeding auth secret --"
aws ssm get-parameter --region us-east-1 --name /claude/oauth-token --with-decryption \
  --query Parameter.Value --output text 2>/dev/null \
  | gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo "$FULL"
echo "  Set CLAUDE_CODE_OAUTH_TOKEN"

# 3. Invoke /install-workflow
echo ""
echo "-- Invoking /install-workflow $WORKFLOW via claude -p --"
PROMPT="We are in a fresh clone of github repo $FULL. The repo already has CLAUDE_CODE_OAUTH_TOKEN set as a secret (confirm via gh secret list and skip the 'claude setup-token' step — proceed on the OAuth path). Execute the /install-workflow skill for workflow name: $WORKFLOW. Follow every step including the Step-5 engine check (if upstream omits engine:, add engine: claude and recompile), the OAuth post-compile tweak (two-pass sed), gh aw validate, then commit and push to origin/main. Do not pause for confirmations — proceed autonomously. When done, print 'INSTALL_WORKFLOW_E2E_DONE' on its own line."

cd "$WORKDIR/repo"
claude -p "$PROMPT" \
  --plugin-dir "$REPO_ROOT" \
  --permission-mode bypassPermissions \
  --allowed-tools "Bash,Read,Write,Edit,Grep,Glob" \
  > "$WORKDIR/skill-output.log" 2>&1 || true
cd - >/dev/null
tail -5 "$WORKDIR/skill-output.log"

# 4. Assert against remote
echo ""
echo "-- Assertions --"
rm -rf "$WORKDIR/verify"
git clone "https://github.com/$FULL.git" "$WORKDIR/verify" --quiet
cd "$WORKDIR/verify"

md=".github/workflows/${WORKFLOW}.md"
lock=".github/workflows/${WORKFLOW}.lock.yml"

[ -f "$md" ]   && pass "source committed: $md"   || fail "missing source: $md"
[ -f "$lock" ] && pass "lockfile committed: $lock" || fail "missing lockfile: $lock"

if [ -f "$md" ]; then
  grep -q "^engine: claude" "$md" \
    && pass "frontmatter has engine: claude" \
    || fail "frontmatter missing engine: claude (Step 5 not applied)"
  grep -q "^source: githubnext/agentics" "$md" \
    && pass "frontmatter has source: githubnext/agentics" \
    || fail "frontmatter missing source: githubnext/agentics"
fi

if [ -f "$lock" ]; then
  api=$(grep -c "ANTHROPIC_API_KEY" "$lock")
  oauth=$(grep -c "CLAUDE_CODE_OAUTH_TOKEN" "$lock")
  if [ "$api" -ge 2 ] && [ "$oauth" -ge 5 ]; then
    pass "OAuth tweak applied (API=$api, OAUTH=$oauth; expect API≥2 OAUTH≥5)"
  else
    fail "OAuth tweak shape wrong (API=$api, OAUTH=$oauth) — verify the two-pass sed ran"
  fi
  # The --exclude-env carve-out must still reference ANTHROPIC_API_KEY, not CLAUDE_CODE_OAUTH_TOKEN
  if grep -q "exclude-env ANTHROPIC_API_KEY" "$lock" && ! grep -q "exclude-env CLAUDE_CODE_OAUTH_TOKEN" "$lock"; then
    pass "--exclude-env carve-out preserved (ANTHROPIC_API_KEY stays, not replaced)"
  else
    fail "--exclude-env carve-out wrong — Pass 2 of the sed tweak was skipped or over-applied"
  fi
fi

cd - >/dev/null

grep -q "INSTALL_WORKFLOW_E2E_DONE" "$WORKDIR/skill-output.log" \
  && pass "skill printed INSTALL_WORKFLOW_E2E_DONE" \
  || fail "skill did not print completion marker (stalled or errored; log: $WORKDIR/skill-output.log)"

# 5. Cleanup
echo ""
if [ "$fails" -eq 0 ] && [ "$KEEP" != true ]; then
  echo "-- All green; deleting throwaway repo --"
  cleanup_repo "$FULL" || fails=$((fails+1))
  rm -rf "$WORKDIR"
else
  echo "-- Kept: $FULL (repo) and $WORKDIR (logs) --"
  echo "   Skill output: $WORKDIR/skill-output.log"
fi

echo ""
if [ "$fails" -gt 0 ]; then
  echo "=== FAILED ($fails assertion(s)) ==="
  exit 1
else
  echo "=== /install-workflow E2E passed ==="
fi
