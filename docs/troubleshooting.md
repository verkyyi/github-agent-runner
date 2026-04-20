# Troubleshooting

Quick diagnostics for the most common issues with `github-agent-runner` and the workflows it installs.

---

## Prerequisites not met

### `gh: command not found`

Install the GitHub CLI: https://cli.github.com/manual/installation

Then authenticate:

```bash
gh auth login
```

### `gh aw: unknown command`

Install the `gh-aw` extension:

```bash
gh extension install githubnext/gh-aw
```

### Plugin not loading in Claude Code

Verify the plugin manifest is reachable from Claude Code:

```bash
ls .claude-plugin/plugin.json   # from repo root
```

If running locally, launch with `claude --plugin-dir .` from the repository root.

---

## Auth issues — OAuth path

### `Not logged in · Please run /login`

**Cause**: Over-tweaked lock file. Pass 2 of the sed sequence was skipped, so `--exclude-env CLAUDE_CODE_OAUTH_TOKEN` stripped the OAuth token from the inner sandbox before `claude` could see it.

**Fix**: Re-run Pass 2 only:

```bash
sed -i 's/--exclude-env CLAUDE_CODE_OAUTH_TOKEN/--exclude-env ANTHROPIC_API_KEY/g' \
  .github/workflows/<workflow>.lock.yml
```

Then verify:

```bash
grep -c ANTHROPIC_API_KEY .github/workflows/<workflow>.lock.yml   # expect 2
grep -c CLAUDE_CODE_OAUTH_TOKEN .github/workflows/<workflow>.lock.yml  # expect 9
```

If `ANTHROPIC_API_KEY` count is 0, re-apply [the full two-pass tweak](../skills/install-workflow/auth.md#step-3--apply-the-post-compile-tweak-to-every-lockyml).

### `authentication_failed` / HTTP 401 in workflow logs

**Cause**: The `CLAUDE_CODE_OAUTH_TOKEN` secret is expired, malformed, or set on the wrong repository.

**Fix**:

1. Regenerate a fresh token: `claude setup-token` (requires a real TTY, not piped)
2. Re-set the secret: `gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo <owner>/<repo>`
3. Confirm the secret name appears: `gh secret list --repo <owner>/<repo>`

### Tweak reverted after `gh aw compile` / `gh aw upgrade`

**Cause**: Expected behavior. `gh aw compile` regenerates `.lock.yml` from the `.md` source, which discards the tweak.

**Fix**: Re-apply [Steps 3–4 from auth.md](../skills/install-workflow/auth.md#step-3--apply-the-post-compile-tweak-to-every-lockyml) after any recompile event.

Commands that trigger a recompile: `gh aw compile`, `gh aw upgrade`, `gh aw fix`.

Commands that are safe: `gh aw validate` (never recompiles).

### `gh secret list` doesn't show `CLAUDE_CODE_OAUTH_TOKEN`

**Cause**: The secret was set on a different repository (a common mistake when working across forks or related repos).

**Fix**: Always use the explicit `--repo` flag:

```bash
gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo <owner>/<repo>
gh secret list --repo <owner>/<repo>
```

---

## Auth issues — API-key path

### Workflow runs but bills more tokens than expected

Review the `engine.max-turns` and `timeout-minutes` values in the workflow's `.md` source. These cap a single run's cost:

```yaml
---
engine: claude
engine.max-turns: 20
timeout-minutes: 15
---
```

Run `gh aw compile <workflow>` to regenerate the lock file after changing frontmatter. (No tweak needed for API-key path.)

---

## Workflow not running

### Workflow shows as skipped in GitHub Actions

An upstream job in the same workflow file failed before the `agent` job ran. Check the Actions tab for the failing job (e.g., a linter or setup step). Fix that job first — auth is never reached if the pipeline is skipped.

### Workflow never triggers

Verify the trigger configured in the `.md` source matches what you expect (e.g., `schedule`, `push`, `issues.labeled`). Compiled triggers live in the `on:` block of the `.lock.yml`. Use `gh aw validate` to check the file is structurally valid.

---

## Discovery issues

### `/discover-workflows` returns no recommendations

The skill fetches the upstream `githubnext/agentics` catalog at runtime. If the fetch fails (network error, rate limit, GitHub API issue), the skill stops rather than guessing. Retry after a moment. If the problem persists, check `gh api rate_limit` for rate-limit state.

### Recommendations don't seem relevant to this repo

The skill inspects repo shape signals: language files, test presence, CI configuration, recent activity. Ensure your repo has a non-empty commit history and standard file layout (e.g., `package.json` for Node, `pyproject.toml` for Python) so the detection heuristics have signal to work with.

---

## Installation issues

### `gh aw add` fails with permission error

Ensure you have write access to the target repository:

```bash
gh repo view <owner>/<repo> --json viewerPermission
```

The output should show `WRITE` or `ADMIN`.

### Lock file already exists

`gh aw add` may refuse to overwrite an existing `.lock.yml`. If reinstalling, remove the existing lock file first and re-run:

```bash
rm .github/workflows/<workflow>.lock.yml
gh aw add <workflow>
```

Then re-apply the OAuth tweak if applicable.

---

## Getting more help

- **auth.md** — complete OAuth and API-key flows with failure modes: [skills/install-workflow/auth.md](../skills/install-workflow/auth.md)
- **Tests README** — how the plugin's test suite is structured: [tests/README.md](../tests/README.md)
- **Issues** — open a bug report at `https://github.com/verkyyi/github-agent-runner/issues`
