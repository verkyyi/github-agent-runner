# Auth decision tree

How the install-workflow skill picks and applies auth for a gh-aw workflow with `engine: claude`. Validated end-to-end 2026-04-19 against `verkyyi/github-agent-runner` and `verkyyi/agentfolio`.

## This is Anthropic's documented path — not a workaround

The OAuth path below uses `claude setup-token` to mint a long-lived `sk-ant-oat01-*` token and runs it through the official `@anthropic-ai/claude-code` CLI. This is the pattern Anthropic documents at [code.claude.com/docs/en/github-actions](https://code.claude.com/docs/en/github-actions) and explicitly permits under their Consumer Terms (updated 2026-02-20): subscription OAuth tokens are forbidden in *third-party* products, but the official CLI is on the permitted allow-list alongside Claude.ai and Claude Desktop.

What remains is a **gh-aw-specific implementation detail**: gh-aw's sandbox proxy (`awf`) strips subscription-scoped environment variables by default via `--exclude-env ANTHROPIC_API_KEY`. The post-compile tweak in Step 3 preserves that carve-out while letting `CLAUDE_CODE_OAUTH_TOKEN` through. It adjusts how gh-aw's own sandbox handles env vars — it does **not** circumvent Anthropic policy.

Two distinct concerns, often conflated:

| Concern | Status |
|---|---|
| *Can a Claude subscription OAuth token be used in GitHub Actions via the official CLI?* | **Yes, documented and permitted** by Anthropic. |
| *Does gh-aw natively plumb `CLAUDE_CODE_OAUTH_TOKEN` through its sandbox proxy without a post-compile tweak?* | **Not yet** (tracked in gh-aw issue #16498). The tweak below bridges this. |

## Decide the path

Ask the user (once per target repo):

> "Do you have a Claude Pro ($20), Max ($100), or Max ($200) subscription?"

- **Yes** → OAuth path (preferred — free for subscribers)
- **No / unsure** → API-key path (pay-per-token; set spend caps)
- **Both available** → OAuth path; fall back to API key if OAuth validation later fails

Never guess. Ask if ambiguous.

## OAuth path (preferred)

### Step 1 — generate the subscription OAuth token

The user runs, in a real TTY **on a machine with a browser available**:

```
claude setup-token
```

Opens browser auth flow, prints a token starting with `sk-ant-oat01-...`. The skill never sees the token.

**Do NOT run this inside**: headless containers / dev-containers without port forwarding, SSH sessions without browser forwarding, CI runners, or the Claude Code REPL itself — the command will silently hang waiting for a browser callback that never arrives. When in doubt, run it on the user's local laptop and paste the token into `gh secret set` in Step 2 (which can run anywhere, since stdin-piped secret values don't need a browser).

### Step 2 — set the repo secret

```
gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo <owner>/<repo>
```

User pastes the token when prompted (stdin, no echo). The skill confirms via `gh secret list` — the secret name should appear, but the value must stay unseen.

### Step 3 — apply the post-compile tweak to every `.lock.yml`

After `gh aw add <workflow>` (which auto-compiles), patch the generated `.lock.yml`:

```bash
# Pass 1: swap every ANTHROPIC_API_KEY to CLAUDE_CODE_OAUTH_TOKEN
sed -i 's/ANTHROPIC_API_KEY/CLAUDE_CODE_OAUTH_TOKEN/g' .github/workflows/<workflow>.lock.yml

# Pass 2: CRITICAL — revert the --exclude-env occurrences back to ANTHROPIC_API_KEY
sed -i 's/--exclude-env CLAUDE_CODE_OAUTH_TOKEN/--exclude-env ANTHROPIC_API_KEY/g' .github/workflows/<workflow>.lock.yml
```

**Why the carve-out is non-negotiable**: `--exclude-env <NAME>` tells the `awf` sandbox to strip `<NAME>` from the inner sandbox env. The original default excludes `ANTHROPIC_API_KEY` (a security default — the API proxy handles auth externally, no need to leak the secret into the inner sandbox). If you replace that one occurrence with `CLAUDE_CODE_OAUTH_TOKEN`, you strip your own OAuth token from the sandbox — the inner `claude` CLI then has no auth and fails with:

```
Not logged in · Please run /login
```

Leaving `--exclude-env ANTHROPIC_API_KEY` in place is a harmless no-op (the named var doesn't exist on the host) AND lets the real `CLAUDE_CODE_OAUTH_TOKEN` reach the CLI inside the sandbox.

### Step 4 — verify the tweak shape

Each tweaked `.lock.yml` should show:

```
$ grep -c ANTHROPIC_API_KEY <workflow>.lock.yml
2                                                 # only inside --exclude-env
$ grep -c CLAUDE_CODE_OAUTH_TOKEN <workflow>.lock.yml
9                                                 # everywhere else
```

If `ANTHROPIC_API_KEY` count is 0, you over-tweaked → the CLI will fail to auth. If it's >2, you under-tweaked → gh-aw will ask for an API key that isn't there.

### Step 5 — know the fragility

**`gh aw compile` regenerates `.lock.yml` from the `.md` source, reverting the tweak.** Other commands that trigger recompilation: `gh aw upgrade`, `gh aw fix`, and any workflow-source edit. The skill must re-apply Steps 3–4 after any recompile event.

`gh aw validate` does NOT regenerate `.lock.yml` — safe to run anytime.

## API-key path (fallback)

When the user isn't on a Claude subscription:

### Step 1 — provision the API key

Guide the user to console.anthropic.com → API Keys → Create. Name it something like `gh-aw-<repo>`.

### Step 2 — set the repo secret

```
gh secret set ANTHROPIC_API_KEY --repo <owner>/<repo>
```

### Step 3 — NO tweak needed

gh-aw's default `engine: claude` compilation already wires `ANTHROPIC_API_KEY`. Ship as-compiled.

### Step 4 — pitch spend caps

API-key path means every workflow run bills tokens. Before committing, help the user add:

- `engine.max-turns: 20` in frontmatter (caps a single run's turns)
- Conservative `timeout-minutes:` at workflow level
- Budget alert workflow (future — not v0.1)

## Why this is the official path (ToS specifics)

gh-aw doesn't call Anthropic's Messages API directly. Its compiled `.lock.yml` shells out to the official `@anthropic-ai/claude-code` npm CLI (version pinned in the lock, e.g. `2.1.98`). The CLI is on Anthropic's OAuth-eligible product allow-list alongside Claude.ai, Claude Desktop, and Claude Cowork (Anthropic Consumer Terms, "Except when you are accessing our Services via an Anthropic API Key **or where we otherwise explicitly permit it**"). Running the official CLI with a subscription OAuth token inside a GitHub Actions runner is the same pattern Anthropic documents at [code.claude.com/docs/en/github-actions](https://code.claude.com/docs/en/github-actions).

**Boundary that matters**: do NOT use the OAuth token to call the Messages API directly (`sk-ant-oat01-*` is rejected there per `anthropics/claude-code#37205`). The official CLI is the required intermediary.

## Upstream trajectory — what's a proxy issue vs. a policy issue

The two concerns separated at the top of this document have different trajectories:

**Anthropic-side (policy)**: stable. The February 2026 ToS update locked in what's permitted (official CLI with subscription OAuth) and what isn't (third-party products with subscription OAuth). No indication of further tightening that affects the official-CLI path.

**gh-aw-side (proxy implementation)**: open. gh-aw had native `CLAUDE_CODE_OAUTH_TOKEN` support via `AlternativeSecrets` until PR #16757 removed it on 2026-02-19. Issue #16498 tracks re-introduction; maintainer @dsyme left the door open for "legitimate automated OIDC techniques." PR #20473 (merged 2026-03-11) added `AuthDefinition` scaffolding that could host proper OAuth re-enablement. Until that lands, the post-compile tweak bridges gh-aw's sandbox proxy for us — no Anthropic-level change required.

## Failure modes and what they mean

| Symptom | Likely cause | Fix |
|---|---|---|
| `Not logged in · Please run /login` in agent log | Over-tweaked — `--exclude-env CLAUDE_CODE_OAUTH_TOKEN` strips token from sandbox | Run Step 3 Pass 2 |
| `authentication_failed` / 401 in agent log | Token expired or malformed; wrong secret in repo | User runs `claude setup-token` again, re-sets secret |
| Workflow skipped `agent` job | Upstream job failed (e.g. super-linter) — auth never reached | Fix upstream job first |
| `gh aw compile` reverted the tweak | Expected | Re-run Step 3 |
| `gh secret list` doesn't show CLAUDE_CODE_OAUTH_TOKEN | User set it on the wrong repo | Verify with `--repo <owner>/<repo>` flag |
