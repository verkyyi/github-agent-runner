# github-agent-runner

Host repo for the **sidekick** Claude Code plugin — conversational discovery and installation of GitHub agentic workflows, with subscription-aware auth setup.

> **Status**: v0.1, pre-scope-lock.

## What is this?

`sidekick` is a Claude Code plugin that helps you add AI-powered automation to any GitHub repository. It does two things:

1. **Discover** — recommends 1–3 agentic workflows from a curated catalog that match your repo's shape (language, CI setup, activity level, etc.).
2. **Install** — walks you through fetching, authenticating, and wiring up each workflow end-to-end, including the OAuth token tweak that makes your Claude subscription work inside GitHub Actions.

This repo also **dogfoods six of those workflows on itself**, so you can see exactly how they're configured.

## Installed workflows

| Workflow | Trigger | Purpose |
|---|---|---|
| [repo-assist](.github/workflows/repo-assist.md) | Every 12 h + `/repo-assist` | Labels issues, comments to unblock contributors, opens draft PRs for bug fixes and improvements |
| [daily-plan](.github/workflows/daily-plan.md) | Daily | Analyzes repo state and maintains a rolling project-plan Discussion |
| [update-docs](.github/workflows/update-docs.md) | Every push to `main` | Detects documentation drift and opens draft PRs to keep docs in sync with code changes |
| [q](.github/workflows/q.md) | `/q` or 🚀 reaction | Expert workflow optimizer — audits live logs, identifies inefficiencies, opens optimization PRs |
| [markdown-linter](.github/workflows/markdown-linter.md) | Weekdays at 14:00 UTC | Runs Super Linter on Markdown; opens time-limited issues for violations |
| [pr-nitpick-reviewer](.github/workflows/pr-nitpick-reviewer.md) | `/nit` on a PR | Inline style and best-practice review (up to 10 comments, non-blocking) |

All six use `engine: claude` and are pre-configured with the [OAuth token tweak](skills/install/auth.md) so they run on your Claude subscription rather than billing the API per-token.

## Prerequisites

To use the sidekick plugin:

- [Claude Code](https://claude.ai/code) CLI installed and authenticated
- `gh` CLI authenticated (`gh auth login`)
- `gh aw` extension installed (`gh extension install githubnext/gh-aw`)

To run the installed workflows on your own fork:

- A Claude Pro, Max ($100), or Max ($200) subscription **or** an [Anthropic API key](https://console.anthropic.com)
- The appropriate secret set on the repository:
  - OAuth path: `CLAUDE_CODE_OAUTH_TOKEN`
  - API-key path: `ANTHROPIC_API_KEY`

See [skills/install/auth.md](skills/install/auth.md) for the complete auth decision tree.

## Quick start

```bash
# Load sidekick for local development
git clone https://github.com/verkyyi/github-agent-runner
cd github-agent-runner
claude --plugin-dir .
```

Then inside Claude Code:

```
/sidekick:discover    # get tailored workflow recommendations for your repo
/sidekick:install     # install a recommended workflow with full auth setup
```

## How the skills work

### `/sidekick:discover`

Inspects your repo's shape (language, test presence, CI configuration, recent activity) using only local `git` and filesystem tools — no external API calls. Loads the curated [catalog](skills/discover/catalog.md) and recommends up to 3 workflows that fit, each with a one-sentence reason specific to your repo and an estimated setup friction level. Hands off directly to `/sidekick:install` once you pick one.

### `/sidekick:install`

Takes a workflow name (or prompts you to run `/sidekick:discover` first) and:

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

Full details — including the two-pass tweak rationale, verification grep counts, failure modes, and the ToS boundary explanation — are in [skills/install/auth.md](skills/install/auth.md).

**Important**: `gh aw compile` reverts the OAuth tweak in `.lock.yml` files. Re-apply [Steps 3–4 from auth.md](skills/install/auth.md#step-3--apply-the-post-compile-tweak-to-every-lockyml) after any recompile event (`gh aw compile`, `gh aw upgrade`, `gh aw fix`, or editing the `.md` source).

## Repository layout

```
.claude-plugin/
  plugin.json                      # sidekick plugin manifest (name, version, license)

skills/
  discover/
    SKILL.md                       # /sidekick:discover logic and hard rules
    catalog.md                     # curated workflow catalog (stub until scope-lock)
  install/
    SKILL.md                       # /sidekick:install logic and hard rules
    auth.md                        # OAuth vs. API-key decision tree

.github/
  agents/
    agentic-workflows.agent.md     # dispatcher agent for workflow operations
  aw/
    actions-lock.json              # gh-aw extension version lock
  workflows/
    repo-assist.{md,lock.yml}
    daily-plan.{md,lock.yml}
    update-docs.{md,lock.yml}
    q.{md,lock.yml}
    markdown-linter.{md,lock.yml}
    pr-nitpick-reviewer.{md,lock.yml}
    agentics-maintenance.yml       # auto-generated by gh-aw; manages expiring issues/PRs
    copilot-setup-steps.yml        # installs gh-aw CLI for GitHub Copilot Agent sessions
    shared/
      reporting.md                 # shared reporting component (run-link formatting)

.vscode/
  mcp.json                         # MCP server config (gh-aw tools for Copilot in VS Code)
  settings.json                    # GitHub Copilot markdown association settings
```

`.lock.yml` files are marked as `linguist-generated` and `merge=ours` in `.gitattributes` to prevent spurious merge conflicts.

### Infrastructure workflows

Two workflow files are not user-installed — they are managed entirely by `gh aw`:

| File | How it's created | Purpose |
|---|---|---|
| `agentics-maintenance.yml` | Auto-generated on `gh aw compile` when any workflow uses `expires:` | Cleans up time-limited issues and PRs on a schedule |
| `copilot-setup-steps.yml` | Manually committed once | Pre-installs the `gh-aw` CLI extension so GitHub Copilot Agent sessions have it available |

Do not edit `agentics-maintenance.yml` by hand — it is regenerated automatically.

## Local development

```bash
claude --plugin-dir .
```

Changes to `skills/*/SKILL.md` take effect on the next Claude Code session reload. Changes to `.lock.yml` files can be validated at any time with `gh aw validate` (safe — does not recompile).

## Publishing

Once v0.1 is scope-locked:

1. Fill in `skills/discover/catalog.md` with curated entries (5–8 workflows from the `githubnext/agentics` catalog)
2. Update `plugin.json` with the final author name and repository URL
3. Submit via `claude.ai/settings/plugins/submit` or `platform.claude.com/plugins/submit`

> The catalog is intentionally empty until scope-lock — this prevents anchoring recommendations before curation is complete.
