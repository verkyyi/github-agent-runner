#!/usr/bin/env bash
# Tier-3 end-to-end verification: real agent-team pipeline run on the playground.
#
# Opens a unique canned issue, labels agent-team, polls until terminal state
# or budget exhausted, asserts outcome, records per-stage timings, and flags
# yellow-band regressions vs. the last recorded run.
#
# Run manually before releases or on a weekly cron. Costs ~20-30 min + Claude
# tokens (free on OAuth subscription).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HISTORY_FILE="$SCRIPT_DIR/e2e-history.jsonl"
PLAYGROUND="${PLAYGROUND:-verkyyi/agent-team-playground}"
POLL_INTERVAL=30                # seconds between polls
POLL_BUDGET=2100                # 35 min polling ceiling
YELLOW_MULTIPLIER=150           # per-mille: 150% of baseline = yellow

# Exit codes: 0 green, 1 red (hard fail), 2 yellow (regression warning)
EXIT_CODE=0
WARN_LINES=()
FAIL_LINES=()

pass() { echo "  [PASS] $1"; }
fail() { echo "  [FAIL] $1"; FAIL_LINES+=("$1"); EXIT_CODE=1; }
warn() { echo "  [WARN] $1"; WARN_LINES+=("$1"); [ $EXIT_CODE -eq 0 ] && EXIT_CODE=2; }

command -v gh >/dev/null || { echo "gh CLI required"; exit 1; }
command -v jq >/dev/null || { echo "jq required"; exit 1; }

STAMP=$(date -u +%Y%m%d%H%M%S)
FUNC_NAME="greet_$STAMP"
echo "=== Tier-3 E2E on $PLAYGROUND (stamp=$STAMP) ==="
echo ""

# --- 1. Dispatch: open the canned issue ---
echo "-- Dispatching canned task --"
ISSUE_URL=$(gh issue create --repo "$PLAYGROUND" \
  --title "E2E: add ${FUNC_NAME}() function" \
  --body "Add a \`${FUNC_NAME}(name: str) -> str\` function to \`src/greet.py\` that returns \`\"Hello from e2e, <name>!\"\`. Add a regression test in \`tests/test_greet.py\` that asserts \`${FUNC_NAME}(\"world\") == \"Hello from e2e, world!\"\`." 2>&1 | tail -1)
ISSUE_NUM="${ISSUE_URL##*/}"
echo "  Opened issue #$ISSUE_NUM: $ISSUE_URL"
DISPATCH_TS=$(date +%s)
gh issue edit "$ISSUE_NUM" --repo "$PLAYGROUND" --add-label agent-team >/dev/null
echo "  Labeled agent-team at $(date -u +%H:%M:%SZ)"
echo ""

# --- 2. Poll until terminal state or budget exhausted ---
echo "-- Polling pipeline (budget ${POLL_BUDGET}s, interval ${POLL_INTERVAL}s) --"
TERMINAL=""
START_TS=$(date +%s)
while :; do
  ELAPSED=$(( $(date +%s) - START_TS ))
  [ $ELAPSED -ge $POLL_BUDGET ] && { TERMINAL="timeout"; break; }
  labels=$(gh issue view "$ISSUE_NUM" --repo "$PLAYGROUND" --json labels --jq '[.labels[].name] | join(",")' 2>/dev/null || echo "")
  if [[ "$labels" == *"state:done"* ]]; then TERMINAL="done"; break; fi
  if [[ "$labels" == *"state:blocked"* ]]; then TERMINAL="blocked"; break; fi
  printf "  [%4ds] labels: %s\n" "$ELAPSED" "${labels:-<none>}"
  sleep "$POLL_INTERVAL"
done
WALL=$(( $(date +%s) - START_TS ))
echo "  Terminal=$TERMINAL after ${WALL}s"
echo ""

# --- 3. Hard-fail checks ---
echo "-- Terminal state assertions --"
case "$TERMINAL" in
  done)    pass "Issue reached state:done" ;;
  blocked) fail "Issue reached state:blocked — pipeline halted for human intervention" ;;
  timeout) fail "Polling budget exhausted (${POLL_BUDGET}s) without terminal state — pipeline stalled" ;;
esac

# --- 4. Output-correctness assertions (only meaningful if state:done) ---
PR_NUM=""
if [ "$TERMINAL" = "done" ]; then
  PR_NUM=$(gh pr list --repo "$PLAYGROUND" --search "E2E: add ${FUNC_NAME} in:title" --json number --jq '.[0].number // empty')
  if [ -z "$PR_NUM" ]; then
    fail "No PR found for issue #$ISSUE_NUM"
  else
    pass "PR #$PR_NUM opened"
    pr_body=$(gh pr view "$PR_NUM" --repo "$PLAYGROUND" --json body --jq '.body')
    echo "$pr_body" | grep -qF "Closes #$ISSUE_NUM" \
      && pass "PR body contains 'Closes #$ISSUE_NUM'" \
      || fail "PR body missing 'Closes #$ISSUE_NUM' — merge won't close the issue"
    echo "$pr_body" | grep -qF "## Test status" \
      && pass "PR body has ## Test status section" \
      || fail "PR body missing ## Test status"

    review=$(gh pr view "$PR_NUM" --repo "$PLAYGROUND" --json comments --jq '.comments[] | select(.body | contains("<!-- agent-team:review")) | .body' | tail -1)
    if [ -n "$review" ]; then
      echo "$review" | grep -qE 'verdict=(approve|approve-with-nits)' \
        && pass "Review comment has verdict=approve" \
        || { echo "$review" | grep -qE 'verdict=kickback' \
             && warn "Review kicked back (was approve in baseline)" \
             || fail "Review comment missing verdict=approve/kickback marker"; }
    else
      fail "No review comment found on PR #$PR_NUM"
    fi
  fi

  summary=$(gh issue view "$ISSUE_NUM" --repo "$PLAYGROUND" --json comments --jq '.comments[] | select(.body | contains("<!-- agent-team:summary")) | .body' | tail -1)
  [ -n "$summary" ] && pass "Pipeline-summary comment posted on issue" || fail "No pipeline-summary comment on issue"
fi
echo ""

# --- 5. Collect per-stage timings ---
echo "-- Per-stage timings --"
declare -A STAGE_SEC
for stage in "Spec Agent" "Planner Agent" "Implementer Agent" "Reviewer Agent"; do
  duration=$(gh run list --repo "$PLAYGROUND" --workflow="$stage" --limit 3 \
    --json databaseId,createdAt,updatedAt,conclusion \
    --jq "[.[] | select(.conclusion == \"success\")] | .[0] | ((.updatedAt | fromdateiso8601) - (.createdAt | fromdateiso8601))" 2>/dev/null || echo 0)
  STAGE_SEC["$stage"]=${duration:-0}
  printf "  %-20s %4ds\n" "$stage:" "${duration:-0}"
done
printf "  %-20s %4ds\n" "total wall-clock:" "$WALL"
echo ""

# --- 6. Compare to last run (yellow-band) ---
echo "-- Baseline comparison (last run) --"
if [ -f "$HISTORY_FILE" ] && [ -s "$HISTORY_FILE" ]; then
  last=$(tail -1 "$HISTORY_FILE")
  for stage in "Spec Agent" "Planner Agent" "Implementer Agent" "Reviewer Agent"; do
    curr=${STAGE_SEC[$stage]}
    base=$(echo "$last" | jq -r ".stages[\"$stage\"] // 0")
    if [ "$base" -gt 0 ] && [ "$curr" -gt 0 ]; then
      ratio=$(( curr * 100 / base ))
      if [ "$ratio" -gt "$YELLOW_MULTIPLIER" ]; then
        warn "$stage: ${curr}s vs baseline ${base}s (${ratio}% — >150% threshold)"
      else
        pass "$stage: ${curr}s vs baseline ${base}s (${ratio}%)"
      fi
    fi
  done
  base_wall=$(echo "$last" | jq -r '.wall_seconds // 0')
  if [ "$base_wall" -gt 0 ]; then
    ratio=$(( WALL * 100 / base_wall ))
    [ "$ratio" -gt "$YELLOW_MULTIPLIER" ] \
      && warn "Total: ${WALL}s vs baseline ${base_wall}s (${ratio}%)" \
      || pass "Total: ${WALL}s vs baseline ${base_wall}s (${ratio}%)"
  fi
else
  echo "  (no prior run — this will be the baseline)"
fi
echo ""

# --- 7. Record this run to history ---
entry=$(jq -cn --arg stamp "$STAMP" --argjson issue "$ISSUE_NUM" \
  --argjson pr "${PR_NUM:-0}" --arg terminal "$TERMINAL" \
  --argjson wall "$WALL" \
  --argjson spec  "${STAGE_SEC["Spec Agent"]}" \
  --argjson plan  "${STAGE_SEC["Planner Agent"]}" \
  --argjson impl  "${STAGE_SEC["Implementer Agent"]}" \
  --argjson review "${STAGE_SEC["Reviewer Agent"]}" \
  '{stamp: $stamp, issue: $issue, pr: $pr, terminal: $terminal, wall_seconds: $wall, stages: {"Spec Agent": $spec, "Planner Agent": $plan, "Implementer Agent": $impl, "Reviewer Agent": $review}}')
echo "$entry" >> "$HISTORY_FILE"
echo "Recorded to $HISTORY_FILE"

# --- 8. Summary ---
echo ""
case $EXIT_CODE in
  0) echo "=== GREEN: all assertions passed; no regression vs. baseline ===" ;;
  1) echo "=== RED: $((${#FAIL_LINES[@]})) hard failure(s) ==="; printf '  - %s\n' "${FAIL_LINES[@]}" ;;
  2) echo "=== YELLOW: $((${#WARN_LINES[@]})) warning(s), no hard failures ==="; printf '  - %s\n' "${WARN_LINES[@]}" ;;
esac
exit "$EXIT_CODE"
