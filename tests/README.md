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

**Tier-2 philosophy**: add invariants only when a bug is caught in review, not preemptively. Each assertion should be linkable to a specific past commit or regression — otherwise it's maintenance drag without evidence of value. Tier-3 (end-to-end dogfood on the playground repo) remains the truth source for emergent behavior; tier-2 prevents regression of known-fixed bugs.

## What's NOT covered (deferred)

- **Integration tests** — real `gh aw add` against a fixture repo,
  real secret setting, real workflow compile. Slow, flaky, high setup
  cost. Not worth it until distribution picks up.
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
