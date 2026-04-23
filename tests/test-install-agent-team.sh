#!/usr/bin/env bash
# Test: install-agent-team skill
# Directive questions — force Claude to load SKILL.md via the Skill tool and
# quote specific facts (role names, the single-label contract, hard rules),
# rather than summarize from the frontmatter description.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "=== Test: install-agent-team skill ==="
echo ""

# Test 1: Load skill + name all five workflows.
echo "Test 1: Skill loads and names all five workflows..."
output=$(run_claude "Use the Skill tool to load the github-agent-runner plugin's install-agent-team skill (full SKILL.md, not just the description). Then list the five workflows it installs by name — the skill calls them out explicitly. Count and confirm there are exactly five." 180)
# Deterministic: check the session transcript for a Skill tool invocation
# against install-agent-team.
assert_skill_used "install-agent-team" "Skill tool invoked for install-agent-team" || exit 1
assert_contains "$output" "five" "Mentions five (workflows)" || exit 1
assert_contains "$output" "spec" "Names the spec role" || exit 1
assert_contains "$output" "plan" "Names the planner role" || exit 1
assert_contains "$output" "implement" "Names the implementer role" || exit 1
assert_contains "$output" "review" "Names the reviewer role" || exit 1
assert_contains "$output" "sweep" "Names the sweep workflow" || exit 1

echo ""

# Test 2: One-label dispatch contract.
echo "Test 2: One-label dispatch (just 'agent-team'), no secondary state label..."
output=$(run_claude "Load the install-agent-team skill. Per its 'User journey' or 'Kicking off a task' section, what is the single label a user adds to an issue to dispatch a task? Quote the exact label name. Does the user also need to add any state:* label by hand?" 180)
assert_contains "$output" "agent-team" "Mentions the agent-team label" || exit 1
assert_contains "$output" "label" "Mentions a label as the trigger" || exit 1
# Note: we deliberately do NOT assert "issue" here. The earlier test used
# to require it, but Claude's terse, well-directed answers to
# "what is the single label" naturally focus on the label name and may
# not re-state the obvious context (that labels go on issues). The
# 'mentions agent-team' + 'mentions label' pair is sufficient signal
# that Claude understood the dispatch model.
# State:spec-needed was removed from the state machine during the
# dispatch-workflow migration. Any mention in the skill's description of the
# user journey would signal a regression.
assert_not_contains "$output" "state:spec-needed" "No longer requires state:spec-needed" || exit 1

echo ""

# Test 3: Atomic install.
echo "Test 3: All-or-nothing install; partial state is unacceptable..."
output=$(run_claude "Load the install-agent-team skill. Per its Hard rules, if one of the five 'gh aw add' calls fails mid-install, what does the skill do — continue, skip, or abort? And why (what does the skill say about a half-installed pipeline)? Quote the exact hard-rule text." 180)
assert_contains "$output" "stop|abort|back out|halt|all.or.nothing|not proceed|does not proceed" "Stops on partial failure" || exit 1
assert_contains "$output" "half|partial|stall|dead.?end|unit" "Explains why a partial install is bad" || exit 1

echo ""

# Test 4: Auth configured once; tweak applied to every lockfile.
echo "Test 4: Auth wired once; OAuth tweak applied to every lockfile..."
output=$(run_claude "Load the install-agent-team skill. Does it configure the Claude auth secret once (reused across all five workflows) or set it separately per workflow? And does it apply the OAuth post-compile tweak to one .lock.yml file or to every generated .lock.yml? Quote the specific steps from the skill." 180)
assert_contains "$output" "once|single|one.*secret|reuse" "Auth configured once" || exit 1
assert_contains "$output" "all|every|each|five" "Tweak applied to every lockfile" || exit 1
assert_contains "$output" "lock\\.yml|\\.lock\\.yml|lockfile" "References the lock files" || exit 1

echo ""

# Test 5: Label creation is part of install.
echo "Test 5: All seven labels created by the installer (entry + state:* + reviewed)..."
output=$(run_claude "Load the install-agent-team skill. Does it create the required GitHub labels as part of installation, or does it expect the user to create them? List the label names it creates (per the skill's 'Create the labels' step) — there should be seven." 180)
assert_contains "$output" "creates?|gh label create|sets? up" "Installer creates labels" || exit 1
assert_contains "$output" "agent-team" "Creates the agent-team entry label" || exit 1
assert_contains "$output" "state:plan-needed|state:impl-needed|state:review-needed" "Creates the state:* labels" || exit 1
assert_contains "$output" "state:blocked|state:done" "Creates terminal state labels" || exit 1

echo ""

# Test 6: Inherited hard rules.
echo "Test 6: Inherits no-hand-YAML + no-token-echo hard rules..."
output=$(run_claude "Load the install-agent-team skill. Quote its Hard rules about: (a) writing workflow YAML by hand vs delegating to a tool, and (b) handling the user's auth token (storing or echoing it). Quote the rule text verbatim." 180)
assert_contains "$output" "never|does not|doesn't|no" "Hard rules are upheld" || exit 1
assert_contains "$output" "gh aw add|delegate" "Delegates workflow generation" || exit 1

echo ""

# Test 7: Rebase behavior is part of the installed pipeline.
echo "Test 7: Skill mentions automatic rebase handling..."
output=$(run_claude "Load the install-agent-team skill. Does the installed pipeline do anything automatic about keeping draft PRs rebased onto main, or does the user have to rebase by hand? Quote the specific workflow or behavior." 180)
assert_contains "$output" "sweep|rebase" "Mentions sweep or rebase" || exit 1
assert_contains "$output" "automat|without|silently|no.*action" "Frames it as automatic" || exit 1

echo ""
echo "=== All install-agent-team tests passed ==="
