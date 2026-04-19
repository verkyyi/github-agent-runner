---
name: install
description: Install a gh-aw workflow into the current repo, including auth setup. Use when the user has picked a workflow (often after /sidekick:discover) and wants it wired up, or types /sidekick:install.
---

# sidekick: install

Install one workflow from the sidekick catalog into the current repo, end to end: fetch, configure auth, commit, verify.

## Flow

1. Resolve the workflow name against `../discover/catalog.md`. If the user didn't name one, suggest running `/sidekick:discover` first and stop.
2. Check prerequisites: `gh` CLI authenticated, `gh aw` extension installed, write access to the repo. Surface missing pieces plainly; don't try to install tools on the user's behalf.
3. Walk the auth decision tree — see `auth.md`. This is the step that differentiates sidekick from `gh aw add`.
4. Run `gh aw add <workflow>` under the hood. Show the command. Don't hide it.
5. Verify: `gh aw compile` succeeds, the generated `.lock.yml` exists, CI passes a dry run if possible.
6. Summarize what changed (files added, secrets needed, next action for the user).

## Hard rules

- Never write workflow YAML by hand. Always delegate to `gh aw add`. If `gh aw` can't produce the result, the workflow isn't in sidekick's catalog.
- Never commit or push without explicit user confirmation. Workflows run on push — users must opt in deliberately.
- Never store or echo the user's auth token. Hand the user a `gh secret set` command to run themselves, or use `gh` to set it via stdin without echoing.

## Out of scope for v0.1

- Uninstalling workflows
- Updating installed workflows
- Installing into repos other than the current working directory
