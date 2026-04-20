# agent-team

A four-workflow pattern for a spec → plan → implement → review pipeline on a single GitHub issue. Each role is a separate gh-aw workflow; they coordinate by **dispatching the next workflow** via gh-aw's `dispatch-workflow` safe-output, passing typed inputs (issue number, iteration counter, optional PR number).

> **Status**: reference pattern. Templates only — `.lock.yml` files are generated when you install into a target repo.

## When to use this

You want multiple specialized agents (not one mega-prompt) collaborating on a task, with a visible audit trail in the issue thread and human override at any step.

## When NOT to use this

- The task is one-shot and doesn't need review (use `repo-assist` instead).
- You want headless UI testing / screenshots (this pattern is text-only by design).
- You need synchronous end-to-end in a single run (use a single workflow with chained steps).

## The handoff model

Each agent finishes its work by **emitting a `dispatch-workflow` safe-output** naming the next agent and passing the required inputs. gh-aw's compiler translates this into a `workflow_dispatch` call, which fires the target workflow even though `GITHUB_TOKEN` did the dispatch (`workflow_dispatch` is explicitly exempt from the GH Actions event-suppression rule that would otherwise block chaining).

```
   label: agent-team  (the only label a human adds)
          │
          ▼
   ┌─────────────┐  dispatch (issue_number, iteration=1)
   │ spec-agent  │─────────────────────────────────────┐
   └─────────────┘                                     │
          ▼                                            ▼
   ┌────────────────┐  dispatch (issue_number, iteration)
   │ planner-agent  │────────────────────────────────┐
   └────────────────┘                                │
                                                     ▼
   ┌────────────────────┐  dispatch (issue_number, pr_number, iteration)
   │ implementer-agent  │──────────────────────────────────────────────┐
   └────────────────────┘                                              │
                                                                       ▼
   ┌────────────────┐  approve ► state:done + pipeline-summary on issue (stop — human merges the PR)
   │ reviewer-agent │  block   ► state:blocked (stop — human resolves)
   └────────────────┘  kickback► dispatch implementer-agent (
                                     issue_number, pr_number,
                                     iteration = iteration + 1
                                 )
```

`state:*` labels (`plan-needed`, `impl-needed`, `review-needed`, `done`, `blocked`) are **cosmetic breadcrumbs for humans** — they let the GitHub UI show pipeline progress at a glance. They do **not** drive control flow; the `dispatch-workflow` safe-outputs do.

## The comment contract

Agents communicate their work product via fenced HTML-comment blocks, which downstream agents grep out of the issue body + comments. Never rely on prose ordering.

```markdown
<!-- agent-team:spec iteration=1 -->
## Spec
...
<!-- /agent-team:spec -->
```

Sections: `spec`, `plan`, `review`, `summary`. Each carries the `iteration` at the time it was produced. The reviewer increments `iteration` on kickback when it dispatches the implementer. When any agent sees `iteration > 3` as its input, it flips the issue to `state:blocked` and stops instead of continuing.

The `summary` block is special: the reviewer posts it on the **issue** (not the PR) on approval only, giving humans a single jump-off point with links to every stage's Actions run and the PR number. It is never produced on kickback or block paths.

```markdown
<!-- agent-team:summary issue=N -->
## ✅ Pipeline complete — ready for human review

| Stage | Run |
|---|---|
| Spec | [link] |
| Plan | [link] |
| Impl | [link] |
| Review | [link] |

**PR**: #N — draft, awaiting your merge.
**Iterations**: N (kickback rounds before approval).

🤖 agent-team / reviewer
<!-- /agent-team:summary -->
```

## Files

| File | Trigger | Dispatches next |
|---|---|---|
| `spec-agent.md` | `issues.labeled` with `agent-team` (fresh issue) | `planner-agent` (issue_number, iteration=1) |
| `planner-agent.md` | `workflow_dispatch` (issue_number, iteration) | `implementer-agent` (issue_number, iteration) |
| `implementer-agent.md` | `workflow_dispatch` (issue_number, iteration, pr_number?) | `reviewer-agent` (issue_number, pr_number, iteration) |
| `reviewer-agent.md` | `workflow_dispatch` (pr_number, issue_number, iteration) | `implementer-agent` on kickback (iteration+1); on approve: posts pipeline-summary on issue, else nothing |

## Install

Use the bundled skill — it's the supported path:

```
/install-agent-team
```

One flow installs all four workflows, wires auth once, applies the OAuth tweak to every lockfile, and creates the seven labels. See [`skills/install-agent-team/SKILL.md`](../../skills/install-agent-team/SKILL.md).

<details>
<summary>Manual install (advanced)</summary>

```bash
gh aw add verkyyi/github-agent-runner/catalog/agent-team/spec-agent.md@main
gh aw add verkyyi/github-agent-runner/catalog/agent-team/planner-agent.md@main
gh aw add verkyyi/github-agent-runner/catalog/agent-team/implementer-agent.md@main
gh aw add verkyyi/github-agent-runner/catalog/agent-team/reviewer-agent.md@main
```

Then apply the OAuth token tweak to each `.lock.yml` per [`skills/install-workflow/auth.md`](../../skills/install-workflow/auth.md), and create the labels (see the skill file for the exact `gh label create` commands).
</details>

## Prerequisites in the target repo

- Repo Actions settings: **Read and write** permissions + **Allow GitHub Actions to create and approve pull requests**.
- Either `CLAUDE_CODE_OAUTH_TOKEN` (subscription) or `ANTHROPIC_API_KEY` repo secret.
- Labels (`agent-team`, `state:plan-needed`, `state:impl-needed`, `state:review-needed`, `state:done`, `state:blocked`, `agent-team:reviewed`) — the install skill creates them.

## Kicking off a task

1. Open an issue describing what you want built.
2. Add the single label `agent-team`.
3. Watch the thread. Each role posts its contribution as a comment; the implementer opens a draft PR that closes the issue when merged. On approval, the reviewer posts a final pipeline-summary comment on the issue with links to every stage's Actions run — your single jump-off point before merging.
4. Human override at any time: add `state:blocked` to halt, edit a comment to steer the next agent, or manually `gh workflow run` a specific role to retry a stuck stage.
5. **Retrying a blocked task**: clear `state:blocked`, then re-add `agent-team`. Spec-agent treats it as a fresh dispatch (because the state:* labels are gone and the spec markers are already satisfied — actually: to redo from scratch, also delete the prior spec comment).

## Limits and gotchas

- **Concurrency**: each workflow uses `concurrency: group: agent-team-issue-${issue_number}` so only one role runs at a time per issue.
- **Max iterations**: default 3 (reviewer kickback → implementer). The counter lives on the `iteration` input passed through the dispatch chain, bumped exclusively by the reviewer on kickback.
- **Non-UI only**: no screenshot capture. Reviewer validates via tests/CI status + reading the diff.
- **Cost**: a single task can easily spend 4× the tokens of a monolithic workflow. Set `timeout-minutes` conservatively and monitor the first few runs.
- **No auto-merge**: the reviewer approves but never merges. Humans merge.
- **Dispatch visibility**: each `dispatch-workflow` call shows up as a new run in the Actions tab, linked to the upstream run. Makes the chain visible.
