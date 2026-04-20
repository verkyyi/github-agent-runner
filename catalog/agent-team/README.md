# agent-team

A four-workflow pattern that turns a GitHub issue thread into an event bus for a spec → plan → implement → review pipeline. Each role is a separate gh-aw workflow; they coordinate by reading and writing structured comments on the issue and by advancing a small label state machine.

> **Status**: reference pattern. Templates only — `.lock.yml` files are generated when you install into a target repo.

## When to use this

You want multiple specialized agents (not one mega-prompt) collaborating on a task, with a visible audit trail in the issue thread and human override at any step.

## When NOT to use this

- The task is one-shot and doesn't need review (use `repo-assist` instead).
- You want headless UI testing / screenshots (this pattern is text-only by design).
- You need synchronous end-to-end in a single run (use a single workflow with chained steps).

## The state machine

The human only ever adds **one** label: `agent-team`. The agents manage the `state:*` labels internally as they pass the task along.

```
   label: agent-team  (the only label a human adds)
          |
          v
   [spec-agent]    posts <!-- agent-team:spec -->   ==>  state:plan-needed
   [planner]       posts <!-- agent-team:plan -->   ==>  state:impl-needed
   [implementer]   opens PR labeled agent-team      ==>  state:review-needed
   [reviewer]      posts <!-- agent-team:review --> ==>  state:done
                                                    OR   state:impl-needed (kickback)
                                                    OR   state:blocked     (max iterations)
```

Spec-agent distinguishes a fresh dispatch (no `state:*` label on the issue, no prior spec block) from label churn (pipeline already in motion) — churn is ignored silently.

Exactly one `state:*` label is expected at a time. Each agent:

1. Is triggered by `issues.labeled` (or `pull_request.labeled` for the reviewer).
2. Early-exits if the triggering label doesn't match its state, or if the issue lacks `agent-team`.
3. Removes its input state label immediately (so re-adding the label is the retry mechanism).
4. Does its work and writes a structured comment.
5. Adds the next state label — or `state:blocked` on max iterations / hard failure.

## The comment contract

Agents communicate via fenced HTML-comment blocks, which downstream agents grep out of the issue body + comments. Never rely on prose ordering.

```markdown
<!-- agent-team:spec iteration=1 -->
## Spec
...
<!-- /agent-team:spec -->
```

Sections: `spec`, `plan`, `review`. Each carries an `iteration` counter. The reviewer increments it on kickback; when any agent sees `iteration > MAX_ITERATIONS` (default 3), it flips to `state:blocked` instead of continuing.

## Files

| File | Trigger | Writes |
|---|---|---|
| `spec-agent.md` | `issues.labeled` with `agent-team` (fresh dispatch) | `<!-- agent-team:spec -->` comment + `state:plan-needed` label |
| `planner-agent.md` | `issues.labeled` with `state:plan-needed` | `<!-- agent-team:plan -->` comment + `state:impl-needed` label |
| `implementer-agent.md` | `issues.labeled` with `state:impl-needed` | PR (with `agent-team` label, `Closes #N`) + `state:review-needed` label on issue |
| `reviewer-agent.md` | `pull_request.labeled` with `agent-team` | `<!-- agent-team:review -->` comment + `state:done` / `state:impl-needed` / `state:blocked` label on issue |

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
3. Watch the thread. Each role posts its contribution as a comment; the implementer opens a PR that closes the issue when merged.
4. Human override at any time: remove a `state:*` label to pause, edit a comment to steer the next agent, or add `state:blocked` to halt.
5. **Retrying a blocked task**: remove all `state:*` labels from the issue, then remove and re-add the `agent-team` label. Spec-agent treats it as a fresh dispatch.

## Limits and gotchas

- **Concurrency**: each workflow uses `concurrency: group: agent-team-issue-${issue_number}` to prevent two roles racing on the same issue.
- **Max iterations**: default 3 (reviewer kickback → implementer). Tune `MAX_ITERATIONS` in each workflow's prompt.
- **Non-UI only**: no screenshot capture. Reviewer validates via tests/CI status + reading the diff.
- **Cost**: a single task can easily spend 4× the tokens of a monolithic workflow. Set `timeout-minutes` conservatively and monitor the first few runs.
- **No auto-merge**: the reviewer approves but never merges. Humans merge.
