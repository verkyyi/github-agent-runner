# agent-team Auto-Rebase Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep agent-team draft PRs rebased onto `main` without human intervention, escalating only when conflicts are semantic.

**Architecture:** The implementer gains a `mode` input. In default `impl` mode it rebases the branch onto `main` at the start of every run. A new `rebase` mode skips spec/plan and only rebases-and-pushes. A new `sweep-agent` workflow runs on a 6-hour cron (and on-demand), enumerates open `agent-team:pr` draft PRs that are behind `main`, and dispatches the implementer in `rebase` mode for each. Mechanical conflicts resolve silently; semantic conflicts escalate via `state:blocked`.

**Tech Stack:** gh-aw (`.md` → `.lock.yml` compilation), GitHub Actions `workflow_dispatch` + `schedule`, `gh` CLI, `git rebase`, bash.

**Spec:** [`docs/superpowers/specs/2026-04-23-agent-team-auto-rebase-design.md`](../specs/2026-04-23-agent-team-auto-rebase-design.md)

---

## Working mode conventions

These files are gh-aw workflow prompts (markdown) and GitHub Actions config (YAML) — not runnable code. "Test" in this plan means:

1. **Syntactic validation:** `gh aw compile <path>` produces a `.lock.yml` without errors.
2. **Semantic validation:** `gh aw validate` succeeds against the compiled output.
3. **Shape check:** grep/inspect the generated lock file to confirm frontmatter fields (triggers, permissions, safe-outputs) compiled as intended.
4. **Smoke test (final task):** run the sweep against the playground repo manually via `gh workflow run` and watch the dispatched implementer run.

Unit-testing the prompt body itself is not possible; correctness is verified by the smoke test.

---

## Task 1: Add `mode` input to implementer-agent and rebase-at-start to `impl` mode

**Files:**
- Modify: `catalog/agent-team/implementer-agent.md` (frontmatter + "Normal path" section)

Purpose of this task: give the implementer a new input it can be invoked with, and make the default path (`impl` mode) rebase onto `main` before it starts editing. The new `rebase` mode branch is added in Task 2.

- [ ] **Step 1: Read the current file to locate the exact edit points**

Run: `sed -n '1,50p' catalog/agent-team/implementer-agent.md` to see the frontmatter; `sed -n '100,130p' catalog/agent-team/implementer-agent.md` to see the "Normal path" steps 1-3.

Confirm:
- The `workflow_dispatch.inputs` block is at lines 10-26 (after the opening `---`).
- The "Normal path" section begins at line 108.
- Step 2 (branch selection) is at lines 117-119.

- [ ] **Step 2: Add the `mode` input to frontmatter**

In `catalog/agent-team/implementer-agent.md`, inside `on.workflow_dispatch.inputs` (after the `pr_number` input, before the closing of the inputs block, i.e. after line 26), insert:

```yaml
      mode:
        description: >-
          Implementer behavior mode. `impl` (default) runs the normal spec→plan→PR flow and rebases onto main at the start.
          `rebase` skips spec/plan and only rebases the existing PR onto main, runs tests, and pushes.
        required: false
        type: string
        default: "impl"
```

(Indentation: two spaces deeper than `pr_number`, matching YAML block structure.)

- [ ] **Step 3: Add a top-level mode dispatch at the start of the prompt body**

Immediately after the opening line `You are the **implementer**...` (currently line 93), insert a new section **before** "## Iteration guard":

```markdown
## Mode dispatch

Check `inputs.mode`:
- `impl` (default) or empty → follow the **Normal path** below.
- `rebase` → follow the **Rebase-only mode** section instead; skip the Normal path entirely.

Any other value → add `state:blocked` to `inputs.issue_number`, post `🛑 agent-team: unknown implementer mode "<value>".` on the issue, stop.
```

(The "Rebase-only mode" section itself is added in Task 2. It's fine for this task to reference a section that doesn't exist yet; Task 2 adds it before compilation of the final result.)

- [ ] **Step 4: Add the rebase-at-start step inside the Normal path**

In the "Normal path" section, between current step 2 (branch pick) and current step 3 (implement), insert a new step numbered 2.5 (and renumber remaining steps 3→4, 4→5, etc., **or** insert it as step 3 and renumber everything after — whichever minimizes diff). Use this exact content:

```markdown
3. **Rebase the branch onto `main` before editing**:
   - `git fetch origin main`
   - If this is a fresh branch (inputs.pr_number empty) and you just branched from `main`, this is a no-op — skip.
   - Otherwise: `git rebase origin/main`.
     - **Clean rebase** → proceed.
     - **Rebase produces conflicts** → attempt resolution (see "Conflict resolution" below). If resolved and the project's tests still pass after resolution, proceed. If not, `git rebase --abort`, add `state:blocked` to the issue, comment on the PR (or on the issue if no PR yet) with the conflicting file list and a one-sentence reason, and stop. Do not dispatch the reviewer.
```

Renumber subsequent steps accordingly (what was step 3 becomes step 4, etc., through what was step 7 becoming step 8).

- [ ] **Step 5: Add a "Conflict resolution" subsection under "## Rules"**

At the end of the file, before the final `## Rules` list items (or as a new `## Conflict resolution` section between "## Rules" and the end of file), append:

```markdown
## Conflict resolution

When `git rebase origin/main` produces conflicts (either in `impl` mode's rebase-at-start step or in `rebase` mode):

1. Read each conflicted file. Look at the conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`).
2. **Resolve only if the two sides edit disjoint concerns** — e.g. one side renames a variable, the other side adds an unrelated function nearby. Keep both changes.
3. **Do not resolve** if either side changed the same logic (e.g. both sides modified the same function body in ways that affect behavior). That's a semantic conflict requiring human judgment.
4. After resolving, `git add <files>` and `git rebase --continue`.
5. After all conflicts are resolved (or none existed), run the project's test command **once**. If tests pass → push. If tests fail → `git rebase --abort` (or `git reset --hard ORIG_HEAD` if already past rebase), escalate via `state:blocked` with the failing test output.

Escalation format (when blocking due to unresolvable conflict or test failure after resolve):
- Add `state:blocked` to `inputs.issue_number`.
- Comment on the PR (or issue, if no PR yet) — body:
  ```
  🛑 agent-team / <impl-or-rebase>: rebase onto main blocked.

  **Reason**: <semantic conflict in <files> | tests failed after mechanical resolve>
  **Conflicting files**: <list>
  **What I tried**: <one sentence>
  **Next**: human resolves locally, then removes state:blocked to re-enter the pipeline.
  ```
- Stop. Do not dispatch downstream.
```

- [ ] **Step 6: Compile and validate**

Run:
```bash
cd /tmp && mkdir -p aw-compile-check && cd aw-compile-check
cp /home/dev/projects/github-agent-runner/catalog/agent-team/implementer-agent.md .
gh aw compile implementer-agent.md
```

Expected: an `implementer-agent.lock.yml` is produced, no errors.

Run:
```bash
grep -c '"mode"' implementer-agent.lock.yml
```

Expected: at least 1 (the new input shows up in the compiled `workflow_dispatch.inputs`).

Then `gh aw validate` on the lock file. Expected: no errors.

- [ ] **Step 7: Commit**

```bash
cd /home/dev/projects/github-agent-runner
git add catalog/agent-team/implementer-agent.md
git commit -m "agent-team: add mode input + rebase-at-start to implementer"
```

---

## Task 2: Add rebase-only mode to implementer-agent

**Files:**
- Modify: `catalog/agent-team/implementer-agent.md` (add "Rebase-only mode" section)

- [ ] **Step 1: Add the "Rebase-only mode" section**

In `catalog/agent-team/implementer-agent.md`, insert a new `## Rebase-only mode` section **between** the "Mode dispatch" section (added in Task 1) and the "## Iteration guard" section. Content:

```markdown
## Rebase-only mode

Triggered when `inputs.mode == "rebase"`. Purpose: keep an existing PR current with `main` without doing any implementation work. Called by the sweep workflow (and can be invoked manually via `gh workflow run`).

**Preconditions** (fail fast):
- `inputs.pr_number` must be set. If empty, add `state:blocked` to `inputs.issue_number`, comment `🛑 agent-team / rebase: mode=rebase requires pr_number.`, stop.

**Steps**:

1. Check out the PR branch:
   - `gh pr view <inputs.pr_number> --json headRefName,state,isDraft` — confirm the PR is open and draft. If closed or merged, stop silently (nothing to do).
   - `git fetch origin <branch> && git checkout <branch>`

2. Fetch `main`:
   - `git fetch origin main`
   - If `main` is already an ancestor of `HEAD` (`git merge-base --is-ancestor origin/main HEAD`), the PR is current. Stop silently — post no comment.

3. Rebase:
   - `git rebase origin/main`.
   - On conflicts → follow "Conflict resolution" (same rules as `impl` mode). Clean rebase or successful mechanical resolve → continue to step 4.

4. Run the project's test command once. Use the same test-command detection as `impl` mode (read `package.json` / `Makefile` / CI files). If no test command is detectable, skip and note that in step 5.
   - Tests pass → continue to step 5.
   - Tests fail → `git rebase --abort` (or reset if already past), escalate per "Conflict resolution" escalation format, stop.

5. Push:
   - `git push --force-with-lease origin HEAD:<branch>`
   - Post one comment on the PR — body:
     ```
     🤖 agent-team / rebase: rebased onto main at <short-sha>.

     - Rebase: <clean | resolved N mechanical conflict(s) in <files>>
     - Tests: <✅ passed | ⚠ skipped — no test command detected>
     ```

6. Stop. **Do not dispatch the reviewer.** Rebase mode is terminal.

**Rules for this mode**:
- Never read the spec or plan. This mode addresses no requirements changes.
- Never dispatch downstream. The PR stays in whatever state it was in (`state:review-needed`, `state:done`, etc.) — a rebase doesn't reset review.
- Never touch files beyond what `git rebase` modifies. No spec-driven edits.
- Force-push uses `--force-with-lease` so a concurrent human push isn't clobbered.
```

- [ ] **Step 2: Update `safe-outputs` if needed**

The existing `safe-outputs` block already allows `push-to-pull-request-branch`, `add-comment`, `add-labels`, `dispatch-workflow`. Rebase mode uses:
- `push-to-pull-request-branch` — already present, `max: 1` is enough.
- `add-comment` — already present, `max: 2`, enough for the success comment + any escalation comment.
- `add-labels` with `state:blocked` — already present.

Confirm by reading lines 62-88 of the current file. No changes needed if those are present. If the current `max` on any is tight, bump `add-comment.max` to `3` (rebase comment + escalation comment + buffer).

- [ ] **Step 3: Compile and validate**

```bash
cd /tmp/aw-compile-check
cp /home/dev/projects/github-agent-runner/catalog/agent-team/implementer-agent.md .
gh aw compile implementer-agent.md
gh aw validate implementer-agent.lock.yml
```

Expected: no errors. Grep the output:
```bash
grep -c "Rebase-only mode" implementer-agent.lock.yml
```
Expected: at least 1 (the prompt body is embedded in the lock file).

- [ ] **Step 4: Commit**

```bash
cd /home/dev/projects/github-agent-runner
git add catalog/agent-team/implementer-agent.md
git commit -m "agent-team: add rebase-only mode to implementer"
```

---

## Task 3: Create `sweep-agent.md`

**Files:**
- Create: `catalog/agent-team/sweep-agent.md`

- [ ] **Step 1: Create the file with the full contents below**

Exact contents for `catalog/agent-team/sweep-agent.md`:

```markdown
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
```

- [ ] **Step 2: Compile and validate**

```bash
cd /tmp/aw-compile-check
cp /home/dev/projects/github-agent-runner/catalog/agent-team/sweep-agent.md .
gh aw compile sweep-agent.md
gh aw validate sweep-agent.lock.yml
```

Expected: no errors.

- [ ] **Step 3: Verify trigger shape in the compiled lock file**

```bash
grep -A3 "^on:" sweep-agent.lock.yml | head -10
```

Expected output includes `schedule:` with the `cron: "17 */6 * * *"` and `workflow_dispatch:`.

- [ ] **Step 4: Commit**

```bash
cd /home/dev/projects/github-agent-runner
git add catalog/agent-team/sweep-agent.md
git commit -m "agent-team: add sweep-agent for periodic rebase dispatch"
```

---

## Task 4: Update install-agent-team skill

**Files:**
- Modify: `skills/install-agent-team/SKILL.md`

- [ ] **Step 1: Update the description frontmatter**

In `skills/install-agent-team/SKILL.md`, change the frontmatter `description` from:

```
Install the full four-role agent-team pattern (spec → plan → impl → review) into the current repo as one unified setup.
```

to:

```
Install the full agent-team pattern (spec → plan → impl → review + periodic sweep) into the current repo as one unified setup.
```

- [ ] **Step 2: Update the opening paragraph**

Change the first paragraph under `# install-agent-team` from "Install all four agent-team workflows..." to "Install all five agent-team workflows..." (or similar minimal edit that keeps the rest).

Actual edit — replace line 8:
```
Install all four agent-team workflows into the current repo in one pass: fetch, wire auth once, apply the OAuth tweak to every lockfile, create the labels, validate, commit.
```
with:
```
Install all five agent-team workflows (spec, planner, implementer, reviewer, and the sweep that keeps PRs rebased) into the current repo in one pass: fetch, wire auth once, apply the OAuth tweak to every lockfile, create the labels, validate, commit.
```

- [ ] **Step 3: Update step 1 ("Explain what's about to happen")**

Change "four workflows will be added" to "five workflows will be added (four pipeline roles + a sweep that runs every 6 hours to keep PRs rebased)".

- [ ] **Step 4: Update step 4 (the install sequence)**

After the existing `gh aw add ... reviewer-agent.md@main` line, add:

```bash
gh aw add verkyyi/github-agent-runner/catalog/agent-team/sweep-agent.md@main
```

Update the error-handling sentence that follows — change "The four are a unit" to "The five are a unit" (or equivalent).

- [ ] **Step 5: Update step 5 (OAuth tweak)**

Change "For each of the four `.lock.yml` files" to "For each of the five `.lock.yml` files".

- [ ] **Step 6: Update step 8 (summary)**

Change "Four files added" to "Five files added" and list each `.md` + `.lock.yml` pair (the existing text says "name each" — the engineer filling this in should add `sweep-agent` to whatever list format is used).

- [ ] **Step 7: Update "Hard rules" section**

Change "If any of the four `gh aw add` calls fails" to "If any of the five `gh aw add` calls fails".

- [ ] **Step 8: Commit**

```bash
cd /home/dev/projects/github-agent-runner
git add skills/install-agent-team/SKILL.md
git commit -m "install-agent-team: include sweep-agent in install flow"
```

---

## Task 5: Update the catalog README

**Files:**
- Modify: `catalog/agent-team/README.md`

- [ ] **Step 1: Update the top paragraph**

Change the first paragraph from "A four-workflow pattern..." to "A five-workflow pattern for a spec → plan → implement → review pipeline, plus a sweep that keeps draft PRs rebased. Each role is a separate gh-aw workflow...". Leave the rest of the sentence intact.

- [ ] **Step 2: Add a row to the Files table**

Find the `## Files` section (around line 64). Add a fifth row:

```markdown
| `sweep-agent.md` | `schedule` (every 6h) + `workflow_dispatch` | `implementer-agent` in `rebase` mode, per stale PR |
```

- [ ] **Step 3: Add a "Rebase handling" subsection**

Between `## The handoff model` (ends ~line 49) and `## The comment contract` (starts ~line 51), insert a new subsection:

```markdown
## Rebase handling

Draft PRs drift out of date as `main` advances. Two mechanisms keep them current, no human action required:

1. **Rebase at start of every implementer run** — `impl` mode begins with `git fetch origin main && git rebase origin/main`. Catches drift within the pipeline (initial impl, kickback cycles).
2. **Scheduled sweep** — `sweep-agent.md` runs every 6 hours (and on-demand via `workflow_dispatch`). It lists open `agent-team:pr` draft PRs, checks each for `main`-ancestry, and dispatches the implementer in `rebase` mode for any that are behind. Catches the common "PR sat waiting for human merge, main moved" case.

Both paths share the same escalation rule: mechanical conflicts resolve silently; semantic conflicts (overlapping logic, tests fail after resolve) escalate via `state:blocked` with a targeted comment. The human sees the PR only when it's ready to merge or when their judgment is needed.
```

- [ ] **Step 4: Update the "Install" manual block**

Under the `<details>` "Manual install (advanced)" block, add a fifth `gh aw add` line:

```bash
gh aw add verkyyi/github-agent-runner/catalog/agent-team/sweep-agent.md@main
```

- [ ] **Step 5: Update the flow diagram (optional but recommended)**

The ASCII diagram under `## The handoff model` currently ends at the reviewer's kickback loop. Add, after the existing diagram, a small note:

```
   (Separately, on a 6-hour cron)
   ┌─────────────┐  dispatch (issue_number, pr_number, mode=rebase)
   │ sweep-agent │─────────────────────────► implementer-agent  (for each stale PR)
   └─────────────┘
```

- [ ] **Step 6: Commit**

```bash
cd /home/dev/projects/github-agent-runner
git add catalog/agent-team/README.md
git commit -m "agent-team: document sweep + rebase-handling in README"
```

---

## Task 6: Update install-agent-team behavior tests

**Files:**
- Modify: `tests/test-install-agent-team.sh`

These are prompt-based tests that ask Claude questions about the skill and assert keywords in the response. Two tests need adjustment for the fifth workflow; one new test verifies the rebase concept is mentioned.

- [ ] **Step 1: Update Test 1 ("names all four roles")**

In `tests/test-install-agent-team.sh`, find the Test 1 block (lines 15-25). Change:
- The prompt text from "list the four roles it installs" to "list the five workflows it installs".
- `assert_contains "$output" "four" ...` to `assert_contains "$output" "five" "Mentions five (workflows)"`.
- Add: `assert_contains "$output" "sweep" "Names the sweep workflow" || exit 1`

- [ ] **Step 2: Update Test 3 ("atomic install")**

Find Test 3 (around lines 46-51). The prompt text "if one of the four 'gh aw add' calls fails" should become "if one of the five 'gh aw add' calls fails". No other assertions change.

- [ ] **Step 3: Update Test 4 ("auth wired once")**

Find Test 4 (around lines 55-60). In `assert_contains`, change the failure message "four" to "five" if present in the regex options list.

- [ ] **Step 4: Add a new Test 7 for rebase behavior awareness**

At the end of the file, before `echo "=== All install-agent-team tests passed ==="`, add:

```bash
# Test 7: Rebase behavior is part of the installed pipeline.
echo "Test 7: Skill mentions automatic rebase handling..."
output=$(run_claude "Load the install-agent-team skill. Does the installed pipeline do anything automatic about keeping draft PRs rebased onto main, or does the user have to rebase by hand? Quote the specific workflow or behavior." 180)
assert_contains "$output" "sweep|rebase" "Mentions sweep or rebase" || exit 1
assert_contains "$output" "automat|without|silently|no.*action" "Frames it as automatic" || exit 1

echo ""
```

- [ ] **Step 5: Run the tests locally against the updated skill**

```bash
cd /home/dev/projects/github-agent-runner
./tests/test-install-agent-team.sh
```

Expected: all tests pass. If any fails because Claude's answer phrasing doesn't match the assertion regex, adjust the regex (not the skill) — the skill is the source of truth.

Cost note: these are live Claude calls. Budget ~5-10 min wall-clock and a few thousand tokens.

- [ ] **Step 6: Commit**

```bash
git add tests/test-install-agent-team.sh
git commit -m "tests: cover sweep-agent in install-agent-team behavior suite"
```

---

## Task 7: Update the e2e install test

**Files:**
- Modify: `tests/test-e2e-install-agent-team.sh`

- [ ] **Step 1: Update the PROMPT string**

Find the `PROMPT=` line (around line 120). Change "install all four agent-team workflows" to "install all five agent-team workflows (including the sweep)".

- [ ] **Step 2: Update the assertion loop**

Find the `for wf in spec-agent planner-agent implementer-agent reviewer-agent; do` line (around line 138). Change to:

```bash
for wf in spec-agent planner-agent implementer-agent reviewer-agent sweep-agent; do
```

No other changes needed — the loop body already checks for `.md`, `.lock.yml`, and OAuth-tweak grep counts for each workflow name.

- [ ] **Step 3: (Optional) Add a quick sweep-trigger smoke assertion**

After the main assertion loop, add a check that the sweep workflow was actually registered with GitHub Actions:

```bash
# Sweep workflow is registered and dispatchable
if gh workflow list --repo "$FULL" --json name,path --jq '.[] | select(.path | contains("sweep-agent")) | .name' | grep -q .; then
  pass "sweep-agent workflow registered with Actions"
else
  fail "sweep-agent workflow not registered"
fi
```

Insert this before the existing "Labels" check.

- [ ] **Step 4: Run the e2e test locally (optional — costs ~5-8 min + creates a throwaway repo)**

```bash
cd /home/dev/projects/github-agent-runner
./tests/test-e2e-install-agent-team.sh
```

Expected: all assertions pass, including the five-workflow loop and the new sweep-registration check. If running this is too costly, skip and rely on the Task 8 smoke test instead.

- [ ] **Step 5: Commit**

```bash
git add tests/test-e2e-install-agent-team.sh
git commit -m "tests: extend e2e install check to cover sweep-agent"
```

---

## Task 8: Smoke-test the sweep against the playground repo

**Files:** none modified — this is manual verification.

Goal: confirm the sweep actually dispatches an implementer-in-rebase-mode run against a real stale PR, and that the rebase either pushes silently or escalates cleanly.

- [ ] **Step 1: Install the updated pipeline into `verkyyi/agent-team-playground`**

From the playground repo, run `/install-agent-team` with the plugin pointed at the current dev branch (not `main` — use the feature branch with the new sweep). The install should report 5 files added, OAuth tweak applied to 5 lockfiles.

If the playground already has an older agent-team install, remove the four existing `.lock.yml` files + `.md` sources first, then reinstall.

- [ ] **Step 2: Create a stale PR deliberately**

In the playground:
1. Open an issue with label `agent-team` describing a trivial change (e.g. "add a blank line to README").
2. Let the full pipeline run — spec, plan, impl, review, approve. You now have a draft PR.
3. Without merging, push an unrelated commit directly to `main` (e.g. edit a different file). This makes the PR "behind main."

- [ ] **Step 3: Trigger the sweep manually**

```bash
gh workflow run sweep-agent.lock.yml --repo verkyyi/agent-team-playground
```

Watch the run (`gh run watch`). Expected in the logs:
- `gh pr list` returns the one open draft PR.
- Ancestry check fails (PR is behind).
- `dispatch-workflow` fires for `implementer-agent` with `mode=rebase`.

- [ ] **Step 4: Verify the implementer-in-rebase-mode run**

Watch the dispatched implementer run. Expected:
- The Mode dispatch section routes to "Rebase-only mode".
- `git rebase origin/main` runs. Since `main`'s new commit is in an unrelated file, rebase is clean.
- Tests run once, pass.
- `git push --force-with-lease` updates the PR branch.
- One comment appears on the PR: `🤖 agent-team / rebase: rebased onto main at <sha>, tests green.`
- The reviewer is **not** dispatched.

- [ ] **Step 5: Verify the escalation path with a real conflict**

Repeat steps 2-4, but this time the commit to `main` must touch the same lines the PR touches. Expected:
- Implementer rebase-mode hits a conflict.
- Per "Conflict resolution": if the conflict is over the same logic, rebase is aborted, `state:blocked` is added to the issue, and a PR comment explains. No push happens.

- [ ] **Step 6: Record the smoke-test results**

Paste the two run URLs (the successful rebase and the blocked conflict) into the PR description for this feature work, as evidence the sweep works end-to-end.

- [ ] **Step 7: Open the PR for review**

```bash
gh pr create --base main --draft \
  --title "agent-team v0.2: auto-rebase via sweep + implementer rebase mode" \
  --body-file docs/superpowers/plans/2026-04-23-agent-team-auto-rebase.md
```

(Body-file is a placeholder — write a proper PR body summarizing spec, tasks, smoke results.)

---

## Self-review checklist (run by the plan author, not the implementer)

- [x] Every spec requirement maps to a task:
  - "Implementer rebases at start of `impl`" → Task 1
  - "New `rebase` mode" → Task 2
  - "Sweep workflow on schedule + dispatch" → Task 3
  - "Install skill includes sweep" → Task 4
  - "README documents behavior" → Task 5
  - "Tests cover the new shape" → Tasks 6, 7
  - "Smoke test on playground" → Task 8
  - "Escalation via state:blocked" → covered in Task 1 (Conflict resolution section), referenced by Task 2
- [x] No TBD/TODO/"similar to earlier" placeholders; every prompt body, YAML block, and shell command is written out.
- [x] Type consistency: input name `mode` is used identically in the implementer frontmatter (Task 1), the dispatch section (Task 1), the rebase-only-mode body (Task 2), and the sweep's `dispatch-workflow` call (Task 3). Values `"impl"` and `"rebase"` are used consistently. The escalation comment format is identical across both modes.
- [x] Test strategy is honest: no claim that prompt bodies are "tested" in the code-unit-test sense — validation is `gh aw compile` + `gh aw validate` + behavior-probe tests (Task 6) + e2e file-presence (Task 7) + manual playground smoke (Task 8).
