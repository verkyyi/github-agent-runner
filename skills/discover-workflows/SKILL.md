---
name: discover-workflows
description: Recommend GitHub agent workflows (gh-aw) tailored to this repo. Use when the user asks which automations to add to their repo, what agentic workflows would help, or types /discover-workflows.
---

# discover-workflows

Recommend 1-3 workflows from the upstream `githubnext/agentics` catalog that fit the user's current repo. No local catalog — every call fetches the latest state from upstream.

## Flow

1. Detect repo shape: language, framework, test presence, CI presence, size (files, LOC), activity (recent commits). Use `git` and filesystem inspection only — no external calls yet.
2. Fetch the upstream workflow list:
   - Prefer `gh aw list` (or equivalent listing verb) if it enumerates upstream workflows.
   - Otherwise, `gh api repos/githubnext/agentics/contents/workflows` to list available `.md` workflow files, and fetch `githubnext/agentics`'s README or `workflows/README.md` for one-line descriptions.
3. Short-list ~5 candidates by matching names + descriptions to the detected repo shape. Do NOT read every workflow's body at this stage — that's too many tokens.
4. For each short-listed candidate, fetch the workflow's frontmatter only (`gh api repos/githubnext/agentics/contents/workflows/<name>.md` → base64-decode → parse YAML frontmatter). Confirm triggers, required secrets, and fit signals.
5. Pick 1-3 whose frontmatter genuinely matches the repo shape. The recommendation IS the product — don't fall back to "here's the full list."
6. For each recommendation, show: name, one-line purpose, why it fits THIS repo (one sentence, specific), estimated setup friction.
7. Ask which (if any) the user wants to install. Hand off to `/install-workflow <name>`.

## Hard rules

- Never recommend a workflow whose required secrets the repo clearly can't produce (e.g. don't recommend a Slack-notification workflow in a repo with no Slack references anywhere).
- Never recommend more than 3 at once. Two is usually right.
- Never draft a custom workflow. If the user asks for one, point them at `zircote/github-agentic-workflows` and stop.
- Never fall back to a stale or inline list if the upstream fetch fails. Surface the error plainly and stop — a broken network beats a stale recommendation.

## Out of scope for v0.1

- Auditing already-installed workflows
- Recommending across multiple repos
- Persisting recommendations or caches between sessions
