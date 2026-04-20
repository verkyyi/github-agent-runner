#!/usr/bin/env bash
# Tier-3 (skill E2E): exercise /install-agent-team on a fresh throwaway repo.
#
# Unlike test-e2e.sh (which tests an already-installed pipeline), this test
# verifies the SKILL itself: given a clean repo, does invoking install-agent-team
# produce the expected end-state (4 compiled lockfiles with OAuth tweak + 7
# labels + no hand-edits needed)?
#
# Usage:
#   ./tests/test-e2e-skill.sh                       # fresh run, cleanup on exit
#   ./tests/test-e2e-skill.sh --keep               # leave repo + branch around
#   ./tests/test-e2e-skill.sh --repo <name>         # use a specific repo name
#
# Cost: ~5-8 min wall-clock, creates 1 private repo per run (deleted on success
# unless --keep). Claude token cost for the skill invocation (OAuth subscription = free).
#
# Prereqs (local machine):
#   - gh CLI authenticated with admin scope (gh repo create + delete)
#   - AWS CLI authenticated, /claude/oauth-token SSM parameter exists (same
#     store we use for the playground's secret)
#   - This plugin cloned at the parent of tests/ (we use --plugin-dir on it)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

OWNER="${OWNER:-verkyyi}"
REPO_NAME=""
KEEP=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --keep)        KEEP=true; shift ;;
    --repo)        REPO_NAME="$2"; shift 2 ;;
    --help|-h)     sed -n '1,25p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

[ -z "$REPO_NAME" ] && REPO_NAME="agent-team-skill-test-$(date -u +%Y%m%d%H%M%S)"
FULL="$OWNER/$REPO_NAME"
WORKDIR="$(mktemp -d -t ateam-skill-XXXXXX)"
trap '[ "$KEEP" = true ] || rm -rf "$WORKDIR"' EXIT

command -v gh >/dev/null || { echo "gh CLI required"; exit 1; }
command -v aws >/dev/null || { echo "aws CLI required (for SSM OAuth token fetch)"; exit 1; }
command -v claude >/dev/null || { echo "claude CLI required"; exit 1; }

fails=0
pass() { echo "  [PASS] $1"; }
fail() { echo "  [FAIL] $1"; fails=$((fails+1)); }

echo "=== Tier-3 skill E2E: /install-agent-team on $FULL ==="

# 1. Create the throwaway repo + seed + push
echo ""
echo "-- Provisioning fresh repo --"
gh repo create "$FULL" --private --description "Throwaway E2E test repo for /install-agent-team" >/dev/null
git clone "https://github.com/$FULL.git" "$WORKDIR/repo" --quiet
(
  cd "$WORKDIR/repo"
  # minimal seed — just enough that the agents have something to reason about later
  cat > README.md <<'README'
# skill-e2e-test
Throwaway repo — exercises `/install-agent-team` end-to-end. Will be deleted on test success.
README
  echo "print('hello')" > hello.py
  git add -A && git -c user.name="e2e" -c user.email="e2e@local" commit -m "seed" --quiet
  git push origin main --quiet
)
echo "  Provisioned $FULL"

# 2. Pre-set the CLAUDE_CODE_OAUTH_TOKEN secret (auth setup is not exercised by
# this test — it's known headless-hostile and documented separately in auth.md).
echo ""
echo "-- Pre-seeding auth secret --"
aws ssm get-parameter --region us-east-1 --name /claude/oauth-token --with-decryption \
  --query Parameter.Value --output text 2>/dev/null \
  | gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo "$FULL"
echo "  Set CLAUDE_CODE_OAUTH_TOKEN"

# 3. Invoke the skill via claude -p against the repo clone
echo ""
echo "-- Invoking /install-agent-team via claude -p --"
PROMPT="We are in a fresh clone of github repo $FULL. The repo already has CLAUDE_CODE_OAUTH_TOKEN set as a secret (skip the 'claude setup-token' step in your install flow — confirm via gh secret list and proceed). Execute the /install-agent-team skill end-to-end: install all four agent-team workflows, apply the OAuth tweak to every lockfile, create the seven labels, validate. Commit and push all changes to origin/main. Do not pause for confirmations — proceed autonomously. When done, print 'SKILL_E2E_DONE' on its own line."

cd "$WORKDIR/repo"
claude -p "$PROMPT" \
  --plugin-dir "$REPO_ROOT" \
  --permission-mode bypassPermissions \
  --allowed-tools "Bash,Read,Write,Edit,Grep,Glob" \
  > "$WORKDIR/skill-output.log" 2>&1 || true
cd - >/dev/null
tail -5 "$WORKDIR/skill-output.log"

# 4. Assertions against remote state (pull to verify commits landed)
echo ""
echo "-- Assertions --"
rm -rf "$WORKDIR/verify"
git clone "https://github.com/$FULL.git" "$WORKDIR/verify" --quiet
cd "$WORKDIR/verify"

for wf in spec-agent planner-agent implementer-agent reviewer-agent; do
  [ -f ".github/workflows/${wf}.md" ] && pass "workflow source committed: ${wf}.md" \
    || fail "missing workflow source: ${wf}.md"
  [ -f ".github/workflows/${wf}.lock.yml" ] && pass "lockfile committed: ${wf}.lock.yml" \
    || fail "missing lockfile: ${wf}.lock.yml"
  if [ -f ".github/workflows/${wf}.lock.yml" ]; then
    api=$(grep -c "ANTHROPIC_API_KEY" ".github/workflows/${wf}.lock.yml")
    oauth=$(grep -c "CLAUDE_CODE_OAUTH_TOKEN" ".github/workflows/${wf}.lock.yml")
    if [ "$api" -ge 2 ] && [ "$oauth" -ge 5 ]; then
      pass "${wf} OAuth tweak applied (API=${api}, OAUTH=${oauth})"
    else
      fail "${wf} OAuth tweak shape wrong (API=${api}, OAUTH=${oauth}; expect API≥2 OAUTH≥5)"
    fi
  fi
done

cd - >/dev/null

# Labels
want_labels=(agent-team state:plan-needed state:impl-needed state:review-needed state:done state:blocked agent-team:reviewed)
have=$(gh label list --repo "$FULL" --limit 50 --json name --jq '[.[].name] | join(",")')
for lbl in "${want_labels[@]}"; do
  echo "$have" | grep -q "$lbl" && pass "label created: $lbl" || fail "label missing: $lbl"
done

# Did the agent print the completion marker?
grep -q "SKILL_E2E_DONE" "$WORKDIR/skill-output.log" \
  && pass "skill printed SKILL_E2E_DONE" \
  || fail "skill did not print SKILL_E2E_DONE (may have stalled or errored; see $WORKDIR/skill-output.log)"

# 5. Cleanup (or keep for inspection)
echo ""
if [ "$fails" -eq 0 ] && [ "$KEEP" != true ]; then
  echo "-- All green; deleting throwaway repo --"
  gh repo delete "$FULL" --yes 2>&1 | tail -1
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
  echo "=== Skill E2E passed ==="
fi
