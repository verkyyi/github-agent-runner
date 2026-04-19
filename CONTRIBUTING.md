# Contributing to sidekick

Thanks for improving sidekick. This guide covers everything needed to add catalog entries, extend skills, or contribute fixes.

## Prerequisites

- [Claude Code](https://claude.ai/code) CLI installed and authenticated
- `gh` CLI authenticated (`gh auth login`)
- `gh aw` extension installed (`gh extension install githubnext/gh-aw`)
- Write access to your fork

## Development setup

```bash
git clone https://github.com/verkyyi/github-agent-runner
cd github-agent-runner
claude --plugin-dir .
```

`--plugin-dir .` tells Claude Code to load the plugin manifest from `.claude-plugin/plugin.json` and discover skills in `skills/*/SKILL.md`. The plugin runs entirely locally — no build step, no compilation.

### VS Code + GitHub Copilot

If you use VS Code, two configuration files activate automatically when you open the repository:

- `.vscode/mcp.json` — registers `gh aw mcp-server` as an MCP server named `github-agentic-workflows`, giving Copilot Agent access to gh-aw tooling without any manual setup.
- `.vscode/settings.json` — enables GitHub Copilot for Markdown files so you get completions and inline chat while editing skill and workflow sources.

No manual activation is needed.

## How the plugin works

```
.claude-plugin/plugin.json      ← plugin manifest (name, version, description)
skills/
  discover/
    SKILL.md                    ← defines /sidekick:discover
    catalog.md                  ← data loaded by the skill at runtime
  install/
    SKILL.md                    ← defines /sidekick:install
    auth.md                     ← data loaded by the skill at runtime
```

**Skill loading**: Claude Code reads each `SKILL.md` file's YAML frontmatter to register the skill under `/sidekick:<name>`. The `description` field in the frontmatter determines when Claude invokes the skill automatically based on user intent. The body of `SKILL.md` is the full instruction set for that skill.

**Data files** (`catalog.md`, `auth.md`) are not registered as skills — they are loaded by skills at runtime as plain markdown. Keep them colocated with the skill that owns them.

**Reload**: Changes to `SKILL.md` files take effect on the next Claude Code session. Changes to data files (`catalog.md`, `auth.md`) take effect immediately within the current session because skills re-read them on each invocation.

## What to contribute

### Adding catalog entries

The catalog at `skills/discover/catalog.md` is the core product value of sidekick. It currently contains 7 curated entries. Before adding a new entry:

1. Find the workflow in the [`githubnext/agentics`](https://github.com/githubnext/agentics) catalog.
2. Install it locally with `gh aw add <workflow>` and verify it works end-to-end.
3. Determine the correct auth requirement by checking whether the `.lock.yml` uses `engine: claude` (needs the OAuth tweak) or a different engine (may differ).

Each entry must use the template defined in `catalog.md`:

```markdown
## <workflow-name>

- **Upstream source**: `<path-in-githubnext/agentics>` or URL
- **One-line purpose**: <what it does for the repo owner>
- **Fits repos that**: <concrete signals — e.g. "have a `tests/` directory", "use pnpm">
- **Setup friction**: low / medium / high
- **Auth requirement**: OAuth path / API-key path / either
```

Quality over quantity. Aim for entries you would personally recommend, not an exhaustive list.

### Adding a skill

1. Create `skills/<skill-name>/SKILL.md` with YAML frontmatter:

   ```markdown
   ---
   name: <skill-name>
   description: <one sentence — used for automatic invocation matching>
   ---

   # sidekick: <skill-name>

   <instruction body>
   ```

2. The skill is invocable as `/sidekick:<skill-name>` immediately on reload.
3. Colocate any data files the skill needs in `skills/<skill-name>/`.
4. Add hard rules and out-of-scope sections following the pattern in `discover/SKILL.md` and `install/SKILL.md`.

### Fixing existing skills

Edit the relevant `SKILL.md` or data file. Test by running the skill locally with `claude --plugin-dir .`. Describe what the skill did wrong and how the change fixes it in the PR body.

## Testing

There is no automated test harness for skills — they are instruction sets interpreted by Claude Code, not code with unit tests. The validation steps are:

1. **Load the plugin**: `claude --plugin-dir .` — confirm no startup errors.
2. **Run the skill manually**: invoke `/sidekick:discover` or `/sidekick:install` and walk through the flow.
3. **Validate lock files** (if you changed `.lock.yml` files): `gh aw validate` — safe, does not recompile.
4. **Check grep counts** (if you applied the OAuth tweak): see [skills/install/auth.md](skills/install/auth.md#step-4--verify-the-tweak-shape).

Never test by committing untested changes to `main`. The installed workflows run on push to `main`, so a broken install skill or a bad `.lock.yml` will trigger a live workflow run.

## Workflow files

The `.github/workflows/` directory contains seven dogfooded workflows. These are managed by `gh aw` — do not edit `.lock.yml` files by hand except to apply the OAuth tweak described in [skills/install/auth.md](skills/install/auth.md).

If a workflow `.md` source needs changing:

1. Edit the `.md` file.
2. Run `gh aw compile <workflow>` to regenerate the `.lock.yml`.
3. Re-apply the OAuth tweak (Steps 3–4 from `auth.md`) before committing.
4. Run `gh aw validate` to confirm the generated file is valid.

## Submitting changes

1. Fork the repo and create a branch: `git checkout -b <type>/<short-description>`
2. Make changes and test locally.
3. Open a draft PR against `main`. Draft PRs trigger the `pr-nitpick-reviewer` workflow on `/nit` — use it for style feedback before marking ready.
4. The `update-docs` workflow runs on every push to `main` and will open a follow-up PR if your change creates a documentation gap.

Branch naming conventions:

| Type | Prefix |
|---|---|
| New catalog entry | `catalog/<workflow-name>` |
| New skill | `skill/<skill-name>` |
| Bug fix | `fix/<short-description>` |
| Documentation | `docs/<short-description>` |

## Publishing (maintainers only)

See the [Publishing section of the README](README.md#publishing) for the steps to submit the plugin to the Claude plugin registry.
