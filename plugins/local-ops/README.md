# local-ops MCP

A minimal, dependency-free MCP server that lets ChatGPT manage files, directories, and local Git repositories inside one explicitly configured directory.

## Requirements

- Node.js 20 or newer
- ChatGPT desktop app with local MCP support

## Test

```powershell
npm test
```

## Install it as a ChatGPT desktop plugin

The repository root is also a local plugin. In ChatGPT desktop, open **Settings → Plugins**, choose **Browse directory**, and select this repository:

```text
<LOCAL_OPS_DIR>
```

Install or enable **Local Ops**, restart the app, and select Local Ops from the composer plugin/tool picker. The plugin's `.mcp.json` currently grants access to:

```text
<WORKSPACE_DIR>
```

Edit `LOCAL_OPS_ROOT` in `.mcp.json` before installation if a different directory should be accessible.

## Add only the MCP server to Codex

Open **Settings → MCP servers → Add server**, choose **STDIO**, and enter:

- Name: `local-ops`
- Command: `node`
- Arguments: the absolute path to `server.mjs`
- Environment variable: `LOCAL_OPS_ROOT` = the absolute directory Chat may access

Restart the Codex host and inspect its connected MCP servers to verify that these tools are present:

- `list_directory`, `read_file`, `write_file`
- `create_directory`, `delete_directory`
- `delete_file`, `copy_file`, `move_file`, `move_directory`, `rename_file`
- `git_status`, `git_diff_unstaged`, `git_diff_staged`, `git_log`
- `git_show`, `git_branch`, `git_add`, `git_commit`, `git_amend_message`
- `git_fetch`, `git_pull`, `git_push` when their remote switches are enabled

Chat mode in some desktop builds does not expose a `/mcp` slash command; install the plugin above for Chat mode.

Example `config.toml` entry:

```toml
[mcp_servers.local-ops]
command = "node"
args = ["C:\\absolute\\path\\to\\local-ops-mcp\\server.mjs"]
env = { LOCAL_OPS_ROOT = "D:\\Projects\\allowed-workspace", LOCAL_OPS_GIT_READ = "true", LOCAL_OPS_GIT_WRITE = "true", LOCAL_OPS_GIT_REMOTE = "false", LOCAL_OPS_GIT_FETCH = "true", LOCAL_OPS_GIT_PULL = "false", LOCAL_OPS_GIT_PUSH = "false" }
enabled_tools = ["list_directory", "read_file", "write_file", "create_directory", "delete_directory", "delete_file", "copy_file", "move_file", "move_directory", "rename_file", "git_status", "git_diff_unstaged", "git_diff_staged", "git_log", "git_show", "git_branch", "git_add", "git_commit", "git_amend_message", "git_fetch", "git_pull", "git_push"]
default_tools_approval_mode = "writes"
```

## Git support

Git must be installed and available on `PATH`. Repository paths are workspace-relative and the resolved repository must remain below `LOCAL_OPS_ROOT`.

`git_add` requires an explicit list of repository-relative paths, and `git_commit` commits only changes that are already staged. `git_amend_message` rewrites only the latest local commit message without including staged or working-tree changes; use it only before push or when history rewriting is explicitly intended. Checkout, reset, branch deletion, force push, remote branch deletion, arbitrary Git arguments, and general shell execution are not exposed.

Remote tools use existing configured remotes and the computer's Git Credential Manager or SSH credentials; they never accept credentials as tool input. `git_pull` always uses `--ff-only`. `git_push` sends only `HEAD` to the current branch's configured upstream using a non-force refspec. Network URLs and local remotes inside `LOCAL_OPS_ROOT` are allowed; local remotes outside the root are rejected.

Git commands time out after 30 seconds by default, and remote commands after 60 seconds. Override with `LOCAL_OPS_GIT_TIMEOUT_MS` and `LOCAL_OPS_GIT_REMOTE_TIMEOUT_MS`; command output shares the `LOCAL_OPS_MAX_BYTES` limit.

### Git switches

| Environment variable | Default | Controls |
| --- | --- | --- |
| `LOCAL_OPS_GIT_READ` | `true` | status, diff, log, show, branch |
| `LOCAL_OPS_GIT_WRITE` | `true` | add, commit, amend message |
| `LOCAL_OPS_GIT_REMOTE` | `false` | Master switch for every remote tool |
| `LOCAL_OPS_GIT_FETCH` | `true` | fetch, when the master switch is enabled |
| `LOCAL_OPS_GIT_PULL` | `false` | fast-forward-only pull, when the master switch is enabled |
| `LOCAL_OPS_GIT_PUSH` | `false` | current-branch push, when the master switch is enabled |

Disabled tools are omitted from MCP `tools/list` and direct calls are rejected. Boolean values accept `true`/`false`, `1`/`0`, `yes`/`no`, or `on`/`off`.

After changing a switch, restart Local Ops Tunnel so the server applies the new policy. If tools were added to or removed from `tools/list`, first refresh the app from its ChatGPT details page to pull its current tool list. If the current UI has no refresh action or a refresh still does not update the list in practice, delete the old Local Ops custom connector and recreate it with the same Tunnel ID while the Tunnel is running. That fallback is a project troubleshooting observation, not a platform guarantee. Do not delete the OpenAI Platform Tunnel or reinitialize the local tunnel-client profile.

## Safety properties

- Paths are resolved below `LOCAL_OPS_ROOT`; `..` escapes and symlink escapes are rejected.
- Existing files cannot be overwritten unless `overwrite=true`.
- `expected_sha256` can guard against overwriting a file changed since it was read.
- Non-empty directories require `recursive=true` before deletion, and the workspace root can never be deleted.
- Move and rename operations refuse to replace an existing destination.
- Files are limited to 2 MiB by default. Override with `LOCAL_OPS_MAX_BYTES`.
- No general shell or administrator tool is exposed; Git commands use fixed argument arrays without a shell, and remote tools are disabled by default.
- Protocol logs go to stderr so stdout remains reserved for MCP JSON-RPC messages.
