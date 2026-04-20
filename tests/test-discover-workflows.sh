#!/usr/bin/env bash
# Test: discover-workflows skill
# Directive questions — each prompt tells Claude to load SKILL.md via the Skill
# tool and quote a specific fact, rather than describe the skill from its
# short frontmatter blurb. Deterministic assertions, not LLM-phrasing lottery.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "=== Test: discover-workflows skill ==="
echo ""

# Test 1: Purpose + upstream source (one Skill-tool load covers both).
echo "Test 1: Skill loads and documents its upstream source..."
output=$(run_claude "Use the Skill tool to load the github-agent-runner plugin's discover-workflows skill, then answer: (1) in one sentence what is its purpose? and (2) what upstream repository does it fetch its workflow list from at runtime? Quote the upstream repo path exactly as it appears in SKILL.md." 180)
# Deterministic: check the session transcript for a Skill tool invocation
# against the discover-workflows skill, not Claude's prose mentioning the
# name. Structural, variance-free.
assert_skill_used "discover-workflows" "Skill tool invoked for discover-workflows" || exit 1
assert_contains "$output" "agentics|gh-aw|upstream|catalog" "Mentions source (agentics / gh-aw / catalog)" || exit 1
assert_contains "$output" "recommend|suggest|shortlist|tailor|fit|pick" "Frames itself as recommendation, not listing" || exit 1

echo ""

# Test 2: Runtime fetch (no static catalog).
echo "Test 2: Runtime source fetch, not a local static catalog..."
output=$(run_claude "Load the discover-workflows skill via the Skill tool. Does it ship a local catalog of workflows, or fetch them from a remote source at runtime? Name the upstream repo and quote the specific phrase from SKILL.md that confirms this (wording about fetching at runtime or no local catalog to drift)." 180)
assert_contains "$output" "agentics|gh-aw|githubnext" "Names upstream source" || exit 1
assert_contains "$output" "fetch|runtime|live|remote|network|on demand|API" "Describes dynamic retrieval" || exit 1

echo ""

# Test 3: Fail-stop on upstream unreachable.
echo "Test 3: Fail-stop when upstream catalog is unreachable..."
output=$(run_claude "Per the discover-workflows skill's SKILL.md, if the upstream source (githubnext/agentics) is unreachable at runtime, what does the skill do? Quote the specific instruction about failure handling verbatim." 180)
assert_contains "$output" "stop|error|fail|surface|report|abort" "Surfaces the failure" || exit 1

echo ""
echo "=== All discover-workflows tests passed ==="
