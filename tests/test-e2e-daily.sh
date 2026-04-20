#!/usr/bin/env bash
# Tier-3 (light): verify daily-repo-status end-to-end on the playground.
#
# Dispatches the workflow, waits for it to complete, asserts a report
# issue was created with the expected title prefix and labels.
# ~3-5 min. Opt-in via run-tests.sh --with-e2e or direct invocation.
#
# Side effect: creates one [repo-status] issue per run. The workflow's
# close-older-issues: true means the prior one is closed, so no
# accumulation — just churn.
set -euo pipefail

PLAYGROUND="${PLAYGROUND:-verkyyi/agent-team-playground}"
WORKFLOW_NAME="Daily Repo Status"
POLL_INTERVAL=20
POLL_BUDGET=420   # 7 min ceiling

command -v gh >/dev/null || { echo "gh CLI required"; exit 1; }
command -v jq >/dev/null || { echo "jq required"; exit 1; }

fails=0
pass() { echo "  [PASS] $1"; }
fail() { echo "  [FAIL] $1"; fails=$((fails+1)); }

echo "=== Tier-3 E2E: daily-repo-status on $PLAYGROUND ==="

# ISO-8601 timestamp just before dispatch — used to filter for the run we triggered
BEFORE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
sleep 1   # ensure strictly-after comparison works even on fast clocks

echo ""
echo "-- Dispatching workflow --"
gh workflow run "$WORKFLOW_NAME" --repo "$PLAYGROUND" >/dev/null
echo "  Dispatched at $BEFORE"

echo ""
echo "-- Polling for completion (budget ${POLL_BUDGET}s) --"
START_TS=$(date +%s)
RUN_ID=""
CONCLUSION=""
while :; do
  ELAPSED=$(( $(date +%s) - START_TS ))
  [ $ELAPSED -ge $POLL_BUDGET ] && { fail "Polling timeout (${POLL_BUDGET}s) — workflow never completed"; break; }

  RUN_ID=$(gh run list --repo "$PLAYGROUND" --workflow "$WORKFLOW_NAME" --limit 5 \
    --json databaseId,status,conclusion,createdAt \
    --jq "[.[] | select(.createdAt >= \"$BEFORE\")] | .[0].databaseId // empty")

  if [ -n "$RUN_ID" ]; then
    STATUS=$(gh run view "$RUN_ID" --repo "$PLAYGROUND" --json status,conclusion \
      --jq '"\(.status)|\(.conclusion // "")"')
    printf "  [%4ds] run %s: %s\n" "$ELAPSED" "$RUN_ID" "$STATUS"
    if [[ "$STATUS" == "completed|"* ]]; then
      CONCLUSION="${STATUS#completed|}"
      break
    fi
  else
    printf "  [%4ds] no run found yet (createdAt > %s)\n" "$ELAPSED" "$BEFORE"
  fi
  sleep "$POLL_INTERVAL"
done

WALL=$(( $(date +%s) - START_TS ))
echo ""
echo "-- Assertions --"
if [ -z "$CONCLUSION" ]; then
  fail "No terminal conclusion captured (polling gave up)"
elif [ "$CONCLUSION" = "success" ]; then
  pass "Run $RUN_ID completed with conclusion=success in ${WALL}s"
else
  fail "Run $RUN_ID ended with conclusion=$CONCLUSION (expected success)"
fi

# Issue assertions (only if run succeeded)
if [ "$CONCLUSION" = "success" ]; then
  issue=$(gh issue list --repo "$PLAYGROUND" --label daily-status --limit 5 \
    --json number,title,createdAt,labels \
    --jq "[.[] | select(.createdAt >= \"$BEFORE\")] | .[0] // empty")
  if [ -z "$issue" ]; then
    fail "No issue created with label daily-status newer than $BEFORE"
  else
    num=$(echo "$issue" | jq -r '.number')
    title=$(echo "$issue" | jq -r '.title')
    pass "Issue #$num created: $title"

    echo "$issue" | jq -e '.title | startswith("[repo-status]")' >/dev/null \
      && pass "Title has [repo-status] prefix" \
      || fail "Title missing [repo-status] prefix"

    echo "$issue" | jq -e '[.labels[].name] | contains(["report","daily-status"])' >/dev/null \
      && pass "Issue has both expected labels (report, daily-status)" \
      || fail "Issue missing expected labels"
  fi
fi

echo ""
if [ "$fails" -gt 0 ]; then
  echo "=== FAILED ($fails assertion(s)) ==="
  exit 1
else
  echo "=== All daily-repo-status E2E assertions passed ==="
fi
