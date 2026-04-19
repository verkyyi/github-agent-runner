# github-agent-runner

Host repo for the **sidekick** Claude Code plugin.

- Plugin manifest: `.claude-plugin/plugin.json`
- Skills: `skills/discover/`, `skills/install/`
- Status: v0.1, pre-scope-lock. See memos/notes in session history.

Invocation (once published): `/sidekick:discover` and `/sidekick:install`.

## Local install for development

```
claude --plugin-dir .
```

## Publishing

Submit via `claude.ai/settings/plugins/submit` or `platform.claude.com/plugins/submit` once v0.1 is ready.
