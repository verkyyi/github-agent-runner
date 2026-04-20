# Curated workflow catalog

7 hand-picked entries from [`githubnext/agentics`](https://github.com/githubnext/agentics/tree/main/workflows).
All require Claude auth — see `../install-workflow/auth.md` for the OAuth vs API-key decision.

---

## issue-triage

- **Upstream source**: `githubnext/agentics/workflows/issue-triage.md`
- **One-line purpose**: Labels new issues, detects spam, and posts an analysis comment with debugging tips and reproduction steps — automatically, the moment an issue lands.
- **Fits repos that**: receive issues regularly; have a label set already defined; maintainers who are time-poor and want triage handled before they even look at their inbox.
- **Setup friction**: low — one secret (Claude auth), no YAML to edit; customize the prompt body after install if you want custom label logic.
- **Auth requirement**: either

---

## pr-nitpick-reviewer

- **Upstream source**: `githubnext/agentics/workflows/pr-nitpick-reviewer.md`
- **One-line purpose**: On-demand nitpicky code review (style, naming, complexity, test gaps) triggered by a `/nit` slash command on any PR.
- **Fits repos that**: have active PR flow; want a second set of eyes on style points that linters miss; already do code review but want the small stuff caught automatically.
- **Setup friction**: low — one secret (Claude auth), slash-command trigger so it never runs unsolicited.
- **Auth requirement**: either

---

## markdown-linter

- **Upstream source**: `githubnext/agentics/workflows/markdown-linter.md`
- **One-line purpose**: Runs Super Linter against all Markdown files on a weekday schedule and files a structured issue when violations are found.
- **Fits repos that**: have docs, READMEs, or wiki-style Markdown; care about consistent formatting; want documentation quality tracked automatically.
- **Setup friction**: low — one secret (Claude auth), schedule runs automatically; no extra config needed.
- **Auth requirement**: either

---

## pr-fix

- **Upstream source**: `githubnext/agentics/workflows/pr-fix.md`
- **One-line purpose**: Analyzes CI failures in a PR, implements a fix, and pushes the corrected commit — invoked via `/pr-fix` slash command.
- **Fits repos that**: have CI (tests, linters, type-checks); contributors whose PRs sometimes get stuck on red CI; maintainers who want to unblock PRs without context-switching.
- **Setup friction**: medium — one secret (Claude auth) plus `push-to-pull-request-branch` permission; review the pushed fix before merging.
- **Auth requirement**: either

---

## weekly-issue-summary

- **Upstream source**: `githubnext/agentics/workflows/weekly-issue-summary.md`
- **One-line purpose**: Posts a weekly GitHub Discussion with issue-activity trend charts (opened vs closed, resolution time) and actionable recommendations.
- **Fits repos that**: have a `Discussions` feature enabled and an `audits` category; track issues actively; want a team-visible pulse on backlog health every Monday.
- **Setup friction**: medium — one secret (Claude auth) plus Discussions must be enabled; create an `audits` discussion category if it doesn't exist.
- **Auth requirement**: either

---

## daily-malicious-code-scan

- **Upstream source**: `githubnext/agentics/workflows/daily-malicious-code-scan.md`
- **One-line purpose**: Scans all commits from the last 3 days for secret-exfiltration patterns, out-of-context code, obfuscation, and supply-chain red flags; surfaces findings as GitHub code-scanning alerts.
- **Fits repos that**: accept third-party contributions; care about supply-chain security; want threat detection without paying for a dedicated SAST tool.
- **Setup friction**: low — one secret (Claude auth); findings appear in the Security tab automatically.
- **Auth requirement**: either

---

## daily-repo-status

- **Upstream source**: `githubnext/agentics/workflows/daily-repo-status.md`
- **One-line purpose**: Creates a daily GitHub issue summarizing recent activity (issues, PRs, releases, code changes) with productivity insights and recommended next steps.
- **Fits repos that**: have a small team or solo maintainer who wants a morning briefing; track multiple concurrent workstreams; close older status issues automatically.
- **Setup friction**: low — one secret (Claude auth), fully automatic once installed.
- **Auth requirement**: either
