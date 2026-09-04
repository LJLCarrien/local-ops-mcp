# Contributing

Thanks for helping improve Local Ops MCP.

## Before opening a change

1. Do not include Runtime API Keys, real Tunnel IDs, private repository URLs, personal paths, proxy ports, account details, screenshots, or logs containing private data.
2. Keep each pull request focused on one independently testable change.
3. Preserve the workspace boundary, fixed Git argument lists, safe default switches, output limits, and command timeouts.
4. Add or update tests whenever behavior changes.

## Validate locally

```powershell
npm test
git diff --check
```

Review the complete diff before committing. For security reports, follow [SECURITY.md](./SECURITY.md) instead of publishing exploit details in an issue.
