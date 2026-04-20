---
name: install-agent-team
description: Install the full four-role agent-team pattern (spec → plan → impl → review) into the current repo as one unified setup. Use when the user wants an end-to-end agent pipeline driven by a single issue label, or types /install-agent-team.
---

# install-agent-team

Install all four agent-team workflows into the current repo in one pass: fetch, wire auth once, apply the OAuth tweak to every lockfile, create the labels, validate, commit.

The result: the user dispatches a task by adding a single `agent-team` label to any issue. The four agents coordinate across the thread via structured comments and a small internal state machine.

## When to use this

- User says "install agent-team", "set up the agent pipeline", "install the spec/plan/impl/review workflows", or similar.
- User types `/install-agent-team`.
- User has just heard about the pattern via `/discover-workflows` and asked to install it as a unit.

## When NOT to use this

- User wants a single workflow (e.g. `daily-repo-status`, `repo-assist`) — hand off to `/install-workflow` instead.
- User's repo has no tests AND they want PRs that check passing tests — warn them: the reviewer expects a runnable test command. Offer to install anyway with the caveat that the reviewer will note "no test infrastructure" on every PR.

## Flow

### 1. Explain what's about to happen

One paragraph: four workflows will be added, one auth secret will be set, seven labels will be created, nothing runs until the user opens an issue and adds `agent-team`. Ask for explicit confirmation to proceed. The user must opt in — workflows run on push.

### 2. Preflight

Check in parallel:

- `gh` CLI authenticated (`gh auth status`)
- **`workflow` scope present on the `gh` token** (`gh auth status -t 2>&1 | grep -i 'token scopes'`). Without it, the user's first `git push` of `.github/workflows/*.lock.yml` will fail with *"refusing to allow an OAuth App to create or update workflow ... without `workflow` scope"*. If missing, have the user run `gh auth refresh -s workflow -h github.com` (browser flow, ~30 sec) before continuing.
- `gh aw` extension installed (`gh extension list | grep gh-aw`)
- Current dir is a git repo clean enough to commit (`git status --porcelain`)
- User has write access to `origin` (`gh repo view --json viewerPermission`)
- Repo Actions settings allow PR creation. Warn the user this must be ON in Settings → Actions → General → "Allow GitHub Actions to create and approve pull requests". The skill cannot flip this.

If any check fails, surface it plainly. Don't install tools on the user's behalf.

### 3. Set up auth once

Pick the path per `skills/install-workflow/auth.md`:

- Ask once: "Claude Pro / Max subscription, or API key?"
- Check `gh secret list` first — if `CLAUDE_CODE_OAUTH_TOKEN` (OAuth) or `ANTHROPIC_API_KEY` (API) already exists, reuse it. Do not re-prompt.
- Otherwise guide the user through `claude setup-token` + `gh secret set CLAUDE_CODE_OAUTH_TOKEN`, or `gh secret set ANTHROPIC_API_KEY` directly.

Never echo or store the token. One secret covers all four workflows.

### 4. Install all four workflows

Run, in sequence (each `gh aw add` auto-compiles):

```bash
gh aw add verkyyi/github-agent-runner/catalog/agent-team/spec-agent.md@main
gh aw add verkyyi/github-agent-runner/catalog/agent-team/planner-agent.md@main
gh aw add verkyyi/github-agent-runner/catalog/agent-team/implementer-agent.md@main
gh aw add verkyyi/github-agent-runner/catalog/agent-team/reviewer-agent.md@main
```

If any fails, stop and surface the exact error — do not proceed with a partial install. The four are a unit; a half-installed pipeline dead-ends on the first handoff.

### 5. Apply the OAuth tweak (OAuth path only)

For each of the four `.lock.yml` files just generated, apply the two-pass sed from `skills/install-workflow/auth.md` Step 3. Then verify grep counts on each file per auth.md Step 4. API-key path skips this step entirely.

### 6. Create the labels

Create these labels (idempotent — ignore "already exists" errors):

```bash
gh label create agent-team              --color 7C3AED --description "Opt-in marker for the agent-team pipeline" --force
gh label create state:plan-needed       --color FEF08A --description "agent-team: ready for the planner" --force
gh label create state:impl-needed       --color FCD34D --description "agent-team: ready for the implementer" --force
gh label create state:review-needed     --color FDBA74 --description "agent-team: ready for the reviewer" --force
gh label create state:done              --color 86EFAC --description "agent-team: task approved by reviewer" --force
gh label create state:blocked           --color F87171 --description "agent-team: paused, human intervention required" --force
gh label create agent-team:reviewed     --color A7F3D0 --description "agent-team: PR has been reviewed" --force
```

(The implementer also adds an `agent-team` label to the PR it opens. Same label as the issue entry — one label, two roles: opt-in on issues, reviewer trigger on PRs.)

### 7. Validate

```bash
gh aw validate
```

Runs against all lock files. Safe (no recompile).

### 8. Summarize

Show the user, in this order:

- Four files added under `.github/workflows/` (name each `.md` + `.lock.yml` pair)
- Secret configured (name only, never value) or reused
- Tweak applied to N lock files (or "skipped — API-key path")
- Seven labels created (or "N already existed, skipped")
- **How to dispatch a task**: *"Open an issue describing what you want built. Add the `agent-team` label. Done."*
- Reminder: `gh aw compile` reverts the OAuth tweak. Re-apply on every recompile. `gh aw validate` is safe.

Then ask whether to commit and push. Do not commit without explicit confirmation.

## Hard rules

- **All or nothing**. If any of the four `gh aw add` calls fails, stop and back out. A half-installed pipeline is worse than none — users will dispatch tasks that stall silently.
- Never write the workflow YAML by hand. Always delegate to `gh aw add`. The `.md` sources live in this plugin's `catalog/agent-team/`.
- Never store or echo the auth token. Pipe through `gh secret set` stdin.
- Never skip the `--exclude-env ANTHROPIC_API_KEY` carve-out when applying the OAuth tweak. See `skills/install-workflow/auth.md` for why.
- Never commit or push without explicit user confirmation. Workflows run on push.
- Never install on top of an existing agent-team setup without asking. If `.github/workflows/spec-agent.lock.yml` already exists, ask before overwriting — the user may have customized it.

## User journey (for surfacing to the user)

After install, the entire per-task journey is:

1. User opens an issue describing a task.
2. User adds label `agent-team`.
3. Spec agent posts a spec comment → `state:plan-needed`.
4. Planner posts a plan comment → `state:impl-needed`.
5. Implementer opens a draft PR (`Closes #N`) → `state:review-needed` on the issue.
6. Reviewer posts a verdict on the PR → `state:done` (approve) or back to `state:impl-needed` (kickback, max 3 rounds).
7. User reviews the approved PR and merges. Agents never merge.

Escape hatches at any time: remove a state label to pause, edit a comment to steer the next agent, add `state:blocked` to halt.

## Out of scope for v0.1

- Uninstalling the pipeline (remove the four `.md`/`.lock.yml` files + labels manually)
- Cross-repo install
- Customizing max iterations without editing the workflow source
- Turning individual roles on/off — the four are designed to work as a unit
