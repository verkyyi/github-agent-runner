---
name: install-workflow
description: Install a gh-aw workflow into the current repo, including auth setup. Use when the user has picked a workflow (often after /github-agent-runner:discover-workflows) and wants it wired up, or types /github-agent-runner:install-workflow.
---

# github-agent-runner: install-workflow

Install one workflow from the catalog into the current repo, end to end: fetch, configure auth, commit, verify.

## Flow

1. Resolve the workflow name against `../discover-workflows/catalog.md`. If the user didn't name one, suggest running `/github-agent-runner:discover-workflows` first and stop.
2. Check prerequisites: `gh` CLI authenticated, `gh aw` extension installed, write access to the repo. Surface missing pieces plainly; don't try to install tools on the user's behalf.
3. Pick auth path and set the secret — see `auth.md`. Ask once: subscription or API key? Then for OAuth path guide the user through `claude setup-token` + `gh secret set CLAUDE_CODE_OAUTH_TOKEN`; for API-key path, `gh secret set ANTHROPIC_API_KEY`.
4. Run `gh aw add <workflow>` — compiles the `.lock.yml`.
5. **If OAuth path**: apply the post-compile tweak from `auth.md` Step 3 (two-pass sed — never skip the `--exclude-env` carve-out). Verify with the grep counts in `auth.md` Step 4.
6. Run `gh aw validate` (safe — does not recompile).
7. Summarize what changed (files added, secret set, tweak applied if applicable). Remind: `gh aw compile` reverts the tweak — re-apply on every recompile.

## Hard rules

- Never write workflow YAML by hand. Always delegate to `gh aw add`. If `gh aw` can't produce the result, the workflow isn't in the catalog.
- Never commit or push without explicit user confirmation. Workflows run on push — users must opt in deliberately.
- Never store or echo the user's auth token. Hand the user a `gh secret set` command to run themselves, or use `gh` to set it via stdin without echoing.
- When applying the OAuth tweak, never skip the `--exclude-env ANTHROPIC_API_KEY` carve-out. The blanket sed-replace strips the token from the sandbox and breaks auth (`"Not logged in"`). See `auth.md` for the two-pass pattern.
- Never run `gh aw compile` silently after the tweak is applied; it reverts the tweak. If recompilation is needed, re-apply Steps 5 from the flow before committing.

## Out of scope for v0.1

- Uninstalling workflows
- Updating installed workflows
- Installing into repos other than the current working directory
