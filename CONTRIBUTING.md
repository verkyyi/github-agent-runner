# Contributing to github-agent-runner

Thanks for improving this plugin. This guide covers everything needed to add catalog entries, extend skills, or contribute fixes.

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

## How the plugin works

```
.claude-plugin/plugin.json      ← plugin manifest (name, version, description)
skills/
  discover-workflows/
    SKILL.md                    ← defines /discover-workflows
  install-workflow/
    SKILL.md                    ← defines /install-workflow
    auth.md                     ← data loaded by the skill at runtime
```

**Skill loading**: Claude Code reads each `SKILL.md` file's YAML frontmatter to register the skill. Because the skill names (`discover-workflows`, `install-workflow`) are unique across installed plugins, users invoke them with the short form (`/discover-workflows`). Prefix with the plugin name (`/github-agent-runner:discover-workflows`) only on collision. The `description` field in the frontmatter determines when Claude invokes the skill automatically based on user intent. The body of `SKILL.md` is the full instruction set for that skill.

**Data files** (`auth.md`) are not registered as skills — they are loaded by skills at runtime as plain markdown. Keep them colocated with the skill that owns them. The discovery skill does not use any local data file — it fetches `githubnext/agentics` at runtime.

**Reload**: Changes to `SKILL.md` files take effect on the next Claude Code session. Changes to `auth.md` take effect immediately within the current session because the install skill re-reads it on each invocation.

## What to contribute

### Improving discovery matching

The `discover-workflows` skill fetches the upstream `githubnext/agentics` catalog at runtime and matches workflows against the detected repo shape. There is no local catalog to edit; contributions go into `skills/discover-workflows/SKILL.md` and target one of:

- **Better repo-shape detection** — add signals the skill inspects (new language markers, framework fingerprints, CI conventions).
- **Better matching heuristics** — tighten the rules that decide which upstream workflow descriptions fit which repo shapes.
- **Error handling** — failure modes when the upstream fetch is slow, rate-limited, or blocked.

Test end-to-end against a real repo before opening a PR: run `/discover-workflows` on at least two different repo shapes and confirm the recommendations make sense for each.

### Adding a skill

1. Create `skills/<skill-name>/SKILL.md` with YAML frontmatter:

   ```markdown
   ---
   name: <skill-name>
   description: <one sentence — used for automatic invocation matching>
   ---

   # <skill-name>

   <instruction body>
   ```

2. The skill is invocable as `/<skill-name>` immediately on reload (or `/github-agent-runner:<skill-name>` if the short name collides with another plugin).
3. Colocate any data files the skill needs in `skills/<skill-name>/`.
4. Add hard rules and out-of-scope sections following the pattern in `discover-workflows/SKILL.md` and `install-workflow/SKILL.md`.

### Fixing existing skills

Edit the relevant `SKILL.md` or data file. Test by running the skill locally with `claude --plugin-dir .`. Describe what the skill did wrong and how the change fixes it in the PR body.

## Testing

The plugin ships a three-tier test suite under `tests/`. Run all fast tests before opening a PR:

```bash
./tests/run-tests.sh           # tier 2 (invariants) + tier 1 (skill tests)
./tests/run-tests.sh --verbose # show per-assertion output
```

| Tier | What it tests | Speed |
|---|---|---|
| 2 — Invariants | Grep/filesystem checks for known past bugs. No Claude invocation. | <1s |
| 1 — Skills | Headless `claude -p` invocations verifying skill load and instruction coverage. | ~4-5 min |
| 3 — E2E (opt-in) | Real pipeline runs on the playground repo. Run manually before releases. | 20-35 min |

CI ([`.github/workflows/ci-tests.yml`](.github/workflows/ci-tests.yml)) runs tier 2 + tier 1 on every PR and push to `main`.

For lock-file and OAuth-tweak changes, also run:

- **Validate lock files**: `gh aw validate` — safe, does not recompile.
- **Check grep counts**: see [skills/install-workflow/auth.md](skills/install-workflow/auth.md#step-4--verify-the-tweak-shape).

See [`tests/README.md`](tests/README.md) for full details, including tier-3 usage and requirements.

Never commit untested changes to `main`. The installed workflows run on push, so a broken skill or bad `.lock.yml` triggers a live workflow run.

## Workflow files

The `.github/workflows/` directory contains seven dogfooded workflows. These are managed by `gh aw` — do not edit `.lock.yml` files by hand except to apply the OAuth tweak described in [skills/install-workflow/auth.md](skills/install-workflow/auth.md).

If a workflow `.md` source needs changing:

1. Edit the `.md` file.
2. Run `gh aw compile <workflow>` to regenerate the `.lock.yml`.
3. Re-apply the OAuth tweak (Steps 3–4 from `auth.md`) before committing.
4. Run `gh aw validate` to confirm the generated file is valid.

## Submitting changes

1. Fork the repo and create a branch: `git checkout -b <type>/<short-description>`
2. Make changes and test locally.
3. Open a draft PR against `main`.
4. The `update-docs` workflow runs on a daily schedule (and is manually dispatchable via `gh workflow run update-docs.lock.yml`); it opens a follow-up PR when your change creates a documentation gap.

Branch naming conventions:

| Type | Prefix |
|---|---|
| New skill | `skill/<skill-name>` |
| Discovery-logic improvement | `discover/<short-description>` |
| Bug fix | `fix/<short-description>` |
| Documentation | `docs/<short-description>` |

## Publishing (maintainers only)

1. Bump the version in `.claude-plugin/plugin.json` (follows semver).
2. Create a GitHub Release tagged `v<version>` with a changelog entry. The marketplace JSON at `.claude-plugin/marketplace.json` references `main`, so existing installations pick up the new version automatically on next use.
3. Update the external registry listings:
   - **[claude-plugins.dev](https://claude-plugins.dev)** — update the plugin entry via the registry's contributor interface.
   - **[ClaudePluginHub](https://claudepluginhub.com)** — update via their contributor portal.

Registry credentials are held by the project owner.
