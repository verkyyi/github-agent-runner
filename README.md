# github-agent-runner

A Claude Code plugin for conversational discovery and installation of GitHub agentic workflows (gh-aw), with subscription-aware auth setup.

> **Status**: v0.2.1 — see [Releases](https://github.com/verkyyi/github-agent-runner/releases) for the changelog.

## What is this?

`github-agent-runner` is a Claude Code plugin that helps you add AI-powered automation to any GitHub repository. It does two things:

1. **Discover** — recommends 1–3 agentic workflows from the [`githubnext/agentics`](https://github.com/githubnext/agentics) catalog that match your repo's shape (language, CI setup, activity level, etc.).
2. **Install** — walks you through fetching, authenticating, and wiring up each workflow end-to-end, including the OAuth token tweak that makes your Claude subscription work inside GitHub Actions.

It also ships the **agent-team** pattern — four workflows (spec → plan → impl → review) installable in one pass via `/install-agent-team`. See [catalog/agent-team/](catalog/agent-team/README.md).

## Quick start

Open your repo in Claude Code (or any coding agent) and paste:

> Install the github-agent-runner plugin from `https://raw.githubusercontent.com/verkyyi/github-agent-runner/main/.claude-plugin/marketplace.json` and recommend workflows for this repo.

The agent will add the marketplace, install the plugin, and run `/discover-workflows` — pick a recommendation and it hands off to `/install-workflow` for the full auth + setup walkthrough.

**First time? Skip discovery and try the starter.** Running `/install-workflow` with no arguments pitches `daily-repo-status` — a zero-risk workflow that creates a daily GitHub issue summarizing your repo activity. It only needs read + issue-create permissions and gives you something visible on your first run before committing to anything broader.

<details>
<summary>Prefer the explicit slash-command form?</summary>

```
/plugin marketplace add https://raw.githubusercontent.com/verkyyi/github-agent-runner/main/.claude-plugin/marketplace.json
/plugin install github-agent-runner
/discover-workflows
```

Both skill names are unique, so the short form works out-of-the-box. If another installed plugin ever ships the same skill name, prefix with the plugin name: `/github-agent-runner:discover-workflows`.
</details>

## Prerequisites

- [Claude Code](https://claude.ai/code) CLI installed and authenticated
- `gh` CLI authenticated (`gh auth login`)
- `gh aw` extension installed (`gh extension install githubnext/gh-aw`)
- A Claude Pro/Max subscription **or** an [Anthropic API key](https://console.anthropic.com) for the installed workflows themselves — see [Authentication](#authentication).

## Authentication

Two paths are supported:

| | OAuth path (preferred) | API-key path (fallback) |
|---|---|---|
| **Who** | Claude Pro / Max subscribers | Non-subscribers |
| **Secret** | `CLAUDE_CODE_OAUTH_TOKEN` | `ANTHROPIC_API_KEY` |
| **Cost** | Free (included in subscription) | Pay-per-token |
| **Post-compile tweak** | Required (two-pass sed) | Not needed |

Full details — including the two-pass tweak rationale, verification grep counts, failure modes, and the ToS boundary explanation — are in [skills/install-workflow/auth.md](skills/install-workflow/auth.md).

## Running on this repo

This repo dogfoods [`daily-repo-status`](.github/workflows/daily-repo-status.md), [`update-docs`](.github/workflows/update-docs.md), and [`weekly-research`](.github/workflows/weekly-research.md) — a live example of what `/install-workflow` sets up. See the `.github/workflows/` directory for the compiled `.lock.yml` files.

## Multi-workflow patterns

Beyond the one-workflow-per-job templates above, this repo ships reference patterns for **multiple workflows collaborating** via the GitHub issue thread as an event bus:

- **[agent-team](catalog/agent-team/README.md)** — four roles (spec → plan → impl → review) coordinating through structured comment blocks and a small internal label state machine. Install all four in one pass with `/install-agent-team`; dispatch tasks by opening an issue and adding a single `agent-team` label. Use when you want visible handoffs, human override between steps, and an audit trail per task.

  **See it in action**: [verkyyi/agent-team-playground#5](https://github.com/verkyyi/agent-team-playground/pull/5) — a complete spec → plan → impl → review run on a toy `greet()` function, with all four workflow runs linked and the reviewer's approve comment posted back on the issue thread.

## Uninstall

Remove the plugin from Claude Code:

```
/plugin uninstall github-agent-runner
/plugin marketplace remove github-agent-runner   # if you added the marketplace
```

To remove workflows this plugin installed into your target repo:

- `gh aw remove <workflow>` for each installed workflow (deletes both the `.md` source and the compiled `.lock.yml`), then commit the deletion.
- `gh secret delete CLAUDE_CODE_OAUTH_TOKEN` — or `ANTHROPIC_API_KEY`, whichever path you used — to unset the auth secret.
- For `agent-team` specifically, also delete the seven labels: `gh label delete agent-team`, `gh label delete agent-team:reviewed`, plus `gh label delete state:<name>` for each of `plan-needed`, `impl-needed`, `review-needed`, `done`, and `blocked`.

Nothing else is persisted — the plugin writes only to your target repo (under user approval) and holds no local state outside Claude Code's own plugin directory.

## Local development

```bash
claude --plugin-dir .
```

<details>
<summary>Repository layout</summary>

```
.claude-plugin/
  plugin.json                      # plugin manifest (name, version, license)
  marketplace.json                 # self-hosted marketplace listing

skills/
  discover-workflows/SKILL.md
  install-workflow/
    SKILL.md
    auth.md                        # OAuth vs. API-key decision tree
  install-agent-team/SKILL.md      # unified installer (4 roles + labels + auth)

catalog/
  agent-team/                      # spec → plan → impl → review pattern
    README.md                      # label/comment contract + install steps
    {spec,planner,implementer,reviewer}-agent.md

.github/
  agents/agentic-workflows.agent.md
  aw/actions-lock.json             # gh-aw extension version lock
  workflows/
    agentics-maintenance.yml
    copilot-setup-steps.yml
    {daily-repo-status,update-docs,weekly-research}.{md,lock.yml}
    shared/reporting.md            # pulled verbatim from agentics
```

`.lock.yml` files are marked `linguist-generated` and `merge=ours` in `.gitattributes` to prevent spurious merge conflicts.
</details>

## Publishing (maintainers only)

1. Bump `"version"` in `.claude-plugin/plugin.json` and update the `v<version>` status badge near the top of this README (the `test-invariants` check enforces they stay in sync).
2. Commit to `main`.
3. Create and push a tag: `git tag v<version> && git push origin v<version>`.
4. Draft a GitHub release from the tag — the release body is the human-readable changelog entry.
5. The marketplace URL (`https://raw.githubusercontent.com/verkyyi/github-agent-runner/main/.claude-plugin/marketplace.json`) is stable; existing users pick up the new version automatically on next plugin refresh. For new registry listings, follow the submission flows at [claude-plugins.dev](https://claude-plugins.dev) and [ClaudePluginHub](https://claudepluginhub.com).

## Credits

Built on two open-source projects from the [GitHub Next](https://githubnext.com) team:

- **[github/gh-aw](https://github.com/github/gh-aw)** — the agentic workflow compiler. Every workflow this plugin installs is a gh-aw `.md` source compiled by `gh aw add` / `gh aw compile`. Maintained by [@pelikhan](https://github.com/pelikhan), [@dsyme](https://github.com/dsyme), and others.
- **[githubnext/agentics](https://github.com/githubnext/agentics)** — the curated workflow catalog. `/discover-workflows` surfaces entries from this repo; every dogfooded workflow in `.github/workflows/` traces back to a source `.md` at `githubnext/agentics/workflows/`.

Pattern inspiration from **[superpowers](https://github.com/obra/superpowers)** by [@obra](https://github.com/obra) — our agent-team spec → plan → impl → review loop mirrors the superpowers skill loop, reimplemented inline for headless gh-aw execution.

Plugin listed on [claude-plugins.dev](https://claude-plugins.dev) and [ClaudePluginHub](https://claudepluginhub.com).
