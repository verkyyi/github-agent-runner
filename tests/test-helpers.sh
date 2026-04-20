#!/usr/bin/env bash
# Helper functions for Claude Code skill tests.
#
# Adapted from Jesse Vincent's superpowers plugin (MIT license):
#   https://github.com/obra/superpowers/blob/main/tests/claude-code/test-helpers.sh
#
# Single deviation: run_claude honors a PLUGIN_DIR env var, so tests can
# exercise the plugin in-place without requiring a prior marketplace install.

# Run Claude Code with a prompt and capture output.
# Usage: run_claude "prompt text" [timeout_seconds] [allowed_tools]
# Honors PLUGIN_DIR env var (passes --plugin-dir if set).
run_claude() {
    local prompt="$1"
    local timeout="${2:-60}"
    local allowed_tools="${3:-}"
    local output_file
    output_file=$(mktemp)

    local cmd="claude -p \"$prompt\""
    if [ -n "${PLUGIN_DIR:-}" ]; then
        cmd="$cmd --plugin-dir=\"$PLUGIN_DIR\""
    fi
    if [ -n "$allowed_tools" ]; then
        cmd="$cmd --allowed-tools=$allowed_tools"
    fi
    # Optional CLAUDE_MODEL override. CI does NOT set this — we intentionally
    # run the same default model real users get, so regressions visible to them
    # are visible in CI too. Local devs can export CLAUDE_MODEL=claude-haiku-*
    # for a faster iteration loop; assertions are tuned for Sonnet/Opus output,
    # so Haiku may fail on wording-specific checks.
    if [ -n "${CLAUDE_MODEL:-}" ]; then
        cmd="$cmd --model \"$CLAUDE_MODEL\""
    fi

    if timeout "$timeout" bash -c "$cmd" > "$output_file" 2>&1; then
        cat "$output_file"
        rm -f "$output_file"
        return 0
    else
        local exit_code=$?
        cat "$output_file" >&2
        rm -f "$output_file"
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

export -f run_claude assert_contains assert_not_contains assert_order
