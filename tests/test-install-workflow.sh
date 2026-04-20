#!/usr/bin/env bash
# Test: install-workflow skill
# Verifies that the skill loads and that Claude describes both auth paths,
# the critical OAuth carve-out, and the key hard rules.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "=== Test: install-workflow skill ==="
echo ""

# Test 1: Skill loading + key steps
echo "Test 1: Skill loading and key steps..."
output=$(run_claude "What is the install-workflow skill? Describe its key steps briefly." 90)
assert_contains "$output" "install-workflow|Install Workflow|installs? (a |the )?workflow" "Skill is recognized" || exit 1
assert_contains "$output" "gh aw add" "Mentions gh aw add" || exit 1
assert_contains "$output" "secret|gh secret set" "Mentions secret setup" || exit 1

echo ""

# Test 2: Two auth paths
echo "Test 2: Two auth paths documented..."
output=$(run_claude "What auth options does install-workflow support? Describe the OAuth path and the API-key path." 90)
assert_contains "$output" "CLAUDE_CODE_OAUTH_TOKEN|OAuth" "Documents OAuth path" || exit 1
assert_contains "$output" "ANTHROPIC_API_KEY|API.?key" "Documents API-key path" || exit 1

echo ""

# Test 3: The exclude-env carve-out is understood
echo "Test 3: OAuth exclude-env carve-out..."
output=$(run_claude "In the install-workflow skill, why must the line '--exclude-env ANTHROPIC_API_KEY' be preserved rather than replaced with CLAUDE_CODE_OAUTH_TOKEN?" 90)
assert_contains "$output" "exclude-env|exclude.env" "References the carve-out" || exit 1
assert_contains "$output" "sandbox|strip|Not logged in|auth.*fail" "Explains the failure mode" || exit 1

echo ""

# Test 4: Never writes YAML by hand
echo "Test 4: Never writes workflow YAML by hand..."
output=$(run_claude "Does install-workflow ever write workflow YAML by hand, or does it always delegate? Answer directly." 90)
assert_contains "$output" "never|delegate|does not|always.*delegate" "Always delegates to gh aw add" || exit 1

echo ""

# Test 5: Never stores the auth token
echo "Test 5: Never stores/echoes the auth token..."
output=$(run_claude "Does install-workflow store, echo, or see the user's auth token directly? Answer directly." 90)
assert_contains "$output" "never|does not|doesn't|no" "Never handles the token" || exit 1

echo ""
echo "=== All install-workflow tests passed ==="
