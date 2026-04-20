# github-agent-runner

A Claude Code plugin for conversational discovery and installation of GitHub agentic workflows (gh-aw), with subscription-aware auth setup.

> **Status**: v0.2.1 — polish release on top of v0.2.0's validated [agent-team pipeline](https://github.com/verkyyi/agent-team-playground/pull/5). End-user journey fixes, ~4-min speedup on installed workflows, and a test framework underneath.

## What's new in v0.2.1

- **Critical end-user journey fixes** — `workflow`-scope preflight in both install skills (caught a real first-time-user gotcha), TTY warning for `claude setup-token` in headless environments, stale "every push to main" docs cleaned up.
- **Agent-team pipelines ~4 min faster** — `safe-outputs.threat-detection: false` on all four agent-team workflows skips gh-aw's per-agent threat classifier (appropriate for trusted-input pipelines where the user labels their own issue).
- **Reviewer posts a pipeline-summary comment** on the issue after approve, with links to all four run pages + the PR. One jump-off point for the human.
- **Implementer prompt tuning** — trust-the-plan directive + 5-tool-call budget heuristic. Observed wall-clock: 20m54s → 6m41s on a comparable task (−68%).
- **MIT LICENSE file** added (was already declared in plugin.json).
- **Credits section** explicitly attributes gh-aw (GitHub Next), agentics (same team), and superpowers (Jesse Vincent) in README.

## What's in v0.2.0 (still)

- **`agent-team` pattern** — four workflows (spec → plan → impl → review) that collaborate on a single issue via `workflow_dispatch` handoffs. See [catalog/agent-team/](catalog/agent-team/README.md).
- **`/install-agent-team` skill** — atomic install of all four roles + OAuth tweak + seven labels. See [skills/install-agent-team/SKILL.md](skills/install-agent-team/SKILL.md).

## What is this?

`github-agent-runner` is a Claude Code plugin that helps you add AI-powered automation to any GitHub repository. It does two things:

1. **Discover** — recommends 1–3 agentic workflows from a curated catalog that match your repo's shape (language, CI setup, activity level, etc.).
2. **Install** — walks you through fetching, authenticating, and wiring up each workflow end-to-end, including the OAuth token tweak that makes your Claude subscription work inside GitHub Actions.

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

## Prerequisites

To use the plugin:

- [Claude Code](https://claude.ai/code) CLI installed and authenticated
- `gh` CLI authenticated (`gh auth login`)
- `gh aw` extension installed (`gh extension install githubnext/gh-aw`)

To run the installed workflows on your own repo:

- A Claude Pro, Max ($100), or Max ($200) subscription **or** an [Anthropic API key](https://console.anthropic.com)
- The appropriate secret set on the repository:
  - OAuth path: `CLAUDE_CODE_OAUTH_TOKEN`
  - API-key path: `ANTHROPIC_API_KEY`
- GitHub Discussions enabled if you install `weekly-research` (uses the "ideas" category)

See [skills/install-workflow/auth.md](skills/install-workflow/auth.md) for the complete auth decision tree.

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

## Running on this repo

This repo dogfoods three workflows on itself, chosen as genuinely useful for a small plugin project (not as a showcase of everything in the catalog):

| Workflow | Trigger | Purpose |
|---|---|---|
| [daily-repo-status](.github/workflows/daily-repo-status.md) | Daily | Opens a `[repo-status]` issue summarizing recent activity — the recommended first-run starter |
| [update-docs](.github/workflows/update-docs.md) | Daily + manual | Detects documentation drift and opens draft PRs to keep docs in sync with code changes |
| [weekly-research](.github/workflows/weekly-research.md) | Weekly (Monday) | Strategic research across Anthropic policy, plugin ecosystem, gh-aw upstream, competitors, and solo-founder hiring signal |

All three use `engine: claude` and are pre-configured with the [OAuth token tweak](skills/install-workflow/auth.md). The agent-team pattern under [catalog/agent-team/](catalog/agent-team/README.md) is *not* installed here — it lives in a separate playground repo, since running it here would aim the implementer agent at this repo's own code.

Other workflows from the catalog — `repo-assist`, `q`, `pr-nitpick-reviewer`, `daily-plan`, `markdown-linter` — are valuable on the right repo but were dropped here as too heavy or low-signal for a small solo-maintained plugin. All remain a `/install-workflow` away.

## Multi-workflow patterns

Beyond the one-workflow-per-job templates above, this repo ships reference patterns for **multiple workflows collaborating** via the GitHub issue thread as an event bus:

- **[agent-team](catalog/agent-team/README.md)** — four roles (spec → plan → impl → review) coordinating through structured comment blocks and a small internal label state machine. Install all four in one pass with `/install-agent-team`; dispatch tasks by opening an issue and adding a single `agent-team` label. Use when you want visible handoffs, human override between steps, and an audit trail per task.

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
  install-agent-team/
    SKILL.md                       # /install-agent-team unified installer (all 4 roles + labels + auth)

catalog/
  agent-team/                      # multi-workflow pattern: spec → plan → impl → review
    README.md                      # label/comment contract + install steps
    spec-agent.md
    planner-agent.md
    implementer-agent.md
    reviewer-agent.md

.github/
  agents/
    agentic-workflows.agent.md     # dispatcher agent for workflow operations
  aw/
    actions-lock.json              # gh-aw extension version lock
  workflows/
    agentics-maintenance.yml       # standard GHA workflow: gh-aw version maintenance
    copilot-setup-steps.yml        # standard GHA workflow: Copilot coding agent environment setup
    daily-repo-status.{md,lock.yml}
    update-docs.{md,lock.yml}
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

## Releases

See the [Releases tab](https://github.com/verkyyi/github-agent-runner/releases) for tagged versions and changelogs. Auto-discovered by [claude-plugins.dev](https://claude-plugins.dev); also listed on [ClaudePluginHub](https://claudepluginhub.com).

## Credits

This plugin is built on two open-source projects from the [GitHub Next](https://githubnext.com) team:

- **[github/gh-aw](https://github.com/github/gh-aw)** — the agentic workflow compiler. Every workflow this plugin installs is a gh-aw `.md` source compiled by `gh aw add` / `gh aw compile`. Maintained by [@pelikhan](https://github.com/pelikhan), [@dsyme](https://github.com/dsyme), and others.
- **[githubnext/agentics](https://github.com/githubnext/agentics)** — the curated workflow catalog. `/discover-workflows` surfaces entries from this repo; every dogfooded workflow in `.github/workflows/` traces back to a source `.md` at `githubnext/agentics/workflows/`. The `shared/reporting.md` component under `.github/workflows/shared/` is also pulled from agentics and included verbatim.

Pattern inspiration from **[superpowers](https://github.com/obra/superpowers)** by [@obra](https://github.com/obra) — our agent-team spec → plan → impl → review loop mirrors the superpowers skill loop, reimplemented inline for headless gh-aw execution.
