#!/usr/bin/env bash
# Helper functions for Claude Code skill tests.
#
# Adapted from Jesse Vincent's superpowers plugin (MIT license):
#   https://github.com/obra/superpowers/blob/main/tests/claude-code/test-helpers.sh
#
# Two additions over upstream:
#   1. run_claude honors a PLUGIN_DIR env var (exercise plugin in-place).
#   2. Every claude -p call is captured as a JSONL session transcript, and
#      assert_skill_used greps the transcript for a Skill tool-use event.
#      This is the deterministic "did Claude actually load the skill" check
#      superpowers uses (commit obra/superpowers@24ca8cd9), which eliminates
#      the "Claude's prose doesn't happen to mention the skill name" flake.

# Path to the most recent run_claude invocation's JSONL transcript.
# Populated after every run_claude call. Consumed by assert_skill_used.
LAST_TRANSCRIPT=""

# Run Claude Code with a prompt. Returns the text response to stdout, and
# leaves the full stream-json transcript at $LAST_TRANSCRIPT for structural
# assertions (assert_skill_used).
#
# Usage: run_claude "prompt text" [timeout_seconds] [allowed_tools]
# Honors PLUGIN_DIR (passes --plugin-dir if set) and CLAUDE_MODEL (passes
# --model if set — CI doesn't set it; preserves real-user model parity).
run_claude() {
    local prompt="$1"
    local timeout="${2:-60}"
    local allowed_tools="${3:-}"
    local transcript
    transcript=$(mktemp -t claude-transcript-XXXXXX.jsonl)
    LAST_TRANSCRIPT="$transcript"

    # --output-format stream-json gives us a line-per-event NDJSON transcript,
    # which we keep for assert_skill_used. --verbose is required by the CLI
    # when pairing stream-json with --print.
    #
    # --permission-mode bypassPermissions + --allowed-tools=all: CI runs
    # claude -p from tests/ (or wherever run-tests.sh cd'd to), so by default
    # the sandbox denies reads to ../skills/*.md — Claude answers "I need
    # permission to read that file" and the assertion flakes. Superpowers'
    # test harness uses the same pair (docs/testing.md:236-244); adopting
    # the same defaults here keeps parity with their validated approach.
    # Caller can override allowed_tools to a narrower set if needed.
    local tools_flag="--allowed-tools=${allowed_tools:-all}"
    local cmd="claude -p \"$prompt\" --output-format stream-json --verbose --permission-mode bypassPermissions $tools_flag"
    [ -n "${PLUGIN_DIR:-}" ]      && cmd="$cmd --plugin-dir=\"$PLUGIN_DIR\""
    [ -n "${CLAUDE_MODEL:-}" ]    && cmd="$cmd --model \"$CLAUDE_MODEL\""

    if timeout "$timeout" bash -c "$cmd" > "$transcript" 2>&1; then
        # Extract the final assembled text response for grep-based assertions.
        # `result` event in stream-json carries the full final response; if jq
        # can't find one (cli variant / malformed), fall back to raw transcript.
        local text
        text=$(jq -rs 'map(select(.type=="result") | .result // .text // empty) | .[]' "$transcript" 2>/dev/null)
        if [ -n "$text" ]; then
            echo "$text"
        else
            cat "$transcript"
        fi
        return 0
    else
        local exit_code=$?
        cat "$transcript" >&2
        return $exit_code
    fi
}

# Check if output contains a pattern.
assert_contains() {
    local output="$1" pattern="$2" test_name="${3:-test}"
    if echo "$output" | grep -qE "$pattern"; then
        echo "  [PASS] $test_name"
        return 0
    else
        echo "  [FAIL] $test_name"
        echo "  Expected to find: $pattern"
        echo "  In output:"
        echo "$output" | sed 's/^/    /'
        return 1
    fi
}

# Check if output does NOT contain a pattern.
assert_not_contains() {
    local output="$1" pattern="$2" test_name="${3:-test}"
    if echo "$output" | grep -qE "$pattern"; then
        echo "  [FAIL] $test_name"
        echo "  Did not expect to find: $pattern"
        echo "  In output:"
        echo "$output" | sed 's/^/    /'
        return 1
    else
        echo "  [PASS] $test_name"
        return 0
    fi
}

# Check if pattern A appears before pattern B.
assert_order() {
    local output="$1" pattern_a="$2" pattern_b="$3" test_name="${4:-test}"
    local line_a line_b
    line_a=$(echo "$output" | grep -nE "$pattern_a" | head -1 | cut -d: -f1)
    line_b=$(echo "$output" | grep -nE "$pattern_b" | head -1 | cut -d: -f1)
    if [ -z "$line_a" ]; then
        echo "  [FAIL] $test_name: pattern A not found: $pattern_a"; return 1
    fi
    if [ -z "$line_b" ]; then
        echo "  [FAIL] $test_name: pattern B not found: $pattern_b"; return 1
    fi
    if [ "$line_a" -lt "$line_b" ]; then
        echo "  [PASS] $test_name (A at line $line_a, B at line $line_b)"
        return 0
    else
        echo "  [FAIL] $test_name"
        echo "  Expected '$pattern_a' before '$pattern_b'"
        echo "  But found A at line $line_a, B at line $line_b"
        return 1
    fi
}

# Deterministic "Claude invoked the Skill tool for this skill" assertion —
# structural, not prose-dependent. Greps the JSONL transcript from the most
# recent run_claude call for a tool_use event naming the Skill tool and the
# target skill. Much more robust than grepping Claude's natural-language
# response for the skill name, which varies run-to-run with model sampling.
#
# Pattern inspired by superpowers' skill-triggering/run-test.sh:60-68.
#
# Usage: assert_skill_used "skill-name" "test description"
assert_skill_used() {
    local skill_name="$1" test_name="${2:-skill loaded via Skill tool}"
    if [ -z "$LAST_TRANSCRIPT" ] || [ ! -f "$LAST_TRANSCRIPT" ]; then
        echo "  [FAIL] $test_name — no transcript captured (run_claude first)"
        return 1
    fi
    # Tool-use events in stream-json look like:
    #   {"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"discover-workflows",...}}...]}}
    # Grep handles the two attributes together rather than structurally parsing, which is
    # more forgiving of minor CLI version changes in event shape.
    if grep -q '"name":"Skill"' "$LAST_TRANSCRIPT" \
       && grep -qE "\"skill\"[[:space:]]*:[[:space:]]*\"[^\"]*${skill_name}\"" "$LAST_TRANSCRIPT"; then
        echo "  [PASS] $test_name"
        return 0
    else
        echo "  [FAIL] $test_name — Skill tool was not invoked for '$skill_name'"
        echo "  Transcript: $LAST_TRANSCRIPT"
        return 1
    fi
}

export -f run_claude assert_contains assert_not_contains assert_order assert_skill_used
