# github-agent-runner

A Claude Code plugin for conversational discovery and installation of GitHub agentic workflows (gh-aw), with subscription-aware auth setup.

> **Status**: v0.1, pre-scope-lock.

## What is this?

`github-agent-runner` is a Claude Code plugin that helps you add AI-powered automation to any GitHub repository. It does two things:

1. **Discover** — recommends 1–3 agentic workflows from a curated catalog that match your repo's shape (language, CI setup, activity level, etc.).
2. **Install** — walks you through fetching, authenticating, and wiring up each workflow end-to-end, including the OAuth token tweak that makes your Claude subscription work inside GitHub Actions.

This repo also **dogfoods seven of those workflows on itself**, so you can see exactly how they're configured.

## Installed workflows

| Workflow | Trigger | Purpose |
|---|---|---|
| [repo-assist](.github/workflows/repo-assist.md) | Every 12 h + `/repo-assist` + 👀 reaction | Labels issues, comments to unblock contributors, opens draft PRs for bug fixes and improvements |
| [daily-plan](.github/workflows/daily-plan.md) | Daily | Analyzes repo state and maintains a rolling project-plan Discussion |
| [update-docs](.github/workflows/update-docs.md) | Every push to `main` | Detects documentation drift and opens draft PRs to keep docs in sync with code changes |
| [q](.github/workflows/q.md) | `/q` or 🚀 reaction | Expert workflow optimizer — audits live logs, identifies inefficiencies, opens optimization PRs |
| [markdown-linter](.github/workflows/markdown-linter.md) | Weekdays at 14:00 UTC | Runs Super Linter on Markdown; opens time-limited issues for violations |
| [pr-nitpick-reviewer](.github/workflows/pr-nitpick-reviewer.md) | `/nit` on a PR | Inline style and best-practice review (up to 10 comments, non-blocking) |
| [weekly-research](.github/workflows/weekly-research.md) | Weekly (Monday) | Strategic research across Anthropic policy, plugin ecosystem, gh-aw upstream, competitors, and solo-founder hiring signal |

All seven use `engine: claude` and are pre-configured with the [OAuth token tweak](skills/install-workflow/auth.md) so they run on your Claude subscription rather than billing the API per-token.

## Prerequisites

To use the plugin:

- [Claude Code](https://claude.ai/code) CLI installed and authenticated
- `gh` CLI authenticated (`gh auth login`)
- `gh aw` extension installed (`gh extension install githubnext/gh-aw`)

To run the installed workflows on your own fork:

- A Claude Pro, Max ($100), or Max ($200) subscription **or** an [Anthropic API key](https://console.anthropic.com)
- The appropriate secret set on the repository:
  - OAuth path: `CLAUDE_CODE_OAUTH_TOKEN`
  - API-key path: `ANTHROPIC_API_KEY`
- GitHub Discussions enabled (required by `daily-plan` — uses the "announcements" category — and `weekly-research` — uses the "ideas" category)

See [skills/install-workflow/auth.md](skills/install-workflow/auth.md) for the complete auth decision tree.

## Quick start

Inside any Claude Code session, add the self-hosted marketplace and install the plugin:

```
/plugin marketplace add https://raw.githubusercontent.com/verkyyi/github-agent-runner/main/.claude-plugin/marketplace.json
/plugin install github-agent-runner
```

Then invoke the skills:

```
/discover-workflows    # get tailored workflow recommendations for your repo
/install-workflow      # install a recommended workflow with full auth setup
```

Both skill names are unique, so the short form works out-of-the-box. If another installed plugin ever ships the same skill name, prefix with the plugin name to disambiguate: `/github-agent-runner:discover-workflows`.

> Want to hack on the plugin itself? See [Local development](#local-development) below for the `claude --plugin-dir .` workflow.

## How the skills work

### `/discover-workflows`

Inspects your repo's shape (language, test presence, CI configuration, recent activity) using only local `git` and filesystem tools. Then fetches the current list of workflows from the upstream [`githubnext/agentics`](https://github.com/githubnext/agentics/tree/main/workflows) catalog at runtime — no local catalog to drift — reads frontmatter from the most promising candidates, and recommends up to 3 that fit, each with a one-sentence reason specific to your repo and an estimated setup friction level. Hands off directly to `/install-workflow` once you pick one.

All agentics workflows require Claude auth (OAuth or API-key). See [skills/install-workflow/auth.md](skills/install-workflow/auth.md) for the decision tree.

### `/install-workflow`

Takes a workflow name (or prompts you to run `/discover-workflows` first) and:

1. Checks that `gh` CLI and `gh aw` extension are available, and that you have write access
2. Asks once whether you have a Claude subscription or prefer the API-key path
3. Guides you through setting the appropriate repo secret — never echoes or stores your token
4. Runs `gh aw add <workflow>` to compile the `.lock.yml`
5. For the OAuth path: applies the required two-pass post-compile tweak and verifies the grep counts
6. Runs `gh aw validate` and summarizes every file changed

## Authentication

Two paths are supported:

| | OAuth path (preferred) | API-key path (fallback) |
|---|---|---|
| **Who** | Claude Pro / Max subscribers | Non-subscribers |
| **Secret** | `CLAUDE_CODE_OAUTH_TOKEN` | `ANTHROPIC_API_KEY` |
| **Cost** | Free (included in subscription) | Pay-per-token |
| **Post-compile tweak** | Required (two-pass sed) | Not needed |

Full details — including the two-pass tweak rationale, verification grep counts, failure modes, and the ToS boundary explanation — are in [skills/install-workflow/auth.md](skills/install-workflow/auth.md).

**Important**: `gh aw compile` reverts the OAuth tweak in `.lock.yml` files. Re-apply [Steps 3–4 from auth.md](skills/install-workflow/auth.md#step-3--apply-the-post-compile-tweak-to-every-lockyml) after any recompile event (`gh aw compile`, `gh aw upgrade`, `gh aw fix`, or editing the `.md` source).

## Repository layout

```
.claude-plugin/
  plugin.json                      # plugin manifest (name, version, license)
  marketplace.json                 # self-hosted marketplace listing (enables /plugin marketplace add)

skills/
  discover-workflows/
    SKILL.md                       # /discover-workflows logic and hard rules
  install-workflow/
    SKILL.md                       # /install-workflow logic and hard rules
    auth.md                        # OAuth vs. API-key decision tree

.github/
  agents/
    agentic-workflows.agent.md     # dispatcher agent for workflow operations
  aw/
    actions-lock.json              # gh-aw extension version lock
  workflows/
    agentics-maintenance.yml       # standard GHA workflow: gh-aw version maintenance
    copilot-setup-steps.yml        # standard GHA workflow: Copilot coding agent environment setup
    repo-assist.{md,lock.yml}
    daily-plan.{md,lock.yml}
    update-docs.{md,lock.yml}
    q.{md,lock.yml}
    markdown-linter.{md,lock.yml}
    pr-nitpick-reviewer.{md,lock.yml}
    weekly-research.{md,lock.yml}
    shared/
      reporting.md                 # shared reporting component (run-link formatting)
```

`.lock.yml` files are marked as `linguist-generated` and `merge=ours` in `.gitattributes` to prevent spurious merge conflicts.

## Local development

```bash
claude --plugin-dir .
```

Changes to `skills/*/SKILL.md` take effect on the next Claude Code session reload. Changes to `.lock.yml` files can be validated at any time with `gh aw validate` (safe — does not recompile).

## Publishing

Once v0.1 is scope-locked, submit via `claude.ai/settings/plugins/submit` or `platform.claude.com/plugins/submit`.
