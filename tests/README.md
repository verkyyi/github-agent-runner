# Tests

Fast tests for the github-agent-runner skills, modeled on the
[superpowers][sp] plugin's test suite.

[sp]: https://github.com/obra/superpowers/tree/main/tests/claude-code

Each test invokes Claude Code headlessly (`claude -p`) with a question
about one of the skills, then asserts patterns against the response. If a
future edit removes a critical instruction or introduces contradictions,
Claude's description of the skill will drift and the assertion fails.

## Requirements

- Claude Code CLI on `PATH` (`claude --version` works)
- Valid Claude auth (ambient OAuth or `ANTHROPIC_API_KEY`)

The runner passes `--plugin-dir <repo-root>` to every `claude` invocation,
so you don't need to install the plugin via marketplace first.

## Running

```bash
./tests/run-tests.sh                    # run all fast tests
./tests/run-tests.sh --verbose          # show per-assertion output
./tests/run-tests.sh --test test-install-workflow.sh
./tests/run-tests.sh --timeout 600      # per-test timeout in seconds
```

Exit code 0 = all tests passed. Non-zero = at least one failed.

## CI

[`.github/workflows/ci-tests.yml`](../.github/workflows/ci-tests.yml) runs tier-2 invariants + the three tier-1 skill tests on every PR and on pushes to `main`. Fork PRs fail the tier-1 step (GitHub doesn't leak `CLAUDE_CODE_OAUTH_TOKEN` to fork-originated runs) — maintainers cherry-pick fork changes onto a branch in this repo to get a clean pass.

Tier-3 tests stay out of CI: `test-e2e*.sh` costs real wall-time and (for `test-e2e-install-*.sh`) needs `gh` admin scopes we don't want to grant CI. Run them manually before releases.

## Expected runtime

~3-8 prompts per test file × ~30s each = roughly **4-5 minutes total**.
Each run burns modest tokens against your Claude account.

## What's covered

| Tier | Test file | Verifies | Speed |
|---|---|---|---|
| 2 | `test-invariants.sh` | Grep / filesystem invariants tied to specific past bugs: forbidden stale phrases, required remediation text, file-existence consistency, version alignment. Each invariant carries a commit-sha comment explaining why it exists. No Claude invocation. | <1s |
| 1 | `test-discover-workflows.sh` | Skill loads; mentions `githubnext/agentics`; runtime fetch (no static catalog); fail-stop on upstream error | ~1min |
| 1 | `test-install-workflow.sh`   | Skill loads; mentions `gh aw add` + `gh secret set`; documents both auth paths; understands the `--exclude-env` carve-out; hard rules (never writes YAML by hand, never stores tokens) | ~2min |
| 1 | `test-install-agent-team.sh` | Skill loads; pitches the four roles (spec/plan/impl/review); one-label dispatch via `agent-team`; atomic install (all-or-nothing); auth wired once; OAuth tweak applied to every lockfile; creates the `state:*` label set; inherits the no-hand-written-YAML / no-token-echo hard rules | ~2min |
| 3 | `test-e2e.sh` (opt-in) | Real pipeline run on `verkyyi/agent-team-playground`: opens a unique canned issue, labels `agent-team`, polls until terminal state, asserts PR exists with `Closes #N` + test-status section + reviewer verdict + pipeline-summary comment. Collects per-stage timings and compares to last run — yellow flag if any stage or total wall-clock exceeds 150% of baseline. **Never** in the runner — invoke directly: `./tests/test-e2e.sh` (see below). | ~20-35min |
| 3-skill | `test-e2e-install-workflow.sh` (opt-in, destructive) | Skill E2E for `/install-workflow`: `gh repo create`s a throwaway private repo, pre-seeds the OAuth secret from SSM, invokes the skill via `claude -p --plugin-dir <repo>` with a target workflow (default `daily-repo-status`). Asserts the `.md` + `.lock.yml` are committed, frontmatter has `engine: claude` + `source: githubnext/agentics`, the two-pass OAuth tweak was correctly applied (API≥2, OAUTH≥5, `--exclude-env ANTHROPIC_API_KEY` preserved), and skill printed its completion marker. Single-workflow path is the plugin's core; test exercises Step-5's engine-fix-and-recompile flow since upstream agentics omits `engine:`. Deletes the repo on success (`--keep` to retain). | ~2-4min |
| 3-skill | `test-e2e-install-agent-team.sh` (opt-in, destructive) | Skill E2E for `/install-agent-team` (the multi-workflow installer). Same throwaway-repo pattern: asserts all four workflows committed + OAuth tweak on every lockfile + all seven labels created + skill printed its completion marker. | ~5-8min |

**Tier philosophy**:
- **Tier 2** — add invariants only when a bug is caught in review, not preemptively. Each assertion should be linkable to a specific past commit.
- **Tier 3** — truth source for emergent behavior (handoff breakage, timing drift, end-to-end correctness). Costs real wall-time and Claude tokens; run manually before releases or on a weekly cron.

Exit codes from `test-e2e.sh`: `0` = green, `1` = red (hard failure — pipeline stalled, missing PR, missing verdict marker), `2` = yellow (regression vs. baseline or non-approve verdict, no hard failure).

## Running tier-3

```bash
# Run once against the current playground state (manual, ~20-35 min):
./tests/test-e2e.sh

# Test an unmerged catalog change on a PR branch (reinstalls workflows
# on the playground from the branch, runs the canned task, optionally
# restores the playground to main after):
git push origin my-feature-branch
./tests/test-e2e.sh --install-from-ref my-feature-branch --restore-after main

# Against a different playground:
PLAYGROUND=<owner>/<repo> PLAYGROUND_DIR=/path/to/clone ./tests/test-e2e.sh

# Tighten the yellow-band threshold (default: 150% of last run):
YELLOW_MULTIPLIER=130 ./tests/test-e2e.sh
```

`--install-from-ref` is the pre-merge knob: edits to `catalog/agent-team/*.md` only reach the playground after `gh aw add`, so plain `test-e2e.sh` exercises whatever's currently installed, not your working tree. Push your branch and pass `--install-from-ref <branch>` to test the PR version against the live playground.

Each run appends to `tests/e2e-history.jsonl` (committed). The first run has no baseline — it establishes one. Every subsequent run flags yellows against the immediately prior entry.

### Skill E2E (pre-merge verification of skill edits)

`test-e2e.sh` tests already-installed workflows; it doesn't exercise the install **skills**. Two separate skill-E2E scripts cover the two install surfaces:

```bash
# For PRs that edit skills/install-workflow/SKILL.md — the single-workflow
# installer (plugin core path). Default target: daily-repo-status.
./tests/test-e2e-install-workflow.sh
./tests/test-e2e-install-workflow.sh --workflow update-docs   # alternate target

# For PRs that edit skills/install-agent-team/SKILL.md — the multi-workflow
# installer (agent-team pattern).
./tests/test-e2e-install-agent-team.sh
```

Both scripts follow the same pattern: provision a fresh private throwaway repo, pre-seed the OAuth secret from SSM, invoke the skill via `claude -p --plugin-dir $REPO_ROOT`, assert the remote end-state, delete the repo on success. `--keep` retains the repo for post-mortem.

**What neither exercises**: the `claude setup-token` interactive browser step (headless-hostile by design — see `skills/install-workflow/auth.md`). The test pre-sets the secret and the skill's `gh secret list` check skips the setup flow.

**Destructive**: creates a private repo each run, deletes it on success.

## What's NOT covered (deferred)

- **Per-run provisioning** — each tier-3 run reuses the playground; a truly clean-slate install-from-nothing test (verifies `/install-agent-team` itself, not just the running pipeline) would need `gh repo create` + full install every time. Expensive and not yet warranted.
- **Plugin-manifest JSON validity** — not covered here; `claude -p`
  will itself fail to load the plugin if the manifest is malformed, so
  bad JSON surfaces as test failures indirectly.

## Adding a test

1. Create `test-<skill-name>.sh` in this directory.
2. Source `test-helpers.sh` and use `run_claude` + `assert_contains` /
   `assert_not_contains` / `assert_order` to verify behavior.
3. Add the file name to the `tests=()` array in `run-tests.sh`.
4. Make it executable: `chmod +x test-<skill-name>.sh`.

Pattern arguments are `grep -E` regex; use `|` for alternation.
