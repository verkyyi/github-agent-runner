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

while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v) VERBOSE=true; shift ;;
        --test|-t) SPECIFIC_TEST="$2"; shift 2 ;;
        --timeout) TIMEOUT="$2"; shift 2 ;;
        --help|-h)
            cat <<EOF
Usage: $0 [options]

Options:
  --verbose, -v        Show verbose output
  --test, -t NAME      Run only the specified test file
  --timeout SECONDS    Timeout per test (default: 300)
  --help, -h           Show this help

Tests:
  test-discover-workflows.sh  Verify discover skill's key behaviors
  test-install-workflow.sh    Verify install skill's auth + hard rules
EOF
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

tests=(
    "test-discover-workflows.sh"
    "test-install-workflow.sh"
)

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
