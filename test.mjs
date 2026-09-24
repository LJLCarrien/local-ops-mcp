import { execFile, spawn } from "node:child_process";
import { access, mkdtemp, readFile, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import readline from "node:readline";
import assert from "node:assert/strict";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

const root = await mkdtemp(path.join(os.tmpdir(), "local-ops-test-"));
await writeFile(path.join(root, "hello.txt"), "hello", "utf8");
await execFileAsync("git", ["-C", root, "init"]);
await execFileAsync("git", ["-C", root, "config", "user.name", "Local Ops Test"]);
await execFileAsync("git", ["-C", root, "config", "user.email", "local-ops-test@example.invalid"]);
await execFileAsync("git", ["-C", root, "add", "--", "hello.txt"]);
await execFileAsync("git", ["-C", root, "commit", "-m", "initial"]);
const child = spawn(process.execPath, [new URL("server.mjs", import.meta.url).pathname.slice(process.platform === "win32" ? 1 : 0)], {
  env: { ...process.env, LOCAL_OPS_ROOT: root },
  stdio: ["pipe", "pipe", "inherit"]
});
const output = readline.createInterface({ input: child.stdout, crlfDelay: Infinity });
const iterator = output[Symbol.asyncIterator]();
let id = 0;
async function request(method, params = {}) {
  const requestId = ++id;
  child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id: requestId, method, params })}\n`);
  const { value } = await iterator.next();
  const response = JSON.parse(value);
  assert.equal(response.id, requestId);
  return response.result;
}

const initialized = await request("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "test", version: "1" } });
assert.equal(initialized.serverInfo.name, "local-ops-mcp");
const listed = await request("tools/list");
assert.deepEqual(listed.tools.map((tool) => tool.name), [
  "list_directory",
  "read_file",
  "write_file",
  "create_directory",
  "delete_directory",
  "delete_file",
  "copy_file",
  "move_file",
  "move_directory",
  "rename_file",
  "git_status",
  "git_diff_unstaged",
  "git_diff_staged",
  "git_log",
  "git_show",
  "git_branch",
  "git_add",
  "git_commit",
  "git_amend_message"
]);
const read = await request("tools/call", { name: "read_file", arguments: { path: "hello.txt" } });
assert.match(read.content[0].text, /hello$/);
const digest = read.content[0].text.split("\n", 1)[0].slice("sha256:".length);
const written = await request("tools/call", { name: "write_file", arguments: { path: "hello.txt", content: "updated", overwrite: true, expected_sha256: digest } });
assert.equal(written.isError, undefined);
assert.equal(await readFile(path.join(root, "hello.txt"), "utf8"), "updated");
const created = await request("tools/call", { name: "create_directory", arguments: { path: "parent/child", recursive: true } });
assert.equal(created.isError, undefined);
await access(path.join(root, "parent", "child"));
await writeFile(path.join(root, "parent", "child", "nested.txt"), "nested", "utf8");
const refusedNonEmpty = await request("tools/call", { name: "delete_directory", arguments: { path: "parent" } });
assert.equal(refusedNonEmpty.isError, true);
const deleted = await request("tools/call", { name: "delete_directory", arguments: { path: "parent", recursive: true } });
assert.equal(deleted.isError, undefined);
await assert.rejects(access(path.join(root, "parent")));
const refusedRoot = await request("tools/call", { name: "delete_directory", arguments: { path: ".", recursive: true } });
assert.equal(refusedRoot.isError, true);
await writeFile(path.join(root, "source.txt"), "source", "utf8");
const copied = await request("tools/call", { name: "copy_file", arguments: { source: "source.txt", destination: "copy.txt" } });
assert.equal(copied.isError, undefined);
assert.equal(await readFile(path.join(root, "copy.txt"), "utf8"), "source");
const refusedOverwrite = await request("tools/call", { name: "copy_file", arguments: { source: "source.txt", destination: "copy.txt" } });
assert.equal(refusedOverwrite.isError, true);
await writeFile(path.join(root, "source.txt"), "new source", "utf8");
const overwritten = await request("tools/call", { name: "copy_file", arguments: { source: "source.txt", destination: "copy.txt", overwrite: true } });
assert.equal(overwritten.isError, undefined);
assert.equal(await readFile(path.join(root, "copy.txt"), "utf8"), "new source");
const moved = await request("tools/call", { name: "move_file", arguments: { source: "copy.txt", destination: "moved.txt" } });
assert.equal(moved.isError, undefined);
await assert.rejects(access(path.join(root, "copy.txt")));
await request("tools/call", { name: "create_directory", arguments: { path: "directory-source/nested", recursive: true } });
await writeFile(path.join(root, "directory-source", "nested", "file.txt"), "nested", "utf8");
const movedDirectory = await request("tools/call", { name: "move_directory", arguments: { source: "directory-source", destination: "directory-destination" } });
assert.equal(movedDirectory.isError, undefined);
await assert.rejects(access(path.join(root, "directory-source")));
assert.equal(await readFile(path.join(root, "directory-destination", "nested", "file.txt"), "utf8"), "nested");
await request("tools/call", { name: "create_directory", arguments: { path: "second-directory", recursive: false } });
const refusedExistingDestination = await request("tools/call", { name: "move_directory", arguments: { source: "second-directory", destination: "directory-destination" } });
assert.equal(refusedExistingDestination.isError, true);
const refusedMoveRoot = await request("tools/call", { name: "move_directory", arguments: { source: ".", destination: "moved-root" } });
assert.equal(refusedMoveRoot.isError, true);
await request("tools/call", { name: "create_directory", arguments: { path: "nested-source", recursive: false } });
const refusedNestedDestination = await request("tools/call", { name: "move_directory", arguments: { source: "nested-source", destination: "nested-source/child" } });
assert.equal(refusedNestedDestination.isError, true);
const renamed = await request("tools/call", { name: "rename_file", arguments: { path: "moved.txt", new_name: "renamed.txt" } });
assert.equal(renamed.isError, undefined);
await assert.rejects(access(path.join(root, "moved.txt")));
const refusedRenamePath = await request("tools/call", { name: "rename_file", arguments: { path: "renamed.txt", new_name: "subdir/escaped.txt" } });
assert.equal(refusedRenamePath.isError, true);
const deletedFile = await request("tools/call", { name: "delete_file", arguments: { path: "renamed.txt" } });
assert.equal(deletedFile.isError, undefined);
await assert.rejects(access(path.join(root, "renamed.txt")));
const escaped = await request("tools/call", { name: "read_file", arguments: { path: "../outside.txt" } });
assert.equal(escaped.isError, true);

const gitStatus = await request("tools/call", { name: "git_status", arguments: {} });
assert.match(gitStatus.content[0].text, /^## /);
await writeFile(path.join(root, "hello.txt"), "git update", "utf8");
const unstagedDiff = await request("tools/call", { name: "git_diff_unstaged", arguments: {} });
assert.match(unstagedDiff.content[0].text, /git update/);
const refusedGitEscape = await request("tools/call", { name: "git_add", arguments: { files: ["../outside.txt"] } });
assert.equal(refusedGitEscape.isError, true);
const staged = await request("tools/call", { name: "git_add", arguments: { files: ["hello.txt"] } });
assert.equal(staged.isError, undefined);
const stagedDiff = await request("tools/call", { name: "git_diff_staged", arguments: {} });
assert.match(stagedDiff.content[0].text, /git update/);
const committed = await request("tools/call", { name: "git_commit", arguments: { message: "test: update fixture" } });
assert.match(committed.content[0].text, /test: update fixture/);
await writeFile(path.join(root, "staged-after-commit.txt"), "keep staged", "utf8");
assert.equal((await request("tools/call", { name: "git_add", arguments: { files: ["staged-after-commit.txt"] } })).isError, undefined);
const amended = await request("tools/call", { name: "git_amend_message", arguments: { message: "test: amend fixture message" } });
assert.match(amended.content[0].text, /test: amend fixture message/);
const statusAfterAmend = await request("tools/call", { name: "git_status", arguments: {} });
assert.match(statusAfterAmend.content[0].text, /^A  staged-after-commit\.txt$/m);
const amendedTree = await execFileAsync("git", ["-C", root, "ls-tree", "--name-only", "HEAD", "--", "staged-after-commit.txt"]);
assert.equal(amendedTree.stdout.trim(), "");
await execFileAsync("git", ["-C", root, "reset", "HEAD", "--", "staged-after-commit.txt"]);
const log = await request("tools/call", { name: "git_log", arguments: { max_count: 2 } });
assert.match(log.content[0].text, /test: amend fixture message/);
const shown = await request("tools/call", { name: "git_show", arguments: { revision: "HEAD" } });
assert.match(shown.content[0].text, /test: amend fixture message/);
const refusedRevisionOption = await request("tools/call", { name: "git_show", arguments: { revision: "--help" } });
assert.equal(refusedRevisionOption.isError, true);
const branches = await request("tools/call", { name: "git_branch", arguments: { branch_type: "local" } });
assert.match(branches.content[0].text, /\*/);
const refusedRepoEscape = await request("tools/call", { name: "git_status", arguments: { repo_path: ".." } });
assert.equal(refusedRepoEscape.isError, true);
child.stdin.end();

const disabledChild = spawn(process.execPath, [new URL("server.mjs", import.meta.url).pathname.slice(process.platform === "win32" ? 1 : 0)], {
  env: {
    ...process.env,
    LOCAL_OPS_ROOT: root,
    LOCAL_OPS_GIT_READ: "false",
    LOCAL_OPS_GIT_WRITE: "false",
    LOCAL_OPS_GIT_REMOTE: "true",
    LOCAL_OPS_GIT_FETCH: "false",
    LOCAL_OPS_GIT_PULL: "false",
    LOCAL_OPS_GIT_PUSH: "false"
  },
  stdio: ["pipe", "pipe", "inherit"]
});
const disabledOutput = readline.createInterface({ input: disabledChild.stdout, crlfDelay: Infinity });
const disabledIterator = disabledOutput[Symbol.asyncIterator]();
disabledChild.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/list", params: {} })}\n`);
const disabledList = JSON.parse((await disabledIterator.next()).value).result.tools;
assert.equal(disabledList.some((tool) => tool.name.startsWith("git_")), false);
disabledChild.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id: 2, method: "tools/call", params: { name: "git_status", arguments: {} } })}\n`);
const disabledCall = JSON.parse((await disabledIterator.next()).value).result;
assert.equal(disabledCall.isError, true);
assert.match(disabledCall.content[0].text, /disabled or unknown/);
disabledChild.stdin.end();

const remoteRoot = path.join(root, "remote.git");
await execFileAsync("git", ["init", "--bare", remoteRoot]);
const currentBranch = (await execFileAsync("git", ["-C", root, "branch", "--show-current"])).stdout.trim();
await execFileAsync("git", ["-C", root, "remote", "add", "origin", remoteRoot]);
await execFileAsync("git", ["-C", root, "push", "--set-upstream", "origin", currentBranch]);
const peer = path.join(root, "peer");
await execFileAsync("git", ["clone", remoteRoot, peer]);
await execFileAsync("git", ["-C", peer, "config", "user.name", "Local Ops Peer"]);
await execFileAsync("git", ["-C", peer, "config", "user.email", "local-ops-peer@example.invalid"]);
await writeFile(path.join(peer, "peer.txt"), "from peer", "utf8");
await execFileAsync("git", ["-C", peer, "add", "--", "peer.txt"]);
await execFileAsync("git", ["-C", peer, "commit", "-m", "peer update"]);
await execFileAsync("git", ["-C", peer, "push"]);

const remoteChild = spawn(process.execPath, [new URL("server.mjs", import.meta.url).pathname.slice(process.platform === "win32" ? 1 : 0)], {
  env: {
    ...process.env,
    LOCAL_OPS_ROOT: root,
    LOCAL_OPS_GIT_REMOTE: "true",
    LOCAL_OPS_GIT_FETCH: "true",
    LOCAL_OPS_GIT_PULL: "true",
    LOCAL_OPS_GIT_PUSH: "true"
  },
  stdio: ["pipe", "pipe", "inherit"]
});
const remoteOutput = readline.createInterface({ input: remoteChild.stdout, crlfDelay: Infinity });
const remoteIterator = remoteOutput[Symbol.asyncIterator]();
let remoteId = 0;
async function remoteRequest(method, params = {}) {
  const requestId = ++remoteId;
  remoteChild.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id: requestId, method, params })}\n`);
  const response = JSON.parse((await remoteIterator.next()).value);
  assert.equal(response.id, requestId);
  return response.result;
}

const remoteTools = await remoteRequest("tools/list");
assert.deepEqual(remoteTools.tools.slice(-3).map((tool) => tool.name), ["git_fetch", "git_pull", "git_push"]);
const fetched = await remoteRequest("tools/call", { name: "git_fetch", arguments: {} });
assert.equal(fetched.isError, undefined);
const pulled = await remoteRequest("tools/call", { name: "git_pull", arguments: {} });
assert.equal(pulled.isError, undefined);
assert.equal(await readFile(path.join(root, "peer.txt"), "utf8"), "from peer");
await writeFile(path.join(root, "local.txt"), "from local", "utf8");
assert.equal((await remoteRequest("tools/call", { name: "git_add", arguments: { files: ["local.txt"] } })).isError, undefined);
assert.equal((await remoteRequest("tools/call", { name: "git_commit", arguments: { message: "local update" } })).isError, undefined);
const pushed = await remoteRequest("tools/call", { name: "git_push", arguments: {} });
assert.equal(pushed.isError, undefined);
assert.equal((await execFileAsync("git", ["--git-dir", remoteRoot, "show", `${currentBranch}:local.txt`])).stdout, "from local");

const outsideRemote = await mkdtemp(path.join(os.tmpdir(), "local-ops-outside-remote-"));
await execFileAsync("git", ["init", "--bare", outsideRemote]);
await execFileAsync("git", ["-C", root, "remote", "add", "outside", outsideRemote]);
const refusedOutsideRemote = await remoteRequest("tools/call", { name: "git_fetch", arguments: { remote: "outside" } });
assert.equal(refusedOutsideRemote.isError, true);
assert.match(refusedOutsideRemote.content[0].text, /outside LOCAL_OPS_ROOT/);
remoteChild.stdin.end();
console.log("All local-ops MCP tests passed.");
