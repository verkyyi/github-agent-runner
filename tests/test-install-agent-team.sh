#!/usr/bin/env bash
# Test: install-agent-team skill
# Verifies that the unified installer loads, pitches the single-label dispatch
# model, installs all four roles atomically, wires auth once, applies the
# OAuth tweak to every lockfile, and creates the label set up front.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "=== Test: install-agent-team skill ==="
echo ""

# Test 1: Skill loading + the four roles
echo "Test 1: Skill loading and four-role pitch..."
output=$(run_claude "What is the install-agent-team skill? Describe what it installs." 180)
assert_contains "$output" "install-agent-team|agent.?team" "Skill is recognized" || exit 1
assert_contains "$output" "four" "Mentions four (roles/workflows/agents)" || exit 1
assert_contains "$output" "spec" "Mentions the spec role" || exit 1
assert_contains "$output" "plan" "Mentions the planner role" || exit 1
assert_contains "$output" "implement" "Mentions the implementer role" || exit 1
assert_contains "$output" "review" "Mentions the reviewer role" || exit 1

echo ""

# Test 2: Single-label dispatch is the user-facing contract
echo "Test 2: One-label dispatch model..."
output=$(run_claude "After installing the agent-team via install-agent-team, what does a user do to dispatch a task to the agent pipeline?" 180)
assert_contains "$output" "agent-team" "Mentions the agent-team label" || exit 1
assert_contains "$output" "label" "Mentions a label as the trigger" || exit 1
assert_contains "$output" "issue" "Dispatch is via an issue" || exit 1
# Single-label check: the deprecated two-label form (agent-team + state:spec-needed)
# must not appear as a required step. State:spec-needed was removed from the state
# machine, so any mention here signals the skill has drifted.
assert_not_contains "$output" "state:spec-needed" "No longer requires state:spec-needed" || exit 1

echo ""

# Test 3: Atomic install - all four, not one at a time
echo "Test 3: Atomic / all-or-nothing install..."
output=$(run_claude "If one of the four workflow installs fails during install-agent-team, what does the skill do?" 180)
assert_contains "$output" "stop|abort|back out|halt|all.or.nothing|not proceed|does not proceed" "Stops on partial failure" || exit 1
assert_contains "$output" "half|partial|stall|dead.?end|unit" "Explains why a partial install is bad" || exit 1

echo ""

# Test 4: Auth wired once, tweak applied to every lockfile
echo "Test 4: Auth once + OAuth tweak across all four lockfiles..."
output=$(run_claude "Does install-agent-team ask for auth separately for each of the four workflows, and does it apply the OAuth token tweak to one or to all of the generated .lock.yml files?" 180)
assert_contains "$output" "once|single|one.*secret|reuse" "Auth configured once" || exit 1
assert_contains "$output" "all|every|each|four" "Tweak applied to every lockfile" || exit 1
assert_contains "$output" "lock\\.yml|\\.lock\\.yml|lockfile" "References the lock files" || exit 1

echo ""

# Test 5: Labels created up front as part of install
echo "Test 5: Labels created by the installer..."
output=$(run_claude "Does install-agent-team create GitHub labels as part of installation, or must the user create them manually? List the labels it creates." 180)
assert_contains "$output" "creates?|gh label create|sets? up" "Installer creates labels" || exit 1
assert_contains "$output" "agent-team" "Creates the agent-team entry label" || exit 1
assert_contains "$output" "state:plan-needed|state:impl-needed|state:review-needed" "Creates the state:* labels" || exit 1
assert_contains "$output" "state:blocked|state:done" "Creates terminal state labels" || exit 1

echo ""

# Test 6: Never writes YAML by hand, never stores tokens (inherited hard rules)
echo "Test 6: Hard rules inherited from install-workflow..."
output=$(run_claude "In the install-agent-team skill, does Claude ever write workflow YAML directly, or store/echo the user's auth token? Answer directly." 180)
assert_contains "$output" "never|does not|doesn't|no" "Hard rules are upheld" || exit 1
assert_contains "$output" "gh aw add|delegate" "Delegates workflow generation" || exit 1

echo ""
echo "=== All install-agent-team tests passed ==="
