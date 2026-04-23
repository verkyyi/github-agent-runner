---
engine: claude
description: |
  Sweep agent for the agent-team pattern. Runs on a schedule and on demand,
  enumerates open draft PRs labeled `agent-team:pr`, and dispatches the
  implementer in `rebase` mode for any that have fallen behind `main`.
  No LLM reasoning on the diffs themselves — it's enumerate + ancestry
  check + dispatch.

on:
  schedule:
    - cron: "17 */6 * * *"
  workflow_dispatch: {}

concurrency:
  group: agent-team-sweep
  cancel-in-progress: false

timeout-minutes: 5

permissions:
  contents: read
  issues: read
  pull-requests: read

network:
  allowed:
  - defaults

checkout:
  fetch-depth: 0

tools:
  github:
    toolsets: [default]
    min-integrity: none
  bash: true

safe-outputs:
  threat-detection: false
  add-comment:
    max: 1
    target: "*"
  dispatch-workflow:
    workflows: [implementer-agent]
    max: 20
---

# Sweep Agent

You are the **sweep** for the agent-team pipeline. Your job: find open draft PRs labeled `agent-team:pr` that are behind `main`, and dispatch the implementer in `rebase` mode for each.

## Steps

1. List candidate PRs:
   ```
   gh pr list --label agent-team:pr --state open --draft \
     --json number,headRefName,headRefOid,body --limit 50
   ```

2. For each PR in the list:

   a. Derive `issue_number` by parsing `Closes #<N>` from the PR body. If no `Closes #N` marker exists, **skip that PR** (log the skip; do not dispatch).

   b. Check if the PR is behind `main`:
      ```
      git fetch origin main --quiet
      git merge-base --is-ancestor origin/main <headRefOid>
      ```
      - Exit code `0` → PR is current, skip it.
      - Exit code `1` → PR is behind, dispatch (next step).

   c. Dispatch the implementer in rebase mode via the `dispatch-workflow` safe-output:
      - workflow: `implementer-agent`
      - inputs:
        - `issue_number`: `<N>` (from step 2a)
        - `pr_number`: `<PR number>`
        - `iteration`: `"1"` (rebase mode bypasses the iteration guard; any value works)
        - `mode`: `"rebase"`

3. After the loop, if at least one dispatch was emitted, post one summary comment on the **repository's dashboard issue** (optional — only if a dashboard issue is configured; otherwise skip). Default: post no comment. The dispatched runs' logs are the audit trail.

## Rules

- Sweep never edits code, never rebases itself, never dispatches anything except the implementer in `rebase` mode.
- If `gh pr list` returns zero PRs, stop silently — no comment, no dispatch.
- If more than 20 PRs are behind (unusually large), dispatch the first 20 only. The next sweep run (6h later) picks up the rest. Prevents dispatch-workflow cap from erroring out.
- Sweep is idempotent — running it back-to-back produces zero extra dispatches (the second run sees all PRs current).
- Footer comment (only if one is posted): `🤖 agent-team / sweep`.
