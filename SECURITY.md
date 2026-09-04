# Security Policy

## Supported version

Security fixes are considered only for the latest commit on the default branch. This project is a personal reference implementation and does not promise production support or response-time guarantees.

## Reporting a vulnerability

Do not open a public issue containing a vulnerability, Runtime API Key, Tunnel ID, private file content, repository URL, username, email address, or local path.

Until a dedicated private reporting channel is published, create a minimal public issue asking the maintainer for a private contact method. Do not include exploit details or secrets in that issue.

If a credential or Tunnel ID has already been exposed, revoke or replace it before reporting the problem.

## Security boundaries

- Configure `LOCAL_OPS_ROOT` as one narrow, backed-up project directory. Never use a drive root, home directory, system directory, or secrets directory.
- File deletion and overwriting can cause permanent data loss. Review tool calls and keep versioned backups.
- Remote Git tools contact external systems using credentials already available on the computer. They are disabled by default and should be enabled only when needed.
- Do not use Local Ops with an untrusted repository. Git configuration, attributes, filters, and fetched content can introduce behavior outside this project's direct control.
- The project has automated tests but has not undergone an independent professional security audit.
