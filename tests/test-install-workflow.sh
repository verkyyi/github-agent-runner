#!/usr/bin/env bash
# Test: install-workflow skill
# Directive questions — force Claude to load SKILL.md + auth.md via the Skill
# tool and quote the specific commands / rules under test, rather than describe
# the skill from its frontmatter blurb.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "=== Test: install-workflow skill ==="
echo ""

# Test 1: Load skill body + quote the exact commands it uses.
echo "Test 1: Skill loads; quotes the exact gh-aw and gh-secret commands..."
output=$(run_claude "Use the Skill tool to load the github-agent-runner plugin's install-workflow skill (read the full SKILL.md body, not just the description). Then quote two exact commands from its Flow section: (a) the gh-aw CLI command that fetches and compiles a workflow, and (b) the gh command that sets the auth secret. Quote them verbatim, including the subcommand names." 180)
assert_contains "$output" "install-workflow|Install Workflow|installs? (a |the )?workflow" "Skill is recognized" || exit 1
assert_contains "$output" "gh aw add" "Quotes 'gh aw add' verbatim" || exit 1
assert_contains "$output" "gh secret set" "Quotes 'gh secret set' verbatim" || exit 1

echo ""

# Test 2: Both auth paths explicitly documented.
echo "Test 2: Both auth paths (OAuth + API-key) documented in the skill..."
output=$(run_claude "Load the install-workflow skill and its auth.md file. What two secret names does the skill set — one for the Claude subscription OAuth path and one for the API-key path? Quote both secret names exactly as they appear in auth.md." 180)
assert_contains "$output" "CLAUDE_CODE_OAUTH_TOKEN|OAuth" "Documents OAuth path" || exit 1
assert_contains "$output" "ANTHROPIC_API_KEY|API.?key" "Documents API-key path" || exit 1

echo ""

# Test 3: The exclude-env carve-out.
echo "Test 3: --exclude-env ANTHROPIC_API_KEY carve-out is understood..."
output=$(run_claude "Load install-workflow's auth.md via the Skill or Read tool. Quote verbatim why the line '--exclude-env ANTHROPIC_API_KEY' MUST be preserved in the compiled .lock.yml, rather than being replaced with CLAUDE_CODE_OAUTH_TOKEN by the global sed. Name the specific failure mode (the exact CLI error message) that appears if this rule is violated." 180)
assert_contains "$output" "exclude-env|exclude.env" "References the carve-out" || exit 1
assert_contains "$output" "sandbox|strip|Not logged in|auth.*fail" "Explains the failure mode" || exit 1

echo ""

# Test 4: Never writes YAML by hand — quote the hard rule.
echo "Test 4: Hard rule 'never writes workflow YAML by hand'..."
output=$(run_claude "Load the install-workflow skill. Quote its hard rule about writing workflow YAML by hand — does it delegate, or generate YAML itself? Quote the exact rule text from the Hard rules section." 180)
assert_contains "$output" "never|delegate|does not|always.*delegate" "Always delegates to gh aw add" || exit 1

echo ""

# Test 5: Never stores the auth token — quote the hard rule.
echo "Test 5: Hard rule 'never stores/echoes the auth token'..."
output=$(run_claude "Load the install-workflow skill. Quote its hard rule about handling the user's auth token (storing, echoing, or seeing it directly). Quote the exact rule text from the Hard rules section." 180)
assert_contains "$output" "never|does not|doesn't|no" "Never handles the token" || exit 1

echo ""
echo "=== All install-workflow tests passed ==="
