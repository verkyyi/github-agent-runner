# agent-team auto-rebase — design

**Status**: draft
**Date**: 2026-04-23
**Scope**: v0.2 addition to the `agent-team` catalog entry

## Problem

Today the agent-team pipeline produces a draft PR, approves it, and stops. A human merges. If `main` advances between "approved" and "merged" and the changes touch overlapping files, the PR goes stale or conflicts, and the human has to rebase manually — a chore that should be the team's responsibility, not the stakeholder's.

The agent-team should behave like a real engineering team: keep its own PRs mergeable, and only surface to the human when there's something to *decide* (semantic conflict, ambiguous intent), not when there's something to *do* (mechanical rebase).

## Goals

- Any `agent-team:pr` draft PR that falls behind `main` is rebased automatically without human intervention.
- The human sees the PR only when it is ready to merge or genuinely blocked on judgment.
- Mechanical conflicts (non-overlapping hunks, trivially resolvable text conflicts with tests still green) are resolved silently.
- Semantic conflicts (overlapping logic, test regressions after resolve, or low-confidence resolution) escalate via the existing `state:blocked` channel.
- No new agent role; reuse the implementer with an added mode.

## Non-goals

- Auto-merging PRs. Humans still merge.
- Resolving conflicts on non-agent-team PRs.
- Webhook-driven rebase on every push to `main` (stampede risk; scheduled sweep is enough for v0.2).
- Rebasing draft PRs that aren't labeled `agent-team:pr`.

## Design

### Trigger model

Two triggers, covering every window in which `main` can advance:

| Window | Handled by |
|---|---|
| Before / during an implementer run (initial impl or kickback) | Implementer rebases onto `main` as the first step of its own run |
| PR waiting in review, or approved and waiting for human merge | Scheduled sweep dispatches implementer in rebase-only mode |

No label, no slash command. Rebase is a chore, not a decision — the human doesn't opt in.

### Implementer: new `mode` input

Add an input to `implementer-agent.md`:

```yaml
mode:
  description: Implementer behavior mode. `impl` (default) runs the normal spec→plan→PR flow. `rebase` rebases the existing PR onto main and stops.
  required: false
  type: string
  default: "impl"
```

**`mode: impl`** (unchanged from today, plus one addition): after checking out the branch in step 2, run `git fetch origin main && git rebase origin/main` before making any edits. On conflict, try Claude-led resolution; on failure, escalate (see "Escalation rules" below).

**`mode: rebase`**:
1. `pr_number` is required; fail fast if empty.
2. Check out the PR branch.
3. `git fetch origin main`
4. `git merge-base --is-ancestor origin/main HEAD` → if true, PR is already current; post nothing, exit cleanly.
5. Otherwise: `git rebase origin/main`. On conflict: Claude-led resolution (see below).
6. Run the project's test command once (reuse the same detection logic as normal impl).
7. If clean + tests pass: `git push --force-with-lease`, post one short comment on the PR: `🤖 agent-team / rebase: rebased onto main at <short-sha>, tests green.`
8. Do **not** read the spec or plan. Do **not** dispatch the reviewer. Rebase mode is terminal.

### Sweep workflow

New file: `catalog/agent-team/sweep-agent.md` (or a plain `.github/workflows/agent-team-sweep.yml` — see "Open questions"). Engine-less — it's just `gh` + bash, no LLM needed for enumeration. Trigger:

```yaml
on:
  schedule:
    - cron: "17 */6 * * *"   # every 6h, offset to avoid peak minutes
  workflow_dispatch:
```

Logic:

1. `gh pr list --label agent-team:pr --state open --draft --json number,headRefName,headRefOid,headRepository`
2. For each PR:
   - `git fetch origin main`
   - `git merge-base --is-ancestor origin/main <headRefOid>` → if true, skip (already current).
   - Otherwise: `gh workflow run implementer-agent.yml -f issue_number=<derived from PR body "Closes #N"> -f pr_number=<N> -f iteration=<same as last impl run for this PR> -f mode=rebase`
3. The existing `concurrency: agent-team-issue-<N>` group on the implementer serializes the sweep behind any live impl/review cycle — no extra locking needed.

### Escalation rules (shared between both modes)

After attempting `git rebase origin/main`:

- **Clean rebase, tests pass** → push, short success comment, stop.
- **Conflict, Claude resolves, tests pass** → push, short comment noting `resolved N conflict(s)`, stop.
- **Conflict Claude declines or resolves with low confidence** → `git rebase --abort`, add `state:blocked` to the issue, comment on the PR with the conflicted files + why it escalated, stop.
- **Rebase succeeds but tests fail** → `git rebase --abort`, add `state:blocked`, comment on the PR with the failing test output, stop.

"Low confidence" is defined by the resolution itself: if Claude can't resolve without substantially rewriting either side's logic (not just merging parallel edits), it's semantic and belongs to the human.

### Reviewer: no change

The reviewer stays read-only and role-pure. If the reviewer is mid-run when the sweep fires, the concurrency group makes the sweep wait. If `main` advances *during* a reviewer run (rare, minutes-long window), the next sweep catches it — acceptable latency.

## File changes

- `catalog/agent-team/implementer-agent.md` — add `mode` input; add rebase-at-start to `impl` mode; add `mode: rebase` branch and escalation rules.
- `catalog/agent-team/sweep-agent.md` *(new)* — sweep workflow as described. If a plain workflow YAML fits the catalog pattern better, use `.github/workflows/agent-team-sweep.yml` instead.
- `catalog/agent-team/README.md` — one section on how rebases are handled, escalation signals, and sweep cadence.
- `skills/install-agent-team/SKILL.md` — mention the new sweep workflow in the install list.
- `tests/test-install-agent-team.sh` and `tests/test-e2e-install-agent-team.sh` — extend to cover the sweep file being installed.

## Open questions

1. **Sweep cadence.** Every 6h is a starting point. If the user merges PRs frequently, shorter (every 2h) is fine; if rarely, daily. Adjust after observing real usage.
2. **Sweep as a gh-aw agent vs plain workflow.** The sweep doesn't need an LLM. Plain YAML is simpler and cheaper. But keeping all agent-team files under `catalog/agent-team/` as `.md` gh-aw sources is more consistent. Decide during implementation.
3. **Iteration input for sweep-dispatched rebase.** The sweep needs to pass *some* iteration value. Options: (a) always `"1"` since rebase isn't a "review attempt," (b) query the last impl run's iteration and reuse. (a) is simpler; iteration is used only by the guard in `impl` mode, which rebase-mode skips.
4. **Force-push safety.** `--force-with-lease` protects against overwriting concurrent pushes. Good enough for draft PRs the agent owns; revisit if humans start pushing to agent-team branches directly.
5. **Claude-led conflict resolution prompt.** Needs a concrete, bounded prompt template ("here are the conflict markers, here's each side's intent from the spec and from the last N commits on main; resolve only if the intents don't overlap"). Draft during implementation.

## Deferred to later

- Webhook trigger on push-to-main — revisit if 6h sweep latency turns out to matter in practice. Rejected for v0.2 due to stampede risk and speculative work on non-conflicting PRs.
- A dedicated `maintainer-agent` role — revisit if the implementer prompt gets unwieldy from carrying two modes. Rejected for v0.2 as premature role split.
- Reviewer-driven final-rebase-on-approve — revisit if the sweep turns out to be too slow for fresh approvals. Rejected for v0.2 because it breaks the reviewer's read-only role boundary and doesn't help the common "PR waiting for human merge" window.
