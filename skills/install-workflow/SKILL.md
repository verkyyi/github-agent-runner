---
name: install-workflow
description: Install a gh-aw workflow into the current repo, including auth setup. Use when the user has picked a workflow (often after /discover-workflows) and wants it wired up, or types /install-workflow.
---

# install-workflow

Install one workflow from the upstream `githubnext/agentics` catalog into the current repo, end to end: fetch, configure auth, commit, verify.

## Flow

1. If the user didn't name a workflow, pitch `daily-repo-status` as the recommended starter — it creates a daily GitHub issue summarizing repo activity, needs only read + issue-create permissions, and gives visible value on the first run. Offer to proceed with it, or run `/discover-workflows` for the full catalog. Otherwise, treat the name as a workflow in `githubnext/agentics/workflows/` — `gh aw add <workflow>` in Step 4 will fail cleanly if the name doesn't resolve.
2. Check prerequisites:
   - `gh` CLI authenticated (`gh auth status`)
   - `gh aw` extension installed (`gh extension list | grep gh-aw`)
   - Write access to the repo (`gh repo view --json viewerPermission`)
   - **`workflow` scope present on the `gh` token** — check via `gh auth status -t 2>&1 | grep -i 'token scopes'` or inspect the scopes line. Without it, the user's first `git push` of the generated `.lock.yml` will fail with *"refusing to allow an OAuth App to create or update workflow ... without `workflow` scope"*. If missing, have the user run `gh auth refresh -s workflow -h github.com` (one-line fix, opens a browser auth flow for the scope bump) before proceeding.

   Surface missing pieces plainly; don't try to install tools on the user's behalf.
3. Pick auth path and set the secret — see `auth.md`. Ask once: subscription or API key? Before asking, check `gh secret list` — if the matching secret already exists, skip the setup and use it. Otherwise, for OAuth path guide the user through `claude setup-token` + `gh secret set CLAUDE_CODE_OAUTH_TOKEN`; for API-key path, `gh secret set ANTHROPIC_API_KEY`.
4. Run `gh aw add <workflow>` — fetches source and compiles the `.lock.yml`. **The name must be fully qualified** as `githubnext/agentics/<workflow>` (bare names fail with "invalid workflow specification").
5. Inspect the fetched `.md` for an `engine:` field. Upstream agentics workflows that omit `engine:` default to the `copilot` engine — which ignores the Claude secret and won't use your auth. If missing, add `engine: claude` to the frontmatter and run `gh aw compile <workflow>` to regenerate the `.lock.yml`.
6. **If OAuth path**: apply the post-compile tweak from `auth.md` Step 3 (two-pass sed — never skip the `--exclude-env` carve-out). Verify with the grep counts in `auth.md` Step 4.
7. Run `gh aw validate` (safe — does not recompile).
8. Summarize what changed (files added, secret set or reused, engine fix applied if needed, tweak applied if applicable). Remind: `gh aw compile` reverts the tweak — re-apply on every recompile.

## Hard rules

- Never write workflow YAML by hand. Always delegate to `gh aw add`. If `gh aw` can't produce the result, the workflow isn't in the upstream catalog.
- Never commit or push without explicit user confirmation. Workflows run on push — users must opt in deliberately.
- Never store or echo the user's auth token. Hand the user a `gh secret set` command to run themselves, or use `gh` to set it via stdin without echoing.
- When applying the OAuth tweak, never skip the `--exclude-env ANTHROPIC_API_KEY` carve-out. The blanket sed-replace strips the token from the sandbox and breaks auth (`"Not logged in"`). See `auth.md` for the two-pass pattern.
- Never run `gh aw compile` silently after the tweak is applied; it reverts the tweak. If recompilation is needed, re-apply Step 5 from the flow before committing.

## Out of scope for v0.1

- Uninstalling workflows
- Updating installed workflows
- Installing into repos other than the current working directory
