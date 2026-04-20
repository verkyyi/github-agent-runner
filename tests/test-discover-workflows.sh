#!/usr/bin/env bash
# Test: discover-workflows skill
# Verifies that the skill loads and that Claude describes its key behavior
# (recommends from upstream catalog, fetches at runtime, fails loudly).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "=== Test: discover-workflows skill ==="
echo ""

# Test 1: Skill loading + purpose + scope.
# Patterns are widened for LLM phrasing variance — we check the skill is
# recognized, mentions some form of upstream source, and frames itself
# as making recommendations (not e.g. listing all workflows).
echo "Test 1: Skill loading and purpose..."
output=$(run_claude "What is the discover-workflows skill? Describe its job briefly." 180)
assert_contains "$output" "discover-workflows|Discover Workflows" "Skill is recognized" || exit 1
assert_contains "$output" "agentics|gh-aw|upstream|catalog" "Mentions source (agentics / gh-aw / catalog)" || exit 1
assert_contains "$output" "recommend|suggest|shortlist|tailor|fit|pick" "Frames itself as recommendation, not listing" || exit 1

echo ""

# Test 2: Runtime fetch (the key product decision — no static catalog).
# Asked directly to force Claude to describe the source mechanism.
echo "Test 2: Runtime source..."
output=$(run_claude "Where does the discover-workflows skill get its workflow list from? Is it stored in a local file or fetched from somewhere at runtime?" 180)
assert_contains "$output" "agentics|gh-aw|githubnext" "Names upstream source" || exit 1
assert_contains "$output" "fetch|runtime|live|remote|network|on demand|API" "Describes dynamic retrieval" || exit 1

echo ""

# Test 3: Failure behavior — no fallback to stale data.
echo "Test 3: Failure behavior when upstream unreachable..."
output=$(run_claude "If the upstream source (githubnext/agentics) is unreachable at runtime, what should the discover-workflows skill do?" 180)
assert_contains "$output" "stop|error|fail|surface|report|abort" "Surfaces the failure" || exit 1

echo ""
echo "=== All discover-workflows tests passed ==="
