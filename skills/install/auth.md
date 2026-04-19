# Auth decision tree

STUB — BLOCKED on auth research (memo: 2026-04-19, task 1).

This is the step that differentiates sidekick from `gh aw add`. The shape of this file depends on the answer to one question:

> Under Anthropic's current ToS, can a Claude Pro/Max subscriber use their subscription OAuth token from a GitHub Actions workflow running in their own repo?

## If YES (with or without caveats)

Branches to design:

- User on Pro → OAuth flow, capture token, `gh secret set CLAUDE_CODE_OAUTH_TOKEN`, note rate-limit implications
- User on Max → same as Pro, note higher limits
- User on neither / unsure → detection flow, pitch subscription vs. API key tradeoff

## If NO (flat ban on subscription OAuth in CI)

Branches simplify to API key only:

- Walk user through creating `ANTHROPIC_API_KEY`
- Explain spend caps: `gh aw` supports `max-turns` and `stop-after` — set conservative defaults
- Project monthly cost based on workflow frequency and model choice
- Offer to add a budget-alert workflow

## Research sources to consult (do this first)

- `anthropics/claude-code-action` issues, search: `oauth`, `subscription`, `max`, `pro`
- `anthropics/claude-code` issues #43333, #37686, #32286, #3040
- Anthropic ToS + Usage Policy, changes since 2025-11
- Community posts from last 30 days about subscription-backed GHA

## Do not fill in this file until the research is done

Writing branches against an assumption and then reversing them later is worse than an empty stub. Leave it.
