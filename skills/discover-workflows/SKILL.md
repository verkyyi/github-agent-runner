---
name: discover-workflows
description: Recommend GitHub agent workflows (gh-aw) tailored to this repo. Use when the user asks which automations to add to their repo, what agentic workflows would help, or types /github-agent-runner:discover-workflows.
---

# github-agent-runner: discover-workflows

Recommend 1-3 workflows from the curated catalog that fit the user's current repo.

## Flow

1. Detect repo shape: language, framework, test presence, CI presence, size (files, LOC), activity (recent commits). Use `git` and filesystem inspection only — don't call external APIs.
2. Load the curated catalog: `catalog.md` (colocated with this SKILL.md).
3. Pick 1-3 workflows whose triggers match the repo shape. Do NOT list the full catalog — curation is the product.
4. For each recommendation, show: name, one-line purpose, why it fits THIS repo (one sentence, specific), estimated setup friction.
5. Ask which (if any) the user wants to install. Hand off to `/github-agent-runner:install-workflow <name>`.

## Hard rules

- Never recommend a workflow that requires secrets the repo clearly can't produce (e.g. don't recommend a Slack-notification workflow in a repo with no Slack references anywhere).
- Never recommend more than 3 at once. Two is usually right.
- Never draft a custom workflow. If the user asks for one, point them at `zircote/aw-author` and stop.

## Out of scope for v0.1

- Auditing already-installed workflows
- Recommending across multiple repos
- Freshly reasoning about the catalog each call (v0.1 is fixed catalog)
