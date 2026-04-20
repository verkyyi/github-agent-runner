#!/usr/bin/env bash
# Test runner for github-agent-runner skills.
# Structure adapted from Jesse Vincent's superpowers plugin (MIT):
#   https://github.com/obra/superpowers/blob/main/tests/claude-code/run-skill-tests.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$SCRIPT_DIR"

# Load the plugin from this repo for the whole test run.
export PLUGIN_DIR="$REPO_ROOT"

echo "========================================"
echo " github-agent-runner Skills Test Suite"
echo "========================================"
echo ""
echo "Repository:     $REPO_ROOT"
echo "Plugin dir:     $PLUGIN_DIR"
echo "Test time:      $(date)"
echo "Claude version: $(claude --version 2>/dev/null || echo 'not found')"
echo ""

if ! command -v claude &> /dev/null; then
    echo "ERROR: Claude Code CLI not found"
    echo "Install Claude Code first: https://code.claude.com"
    exit 1
fi

VERBOSE=false
SPECIFIC_TEST=""
TIMEOUT=300
WITH_E2E=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v) VERBOSE=true; shift ;;
        --test|-t) SPECIFIC_TEST="$2"; shift 2 ;;
        --timeout) TIMEOUT="$2"; shift 2 ;;
        --with-e2e) WITH_E2E=true; shift ;;
        --help|-h)
            cat <<EOF
Usage: $0 [options]

Options:
  --verbose, -v        Show verbose output
  --test, -t NAME      Run only the specified test file
  --timeout SECONDS    Timeout per test (default: 300)
  --with-e2e           Also run tier-3 light E2E (test-e2e-daily.sh) against
                       the playground (~5-7 min, dispatches a real workflow).
                       The heavy agent-team E2E (test-e2e.sh, ~20-35 min) is
                       never in the runner — invoke it directly.
  --help, -h           Show this help

Tests:
  test-invariants.sh          Tier-2: fast grep/file invariants tied to past bugs
  test-discover-workflows.sh  Tier-1: skill-description assertions
  test-install-workflow.sh    Tier-1: skill-description assertions (auth + hard rules)
  test-install-agent-team.sh  Tier-1: skill-description assertions (unified installer)
  test-e2e-daily.sh           Tier-3 light: real workflow run on playground (opt-in)
EOF
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Invariants first — tier-2, runs in <1s, no Claude invocation.
# Tier-1 skill tests follow (slow + costs tokens).
# Tier-3 daily E2E added only with --with-e2e.
tests=(
    "test-invariants.sh"
    "test-discover-workflows.sh"
    "test-install-workflow.sh"
    "test-install-agent-team.sh"
)
if [ "$WITH_E2E" = true ]; then
    tests+=("test-e2e-daily.sh")
    # E2E internal polling budget is 7 min; bump wrapper timeout so run-tests
    # doesn't kill the test before its own budget runs out. Only bumps if the
    # user didn't explicitly override.
    [ "$TIMEOUT" = 300 ] && TIMEOUT=600
fi

if [ -n "$SPECIFIC_TEST" ]; then
    tests=("$SPECIFIC_TEST")
fi

passed=0
failed=0
skipped=0

for test in "${tests[@]}"; do
    echo "----------------------------------------"
    echo "Running: $test"
    echo "----------------------------------------"

    test_path="$SCRIPT_DIR/$test"

    if [ ! -f "$test_path" ]; then
        echo "  [SKIP] Test file not found: $test"
        skipped=$((skipped + 1))
        continue
    fi

    [ -x "$test_path" ] || chmod +x "$test_path"

    start_time=$(date +%s)

    if [ "$VERBOSE" = true ]; then
        if timeout "$TIMEOUT" bash "$test_path"; then
            duration=$(( $(date +%s) - start_time ))
            echo "  [PASS] $test (${duration}s)"
            passed=$((passed + 1))
        else
            exit_code=$?
            duration=$(( $(date +%s) - start_time ))
            if [ $exit_code -eq 124 ]; then
                echo "  [FAIL] $test (timeout after ${TIMEOUT}s)"
            else
                echo "  [FAIL] $test (${duration}s)"
            fi
            failed=$((failed + 1))
        fi
    else
        if output=$(timeout "$TIMEOUT" bash "$test_path" 2>&1); then
            duration=$(( $(date +%s) - start_time ))
            echo "  [PASS] (${duration}s)"
            passed=$((passed + 1))
        else
            exit_code=$?
            duration=$(( $(date +%s) - start_time ))
            if [ $exit_code -eq 124 ]; then
                echo "  [FAIL] (timeout after ${TIMEOUT}s)"
            else
                echo "  [FAIL] (${duration}s)"
            fi
            echo ""
            echo "  Output:"
            echo "$output" | sed 's/^/    /'
            failed=$((failed + 1))
        fi
    fi

    echo ""
done

echo "========================================"
echo " Test Results Summary"
echo "========================================"
echo ""
echo "  Passed:  $passed"
echo "  Failed:  $failed"
echo "  Skipped: $skipped"
echo ""

if [ $failed -gt 0 ]; then
    echo "STATUS: FAILED"
    exit 1
else
    echo "STATUS: PASSED"
    exit 0
fi
