---
engine: claude
description: |
  This workflow performs research to  provides industry insights and competitive analysis.
  Reviews recent code, issues, PRs, industry news, and trends to create comprehensive
  research reports. Covers related products, research papers, market opportunities,
  business analysis, and new ideas. Creates GitHub discussions with findings to inform
  strategic decision-making.

on:
  schedule: weekly on monday
  workflow_dispatch:

permissions: read-all

network: defaults

safe-outputs:
  create-discussion:
    title-prefix: "${{ github.workflow }}"
    category: "ideas"

tools:
  github:
    toolsets: [all]
    min-integrity: none # This workflow is allowed to examine and comment on any issues or PRs
  web-fetch:

timeout-minutes: 15

source: githubnext/agentics/workflows/weekly-research.md@96b9d4c39aa22359c0b38265927eadb31dcf4e2a
---

# Weekly Research

## Context

This repository hosts **sidekick** (working name), a Claude Code plugin that wraps `gh-aw` (GitHub Agentic Workflows) to help solo founders/developers discover and install curated agentic workflows into their own repos, using their existing Claude Pro/Max subscription OAuth token instead of a per-token API key. The plugin is pre-release.

When doing external research, anchor to these specific areas — do not drift into unrelated tech trends:

1. **Anthropic platform policy** — ToS changes, OAuth token policy, subscription tier changes, Claude Code product allow-list updates, marketplace announcements. Scan: `anthropic.com/legal`, `code.claude.com/docs`, Anthropic blog, Hacker News posts in the last 7 days tagged "Anthropic" or "Claude."
2. **Claude Code plugin ecosystem** — new plugins in the official marketplace, notable third-party plugin releases, trends in plugin structure (skills vs commands vs hooks). Scan: Claude Code docs, `hesreallyhim/awesome-claude-code`, plugin-related PRs in `anthropics/claude-code`.
3. **`gh-aw` upstream** — new releases, notable PRs/issues (especially anything about auth, engines, marketplace), discussions in `github/gh-aw` and the `githubnext/agentics` catalog. Flag any new workflows added to the catalog since last report.
4. **Competing projects** — workflow install automation, PR assistants, agentic CI harnesses, "discovery" products. Specific repos to check weekly: `zircote/aw-author`, `anthropics/claude-code-action`, any fork of `gh-aw` that adds OAuth back.
5. **Subscription-backed CI discourse** — community posts about using Claude subscriptions in CI (reddit r/ClaudeAI, GitHub issues, HN). Both signal and risk: if Anthropic tightens policy, sidekick's wedge moves.
6. **Solo-founder / job-search relevance** — tech hiring climate for AI-tooling engineers, companies notably hiring in Claude/Anthropic ecosystem, what kind of portfolio artifacts get traction. (This repo is partly a portfolio piece.)

If something notable has happened in an area above, prioritize it in the report. If nothing has, say so briefly and move on rather than padding.

## Job Description

Do a deep research investigation anchored to the areas listed in "Context" above, informed by the repository's current state.

- Read selections of the latest code, issues, PRs, and recent commits for this repo to understand where sidekick stands.
- Read latest trends and news from the software-industry sources on the Web, focused on the six anchors. Do not report on unrelated tech trends (e.g., generic ML news, unrelated language/framework releases) unless they directly connect.

Create a new GitHub discussion with title starting with "${{ github.workflow }}" containing a markdown report with:

- **Anthropic platform signals** — any policy/ToS/product updates that affect sidekick's wedge
- **Claude Code plugin ecosystem** — new plugins, notable releases, structural trends
- **`gh-aw` upstream activity** — releases, breaking changes, new catalog entries, auth-related discussions
- **Competitive landscape** — what other "install automation" / "workflow discovery" tools shipped or moved
- **Subscription-backed CI signals** — community sentiment, policy tightening or loosening
- **Strategic suggestions** — 1–3 concrete things sidekick should consider doing this week (features to add, risks to mitigate, positioning to adjust). Be specific.
- **Enjoyable anecdote** (optional, one paragraph) — something interesting from the research that doesn't fit elsewhere

If a section has nothing new, write "No notable activity this week." Do not invent content to fill it.

Only a new discussion should be created, no existing discussions should be adjusted.

At the end of the report list write a collapsed section with the following:
- All search queries (web, issues, pulls, content) you used
- All bash commands you executed
- All MCP tools you used
